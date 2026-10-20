"""Згенерований дампом SQL проти справжньої схеми: dev, одна транзакція, відкат.

    python3 -m tools.ingest.sql_check                 # SUPABASE_DB_URL_DEV із середовища чи .env
    python3 -m tools.ingest.sql_check out/x.sql ...   # ще й повторне застосування живих дампів не множить подій

Замінив PGlite-тест зі зменшеною схемою (test_sql.mjs): з 20261021120000 події й пропозиції пише функція бази
`private.ingest_offers`, тож перевіряти можна лише на справжній схемі. Джерела тестові (`t_*`): зняття за
відсутністю й запобіжник рахують лише свої пропозиції, справжні дані dev не зачіпаються, усе відкочується.
"""
from __future__ import annotations

import dataclasses
import datetime as dt
import pathlib
import re
import sys
import uuid

from . import emit, pipeline
from .artists import Artist
from .sources import by_slug
from .test_regressions import NOW, raw_event
from .venues import VenueIndex

RUN = "00000000-0000-0000-0000-000000000001"
DEV_REF = "ojadoyxeahepycpmjuvf"
INDEX = VenueIndex([], "Київ", {"Зал": {"lat": 50.45, "lon": 30.53}})


def _source(slug: str, weight: float = 0.8):
    # Політика поясу Concert.ua (`source`) у всіх: час з raw_event читається як є.
    return dataclasses.replace(by_slug("concert_ua"), slug=slug, weight=weight, catalogs=None)


CONCERT, BILET, TICKETS, BAD = _source("t_concert"), _source("t_bilet", 0.7), _source("t_tickets"), _source("t_bad")
KARABAS = _source("t_karabas", 0.7)


def _build(source, **raw):
    item = pipeline._build(raw_event(**raw), source, "Київ", INDEX, NOW)
    item.stage, item.quality = "published", .8
    return item


def _moved(item, **changes):
    moved = dataclasses.replace(item, **changes)
    moved.source_uid = pipeline.occurrence_uid(moved.canonical_url, moved.starts_at)
    moved.event_id = uuid.uuid5(pipeline.NAMESPACE, moved.source_slug + "|" + moved.source_uid)
    return moved


