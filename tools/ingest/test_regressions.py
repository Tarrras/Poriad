"""Регресійні тести на втрату даних і небезпечний SQL. Без мережі."""
import contextlib
import dataclasses
import datetime as dt
import io
import itertools
import json
import tempfile
import types
from pathlib import Path
import unittest
from unittest.mock import patch

from . import emit, extract, normalize, pipeline
from .__main__ import CityRun, main, run_city, _write_sql
from .fetch import Response
from . import fetch
import urllib.error
from email.message import Message
from .sources import Source, by_slug
from .test_ingest import _item
from .venues import VenueIndex

NOW = dt.datetime(2026, 9, 11, 12, tzinfo=dt.timezone.utc)


def raw_event(**overrides):
    return {"@type": "MusicEvent", "name": "Тестовий концерт",
            "url": "https://example.org/event", "startDate": "2026-10-17T18:00:00+03:00",
            "endDate": "2026-10-17T21:00:00+03:00", "image": "https://example.org/image.jpg",
            "location": {"name": "Зал", "address": {"addressLocality": "Київ"}},
            **overrides}


def html(events):
    return '<script type="application/ld+json">' + json.dumps(events) + '</script>'


class RegressionTests(unittest.TestCase):
    def setUp(self):
        # Каталоги вимкнено: ці перевірки про список і сторінки, у каталогів свої.
        self.source = dataclasses.replace(by_slug("concert_ua"), catalogs=None)
        self.index = VenueIndex([], "Київ", {"Зал": {"lat": 50.45, "lon": 30.53}})

    def harvest(self, events):
        with patch("tools.ingest.pipeline.get", return_value=Response("https://example.org", 200, html(events))):
            return pipeline.harvest(self.source, "Київ", self.index, now=NOW)

    def test_same_source_copies_of_one_session_publish_once(self):
        # Одна подія трьома сторінками одного продавця: не ловить ні злиття за ключем, ні між джерелами.
        from tools.ingest import emit
        events = [raw_event(name="Вечір Імпровізації На Двох", url=f"https://example.org/improv{n}")
                  for n in (3, 4, 5)]
        items, counters = self.harvest(events)
        published = [i for i in items if i.stage == "published"]
        copies = [i for i in items if i.stage == "duplicate"]
        self.assertEqual(len(published), 1)
        self.assertEqual(len(copies), 2)
        winner = (published[0].source_slug, published[0].source_uid)
        self.assertTrue(all(c.duplicate_of == winner for c in copies))
        self.assertEqual(counters["published"], 1)
        # Зайва копія знімається і в базі.
        sql = "".join(emit.duplicates_sql(items, "RUN"))
        for copy in copies:
            self.assertIn(copy.canonical_url, sql)

    def test_same_source_winner_does_not_depend_on_page_order(self):
        names = [f"https://example.org/improv{n}" for n in (5, 3, 4)]
        first, _ = self.harvest([raw_event(name="Вечір Імпровізації На Двох", url=u) for u in names])
        second, _ = self.harvest([raw_event(name="Вечір Імпровізації На Двох", url=u) for u in reversed(names)])
        pick = lambda items: next(i.source_uid for i in items if i.stage == "published")
        self.assertEqual(pick(first), pick(second))

    def test_different_titles_at_one_minute_stay_separate(self):
        # Сусідні зали одного закладу в той самий час — дві події навіть від одного продавця.
        events = [raw_event(name="Кіно-галерея", url="https://example.org/a"),
                  raw_event(name="Клуб настільних ігор", url="https://example.org/b")]
        items, _ = self.harvest(events)
        self.assertEqual(sum(i.stage == "published" for i in items), 2)

    def test_same_source_copies_fold_on_nested_titles_and_distance_not_rounding(self):
        # «Bridal Forum» і «Bridal Forum. Offline» — один сеанс; 2 м між копіями через межу округлення — теж.
        loc = lambda lat: {"@type": "Place", "name": "Bridal Hall", "geo": {"latitude": lat, "longitude": 30.53},
                           "address": {"streetAddress": "вул. Б, 1", "addressLocality": "Київ"}}
        events = [raw_event(name="Bridal Forum", url="https://example.org/bf1", location=loc(50.45004)),
                  raw_event(name="Bridal Forum. Offline", url="https://example.org/bf2", location=loc(50.45006))]
        items, _ = self.harvest(events)
        self.assertEqual([round(i.latitude, 4) for i in items], [50.45, 50.4501])   # по різні боки округлення
        self.assertEqual(sum(i.stage == "published" for i in items), 1)
        # Одне слово, вкладене в довшу назву, — замало: «Квіз» і «Квіз Гаррі Поттер» лишаються окремо.
        items, _ = self.harvest([raw_event(name="Квіз", url="https://example.org/q1"),
                                 raw_event(name="Квіз Гаррі Поттер", url="https://example.org/q2")])
        self.assertEqual(sum(i.stage == "published" for i in items), 2)

    def test_merge_winner_takes_what_it_lacks_from_the_copy(self):
        # Concert.ua виграє за вагою, але без опису й виконавця; Badseller віддає обидва.
        from .artists import Artist
        from .test_ingest import _item
        winner, copy = _item("concert_ua", "Я бачу, вас цікавить пітьма"), _item("badseller", "Я бачу, вас цікавить пітьма")
        copy.description, copy.description_len, copy.image_url = "Вистава Дикого театру.", 22, "https://x/i.jpg"
        copy.artists = [Artist("Дикий театр")]
        winner.artists = [Artist("Хтось Інший")]
        pipeline.drop_cross_source_duplicates([winner, copy], {"concert_ua": 0.8, "badseller": 0.69})
        self.assertEqual(copy.stage, "duplicate")
        self.assertEqual([a.name for a in winner.artists], ["Хтось Інший", "Дикий театр"])
        self.assertEqual((winner.description, winner.image_url), ("Вистава Дикого театру.", "https://x/i.jpg"))
        # Абревіатура залу копії не стає артистом переможця, хоч у переможця назва залу інша.
        winner2, copy2 = _item("karabas", "Сільва"), _item("badseller", "Сільва")
        winner2.venue_name, copy2.venue_name = "Театр музичної комедії", "Театр музкомедії (ОАТМК ім. М. Водяного)"
        copy2.artists = [Artist("ОАТМК ім. М. Водяного")]
        pipeline.drop_cross_source_duplicates([winner2, copy2], {"karabas": 0.7, "badseller": 0.69})
        self.assertEqual(winner2.artists, [])

    def test_duplicate_of_a_duplicate_points_to_the_final_winner(self):
        # Згортання одного продавця дало переможця, який потім програв іншому джерелу: копія мусить
        # посилатись на кінцевого, інакше duplicates_sql не зніме її старий рядок.
        from .test_ingest import _item
        top, mid, low = _item("concert_ua", "ДахаБраха"), _item("karabas", "ДахаБраха"), _item("karabas", "ДахаБраха наживо")
        low.stage, low.duplicate_of = "duplicate", (mid.source_slug, mid.source_uid)
        pipeline.drop_cross_source_duplicates([top, mid, low], {"concert_ua": 0.8, "karabas": 0.7})
        self.assertEqual(mid.duplicate_of, (top.source_slug, top.source_uid))
        self.assertEqual(low.duplicate_of, (top.source_slug, top.source_uid))

    def test_bot_challenge_on_a_catalog_page_is_an_error_but_an_empty_catalog_is_not(self):
        source = dataclasses.replace(by_slug("concert_ua"), catalogs={"sport": "sport"})
        def run(catalog_body):
            def fake_get(url, **kwargs):
                return Response(url, 200, catalog_body if "/catalog/" in url else html([raw_event()]))
            with patch("tools.ingest.pipeline.get", side_effect=fake_get):
                return pipeline.harvest(source, "Київ", self.index, now=NOW)[1]
        self.assertEqual(run("<html><body>Нічого не знайдено</body></html>")["catalog_errors"], [])
        self.assertTrue(run("<html><title>Just a moment...</title></html>")["catalog_errors"])

    def test_group_tile_sessions_join_the_crawl_and_a_broken_group_blocks_retire(self):
        # Concert.ua: вистава з кількома сеансами — плитка `/uk/events/…` без JSON-LD у списку й каталозі.
        from .__main__ import _may_retire
        source = dataclasses.replace(by_slug("concert_ua"), catalogs={"kids": "kids"}, performer_details=False)
        tile = '<a href="/uk/events/planeti-kyiv">Планети</a>'
        session = lambda day: raw_event(name="Планети", url=f"https://concert.ua/uk/event/planeti-{day}-10-2026",
                                        startDate=f"2026-10-{day}T14:00:00+03:00", endDate=f"2026-10-{day}T15:30:00+03:00")
        listed = [raw_event(name=f"Концерт {n}", url=f"https://concert.ua/uk/event/c{n}") for n in range(12)]

        def run(group_status):
            def fake_get(url, **kwargs):
                if "/uk/events/" in url:
                    return Response(url, group_status, html([session("24"), session("30")]))
                return Response(url, 200, (html(listed) if "/catalog/" not in url else "") + tile)
            with patch("tools.ingest.pipeline.get", side_effect=fake_get):
                return pipeline.harvest(source, "Київ", self.index, now=NOW)

        items, counters = run(200)
        planets = [i for i in items if i.title == "Планети"]
        self.assertEqual(sorted(i.starts_at.day for i in planets), [24, 30])
        self.assertEqual({i.category for i in planets}, {"kids"})          # жанр каталогу, де трапилась плитка
        self.assertEqual(counters["groups"], {"links": 1, "sessions": 2})
        self.assertTrue(_may_retire(source, items, counters)[0])
        items, counters = run(503)
        self.assertFalse(_may_retire(source, items, counters)[0])

    def test_title_never_exceeds_database_limit(self):
        self.assertLessEqual(len(normalize.normalize_title("А" * 130)), 120)

    def test_nonfinite_and_negative_prices_are_unknown(self):
        for value in ["NaN", "Infinity", "-1"]:
            with self.subTest(value=value):
                self.assertEqual(normalize.parse_price({"offers": {"price": value}}), (None, None))

    def test_foreign_currency_is_not_reported_as_uah(self):
        self.assertEqual(normalize.parse_price({"offers": {"price": "100", "priceCurrency": "EUR"}}), (None, None))

    def test_cancelled_and_postponed_never_publish(self):
        for status in ["EventCancelled", "https://schema.org/EventPostponed"]:
            with self.subTest(status=status):
                items, counters = self.harvest([raw_event(eventStatus=status)])
                self.assertFalse(any(i.stage == "published" for i in items))
                self.assertEqual(len(counters.get("withdrawals", [])), 1)

    def test_custom_collector_flows_through_normalization(self):
        source = Source(slug="dou-test", name="DOU", base_url="https://dou.ua",
            listing_urls={"Київ": "https://dou.ua/calendar/city/Kyiv/"}, weight=.7,
            crawl_delay=1, adapter="dou")
        event = raw_event(url="https://dou.ua/calendar/123/")
        with patch("tools.ingest.pipeline.community.collect",
                   return_value=([event], {"fetched": 3, "coverage": "listing"})):
            items, counters = pipeline.harvest(source, "Київ", self.index, now=NOW)
        self.assertEqual(len(items), 1)
        self.assertEqual(counters["parsed"], 1)

    def test_status_notice_rekeys_new_session_and_withdraws_old(self):
        old = dt.datetime(2026, 10, 17, 18, tzinfo=normalize.zone("Europe/Kyiv"))
        new = dt.datetime(2026, 10, 20, 18, tzinfo=normalize.zone("Europe/Kyiv"))
        current = pipeline._build(raw_event(startDate=new.isoformat()), self.source,
                                  "Київ", self.index, NOW)
        stale = pipeline._build(raw_event(startDate=old.isoformat()), self.source,
                                "Київ", self.index, NOW)
        kept, withdrawals = pipeline.apply_status_notices([current, stale], [{
            "canonical_url": current.canonical_url, "city": "Київ",
            "status": "EventRescheduled", "starts_at": old.isoformat(),
            "new_start": new.isoformat(), "evidence_url": "https://karabas.com/info/"}])
        self.assertEqual(kept, [current])
        self.assertEqual(current.previous_start, old)
        self.assertEqual(withdrawals, [{"url": current.canonical_url,
            "starts_at": old.isoformat(), "reason": "EventRescheduled"}])

    def test_status_notice_never_touches_other_city_or_session(self):
        item = pipeline._build(raw_event(), self.source, "Київ", self.index, NOW)
        notices = [{"canonical_url": item.canonical_url, "city": "Львів",
            "status": "EventCancelled", "starts_at": item.starts_at.isoformat(),
            "evidence_url": "https://karabas.com/info/"}]
        kept, withdrawals = pipeline.apply_status_notices([item], notices)
        self.assertEqual(kept, [item])
        self.assertEqual(withdrawals, [])

    def test_status_notice_withdraws_absent_listing_session_by_city(self):
        notice = {"canonical_url": "https://kyiv.karabas.com/event/1/", "city": "Київ",
            "status": "EventCancelled", "starts_at": "2026-10-17T18:00:00+03:00",
            "evidence_url": "https://karabas.com/info/"}
        kept, withdrawals = pipeline.apply_status_notices([], [notice], city="Київ")
        self.assertEqual(kept, [])
        self.assertEqual(withdrawals[0]["url"], notice["canonical_url"])

    def test_reschedule_detail_adds_new_session_when_missing_from_listing(self):
        old = "2026-10-17T18:00:00+03:00"
        new = "2026-10-20T18:00:00+03:00"
        notice = {"canonical_url": "https://example.org/event", "city": "Київ",
                  "status": "EventRescheduled", "starts_at": old,
                  "new_start": new, "evidence_url": "https://karabas.com/info/"}
        listing = raw_event(url="https://example.org/other")
        moved = raw_event(startDate="2026-10-20T21:00:00+03:00")
        responses = [Response("https://example.org", 200, html([listing])),
                     Response("https://example.org/event", 200, html([moved]))]
        with patch("tools.ingest.pipeline.get", side_effect=responses):
            items, counters = pipeline.harvest(by_slug("karabas"), "Київ", self.index,
                now=NOW, status_notices=[notice])
        added = next(item for item in items if item.canonical_url == notice["canonical_url"])
        self.assertEqual(added.starts_at.isoformat(), new)
        self.assertEqual(added.previous_start.isoformat(), old)

    def test_cancellation_without_date_still_updates_legacy_record(self):
        _, counters = self.harvest([raw_event(eventStatus="EventCancelled", startDate=None)])
        self.assertEqual(len(counters.get("withdrawals", [])), 1)

    def test_other_city_never_uses_listing_coordinates(self):
        item = pipeline._build(raw_event(location={"name": "Зал", "address": {"addressLocality": "Львів"}}),
                               self.source, "Київ", self.index, NOW)
        self.assertIsNone(item.latitude)

    def test_alias_outside_city_is_rejected(self):
        index = VenueIndex([], "Київ", {"Зал": {"lat": 49.84, "lon": 24.03}})
        item = pipeline._build(raw_event(), self.source, "Київ", index, NOW)
        self.assertIsNone(item.latitude)

    def test_ongoing_declared_event_is_kept(self):
        item = pipeline._build(raw_event(startDate="2026-09-10T12:00:00+03:00",
                                        endDate="2026-09-20T12:00:00+03:00"),
                               self.source, "Київ", self.index, NOW)
        self.assertIsNotNone(item)

    def test_seasonal_run_survives_the_permanent_offer_cutoff(self):
        """Ярмарок на 86 днів — подія; океанаріум з квитком на 560 — ні."""
        run = raw_event(startDate="2026-09-10T12:00:00+03:00", endDate="2026-11-20T12:00:00+03:00")
        forever = raw_event(name="Київський океанаріум",
                            url="https://example.org/oceanarium",
                            startDate="2026-09-10T12:00:00+03:00",
                            endDate="2028-03-20T12:00:00+03:00")
        items, counters = self.harvest([run, forever])
        self.assertEqual([i.title for i in items], ["Тестовий концерт"])
        self.assertEqual(counters["reasons"].get("PERMANENT_OFFER"), 1)

    def test_permanent_offer_is_cut_even_before_it_starts(self):
        """Постійна пропозиція не стає подією від того, що її початок у майбутньому."""
        items, counters = self.harvest([raw_event(startDate="2026-10-01T12:00:00+03:00",
                                                  endDate="2027-10-01T12:00:00+03:00")])
        self.assertEqual(items, [])
        self.assertEqual(counters["reasons"].get("PERMANENT_OFFER"), 1)

    def test_same_url_sessions_are_preserved_and_have_distinct_ids(self):
        events = [raw_event(), raw_event(startDate="2026-10-18T18:00:00+03:00")]
        self.assertEqual(len(extract.events_from_html(html(events + events))), 2)
        items, _ = self.harvest(events)
        self.assertEqual(len({i.source_uid for i in items}), 2)
        self.assertEqual(len({i.event_id for i in items}), 2)

    def test_loser_cannot_eliminate_another_candidate(self):
        for order in itertools.permutations("abc"):
            items = {s: _item(s, t) for s, t in zip("abc", ["Альфа Бета", "Альфа", "Бета"])}
            pipeline.drop_cross_source_duplicates([items[s] for s in order], {"a": .7, "b": .8, "c": .6})
            self.assertEqual(items["b"].stage, "published")
            self.assertEqual(items["c"].stage, "published")

    def test_partial_listing_does_not_generate_mass_retirement(self):
        with patch("tools.ingest.__main__.build_index", return_value=self.index), \
             patch("tools.ingest.pipeline.get", return_value=Response("https://example.org", 200, html([raw_event()]))), \
             contextlib.redirect_stdout(io.StringIO()):
            _, parts = run_city("Київ", [self.source], "00000000-0000-0000-0000-000000000001", use_photon=False, now=NOW)
        sql = "".join(parts)
        self.assertNotIn("ingest_run_id is distinct from", sql)
        # Список з однією подією не доводить, що решту скасовано.
        self.assertNotIn("do $retire$", sql)

    def test_robots_failure_is_a_source_error(self):
        with patch("tools.ingest.pipeline.get", side_effect=PermissionError("robots unavailable")):
            items, counters = pipeline.harvest(self.source, "Київ", self.index, now=NOW)
        self.assertEqual(items, [])
        self.assertIn("error", counters)

    def test_empty_parser_result_is_not_success(self):
        _, counters = self.harvest([])
        self.assertIn("error", counters)

    def test_legacy_identity_is_adopted_without_changing_saved_event_id(self):
        items, _ = self.harvest([raw_event()])
        sql = "".join(emit.events_sql(items, "00000000-0000-0000-0000-000000000001"))
        self.assertIn("update public.events", sql)
        self.assertIn("not exists", sql)
        self.assertNotIn("set id=", sql)

    def test_moved_url_adopts_the_old_row_so_saves_stay_attached(self):
        # Подія переїхала на нове посилання: без переходу за назвою, хвилиною й точкою збережена виглядала б скасованою.
        items, _ = self.harvest([raw_event(url="https://example.org/teatr-3")])
        sql = "".join(emit.events_sql(items, "00000000-0000-0000-0000-000000000001"))
        self.assertIn("'https://example.org/teatr-3'", sql)
        self.assertIn("x.canonical_url <> i.url", sql)
        # Назва без хвоста в дужках і розділових знаків: badseller прибрав зал із назв (2026-10-06).
        self.assertIn(f"{emit._title_key_sql('x.title')} = {emit._title_key_sql('i.title')}", sql)
        # Автоматично знятий рядок теж переймається; вимкнене джерело — ні.
        self.assertIn("x.import_status='withdrawn' and x.ingest_run_id is not null", sql)
        self.assertIn("slug='concert_ua' and enabled)", sql)
        # Обидва `distinct on` обов'язкові: інакше дві старі копії отримали б той самий ключ.
        self.assertIn("select distinct on (i.uid)", sql)
        self.assertIn("select distinct on (id)", sql)
        self.assertNotIn("set id=", sql)

    def test_moved_url_adoption_is_one_statement_per_batch(self):
        # Окремий UPDATE на подію займав половину SQL.
        events = [raw_event(name=f"Подія номер {k}", url=f"https://example.org/e{k}") for k in range(12)]
        items, _ = self.harvest(events)
        sql = "".join(emit.events_sql(items, "00000000-0000-0000-0000-000000000001"))
        self.assertEqual(sql.count("with incoming(uid, url, city, title, starts, lat, lon)"), 1)
        # Регекс із класами символів залежить від локалі бази: у локалі C кирилиця зникає.
        self.assertNotIn("[:alnum:]", sql)

    def _complete_crawl(self, n=12):
        return self.harvest([raw_event(name=f"Подія номер {k}", url=f"https://example.org/e{k}")
                             for k in range(n)])

    def test_retire_needs_a_complete_crawl(self):
        from tools.ingest.__main__ import _may_retire
        items, counters = self._complete_crawl()
        self.assertEqual(_may_retire(self.source, items, counters), (True, ""))
        for broken in ({"error": "HTTP 503"}, {"catalog_errors": ["humor с.2: HTTP 503"]},
                       {"catalog_capped": 1}):
            with self.subTest(broken=broken):
                self.assertFalse(_may_retire(self.source, items, {**counters, **broken})[0])
        self.assertFalse(_may_retire(dataclasses.replace(self.source, detail_path="/event/"),
                                     items, counters)[0])
        few, few_counters = self._complete_crawl(3)
        self.assertFalse(_may_retire(self.source, few, few_counters)[0])

    def test_retire_sql_is_scoped_and_guarded(self):
        sql = emit.retire_absent_sql("karabas", "Київ", ["u2", "u1", "u1"], "run")
        self.assertIn("e.city='Київ'", sql)
        self.assertIn("slug='karabas'", sql)
        self.assertIn("v_seen text[] := array['u1','u2']::text[]", sql)
        self.assertIn("e.source_uid <> all (v_seen)", sql)
        # Лише ще не початі: почата подія зі списку зникає сама, і «знято» посеред показу — неправда.
        self.assertIn("e.starts_at > now()", sql)
        self.assertNotIn("ends_at", sql)
        # Запобіжник не мовчить: результат — у звіт прогону й попередженням.
        self.assertIn("'retire_blocked', v_blocked", sql)
        self.assertIn(f"where id = '{emit.stats_run_id('run', 'karabas', 'Київ')}'::uuid", sql)
        self.assertIn("raise warning", sql)
        # За межею обходу (sitemap до horizon_days) відсутність нічого не доводить.
        self.assertNotIn("e.starts_at <", sql)
        self.assertIn("and e.starts_at < '2027-10-09'::date",
                      emit.retire_absent_sql("badseller", "Київ", ["u"], "run", until=dt.date(2027, 10, 9)))
        self.assertIn(f"greatest({emit.RETIRE_ALLOWANCE}, {emit.RETIRE_MAX_SHARE}", sql)
        self.assertNotIn("delete", sql.lower())
        self.assertEqual(emit.retire_absent_sql("karabas", "Київ", [], "run"), "")

    def test_finished_imports_go_stale_last_and_never_by_delete(self):
        sql = emit.retire_finished_sql()
        self.assertIn("private.retire_finished_imports(interval '7 days')", sql)
        self.assertNotIn("delete", sql.lower())
        with self.assertRaises(ValueError):
            emit.retire_finished_sql(-1)
        with tempfile.TemporaryDirectory() as tmp, contextlib.redirect_stdout(io.StringIO()), \
             patch("tools.ingest.__main__.gather_city", return_value=CityRun("Київ", [], [], [])), \
             patch("tools.ingest.__main__.emit_city", return_value=(["select 1;\n"], [])), \
             patch("tools.ingest.__main__.karabas_status.collect", return_value=([], {"pages_fetched": 1})):
            path = Path(tmp) / "events.sql"
            main(["--city", "Київ", "--sql", str(path)])
            body = path.read_text("utf-8")
        self.assertTrue(body.rstrip().endswith(sql.strip() + "\ncommit;"))

    def test_place_followers_are_notified_before_the_finished_step_and_guarded(self):
        sql = emit.notify_follows_sql()
        self.assertIn("perform private.notify_place_follows()", sql)
        self.assertIn("perform private.notify_artist_follows()", sql)
        self.assertLess(sql.index("notify_artist_follows"), sql.index("notify_place_follows"))   # артист забирає слот першим
        # База без міграції не має відкотити транзакцію дампу: виклик під перевіркою наявності функції.
        self.assertIn("to_regprocedure('private.notify_place_follows()') is not null", sql)
        # І збій самого зведення не відкочує дамп: він лише попередження.
        self.assertIn("exception when others then", sql)
        self.assertIn("raise warning", sql)
        self.assertNotIn("delete", sql.lower())
        with tempfile.TemporaryDirectory() as tmp, contextlib.redirect_stdout(io.StringIO()), \
             patch("tools.ingest.__main__.gather_city", return_value=CityRun("Київ", [], [], [])), \
             patch("tools.ingest.__main__.emit_city", return_value=(["select 1;\n"], [])), \
             patch("tools.ingest.__main__.karabas_status.collect", return_value=([], {"pages_fetched": 1})):
            path = Path(tmp) / "events.sql"
            main(["--city", "Київ", "--sql", str(path)])
            body = path.read_text("utf-8")
        self.assertIn(sql, body)
        self.assertLess(body.index(sql), body.index(emit.retire_finished_sql()), "пуш перед завершеними, вони — останні")

    def test_run_city_retires_last_and_only_after_a_full_crawl(self):
        events = [raw_event(name=f"Подія номер {k}", url=f"https://example.org/e{k}") for k in range(12)]
        with patch("tools.ingest.__main__.build_index", return_value=self.index), \
             patch("tools.ingest.pipeline.get", return_value=Response("https://example.org", 200, html(events))), \
             contextlib.redirect_stdout(io.StringIO()):
            _, parts = run_city("Київ", [self.source], "00000000-0000-0000-0000-000000000001",
                                use_photon=False, now=NOW)
        sql = "".join(parts)
        self.assertIn("do $retire$", sql)
        self.assertGreater(sql.index("do $retire$"), sql.index("insert into public.events"))

    def test_explicit_withdrawal_is_scoped_to_source_and_session(self):
        with patch("tools.ingest.__main__.build_index", return_value=self.index), \
             patch("tools.ingest.pipeline.get", return_value=Response("https://example.org", 200,
                   html([raw_event(eventStatus="EventCancelled")]))), \
             contextlib.redirect_stdout(io.StringIO()):
            _, parts = run_city("Київ", [self.source], "00000000-0000-0000-0000-000000000001", use_photon=False, now=NOW)
        sql = "".join(parts)
        self.assertIn("import_status='withdrawn'", sql)
        self.assertIn("source_id=", sql)
        self.assertIn("starts_at=", sql)
        self.assertNotIn("ingest_run_id is distinct from", sql)

    def test_detail_source_ignores_other_hosts_and_reports_failed_detail(self):
        source = dataclasses.replace(self.source, detail_path="/event/", max_details=10)
        page = '<a href="/event/one">one</a><a href="/event/two">two</a><a href="https://other.org/event/x">x</a>'
        responses = [Response("https://concert.ua/uk/kyiv", 200, page),
                     Response("https://concert.ua/event/one", 200, html([raw_event()])),
                     Response("https://concert.ua/event/two", 503, "")]
        with patch("tools.ingest.pipeline.get", side_effect=responses):
            items, counters = pipeline.harvest(source, "Київ", self.index, now=NOW)
        self.assertEqual(len(items), 1)
        self.assertIn("error", counters)
        self.assertEqual(counters["fetched"], 2)

    def test_source_coordinates_work_without_venue_alias(self):
        event = raw_event(location={"name": "Новий зал", "address": {"addressLocality": "Київ"},
                                   "geo": {"latitude": "50.45", "longitude": "30.53"}})
        item = pipeline._build(event, self.source, "Київ", VenueIndex([], "Київ"), NOW)
        self.assertEqual((item.latitude, item.longitude), (50.45, 30.53))
        self.assertEqual(item.venue_how, "source")

    def test_http_retries_transient_errors(self):
        headers = Message()
        headers["Retry-After"] = "0"
        failure = urllib.error.HTTPError("https://example.org", 503, "Unavailable", headers, None)
        with patch("tools.ingest.fetch.allowed", return_value=True), \
             patch("tools.ingest.fetch.crawl_delay", return_value=0), \
             patch("tools.ingest.fetch.time.sleep"), \
             patch("tools.ingest.fetch._opener.open", side_effect=[failure, failure, failure]):
            result = fetch.get("https://example.org", delay=0)
        self.assertEqual(result.status, 503)
        self.assertEqual(getattr(result, "attempts", 1), 3)
        self.assertTrue(getattr(result, "error", None))

    def test_bootstrap_sql_registers_new_source(self):
        from .sources import by_slug
        source = by_slug("ticketsbox")
        sql = emit.sources_sql([source])
        self.assertIn("insert into public.event_sources", sql)
        self.assertIn("'ticketsbox'", sql)
        self.assertIn("on conflict (slug) do nothing", sql)

    def test_probe_uses_same_nested_jsonld_parser(self):
        from tools.probe_event_sources import events_in
        self.assertEqual(len(events_in(html({"@graph": [raw_event()]}))), 1)

    def test_malformed_timezone_does_not_crash_import(self):
        self.assertIsNone(normalize.parse_datetime("2026-10-17T18:00:00+99:99", "source", "Europe/Kyiv"))

    def test_sql_byte_limit_includes_headers_and_manifest(self):
        with tempfile.TemporaryDirectory() as tmp, contextlib.redirect_stdout(io.StringIO()):
            path = Path(tmp) / "events.sql"
            parts = ["select '" + "ї" * 100 + "';\n"] * 4
            _write_sql(path, "00000000-0000-0000-0000-000000000001", parts, 4, 700)
            self.assertTrue(all(p.stat().st_size <= 700 for p in Path(tmp).glob("*.sql")))
            self.assertTrue(path.with_suffix(".manifest.json").exists())

    def test_oversized_statement_fails_before_writing_any_sql(self):
        with tempfile.TemporaryDirectory() as tmp, contextlib.redirect_stdout(io.StringIO()):
            path = Path(tmp) / "events.sql"
            with self.assertRaises(ValueError):
                _write_sql(path, "test", ["select '" + "ї" * 1000 + "';"], 1, 700)
            self.assertEqual(list(Path(tmp).iterdir()), [])

    def test_event_batches_split_by_bytes_between_rows(self):
        items = [_item("concert_ua", "Концерт " + str(n)) for n in range(10)]
        parts = emit.events_sql(items, "00000000-0000-0000-0000-000000000001", max_bytes=8000)
        self.assertGreater(len(parts), 1)
        self.assertTrue(all(len(s.encode()) <= 8000 for s in parts))
        self.assertEqual(sum(s.count("insert into public.events") for s in parts), len(parts))

    def test_same_occurrence_across_listing_and_detail_only_publishes_once(self):
        source = dataclasses.replace(self.source, detail_path="/event/")
        listing = html([raw_event()]) + '<a href="/event/one">one</a>'
        responses = [Response("https://concert.ua/uk/kyiv", 200, listing),
                     Response("https://concert.ua/event/one", 200, html([raw_event()]))]
        with patch("tools.ingest.pipeline.get", side_effect=responses):
            items, _ = pipeline.harvest(source, "Київ", self.index, now=NOW)
        self.assertEqual(len(items), 1)

    def test_generic_word_does_not_merge_different_programmes(self):
        self.assertFalse(pipeline.same_event(_item("karabas", "Вечір джазу"),
                                             _item("concert_ua", "Вечір поезії")))

    def test_rescheduled_duplicate_withdraws_previous_session(self):
        item = _item("internet_bilet", "Концерт", start="2026-10-18T18:00:00+03:00")
        item.previous_start = dt.datetime.fromisoformat("2026-10-17T18:00:00+03:00")
        item.duplicate_of = ("concert_ua", "winner")
        sql = "".join(emit.duplicates_sql([item], "00000000-0000-0000-0000-000000000001"))
        self.assertIn("2026-10-17T18:00:00+03:00", sql)

    def test_listing_previous_date_survives_richer_detail(self):
        source = dataclasses.replace(self.source, detail_path="/event/")
        listing = html([raw_event(eventStatus="EventRescheduled", previousStartDate="2026-10-16T18:00:00+03:00")])
        responses = [Response("https://concert.ua/uk/kyiv", 200, listing + '<a href="/event/one">one</a>'),
                     Response("https://concert.ua/event/one", 200, html([raw_event()]))]
        with patch("tools.ingest.pipeline.get", side_effect=responses):
            items, _ = pipeline.harvest(source, "Київ", self.index, now=NOW)
        self.assertEqual(items[0].previous_start, dt.datetime.fromisoformat("2026-10-16T18:00:00+03:00"))


