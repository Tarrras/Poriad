"""Регресійні тести на втрату даних і небезпечний SQL. Без мережі."""
import contextlib
import dataclasses
import datetime as dt
import io
import itertools
import json
import tempfile
from pathlib import Path
import unittest
from unittest.mock import patch

from . import emit, extract, normalize, pipeline
from .__main__ import main, run_city, _write_sql
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
        self.assertNotIn("<> all (array[", sql)

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
        self.assertIn("lower(x.title) = lower(i.title)", sql)
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
        sql = emit.retire_absent_sql("karabas", "Київ", ["u2", "u1", "u1"])
        self.assertIn("e.city='Київ'", sql)
        self.assertIn("slug='karabas'", sql)
        self.assertIn("<> all (array['u1','u2']::text[])", sql)
        self.assertIn("e.ends_at > now()", sql)
        self.assertIn(f"greatest({emit.RETIRE_ALLOWANCE}, {emit.RETIRE_MAX_SHARE}", sql)
        self.assertNotIn("delete", sql.lower())
        self.assertEqual(emit.retire_absent_sql("karabas", "Київ", []), "")

    def test_finished_imports_go_stale_last_and_never_by_delete(self):
        sql = emit.retire_finished_sql()
        self.assertIn("private.retire_finished_imports(interval '7 days')", sql)
        self.assertNotIn("delete", sql.lower())
        with self.assertRaises(ValueError):
            emit.retire_finished_sql(-1)
        with tempfile.TemporaryDirectory() as tmp, contextlib.redirect_stdout(io.StringIO()), \
             patch("tools.ingest.__main__.run_city", return_value=([], ["select 1;\n"])), \
             patch("tools.ingest.__main__.karabas_status.collect", return_value=([], {"pages_fetched": 1})):
            path = Path(tmp) / "events.sql"
            main(["--city", "Київ", "--sql", str(path)])
            body = path.read_text("utf-8")
        self.assertTrue(body.rstrip().endswith(sql.strip() + "\ncommit;"))

    def test_run_city_retires_last_and_only_after_a_full_crawl(self):
        events = [raw_event(name=f"Подія номер {k}", url=f"https://example.org/e{k}") for k in range(12)]
        with patch("tools.ingest.__main__.build_index", return_value=self.index), \
             patch("tools.ingest.pipeline.get", return_value=Response("https://example.org", 200, html(events))), \
             contextlib.redirect_stdout(io.StringIO()):
            _, parts = run_city("Київ", [self.source], "00000000-0000-0000-0000-000000000001",
                                use_photon=False, now=NOW)
        sql = "".join(parts)
        self.assertIn("<> all (array[", sql)
        self.assertGreater(sql.index("<> all (array["), sql.index("insert into public.events"))

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
             patch("tools.ingest.fetch.urllib.request.urlopen", side_effect=[failure, failure, failure]):
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
        parts = emit.events_sql(items, "00000000-0000-0000-0000-000000000001", max_bytes=5000)
        self.assertTrue(all(len(s.encode()) <= 5000 for s in parts))
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


if __name__ == "__main__":
    unittest.main()