def fixture() -> dict:
    a = _build(CONCERT)
    b = _build(CONCERT, startDate="2026-10-18T18:00:00+03:00")
    moved = _moved(b, starts_at=b.starts_at + dt.timedelta(days=1), ends_at=b.ends_at + dt.timedelta(days=1),
                   previous_start=b.starts_at)
    # Перенесена подія лишає старий id, а артист має знайти саме її (МУР у Дніпрі 2026-10-08).
    # Повтор імені в події не має валити дамп (`on conflict do update` двічі в один рядок).
    moved.artists = [Artist("МУР"), Artist("МУР")]
    loser = dataclasses.replace(moved, source_slug=BILET.slug, previous_start=a.starts_at, stage="duplicate",
                                duplicate_of=(CONCERT.slug, moved.source_uid))
    at = "2026-10-20T18:30:00+03:00"
    tb = dict(startDate=at, endDate="2026-10-20T20:30:00+03:00")
    before = _build(TICKETS, name="П'ята ранку", url="https://example.org/teatr-2", **tb)
    after = _build(TICKETS, name="П'ята ранку", url="https://example.org/teatr-3", **tb)
    other = _build(TICKETS, name="Інша вистава", url="https://example.org/teatr-9", **tb)

    def bs(name, url, at="2026-10-24T19:00:00+03:00"):
        return _build(BAD, name=name, url=url, startDate=at, endDate=at[:11] + "21:00:00+03:00")
    bs_old = [bs("Гедда Габлер (Театр на Подолі)", "https://example.org/hedda-old"),
              bs("Моє століття (Театр на Подолі)", "https://example.org/stolittia-old"),
              bs("Allegretto", "https://example.org/allegretto-old", "2026-11-05T19:30:00+02:00"),
              bs("Ручне", "https://example.org/manual-old", "2026-11-06T19:30:00+02:00")]
    bs_new = [bs("Гедда Габлер", "https://example.org/hedda-new"), bs("Процес", "https://example.org/protses-new"),
              bs("«Allegretto»!", "https://example.org/allegretto-new", "2026-11-05T19:30:00+02:00"),
              bs("Ручне", "https://example.org/manual-new", "2026-11-06T19:30:00+02:00")]
    fresh = _build(CONCERT, url="https://example.org/fresh")
    # Тихий перенос: сторінка з одним сеансом показала інший час (Іво Бобул, 19:00 → 18:00).
    future = (dt.datetime.now(dt.timezone.utc) + dt.timedelta(days=30)).replace(hour=16, minute=0, second=0,
                                                                                 microsecond=0)
    bobul = _build(CONCERT, name="Іво Бобул", url="https://example.org/bobul", startDate=future.isoformat(),
                   endDate=(future + dt.timedelta(hours=2)).isoformat())
    bobul.single_session = True
    bobul_moved = _moved(bobul, starts_at=bobul.starts_at - dt.timedelta(hours=1),
                         ends_at=bobul.ends_at - dt.timedelta(hours=1))
    # На три доби раніше — інший показ на сторінці шоу, не перенос: нова пропозиція, стара лишається своєю.
    early = _build(CONCERT, name="Шоу Рано", url="https://example.org/early", startDate=future.isoformat(),
                   endDate=(future + dt.timedelta(hours=2)).isoformat())
    early.single_session = True
    early_moved = _moved(early, starts_at=early.starts_at - dt.timedelta(days=3),
                         ends_at=early.ends_at - dt.timedelta(days=3))
    # Група з двох продавців в одному дампі: одна подія, дві пропозиції.
    pair_w = _build(CONCERT, name="Гурт Пара", url="https://example.org/pair-w", startDate=future.isoformat(),
                    endDate=(future + dt.timedelta(hours=2)).isoformat())
    pair_c = _build(KARABAS, name="Гурт Пара. Концерт", url="https://example.org/pair-c", startDate=future.isoformat(),
                    endDate=(future + dt.timedelta(hours=2)).isoformat())
    pipeline.drop_cross_source_duplicates([pair_w, pair_c], {CONCERT.slug: CONCERT.weight, KARABAS.slug: KARABAS.weight})
    assert pair_c.stage == "duplicate"
    karabas_uids = [f"https://example.org/k{i}" for i in range(10)]
    return {
        "sources": emit.sources_sql([CONCERT, BILET, TICKETS, BAD, KARABAS]),
        "insert": "".join(emit.events_sql([a, b], RUN)),
        "cancel": "".join(emit.withdrawals_sql(CONCERT.slug, [{"url": a.canonical_url,
                                                                "starts_at": a.starts_at.isoformat()}], RUN)),
        "move": "".join(emit.events_sql([moved], RUN)),
        "duplicate": "".join(emit.duplicates_sql([loser], RUN)),
        "uids": [a.source_uid, b.source_uid, moved.source_uid],
        "a_start": a.starts_at.isoformat(), "url": a.canonical_url,
        "move_before": "".join(emit.events_sql([before], RUN)),
        "move_after": "".join(emit.events_sql([after], RUN)),
        "move_other": "".join(emit.events_sql([other], RUN)),
        "move_uids": [before.source_uid, after.source_uid, other.source_uid],
        "retire_after_move": emit.retire_absent_sql(TICKETS.slug, "Київ", [after.source_uid, other.source_uid], RUN),
        "karabas_uids": karabas_uids,
        "bs_old": "".join(emit.events_sql(bs_old, RUN)),
        "bs_new": "".join(emit.events_sql(bs_new, RUN)),
        "bs_old_uids": [i.source_uid for i in bs_old],
        "bs_new_uids": [i.source_uid for i in bs_new],
        "insert_a": "".join(emit.events_sql([a], RUN)),
        "fresh": "".join(emit.events_sql([fresh], RUN)),
        "fresh_uid": fresh.source_uid,
        "retire_one": emit.retire_absent_sql(KARABAS.slug, "Київ", karabas_uids[:9], RUN),
        "retire_mass": emit.retire_absent_sql(KARABAS.slug, "Київ", karabas_uids[:1], RUN),
        "karabas_stats_id": emit.stats_run_id(RUN, KARABAS.slug, "Київ"),
        # TicketsBox: картка показує новий час сеансу, стара пропозиція того ж посилання знімається.
        "tb_replaced": emit.retire_replaced_sql(TICKETS.slug, [after], RUN),
        # За межею обходу (sitemap до horizon_days) відсутність нічого не доводить.
        "retire_until": emit.retire_absent_sql(KARABAS.slug, "Київ", karabas_uids, RUN, until=dt.date(2026, 12, 1)),
        # Колишній сеанс знову в афіші: його обчислений id уже носить перенесена подія.
        "b_again": "".join(emit.events_sql([b], RUN)),
        "bobul": "".join(emit.events_sql([bobul], RUN)),
        "bobul_moved": "".join(emit.events_sql([bobul_moved], RUN)),
        "bobul_uids": [bobul.source_uid, bobul_moved.source_uid], "bobul_moved_start": bobul_moved.starts_at.isoformat(),
        "early": "".join(emit.events_sql([early], RUN)),
        "early_moved": "".join(emit.events_sql([early_moved], RUN)),
        "early_uids": [early.source_uid, early_moved.source_uid],
        "pair": "".join(emit.events_sql([pair_w], RUN) + emit.events_sql([pair_c], RUN)
                        + emit.duplicates_sql([pair_w, pair_c], RUN)),
        "pair_uids": [pair_w.source_uid, pair_c.source_uid],
    }