class Demotion(unittest.TestCase):
    def test_reviewed_event_withdraws_its_live_row_reversibly(self):
        from .test_ingest import _item
        run = "00000000-0000-0000-0000-000000000001"
        kept, demoted = _item("concert_ua", "Живий"), _item("concert_ua", "Без точки", lat=None, lon=None)
        demoted.stage, demoted.reject_reason = "review", "NO_GEO"
        sql = "".join(emit.demote_sql([kept, demoted], run))
        self.assertEqual(sql.count("update public.events"), 1)
        self.assertIn(f"source_uid='{demoted.source_uid}'", sql)
        self.assertIn("import_status='withdrawn'", sql)
        self.assertIn(f"ingest_run_id='{run}'", sql)          # з run_id — наступний обхід поверне в live
        self.assertIn("import_status='live'", sql)             # ручне зняття не перезаписується
        self.assertEqual(emit.demote_sql([kept], run), [])


class Robustness(unittest.TestCase):
    """Одна брудна подія чи зламана верстка не мають ні валити дамп, ні минати мовчки."""

    def setUp(self):
        self.source = dataclasses.replace(by_slug("concert_ua"), catalogs=None)
        self.index = VenueIndex([], "Київ", {"Зал": {"lat": 50.45, "lon": 30.53}})

    def harvest(self, events):
        with patch("tools.ingest.pipeline.get", return_value=Response("https://example.org", 200, html(events))):
            return pipeline.harvest(self.source, "Київ", self.index, now=NOW)

    def test_lone_surrogate_is_dropped_from_text_and_url(self):
        self.assertEqual(normalize.clean_text("Джаз\ud800 вечір"), "Джаз вечір")
        self.assertEqual(normalize.clean_url(" https://example.org/a\udfff\u200e "), "https://example.org/a")
        "".join([normalize.clean_text("x\ud800"), normalize.clean_url("y\udc00")]).encode("utf-8")

    def test_url_keeps_query_entities_and_rejects_overlong(self):
        # html.unescape зробив би з `&reg` «®» і змінив ключ події.
        self.assertEqual(normalize.clean_url("https://example.org/?a=1&region=2"), "https://example.org/?a=1&region=2")
        self.assertEqual(normalize.clean_url("https://example.org/" + "a" * 2100), "")

    def test_build_clips_address_and_drops_overlong_urls(self):
        long_address = {"name": "Зал", "address": {"streetAddress": "вул. " + "Д" * 400,
                                                   "addressLocality": "Київ"}}
        item = pipeline._build(raw_event(location=long_address), self.source, "Київ", self.index, NOW)
        self.assertLessEqual(len(item.address), 300)
        item = pipeline._build(raw_event(location={"name": "Зал " + "ї" * 400}), self.source, "Київ",
                               self.index, NOW)
        self.assertLessEqual(len(item.address), 300)
        item = pipeline._build(raw_event(image="https://example.org/" + "i" * 2100), self.source, "Київ",
                               self.index, NOW)
        self.assertIsNone(item.image_url)
        self.assertIsNone(pipeline._build(raw_event(url="https://example.org/" + "u" * 2100),
                                          self.source, "Київ", self.index, NOW))

    def test_one_crashing_event_is_skipped_and_reported(self):
        real = pipeline._build
        calls = iter([RuntimeError("дивна розмітка")])

        def flaky(*args, **kwargs):
            error = next(calls, None)
            if error:
                raise error
            return real(*args, **kwargs)
        with patch("tools.ingest.pipeline._build", side_effect=flaky):
            items, counters = self.harvest([raw_event(url="https://example.org/bad"),
                                            raw_event(name="Інший концерт", url="https://example.org/ok")])
        self.assertEqual(len(items), 1)
        self.assertEqual(len(counters["bad_events"]), 1)
        self.assertIn("https://example.org/bad", counters["bad_events"][0])
        self.assertNotIn("error", counters)

    def test_unwritable_event_goes_to_review_not_into_the_dump(self):
        from .test_ingest import _item
        good, bad = _item("concert_ua", "Добрий концерт"), _item("concert_ua", "Поганий концерт")
        bad.title = "Поганий\ud800 концерт"
        odd_venue = _item("concert_ua", "Концерт у дивному залі")
        odd_venue.venue_display = "Зал\ud800"
        long_url = _item("concert_ua", "Задовге посилання")
        long_url.canonical_url = "https://x/" + "u" * 2100
        items = [good, bad, long_url, odd_venue]
        report = emit.drop_unwritable(items, "00000000-0000-0000-0000-000000000001")
        self.assertEqual(len(report), 2)
        self.assertEqual([i.stage for i in items], ["published", "review", "review", "published"])
        "".join(emit.events_sql(items, "00000000-0000-0000-0000-000000000001")).encode("utf-8")
        emit.venues_sql(items, "Київ").encode("utf-8")      # у кеш майданчиків той зал не йде

    def test_parsed_but_nothing_usable_is_a_source_error(self):
        past = raw_event(startDate="2026-01-01T18:00:00+02:00", endDate="2026-01-01T21:00:00+02:00")
        items, counters = self.harvest([past])
        self.assertEqual(items, [])
        self.assertTrue(counters["error"].startswith("NO_USABLE_EVENTS"))

    def test_sharp_drop_against_previous_report_is_an_error(self):
        from .__main__ import mark_sharp_drops
        previous = [{"city": "Київ", "source": "karabas", "items": 100},
                    {"city": "Київ", "source": "dou", "items": 4}]
        now = [{"city": "Київ", "source": "karabas", "items": 20},
               {"city": "Київ", "source": "dou", "items": 0}]
        self.assertEqual(len(mark_sharp_drops(now, previous)), 1)
        self.assertTrue(now[0]["error"].startswith("SHARP_DROP"))
        self.assertNotIn("error", now[1])            # мале джерело — шум, а не спад
        steady = [{"city": "Київ", "source": "karabas", "items": 90}]
        self.assertEqual(mark_sharp_drops(steady, previous), [])
        self.assertEqual(mark_sharp_drops(steady, []), [])

    def test_one_source_crash_does_not_stop_the_run(self):
        from .__main__ import gather_city
        broken = dataclasses.replace(self.source, slug="broken")
        with patch("tools.ingest.__main__.build_index", return_value=self.index), \
             patch("tools.ingest.__main__.harvest", side_effect=KeyError("at")), \
             contextlib.redirect_stdout(io.StringIO()):
            reports = []
            run = gather_city("Київ", [broken], "run", use_photon=False, now=NOW, reports=reports)
        self.assertEqual(run.items, [])
        self.assertTrue(reports[0]["error"].startswith("CRASH KeyError"))

    def test_artists_are_settled_across_all_cities(self):
        # «Театр 057» у Дніпрі й Харкові: по місту — «в одному місці» (майданчик), по всіх — трупа.
        from .artists import Artist
        from .test_ingest import _item
        runs, seen = [], []
        for city, lat in (("Дніпро", 48.46), ("Харків", 50.0)):
            it = _item("badseller", "Вистава", lat=lat)
            it.city, it.artists = city, [Artist("Театр 057")]
            runs.append(CityRun(city, [], [it], []))
        def fake_emit(run, *_, **__):
            seen.extend(a.name for i in run.items for a in i.artists)
            return [], []
        with contextlib.redirect_stdout(io.StringIO()), \
             patch("tools.ingest.__main__.karabas_status.collect", return_value=([], {"pages_fetched": 1})), \
             patch("tools.ingest.__main__.gather_city", side_effect=lambda city, *a, **k: runs.pop(0) if runs else None), \
             patch("tools.ingest.__main__.emit_city", side_effect=fake_emit):
            main(["--city", "Дніпро", "--city", "Харків", "--source", "badseller"])
        self.assertEqual(seen, ["Театр 057", "Театр 057"])

    def test_sharp_drop_fails_the_run(self):
        with tempfile.TemporaryDirectory() as tmp, contextlib.redirect_stdout(io.StringIO()), \
             contextlib.redirect_stderr(io.StringIO()), \
             patch("tools.ingest.__main__.karabas_status.collect", return_value=([], {"pages_fetched": 1})):
            report_path = Path(tmp) / "report.json"
            report_path.write_text(json.dumps({"sources": [{"city": "Київ", "source": "concert_ua",
                                                            "items": 50}]}), "utf-8")

            def fake_gather_city(city, sources, run_id, reports=None, **_):
                reports.append({"city": city, "source": "concert_ua", "items": 3})
                return None
            with patch("tools.ingest.__main__.gather_city", side_effect=fake_gather_city):
                code = main(["--city", "Київ", "--source", "concert_ua", "--report", str(report_path)])
            self.assertEqual(code, 1)
            saved = json.loads(report_path.read_text("utf-8"))["sources"][0]
            self.assertTrue(saved["error"].startswith("SHARP_DROP"))

    def test_dump_pins_standard_conforming_strings(self):
        with tempfile.TemporaryDirectory() as tmp, contextlib.redirect_stdout(io.StringIO()):
            path = Path(tmp) / "events.sql"
            _write_sql(path, "run", ["select 'a\\b';\n"], 1)
            body = path.read_text("utf-8")
        self.assertIn("begin;\nset local standard_conforming_strings = on;\n", body)

    def test_upsert_respects_manual_withdrawal_and_disabled_source(self):
        from .test_ingest import _item
        sql = emit._insert([_item("concert_ua", "Концерт")], "00000000-0000-0000-0000-000000000001")
        self.assertIn("join public.event_sources s on s.slug=v.slug\nwhere s.enabled", sql)
        self.assertIn("events.import_status='withdrawn' and events.ingest_run_id is null", sql)

    def test_demote_spares_what_another_city_published(self):
        # Karabas показує дніпровську подію й на сторінці Києва: там вона CITY_MISMATCH у черзі.
        from .test_ingest import _item
        copy = _item("karabas", "Концерт")
        copy.stage, copy.reject_reason = "review", "CITY_MISMATCH"
        self.assertEqual(emit.demote_sql([copy], "run", {(copy.source_slug, copy.source_uid)}), [])
        self.assertEqual(len(emit.demote_sql([copy], "run")), 1)

    def test_automatic_withdrawals_carry_run_id(self):
        from .test_ingest import _item
        loser = _item("internet_bilet", "Концерт")
        loser.duplicate_of = ("concert_ua", "winner")
        run = "00000000-0000-0000-0000-000000000009"
        self.assertIn(f"ingest_run_id='{run}'", "".join(emit.duplicates_sql([loser], run)))
        self.assertIn(f"ingest_run_id='{run}'", emit.retire_absent_sql("karabas", "Київ", ["u"], run))


