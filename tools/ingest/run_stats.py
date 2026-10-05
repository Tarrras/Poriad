"""Зведення останнього обходу з бази для аналітика (`analyze_run.sh`): лише SELECT-и.

    python3 -m tools.ingest.run_stats --env prod      # текст у stdout
    python3 -m tools.ingest.run_stats --env dev

Аналітик (сесія Claude Code) бази не бачить: він читає цей текст. Так йому не потрібні ні MCP з OAuth
(на runner його нема), ні права на базу, а дані однакові щоразу. Запити — ті, що описані в README,
розділ «Статистика прогонів». Рядок зʼєднання — як у `tools/apply_sql.py` (`--env`, `.env`, секрети).
"""
from __future__ import annotations

import argparse
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent.parent))
from tools import apply_sql  # noqa: E402

PAIRS_LIMIT = 15
VENUES_LIMIT = 20


def _table(header: list[str], rows: list[tuple]) -> str:
    if not rows:
        return "  (порожньо)"
    cells = [[("—" if v is None else str(v)) for v in r] for r in rows]
    widths = [max(len(str(h)), *(len(c[i]) for c in cells)) for i, h in enumerate(header)]
    # Посилання не обрізаємо: з обрізаним аналітик не може їх звірити.
    widths = [w if any(c[i].startswith("http") for c in cells) else min(w, 60) for i, w in enumerate(widths)]
    line = lambda row: "  " + " | ".join(c[:w].ljust(w) for c, w in zip(row, widths))
    return "\n".join([line(header), line(["-" * w for w in widths]), *(line(c) for c in cells)])


def build_report(conn) -> str:
    q = lambda sql, *params: conn.execute(sql, params).fetchall()
    runs = q("select run_id, max(finished_at) from private.ingest_runs where run_id is not null"
             " group by run_id order by 2 desc limit 2")
    if not runs:
        return "НЕМАЄ ДАНИХ: у private.ingest_runs жодного обходу (дамп не дійшов до бази або статистика не пишеться)."
    (last, last_at), prev = runs[0], (runs[1][0] if len(runs) > 1 else None)
    gap = f"записано {runs[1][1]:%Y-%m-%d %H:%M} UTC, за {(last_at - runs[1][1]).total_seconds() / 3600:.1f} год до останнього" \
        if len(runs) > 1 else ""
    age = q("select round(extract(epoch from now() - %s::timestamptz) / 60)", last_at)[0][0]
    events = q("select count(*) from public.events where ingest_run_id = %s", last)[0][0]
    out = [f"Останній обхід: run_id={last}, записано {last_at:%Y-%m-%d %H:%M} UTC ({int(age)} хв тому), "
           f"подій із цим run_id у events: {events}.",
           f"Попередній обхід: {f'run_id={prev}, {gap}' if prev else 'немає (порівняти нема з чим)'}.", ""]

    out += ["== Джерело × місто: останній обхід проти попереднього («було» — попередній обхід)"]
    rows = q("select s.slug, coalesce(r.city,'(статуси Karabas)'), r.parsed, p.parsed, r.published, p.published,"
             " r.merged, p.merged, r.review, p.review, r.error, p.error"
             " from private.ingest_runs r join public.event_sources s on s.id = r.source_id"
             " left join private.ingest_runs p on p.run_id = %s and p.source_id = r.source_id"
             "   and p.city is not distinct from r.city"
             " where r.run_id = %s order by s.slug, r.city", prev, last)
    out += [_table(["джерело", "місто", "parsed", "було", "published", "було", "merged", "було", "review", "було",
                    "error", "було error"], rows), ""]

    out += ["== Черга перегляду за причинами (останній обхід)"]
    out += [_table(["причина", "подій"], q(
        "select split_part(coalesce(i.reject_reason,'—'), ' ', 1), count(*) from private.ingest_items i"
        " join private.ingest_runs r on r.id = i.run_id where r.run_id = %s and i.stage = 'review'"
        " group by 1 order by 2 desc", last)), ""]

    out += [f"== Найчастіші майданчики без координат (NO_GEO; кандидати в aliases.json), топ {VENUES_LIMIT}"]
    out += [_table(["місто", "майданчик", "подій"], q(
        "select r.city, i.raw->>'venue', count(*) from private.ingest_items i"
        " join private.ingest_runs r on r.id = i.run_id"
        " where r.run_id = %s and i.stage = 'review' and i.raw->>'lat' is null"
        "   and i.reject_reason like 'NO_GEO%%'"
        " group by 1, 2 order by 3 desc limit %s", last, VENUES_LIMIT)), ""]

    out += ["== Опубліковані: чим визначено категорію й майданчик, за джерелами"]
    out += [_table(["джерело", "опубліковано", "категорія fallback", "категорія agent", "майданчик photon"], q(
        "select i.raw->>'source', count(*), count(*) filter (where i.raw->>'category_how' = 'fallback'),"
        " count(*) filter (where i.raw->>'category_how' = 'agent'),"
        " count(*) filter (where i.raw->>'venue_match' = 'photon')"
        " from private.ingest_items i join private.ingest_runs r on r.id = i.run_id"
        " where r.run_id = %s and i.stage = 'published' group by 1 order by 2 desc", last)), ""]

    out += [f"== Пари злитих дублів з найбільшою різницею в назвах (до {PAIRS_LIMIT}): копія → переможець"]
    out += [_table(["копія", "переможець", "джерело копії", "початок", "посилання копії", "посилання переможця"], q(
        "select d.raw->>'title', e.title, d.raw->>'source', d.raw->>'starts_at', d.url, e.canonical_url"
        " from private.ingest_items d join private.ingest_runs r on r.id = d.run_id"
        " join public.events e on e.id = d.candidate_event_id"
        " where r.run_id = %s and d.stage = 'duplicate'"
        " order by abs(length(d.raw->>'title') - length(e.title)) desc limit %s", last, PAIRS_LIMIT))]
    return "\n".join(out)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--env", choices=("dev", "prod"), required=True)
    ap.add_argument("--db-url")
    args = ap.parse_args(argv)
    conn = apply_sql.connect(apply_sql.database_url(args, writing=False), "60s")
    try:
        conn.execute("set default_transaction_read_only = on")      # навіть помилка в запиті нічого не змінить
        print(build_report(conn))
    finally:
        conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