def _connect():
    import psycopg
    url = __import__("os").environ.get("SUPABASE_DB_URL_DEV")
    if not url:
        env = pathlib.Path(__file__).resolve().parents[2] / ".env"
        for line in env.read_text("utf-8").splitlines() if env.exists() else []:
            if line.startswith("SUPABASE_DB_URL_DEV="):
                url = line.partition("=")[2].strip().strip("\"'")
    if not url or DEV_REF not in url:
        raise SystemExit(f"Потрібен SUPABASE_DB_URL_DEV проєкту {DEV_REF} (у середовищі чи .env)")
    return psycopg.connect(url, autocommit=False)


def check(paths: list[str]) -> None:
    f = fixture()
    conn = _connect()
    q = lambda sql, *args: conn.execute(sql, args).fetchall()
    one = lambda sql, *args: (q(sql, *args) or [(None,)])[0][0]
    status = lambda uid: one("select status from public.event_offers where source_uid=%s", uid)
    event_of = lambda uid: one("select event_id from public.event_offers where source_uid=%s", uid)
    run = lambda key: conn.execute(f[key])
    try:
        conn.execute("set local statement_timeout = '120s'")
        run("sources")
        src = lambda slug: one("select id from public.event_sources where slug=%s", slug)

        def legacy(event_id, slug, uid, url, starts, ends, title="Тестовий концерт", city="Київ", status="live",
                   run_id=RUN):
            """Рядок, якого ще не торкався новий дамп: подія й одна пропозиція, як після міграції."""
            conn.execute(
                "insert into public.events(id,title,description,category,city,address,latitude,longitude,starts_at,"
                "ends_at,time_zone,origin,source_id,source_uid,canonical_url,import_status,ingest_run_id) values"
                " (%s,%s,'','music',%s,'Зал',50.45,30.53,%s,%s,'Europe/Kyiv','import',%s,%s,%s,%s,%s)",
                (event_id, title, city, starts, ends, src(slug), uid, url, status, run_id))
            conn.execute(
                "insert into public.event_offers(event_id,source_id,source_uid,canonical_url,title,starts_at,status,"
                "ingest_run_id) values (%s,%s,%s,%s,%s,%s,%s,%s)",
                (event_id, src(slug), uid, url, title, starts, "withdrawn" if status == "withdrawn" else "live", run_id))

        offers_of = lambda slug: one("select count(*) from public.event_offers where source_id=%s", src(slug))
        a_end = (dt.datetime.fromisoformat(f["a_start"]) + dt.timedelta(hours=3)).isoformat()
        legacy_id = str(uuid.uuid4())
        legacy(legacy_id, CONCERT.slug, f["url"], f["url"], f["a_start"], a_end)
        run("insert"); run("insert")
        assert offers_of(CONCERT.slug) == 2, "повтор дампу не множить пропозицій"
        assert str(event_of(f["uids"][0])) == legacy_id, "старий URL-ключ переймається, id події той самий"
        run("cancel")
        assert status(f["uids"][0]) == "withdrawn" and status(f["uids"][1]) == "live", "явне скасування — лише свій сеанс"
        assert one("select import_status from public.events where id=%s", legacy_id) == "withdrawn", "подія без живих"
        second = event_of(f["uids"][1])
        run("move"); run("move")
        assert offers_of(CONCERT.slug) == 2 and event_of(f["uids"][2]) == second, "явний перенос — та сама пропозиція й подія"
        assert [r[0] for r in q("select a.key from public.event_artists ea join public.artists a on a.id=ea.artist_id"
                                " where ea.event_id=%s", second)] == ["мур"], "артист знайшов перенесену подію"
        # Копія іншого продавця жила окремою подією: тепер вона — пропозиція події переможця, а подія — надгробок.
        bilet_id = str(uuid.uuid4())
        legacy(bilet_id, BILET.slug, f["url"], f["url"], f["a_start"], a_end)
        run("duplicate")
        assert event_of(f["uids"][2]) == second and q(
            "select 1 from public.event_offers where source_id=%s and event_id=%s", src(BILET.slug), second), \
            "копія приєднана до переможця"
        assert str(one("select merged_into from public.events where id=%s", bilet_id)) == str(second), "надгробок копії"
        assert one("select import_status from public.events where id=%s", second) == "live"
        print("SQL: старий ключ, скасування, явний перенос, артисти, копія → пропозиція переможця OK")

        # Зміна посилання не відриває збережене: той самий сеанс під новою адресою — та сама пропозиція.
        run("move_before")
        moved_event = event_of(f["move_uids"][0])
        run("move_after"); run("move_after")
        assert event_of(f["move_uids"][1]) == moved_event and event_of(f["move_uids"][0]) is None, "нове посилання — та сама"
        assert one("select canonical_url from public.events where id=%s", moved_event) == "https://example.org/teatr-3"
        # Зал зник із назви й посилання: та сама. Паралельна вистава сусіднього залу — ні.
        # Автоматично знята стара переймається й оживає; знята вручну (без run_id) — ні.
        run("bs_old")
        hedda, stolittia, allegretto, manual = (event_of(u) for u in f["bs_old_uids"])
        conn.execute("update public.event_offers set status='withdrawn', ingest_run_id=%s where source_uid=%s",
                     (RUN, f["bs_old_uids"][2]))
        conn.execute("update public.event_offers set status='withdrawn', ingest_run_id=null where source_uid=%s",
                     (f["bs_old_uids"][3],))
        run("bs_new")
        assert event_of(f["bs_new_uids"][0]) == hedda
        assert event_of(f["bs_old_uids"][1]) == stolittia and event_of(f["bs_new_uids"][1]) != stolittia
        assert event_of(f["bs_new_uids"][2]) == allegretto and status(f["bs_new_uids"][2]) == "live"
        assert event_of(f["bs_new_uids"][3]) != manual and status(f["bs_old_uids"][3]) == "withdrawn"
        run("move_other")
        assert event_of(f["move_uids"][2]) not in (None, moved_event), "інша назва в ту саму хвилину — окрема подія"
        run("retire_after_move")
        assert status(f["move_uids"][1]) == "live" and status(f["move_uids"][2]) == "live", "перейняте — «бачене»"

        # Зникнення з афіші знімає лише в межах джерела, міста й майбутнього; масове — блокує запобіжник.
        def karabas(uid, city, starts, ends):
            legacy(str(uuid.uuid4()), KARABAS.slug, uid, uid, starts, ends, title="Подія для зняття", city=city)
        for uid in f["karabas_uids"]:
            karabas(uid, "Київ", "2026-11-01T19:00:00+02:00", "2026-11-01T21:00:00+02:00")
        karabas("https://example.org/k-past", "Київ", "2026-09-01T19:00:00+03:00", "2026-09-01T21:00:00+03:00")
        karabas("https://example.org/k-lviv", "Львів", "2026-11-01T19:00:00+02:00", "2026-11-01T21:00:00+02:00")
        now = dt.datetime.now(dt.timezone.utc)
        karabas("https://example.org/k-now", "Київ", (now - dt.timedelta(hours=1)).isoformat(),
                (now + dt.timedelta(hours=2)).isoformat())
        conn.execute("insert into private.ingest_runs(id, source_id, run_id, city, report) values (%s,%s,%s,'Київ','{}')",
                     (f["karabas_stats_id"], src(KARABAS.slug), RUN))
        run("retire_one")
        assert status("https://example.org/k-now") == "live" and status(f["karabas_uids"][9]) == "withdrawn"
        assert all(status(u) == "live" for u in f["karabas_uids"][:9])
        assert status("https://example.org/k-past") == "live" and status("https://example.org/k-lviv") == "live"
        run("retire_mass")
        assert all(status(u) == "live" for u in f["karabas_uids"][:9]), "зламаний обхід нічого не знімає"
        report = one("select report from private.ingest_runs where id=%s", f["karabas_stats_id"])
        assert [report["retire_blocked"], report["retire_gone"], report["retired"]] == [True, 8, 0], report
        karabas("https://example.org/k-far", "Київ", "2027-01-01T19:00:00+02:00", "2027-01-01T21:00:00+02:00")
        run("retire_until")
        assert status("https://example.org/k-far") == "live", "за межею обходу відсутність нічого не доводить"
        assert str(one("select ingest_run_id from public.event_offers where source_uid=%s", f["karabas_uids"][9])) == RUN
        print("SQL: нове посилання, зали badseller, зняття за відсутністю й запобіжник OK")

        # Автоматичне зняття (з run_id) повертається в live; ручне — ні. Вимкнене джерело не пишеться.
        run("insert_a")
        assert status(f["uids"][0]) == "live"
        conn.execute("update public.event_offers set status='withdrawn', ingest_run_id=null where source_uid=%s",
                     (f["uids"][0],))
        run("insert_a")
        assert status(f["uids"][0]) == "withdrawn" and one(
            "select ingest_run_id from public.event_offers where source_uid=%s", f["uids"][0]) is None
        conn.execute("update public.event_sources set enabled=false where slug=%s", (CONCERT.slug,))
        conn.execute("update public.event_offers set status='withdrawn', ingest_run_id=%s where source_id=%s",
                     (RUN, src(CONCERT.slug)))
        run("insert_a"); run("fresh")
        assert status(f["uids"][0]) == "withdrawn" and status(f["fresh_uid"]) is None, "opt-out: нічого не пишеться"
        conn.execute("update public.event_sources set enabled=true where slug=%s", (CONCERT.slug,))
        run("fresh")
        assert status(f["fresh_uid"]) == "live"

        # TicketsBox переніс сеанс без previousStartDate: стара пропозиція того ж посилання знімається.
        for uid, url, starts in (("https://example.org/teatr-3#old", "https://example.org/teatr-3", "2026-11-20T18:00:00+02:00"),
                                 ("https://example.org/teatr-7#x", "https://example.org/teatr-7", "2026-11-20T18:00:00+02:00"),
                                 ("https://example.org/teatr-3#past", "https://example.org/teatr-3", "2026-09-01T18:00:00+03:00")):
            legacy(str(uuid.uuid4()), TICKETS.slug, uid, url, starts,
                   (dt.datetime.fromisoformat(starts) + dt.timedelta(hours=2)).isoformat(), title="П'ята ранку")
        run("tb_replaced")
        assert status("https://example.org/teatr-3#old") == "withdrawn"
        assert status("https://example.org/teatr-7#x") == "live" and status("https://example.org/teatr-3#past") == "live"
        assert status(f["move_uids"][1]) == "live"

        # Колишній сеанс знову в афіші, а його обчислений id носить перенесена подія: нова з випадковим id.
        run("b_again")
        assert event_of(f["uids"][2]) == second and event_of(f["uids"][1]) not in (None, second)
        print("SQL: ручне зняття, opt-out, TicketsBox, зайнятий id OK")

        # Тихий перенос: та сама пропозиція, та сама подія, новий час.
        run("bobul")
        bobul_event = event_of(f["bobul_uids"][0])
        run("bobul_moved")
        assert event_of(f["bobul_uids"][1]) == bobul_event and event_of(f["bobul_uids"][0]) is None, "тихий перенос"
        assert one("select starts_at from public.events where id=%s", bobul_event) == \
            dt.datetime.fromisoformat(f["bobul_moved_start"]), "подія з новим часом"
        run("early")
        run("early_moved")
        assert event_of(f["early_uids"][0]) not in (None, event_of(f["early_uids"][1])), "на раніше — не тихий перенос"
        # Двоє продавців в одному дампі: одна подія, основний — важчий.
        run("pair")
        assert event_of(f["pair_uids"][0]) == event_of(f["pair_uids"][1]) is not None
        assert one("select canonical_url from public.events where id=%s", event_of(f["pair_uids"][0])) == \
            "https://example.org/pair-w"
        print("SQL: тихий перенос і група продавців OK")

        for path in paths:
            # Свою транзакцію дампу прибираємо: інакше її commit зафіксував би й тестові рядки.
            sql = re.sub(r"^(begin|commit);$", "", pathlib.Path(path).read_text("utf-8"), flags=re.M)
            conn.execute(sql)
            before = one("select count(*) from public.events")
            conn.execute(sql)
            assert one("select count(*) from public.events") == before
            print(f"Повтор живого дампу OK: {path} ({before} подій)")
    finally:
        conn.rollback()
        conn.close()
    print("SQL dev: усе відкочено")


if __name__ == "__main__":
    check(sys.argv[1:])