class FetchLimits(unittest.TestCase):
    class _Body:
        def __init__(self, data, encoding=None):
            self.data, self.status = data, 200
            self.headers = {"Content-Encoding": encoding} if encoding else {}

        def read(self, n=-1):
            return self.data[:n] if n >= 0 else self.data

        def __enter__(self):
            return self

        def __exit__(self, *exc):
            return False

    def _get(self, body):
        with patch("tools.ingest.fetch.allowed", return_value=True), \
             patch("tools.ingest.fetch.crawl_delay", return_value=0), \
             patch("tools.ingest.fetch._opener.open", return_value=body):
            return fetch.get("https://example.org", delay=0)

    def test_oversized_and_gzip_bomb_are_refused_without_retry(self):
        import gzip as gz
        with patch("tools.ingest.fetch.MAX_BYTES", 1000):
            plain = self._get(self._Body(b"x" * 2000))
            bomb = self._get(self._Body(gz.compress(b"0" * 100000), "gzip"))
            fine = self._get(self._Body(gz.compress("афіша".encode()), "gzip"))
        self.assertEqual((plain.status, plain.attempts), (413, 1))
        self.assertEqual(bomb.status, 413)
        self.assertEqual((fine.status, fine.body), (200, "афіша"))

    def test_redirect_to_disallowed_host_is_refused(self):
        import urllib.request
        handler = fetch._Redirects()
        req = urllib.request.Request("https://example.org/a")
        with patch("tools.ingest.fetch.allowed", side_effect=lambda u: "example.org" in u):
            self.assertIsNotNone(handler.redirect_request(req, None, 302, "Found", {}, "https://example.org/b"))
            with self.assertRaises(PermissionError):
                handler.redirect_request(req, None, 302, "Found", {}, "https://tracker.example.net/x")
        req.check_robots = False
        with patch("tools.ingest.fetch.allowed", return_value=False):
            self.assertIsNotNone(handler.redirect_request(req, None, 302, "Found", {}, "https://other.net/"))

    def test_bot_page_and_contact_in_every_user_agent(self):
        from . import geocode, venues
        self.assertIn("https://poriad.app/bot", fetch.USER_AGENT)
        self.assertIn("hello@poriad.app", fetch.USER_AGENT)
        for module in (geocode, venues):
            self.assertIn("USER_AGENT", module.__dict__)


