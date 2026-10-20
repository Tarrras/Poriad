"""Фаза 0 docs/event-offers.md: що кажуть сторінки самих подій. Лише читає базу й сторінки, нічого не пише в базу.

    python3 -m tools.ingest.shadow_checks --env prod     # обхід, дописує журнал
    python3 -m tools.ingest.shadow_checks --report       # зведення за журналом

Кого читаємо щодня: події, за якими стежать (збережені, супутники); зняті за останні 7 днів (чи це справді
скасування); стала панель із 300 живих (чи не пропускає імпорт скасування); живі копії тих і других в інших
продавців. Відповідає на питання 1 специфікації: продавці позначають скасування явно чи просто видаляють
сторінку. Журнал — JSONL поза робочою текою runner-а (`out/` він стирає): `PORUCH_SHADOW` або
~/.poruch/shadow/checks.jsonl.
"""
from __future__ import annotations

import argparse
import collections
import datetime as dt
import json
import os
import pathlib
import sys
import urllib.parse

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent.parent))
from tools import apply_sql  # noqa: E402
from tools.ingest import extract, fetch, normalize, sources  # noqa: E402

JOURNAL = pathlib.Path(os.environ.get("PORUCH_SHADOW", "~/.poruch/shadow/checks.jsonl")).expanduser()
PANEL = 300
SAME_MINUTE = dt.timedelta(minutes=1)
# Сеанс на цю дату живий: EventRescheduled тут означає «перенесено сюди», а не «звідси».
ON = {"EventScheduled", "EventRescheduled", "EventMovedOnline", ""}
GONE_AWAY = {"gone", "redirect_away", "date_missing"}        # сторінка мовчить, але сеансу нема
EXPLICIT = {"cancelled", "postponed", "rescheduled_away"}    # продавець сказав прямо
# Та сама сторінка, один сеанс, інший час: найчастіша зміна (Іво Бобул 23.11, Дніпро: 19:00 → 18:00 без позначки).
SILENT_MOVE = "moved_silent"

SELECT = f"""
with fut as (
  select e.id, s.slug, e.canonical_url as url, e.starts_at, e.import_status, e.updated_at, e.title, e.city
  from public.events e join public.event_sources s on s.id = e.source_id
  -- Злитий рядок (merged_into, 20261021120000) — надгробок, а не знята подія: інакше сотні злиттів пішли б у «зняті».
  where e.origin = 'import' and e.starts_at > now() and e.canonical_url is not null and e.merged_into is null),
base as (
  select f.*, 'watched' as grp from fut f
   where exists (select 1 from public.saved_events v where v.event_id = f.id)
      or exists (select 1 from public.events c where c.companion_of = f.id and c.status = 'published')
  union all
  select f.*, 'withdrawn' from fut f where f.import_status = 'withdrawn' and f.updated_at > now() - interval '7 days'),
panel as (
  select f.*, 'panel' as grp from fut f where f.import_status = 'live'
   order by md5(f.id::text || 'event-offers-phase0') limit {PANEL})
select id, slug, url, starts_at, import_status, grp, null::uuid as twin_of from base
union all select id, slug, url, starts_at, import_status, grp, null from panel
union all
select t.id, t.slug, t.url, t.starts_at, t.import_status, 'twin', b.id from base b
  join fut t on t.id <> b.id and t.import_status = 'live' and t.slug <> b.slug and t.city = b.city
   and abs(extract(epoch from t.starts_at - b.starts_at)) <= 1800 and lower(left(t.title, 12)) = lower(left(b.title, 12))
"""


def _bare(url: str) -> str:
    p = urllib.parse.urlsplit(url or "")
    return f"{p.netloc.removeprefix('www.')}{p.path.rstrip('/')}"