class SitemapLinks(unittest.TestCase):
    def test_city_dates_and_stale_slugs(self):
        xml = "".join(f"<url><loc>{u}</loc></url>" for u in [
            "https://badseller.net/afisha/kyiv/a-2026-10-01",         # сьогодні: беремо
            "https://badseller.net/afisha/kyiv/b-2026-10-31",         # межа горизонту: беремо
            "https://badseller.net/afisha/kyiv/h-2026-10-02-1800",    # другий сеанс дня: беремо
            "https://badseller.net/afisha/kyiv/i-2026-10-02-1900-2",  # і його копія: беремо
            "https://badseller.net/afisha/kyiv/j-2026-10-02-18",      # не час: ні
            "https://badseller.net/afisha/kyiv/c-2026-09-30",         # застарілий slug
            "https://badseller.net/afisha/kyiv/d-2026-11-01",         # за горизонтом
            "https://badseller.net/afisha/lviv/e-2026-10-02",         # інше місто
            "https://badseller.net/afisha/kyiv/zal/f-2026-10-02",     # вкладений шлях
            "https://badseller.net/afisha/podiia/g"])                 # без дати
        today = dt.date(2026, 10, 1)
        got = extract.sitemap_links(xml, "https://badseller.net/afisha/kyiv/",
                                    today, today + dt.timedelta(days=30))
        self.assertEqual(got, ["https://badseller.net/afisha/kyiv/a-2026-10-01",
                               "https://badseller.net/afisha/kyiv/h-2026-10-02-1800",
                               "https://badseller.net/afisha/kyiv/i-2026-10-02-1900-2",
                               "https://badseller.net/afisha/kyiv/b-2026-10-31"])


class SitemapSourceIgnoresListing(unittest.TestCase):
    def test_listing_500_does_not_stop_sitemap_source(self):
        """badseller 2026-10-02: список віддавав HTTP 500, sitemap і картки працювали."""
        import dataclasses
        from .sources import by_slug
        source = dataclasses.replace(by_slug("badseller"), horizon_days=40000, detail_ttl_days=0)
        link = "https://badseller.net/afisha/kyiv/x-2090-06-01"
        raw = {"@type": "TheaterEvent", "name": "Вечір", "startDate": "2090-06-01T19:00:00+03:00",
               "url": link, "location": {"name": "Театр", "address": {"streetAddress": "вул. Б, 1"}}}
        asked = []

        def fake_get(url, **kwargs):
            asked.append(url)
            if url == source.listing_urls["Київ"]:
                return Response(url, 500, "")
            if url == source.sitemap_url:
                return Response(url, 200, f"<loc>{link}</loc>")
            return Response(url, 200, html([raw]))

        with patch("tools.ingest.pipeline.get", side_effect=fake_get), \
             patch("tools.ingest.pipeline._sitemaps", {}):
            items, counters = pipeline.harvest(source, "Київ", VenueIndex([], "Київ"))
        self.assertEqual([i.title for i in items], ["Вечір"])
        self.assertIn(source.listing_urls["Київ"], asked)       # розділ статусів читається зі списку
        self.assertNotIn("error", counters)