def verdict(status: int, redirected: bool, nodes: list[dict], expected: dt.datetime,
            policy: str, tz: str) -> tuple[str, dict]:
    """Що сторінка каже про сеанс `expected`. Розпродаж — лише позначка: стан він не змінює (рішення 20.10).

    Двійник на TS — supabase/functions/offer-check/verdict.ts (фаза 2): спільні кейси verdict_cases.json."""
    if status in (404, 410):
        return "gone", {}
    if status != 200:
        return "error", {}
    if not nodes:
        return ("redirect_away" if redirected else "no_jsonld"), {}
    dates, statuses, names = [], set(), {}
    for n in nodes:
        start = normalize.parse_datetime(n.get("startDate"), policy, tz)
        prev = normalize.parse_datetime(n.get("previousStartDate"), policy, tz)
        raw = str(n.get("eventStatus") or "").rsplit("/", 1)[-1]
        statuses.add(raw)
        if prev and abs(prev - expected) < SAME_MINUTE and not (start and abs(start - expected) < SAME_MINUTE):
            return "rescheduled_away", {"new_start": start.isoformat() if start else None}
        if start and abs(start - expected) < SAME_MINUTE:
            sold = any("SoldOut" in str(o.get("availability")) for o in extract.offers_of(n))
            kind = "scheduled" if raw in ON else {"EventCancelled": "cancelled",
                                                  "EventPostponed": "postponed"}.get(raw, "other")
            return kind, {"raw": raw, "sold_out": sold}
        if start:
            dates.append(start.isoformat())
            names.setdefault(start.isoformat(), str(n.get("name") or ""))
    if not dates:
        # Дата без часу (dou: `startDate: "2026-10-24"`) про сеанс нічого не каже — це не «зник».
        return "no_dates", {"statuses": sorted(statuses)}
    if len(set(dates)) == 1:
        # Назва — щоб відрізнити перенос від адреси, яку продавець віддав іншій події (R4).
        return SILENT_MOVE, {"new_start": dates[0], "name": names[dates[0]], "statuses": sorted(statuses)}
    return "date_missing", {"dates": sorted(dates)[:5], "statuses": sorted(statuses)}


def _interleave(rows: list[dict]) -> list[str]:
    """Адреси по черзі з різних хостів: пауза одного продавця не тримає решту."""
    by_host = collections.defaultdict(list)
    for url in dict.fromkeys(r["url"] for r in rows):
        by_host[urllib.parse.urlsplit(url).netloc].append(url)
    queues, out = list(by_host.values()), []
    while any(queues):
        out += [q.pop(0) for q in queues if q]
    return out


def run(conn) -> int:
    cols = ("id", "slug", "url", "starts_at", "import_status", "grp", "twin_of")
    rows = [dict(zip(cols, r)) for r in conn.execute(SELECT).fetchall()]
    pages = {}
    for url in _interleave(rows):
        src = sources.by_slug(next(r["slug"] for r in rows if r["url"] == url))
        try:
            resp = fetch.get(url, delay=src.crawl_delay, timeout=30, retries=1)
        except PermissionError:
            resp = fetch.Response(url, -1, "", error="robots")
        nodes = extract.events_from_html(resp.body) if resp.status == 200 else []
        pages[url] = (resp, nodes, bool(resp.final_url) and _bare(resp.final_url) != _bare(url))
    now = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")
    JOURNAL.parent.mkdir(parents=True, exist_ok=True)
    with JOURNAL.open("a", encoding="utf-8") as out:
        for r in rows:
            resp, nodes, redirected = pages[r["url"]]
            src = sources.by_slug(r["slug"])
            kind, detail = verdict(resp.status, redirected, nodes, r["starts_at"], src.tz_policy, src.time_zone)
            out.write(json.dumps({
                "at": now, "event": str(r["id"]), "group": r["grp"], "twin_of": r["twin_of"] and str(r["twin_of"]),
                "slug": r["slug"], "url": r["url"], "starts_at": r["starts_at"].isoformat(),
                "db": r["import_status"], "http": resp.status, "final_url": resp.final_url,
                "redirected": redirected, "verdict": kind, **detail,
                **({"error": resp.error[:200]} if resp.error else {})}, ensure_ascii=False) + "\n")
    print(f"{len(rows)} рядків, {len(pages)} сторінок → {JOURNAL}")
    return 0