class RunStats(unittest.TestCase):
    """Зведення для аналітика: лише SELECT, і порожня база — повідомлення, а не падіння."""

    class _Conn:
        def __init__(self, answers):
            self.answers, self.sql = answers, []

        def execute(self, sql, params=()):
            self.sql.append(sql)
            rows = next((r for key, r in self.answers if key in sql), [])
            return types.SimpleNamespace(fetchall=lambda: rows)

    def test_empty_base_says_so(self):
        from .run_stats import build_report
        self.assertIn("НЕМАЄ ДАНИХ", build_report(self._Conn([])))

    def test_report_has_every_section_and_reads_only(self):
        from .run_stats import build_report
        last = ("run-2", dt.datetime(2026, 10, 5, 18, 33))
        conn = self._Conn([
            ("group by run_id order by 2 desc limit 2", [last, ("run-1", dt.datetime(2026, 10, 5, 18, 3))]),
            ("extract(epoch", [(7,)]), ("count(*) from public.events", [(2219,)]),
            ("from private.ingest_runs r join public.event_sources", [
                ("karabas", "Київ", 161, 160, 117, 116, 29, 28, 0, 1, None, None, "253/799", "0", "ЗАБЛОКОВАНО")]),
            ("d.stage = 'duplicate'", [("Копія", "Переможець", "karabas", "2026-10-10",
                                         "https://dnipro.karabas.com/" + "a" * 70, "https://concert.ua/uk/event/b")])])
        text = build_report(conn)
        for part in ("run-2", "за 0.5 год до останнього", "7 хв тому", "2219", "karabas", "Черга перегляду", "без координат",
                     "категорію й майданчик", "злитих дублів", "посилання переможця", "було", "https://concert.ua/uk/event/b", "a" * 70,
                     "253/799", "ЗАБЛОКОВАНО"):
            self.assertIn(part, text)
        self.assertFalse([q for q in conn.sql if not q.lstrip().lower().startswith(("select", "with"))])


class ClaudeProvider(unittest.TestCase):
    """`--agent` за підпискою Max: `claude -p` з промптом у stdin, без ключа API."""

    def test_prompt_goes_through_stdin_with_a_locked_down_cli(self):
        from .agent import Agent
        calls = []

        def fake_run(cmd, **kwargs):
            calls.append((cmd, kwargs))
            return types.SimpleNamespace(returncode=0, stdout='[{"n": 1}]\n', stderr="")

        with patch("tools.ingest.agent.shutil.which", return_value="/bin/claude"), \
             patch("tools.ingest.agent.subprocess.run", fake_run):
            agent = Agent(provider="claude")
            self.assertTrue(agent.ready)
            self.assertEqual(agent.model, "opus")
            self.assertEqual(agent.ask("Питання"), '[{"n": 1}]\n')
        cmd, kwargs = calls[0]
        self.assertEqual(kwargs["input"], "Питання")
        for flag in ("--restricted", "--no-session-persistence", "--strict-mcp-config"):
            self.assertIn(flag, cmd)
        self.assertEqual(cmd[cmd.index("--tools") + 1], "")

    def test_failed_cli_is_an_error_not_an_empty_answer(self):
        from .agent import Agent
        failed = types.SimpleNamespace(returncode=1, stdout="", stderr="Not logged in")
        with patch("tools.ingest.agent.shutil.which", return_value="/bin/claude"), \
             patch("tools.ingest.agent.subprocess.run", return_value=failed):
            with self.assertRaises(RuntimeError):
                Agent(provider="claude").ask("Питання")

    def test_token_with_a_line_break_is_cleaned_and_failures_are_counted(self):
        from .agent import Agent
        seen = []

        def fake_run(cmd, **kwargs):
            seen.append(kwargs["env"].get("CLAUDE_CODE_OAUTH_TOKEN"))
            return types.SimpleNamespace(returncode=1, stdout="", stderr="Invalid auth token")

        with patch("tools.ingest.agent.shutil.which", return_value="/bin/claude"), \
             patch("tools.ingest.agent.subprocess.run", fake_run), \
             patch.dict("os.environ", {"CLAUDE_CODE_OAUTH_TOKEN": "abc\ndef "}):
            agent = Agent(provider="claude")
            with self.assertRaises(RuntimeError):
                agent.ask("Питання")
        self.assertEqual(seen, ["abcdef"])
        self.assertEqual((agent.requests, agent.failures), (1, 1))

    def test_not_ready_without_the_binary(self):
        from .agent import Agent
        with patch("tools.ingest.agent.shutil.which", return_value=None):
            self.assertFalse(Agent(provider="claude").ready)


class CityAndTextNormalisation(unittest.TestCase):
    """Знахідки нічного аналітика 2026-10-04: «Lviv» з dou і `&amp;amp;` у назвах."""

    def test_latin_and_russian_city_names_become_ours(self):
        for raw, ours in (("Lviv", "Львів"), ("Lviv, Ukraine", "Львів"), ("Днепр", "Дніпро"),
                          ("Kyiv", "Київ"), ("Київська область", "Київська область"), ("", "")):
            self.assertEqual(normalize.canonical_city(raw), ours)

    def test_double_escaped_entities_are_decoded(self):
        self.assertEqual(normalize.clean_text("R&amp;amp;D Day"), "R&D Day")
        self.assertEqual(normalize.clean_text("Wine &amp; Talks"), "Wine & Talks")
        self.assertEqual(normalize.clean_text("AT&T"), "AT&T")

    def test_english_city_in_markup_is_not_a_mismatch(self):
        raw = raw_event(location={"@type": "Place", "name": "Hall",
                                  "address": {"streetAddress": "вул. Б, 1", "addressLocality": "Lviv"}})
        item = pipeline._build(raw, Source(slug="x", name="x", base_url="https://example.org",
                               listing_urls={"Львів": "https://example.org"}, weight=.7, crawl_delay=0),
                               "Львів", VenueIndex([], "Львів"), NOW)
        self.assertEqual(item.city, "Львів")
        self.assertNotEqual(item.reject_reason, "CITY_MISMATCH")


class GeocoderNegativeCache(unittest.TestCase):
    def test_not_found_is_asked_again_after_a_month(self):
        from . import geocode
        calls = []

        def fake_get(self, endpoint, query, params):
            calls.append(endpoint)
            return {"features": []} if endpoint == geocode.ENDPOINT else []
        with patch.object(geocode.Geocoder, "_get", fake_get), patch.object(geocode.Geocoder, "_save", lambda self: None):
            g = geocode.Geocoder("Київ", enabled=True)
            key = "Київ|" + geocode.normalize_name(geocode.canonical_street("вул. Нова, 1"))
            now = dt.datetime.now(dt.timezone.utc)
            g._cache = {key: {"v": geocode._RULES_VERSION, "at": (now - dt.timedelta(days=3)).isoformat()}}
            self.assertIsNone(g.lookup_street("вул. Нова, 1"))
            self.assertEqual(calls, [])                                  # свіже «не знайшли» — з кешу
            g._cache = {key: {"v": geocode._RULES_VERSION, "at": (now - dt.timedelta(days=40)).isoformat()}}
            g.lookup_street("вул. Нова, 1")
            self.assertEqual(calls, [geocode.ENDPOINT, geocode.NOMINATIM])   # старе — питаємо знову
            self.assertIn("at", g._cache[key])