def report(lines: list[dict]) -> str:
    """Зведення: останній обхід, відповідь на питання 1, що пропускає імпорт, блокування за хостами."""
    if not lines:
        return f"Журнал порожній: {JOURNAL}"
    days = sorted({l["at"][:10] for l in lines})
    last_at = max(l["at"] for l in lines)
    last = [l for l in lines if l["at"] == last_at]
    out = [f"Журнал: {len(lines)} перевірок за {len(days)} дн. ({days[0]} … {days[-1]}); останній обхід {last_at}.", ""]
    out.append("== Останній обхід: група × вердикт")
    for grp, c in sorted(collections.Counter((l["group"], l["verdict"]) for l in last).items()):
        out.append(f"  {grp[0]:<10} {grp[1]:<17} {c}")

    latest = {}                                      # подія → останній вердикт її власної сторінки
    for l in sorted(lines, key=lambda l: l["at"]):
        if l["group"] != "twin":
            latest[l["event"]] = l
    withdrawn = [l for l in latest.values() if l["db"] == "withdrawn"]
    gone = [l for l in withdrawn if l["verdict"] in GONE_AWAY | EXPLICIT | {SILENT_MOVE}]
    explicit = [l for l in gone if l["verdict"] in EXPLICIT]
    moved = [l for l in gone if l["verdict"] == SILENT_MOVE]
    out += ["", "== Питання 1: зняті події — що на їхніх сторінках (останній вердикт)"]
    for v, c in collections.Counter(l["verdict"] for l in withdrawn).most_common():
        out.append(f"  {v:<17} {c}")
    share = lambda part: f" ({100 * len(part) // len(gone)}%)" if gone else ""
    out.append(f"  Справді нема сеансу: {len(gone)}; продавець сказав прямо: {len(explicit)}{share(explicit)}; "
               f"та сама сторінка, інший час: {len(moved)}{share(moved)}; решта — сторінка мовчки зникла.")

    missed = [l for l in latest.values() if l["db"] == "live" and l["verdict"] in EXPLICIT | GONE_AWAY | {SILENT_MOVE}]
    out += ["", f"== Живі в базі, але сторінка каже інше (пропуск імпорту): {len(missed)}"]
    out += [f"  {l['verdict']:<17} {l['slug']:<14} {l['starts_at'][:16]} {l['url']}" for l in missed[:15]]

    twins = collections.defaultdict(set)
    for l in last:
        if l["group"] == "twin":
            twins[l["twin_of"]].add(l["verdict"])
    pairs = [(latest[e]["verdict"], v) for e, vs in twins.items() if e in latest for v in vs]
    out += ["", "== Копії в інших продавців: вердикт події → вердикт копії (останній обхід)"]
    for (a, b), c in collections.Counter(pairs).most_common(12):
        out.append(f"  {a:<17} → {b:<17} {c}")

    out += ["", "== Помилки й блокування за хостами (усі перевірки)"]
    hosts = collections.defaultdict(collections.Counter)
    for l in lines:
        hosts[urllib.parse.urlsplit(l["url"]).netloc.split(".", 1)[-1]][l["verdict"] == "error"] += 1
    for host, c in sorted(hosts.items()):
        out.append(f"  {host:<22} помилок {c[True]} з {c[True] + c[False]}")
    sold = [l for l in lines if l.get("sold_out")]
    out.append(f"\nРозпродано на сторінці (стан не міняє): {len(sold)} з {len(lines)} перевірок.")
    return "\n".join(out)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--env", choices=("dev", "prod"))
    ap.add_argument("--db-url")
    ap.add_argument("--report", action="store_true")
    args = ap.parse_args(argv)
    if args.report:
        lines = [json.loads(l) for l in JOURNAL.read_text("utf-8").splitlines()] if JOURNAL.exists() else []
        print(report(lines))
        return 0
    if not args.env:
        ap.error("обхід потребує --env")
    conn = apply_sql.connect(apply_sql.database_url(args, writing=False), "60s")
    try:
        conn.execute("set default_transaction_read_only = on")
        return run(conn)
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())