class OsmRefresh(unittest.TestCase):
    """Дамп OSM у кеші старіє тижнями: щоденний обхід оновлює його сам, але не ціною псевдоніма."""

    OLD = "2026-09-18T00:00:00Z"

    def run_refresh(self, fresh_names, tmp=None, mirrors_down=False):
        from . import venues
        old = {"osm3s": {"timestamp_osm_base": self.OLD},
               "elements": [{"lat": 48.4, "lon": 35.0, "tags": {"name": "Feels Live"}}]}
        fresh = {"osm3s": {"timestamp_osm_base": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")},
                 "elements": [{"lat": 48.4, "lon": 35.0, "tags": {"name": n}} for n in fresh_names]}
        own = tmp is None
        tmp = tmp or tempfile.mkdtemp()
        self.asked = getattr(self, "asked", 0)
        with patch.object(venues, "CACHE_DIR", Path(tmp)), patch.object(venues, "_refresh_used", False), \
             contextlib.redirect_stderr(io.StringIO()) as err:
            path = venues._cache_path("Дніпро")
            for city in ("Дніпро", "Харків"):
                if own or not venues._cache_path(city).exists():
                    venues._cache_path(city).write_text(json.dumps(old), "utf-8")

            def fake_fetch(city, refresh=False):
                if refresh:
                    self.asked += 1
                    if not mirrors_down:                     # лежачий Overpass: fetch_osm віддає той самий старий
                        venues._cache_path(city).write_text(json.dumps(fresh), "utf-8")
                return json.loads(venues._cache_path(city).read_text("utf-8"))["elements"]
            with patch.object(venues, "fetch_osm", side_effect=fake_fetch), \
                 patch.object(venues, "load_aliases", return_value={"Feels Garden": "Feels Live"}):
                index = venues.build_index("Дніпро")
                venues.build_index("Харків")                 # друге старе місто того ж прогону вже не оновлюється
            on_disk = json.loads(path.read_text("utf-8"))["osm3s"]["timestamp_osm_base"]
        return index, on_disk, err.getvalue()

    def test_overpass_down_is_retried_in_days_and_once_per_run(self):
        tmp = tempfile.mkdtemp()
        self.run_refresh(["Feels Live"], tmp=tmp, mirrors_down=True)
        self.assertEqual(self.asked, 1)                      # одна спроба за прогін (Дніпро)
        self.run_refresh(["Feels Live"], tmp=tmp, mirrors_down=True)
        self.assertEqual(self.asked, 2)                      # Дніпро на паузі — черга Харкова
        self.run_refresh(["Feels Live"], tmp=tmp, mirrors_down=True)
        self.assertEqual(self.asked, 2)                      # обидва на паузі після невдачі

    def test_old_dump_is_refreshed(self):
        index, on_disk, _ = self.run_refresh(["Feels Live", "Новий клуб"])
        self.assertEqual(self.asked, 1)                      # Харків — у наступному прогоні
        self.assertIsNotNone(index.match("Новий клуб"))
        self.assertNotEqual(on_disk, self.OLD)

    def test_refresh_that_loses_an_alias_is_rejected(self):
        index, on_disk, err = self.run_refresh(["Інший заклад"])             # обʼєкта «Feels Live» у свіжому нема
        self.assertIsNotNone(index.match("Feels Garden"))                   # псевдонім живий на старому дампі
        self.assertEqual(on_disk, self.OLD)
        self.assertIn("губить псевдоніми", err)


class DetailCache(unittest.TestCase):
    """badseller: 1720 карток × 1,5 с — це й був обхід на годину; свіжі картки читаються з диска,
    крім тих, що розділ «Скасовано й перенесено» назвав змінившимися."""

    def setUp(self):
        import dataclasses
        from .sources import by_slug
        self.source = dataclasses.replace(by_slug("badseller"), horizon_days=40000, detail_ttl_days=2)
        self.link = "https://badseller.net/afisha/kyiv/x-2090-06-01"
        self.changed = "https://badseller.net/afisha/kyiv/y-2020-01-01"      # slug поза sitemap-вікном
        self.listing = (f'<section><h2>{self.source.status_heading}</h2>'
                        f'<ul><li><a href="/afisha/kyiv/y-2020-01-01">Y</a></li></ul></section>')
        self.asked = []

        self.lastmod, self.name = None, "Вечір"

        def card(url, status="EventScheduled"):
            return {"@type": "TheaterEvent", "name": f"{self.name} " + url[-4:], "startDate": "2090-06-01T19:00:00+03:00",
                    "url": url, "eventStatus": f"https://schema.org/{status}",
                    "location": {"name": "Театр", "address": {"streetAddress": "вул. Б, 1"}}}

        def fake_get(url, **kwargs):
            self.asked.append(url)
            if url == self.source.listing_urls["Київ"]:
                return Response(url, self.listing_status, self.listing)
            if url == self.source.sitemap_url:
                mod = f"<lastmod>{self.lastmod}</lastmod>" if self.lastmod else ""
                return Response(url, 200, f"<url><loc>{self.link}</loc>{mod}</url>")
            return Response(url, 200, html([card(url)]))
        self.fake_get, self.listing_status = fake_get, 200

    def harvest(self, now):
        with patch("tools.ingest.pipeline.get", side_effect=self.fake_get), \
             patch("tools.ingest.pipeline._sitemaps", {}), \
             patch("tools.ingest.pipeline.CACHE_DIR", self.cache_dir):
            return pipeline.harvest(self.source, "Київ", VenueIndex([], "Київ"), now=now)

    def test_card_is_read_from_disk_until_it_expires(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.cache_dir = Path(tmp)
            first, _ = self.harvest(NOW)
            self.asked.clear()
            again, counters = self.harvest(NOW + dt.timedelta(days=1))
            self.assertEqual(sorted(i.title for i in again), sorted(i.title for i in first))
            self.assertNotIn(self.link, self.asked)
            self.assertEqual(counters["cached"], 1)
            self.harvest(NOW + dt.timedelta(days=3))
            self.assertIn(self.link, self.asked)

    def test_status_failure_reads_live_but_keeps_the_shared_cache(self):
        # Кеш спільний для всіх міст джерела: збій розділу статусів у Києві не має стерти картки Одеси.
        other = "https://badseller.net/afisha/odesa/z-2090-06-01"
        with tempfile.TemporaryDirectory() as tmp:
            self.cache_dir = Path(tmp)
            self.harvest(NOW)
            path = Path(tmp) / "details_badseller.json"
            data = json.loads(path.read_text("utf-8"))
            data[other] = {"at": NOW.isoformat(), "events": []}
            path.write_text(json.dumps(data), "utf-8")
            self.listing_status, self.asked = 500, []
            self.harvest(NOW + dt.timedelta(hours=1))
            self.assertIn(self.link, self.asked)                     # без статусів — наживо
            self.assertIn(other, json.loads(path.read_text("utf-8")))

    def test_sitemap_network_failure_is_a_source_error_not_a_crash(self):
        def broken(url, **kwargs):
            if url == self.source.sitemap_url:
                raise OSError("timed out")
            return self.fake_get(url, **kwargs)
        with tempfile.TemporaryDirectory() as tmp, \
             patch("tools.ingest.pipeline.get", side_effect=broken), \
             patch("tools.ingest.pipeline._sitemaps", {}), patch("tools.ingest.pipeline.CACHE_DIR", Path(tmp)):
            self.listing = ""                                         # без скасованих: самі лише картки sitemap
            items, counters = pipeline.harvest(self.source, "Київ", VenueIndex([], "Київ"), now=NOW)
        self.assertEqual(items, [])
        self.assertEqual(counters["error"], "sitemap: timed out")

    def test_card_of_a_near_event_is_read_more_often(self):
        self.link = "https://badseller.net/afisha/kyiv/x-2026-09-14"       # NOW — 2026-09-11: за 3 дні
        with tempfile.TemporaryDirectory() as tmp:
            self.cache_dir = Path(tmp)
            self.harvest(NOW)
            self.asked.clear()
            self.harvest(NOW + dt.timedelta(hours=12))
            self.assertNotIn(self.link, self.asked)         # ще не старший за добу
            self.harvest(NOW + dt.timedelta(hours=30))
            self.assertIn(self.link, self.asked)            # далека картка (x-2090) того ж віку лишилась би в кеші

    def test_changed_cards_come_first_live_and_beyond_the_sitemap_window(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.cache_dir = Path(tmp)
            self.harvest(NOW)
            self.asked.clear()
            _, counters = self.harvest(NOW + dt.timedelta(hours=1))
            self.assertIn(self.changed, self.asked)                 # живий, хоч і кеш свіжий
            self.assertNotIn(self.link, self.asked)                 # звичайна картка — з кешу
            self.assertEqual(counters["status_links"], 1)

    @patch("tools.ingest.pipeline.DETAIL_AUDIT", 0)
    def test_lastmod_decides_when_a_card_is_read_again(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.cache_dir = Path(tmp)
            self.lastmod = "2020-01-01"
            self.harvest(NOW)
            self.asked.clear()
            self.harvest(NOW + dt.timedelta(days=1))
            self.assertNotIn(self.link, self.asked)         # lastmod старіший за день збереження
            self.lastmod = NOW.date().isoformat()           # змінена в день збереження або пізніше
            self.harvest(NOW + dt.timedelta(days=1))
            self.assertIn(self.link, self.asked)

    def test_audit_reports_a_card_that_changed_without_lastmod(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.cache_dir = Path(tmp)
            self.lastmod = "2020-01-01"
            self.harvest(NOW)
            self.asked.clear()
            self.name = "Інша назва"
            with patch("tools.ingest.pipeline.DETAIL_AUDIT", 10):
                items, counters = self.harvest(NOW + dt.timedelta(days=1))
            self.assertIn(self.link, self.asked)
            self.assertEqual(counters["audit_stale"], [self.link])
            self.assertTrue(any("Інша назва" in i.title for i in items))     # береться свіже

    def test_unreadable_status_section_disables_the_cache(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.cache_dir = Path(tmp)
            self.harvest(NOW)
            self.asked.clear()
            self.listing_status = 500
            items, counters = self.harvest(NOW + dt.timedelta(hours=1))
            self.assertIn(self.link, self.asked)                    
            self.assertEqual(counters["cached"], 0)
            self.assertNotIn("error", counters)


class CrawlRunsSourcesInParallel(unittest.TestCase):
    def test_sources_overlap_but_cities_of_one_source_do_not(self):
        import time
        from .__main__ import Crawl
        from .sources import by_slug
        a, b = by_slug("karabas"), by_slug("concert_ua")
        active, overlap, per_source = {}, [], []

        def fake_harvest(source, city, index, **kwargs):
            active[source.slug] = active.get(source.slug, 0) + 1
            per_source.append(active[source.slug])
            overlap.append(len([n for n in active.values() if n]))
            time.sleep(0.1)
            active[source.slug] -= 1
            return [city], {"source": source.slug}

        with patch("tools.ingest.__main__.harvest", fake_harvest), \
             patch("tools.ingest.__main__.build_index", return_value=None), \
             patch("tools.ingest.__main__.Geocoder", return_value=None):
            crawl = Crawl(["Київ", "Львів"], [a, b], use_photon=False)
            got = {(c, s.slug): crawl.result(c, s)[0] for c in ("Київ", "Львів") for s in (a, b)}
        self.assertEqual(got[("Львів", "karabas")], ["Львів"])
        self.assertEqual(max(per_source), 1)        # один сайт — один запит за раз
        self.assertEqual(max(overlap), 2)           # різні сайти — одночасно


class PerformerDetails(unittest.TestCase):
    """Concert.ua: у списку виконавців немає, у картці є (лайнап стендапу)."""

    def test_lineup_comes_from_detail_and_is_cached(self):
        source = dataclasses.replace(by_slug("concert_ua"), catalogs=None, detail_path=None)
        link = "https://concert.ua/uk/event/x"
        listed = {"@type": "MusicEvent", "name": "Стендап у підвалі", "startDate": "2090-06-01T19:00:00+03:00",
                  "endDate": "2090-06-01T21:00:00+03:00", "url": link, "workPerformed": {"name": "Стендап у підвалі"},
                  "location": {"name": "Бочка", "address": {"addressLocality": "Київ"}}}
        detail = {**listed, "performer": [{"@type": "Person", "name": "Арсен Пучков "},
                                          {"@type": "Person", "name": "Раміль Янгулов"}]}
        calls = []

        def fake_get(url, **kwargs):
            calls.append(url)
            return Response(url, 200, html([detail if url == link else listed]))

        with tempfile.TemporaryDirectory() as tmp, \
             patch("tools.ingest.pipeline.PERFORMER_CACHE", Path(tmp) / "p.json"), \
             patch("tools.ingest.pipeline.get", side_effect=fake_get):
            items, counters = pipeline.harvest(source, "Київ", VenueIndex([], "Київ"))
            again, _ = pipeline.harvest(source, "Київ", VenueIndex([], "Київ"))
        self.assertEqual([a.name for a in items[0].artists], ["Арсен Пучков", "Раміль Янгулов"])
        self.assertEqual([a.name for a in again[0].artists], ["Арсен Пучков", "Раміль Янгулов"])
        self.assertEqual(counters["performer_pages"]["fetched"], 1)
        self.assertEqual(calls.count(link), 1)            # другий прогін узяв із кешу

    def test_other_sessions_on_the_card_join_the_crawl(self):
        # Каталог дає плитку з найближчим сеансом; картка — усі сеанси вистави й добірку інших подій.
        place = {"name": "Planetarium Noosphere"}
        show = lambda day: {"@type": "Event", "name": "Галактика", "location": place,
                            "url": f"https://concert.ua/uk/event/galaktika-{day}", "startDate": f"2090-06-{day}T16:00:00+03:00"}
        other = {"@type": "Event", "name": "Динозаври", "location": place, "url": "https://concert.ua/uk/event/dino-01",
                 "startDate": "2090-06-01T10:00:00+03:00"}
        listed = {**show("12"), "_poruch_category": "kids"}
        with tempfile.TemporaryDirectory() as tmp, \
             patch("tools.ingest.pipeline.PERFORMER_CACHE", Path(tmp) / "p.json"), \
             patch("tools.ingest.pipeline.get", return_value=Response("x", 200, html([show("12"), show("18"), show("29"), other]))):
            raws = [dict(listed)]
            pipeline._enrich_performers(raws, by_slug("concert_ua"), NOW, {})
            again = [dict(listed)]
            pipeline._enrich_performers(again, by_slug("concert_ua"), NOW, {})        # з кешу — те саме
        for got in (raws, again):
            self.assertEqual([r["url"][-2:] for r in got], ["12", "18", "29"])
            self.assertEqual({r.get("_poruch_category") for r in got}, {"kids"})

    def test_performer_cache_keeps_what_another_thread_wrote_meanwhile(self):
        # Concert.ua й Internet-Bilet ділять файл і йдуть паралельно: запис одного не стирає нове від іншого.
        raw = {"@type": "MusicEvent", "name": "Вечір", "url": "https://concert.ua/uk/event/a"}
        with tempfile.TemporaryDirectory() as tmp:
            cache = Path(tmp) / "p.json"

            def fake_get(url, **kwargs):          # поки ця картка читається, інший потік дописав свою
                cache.write_text(json.dumps({"https://x/other": {"at": NOW.isoformat(), "performer": None}}), "utf-8")
                return Response(url, 200, html([{**raw, "performer": {"name": "Хтось"}}]))
            with patch("tools.ingest.pipeline.PERFORMER_CACHE", cache), \
                 patch("tools.ingest.pipeline.get", side_effect=fake_get):
                pipeline._enrich_performers([dict(raw)], by_slug("concert_ua"), NOW, {})
            self.assertEqual(sorted(json.loads(cache.read_text("utf-8"))),
                             ["https://concert.ua/uk/event/a", "https://x/other"])

    def test_card_text_feeds_artists_but_not_description(self):
        """Internet-Bilet: JSON-LD без опису, виконавці в `descr-unified`. Опис у базі лишається порожнім."""
        source = dataclasses.replace(by_slug("internet_bilet"), catalogs=None, detail_path=None)
        link = "https://kyiv.internet-bilet.ua/uk/events/1/x"
        raw = {"@type": "ComedyEvent", "name": "Вечір", "startDate": "2090-06-01T19:00:00+03:00",
               "endDate": "2090-06-01T21:00:00+03:00", "url": link,
               "location": {"name": "Бочка", "address": {"addressLocality": "Київ"}}}
        card = ('<div class="descr-unified"><p>Виступає Богдан Боярин.</p></div>'
                'Придбати квиток на Вечір')

        def fake_get(url, **kwargs):
            return Response(url, 200, html([raw]) + (card if url == link else ""))

        with tempfile.TemporaryDirectory() as tmp, \
             patch("tools.ingest.pipeline.PERFORMER_CACHE", Path(tmp) / "p.json"), \
             patch("tools.ingest.pipeline.get", side_effect=fake_get):
            items, _ = pipeline.harvest(source, "Київ", VenueIndex([], "Київ"))
        self.assertIn("Богдан Боярин", items[0].text)
        self.assertEqual((items[0].description, items[0].description_len), ("", 0))


if __name__ == "__main__":
    unittest.main()
