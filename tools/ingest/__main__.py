"""CLI конвеєра імпорту.

    python3 -m tools.ingest                              # усі міста, суха проба
    python3 -m tools.ingest --city Київ                  # одне місто
    python3 -m tools.ingest --sql out.sql                # усі міста, один файл SQL
    python3 -m tools.ingest --sql-dir out/               # усі міста, SQL по файлу на місто
    python3 -m tools.ingest --source karabas --json out.json

За замовчуванням суха проба: друкує зведення й нічого не змінює. Конвеєр не має доступу до
бази навмисно: обхід чужих сайтів і запис у власну базу — різні за наслідками дії.
"""
from __future__ import annotations

import argparse
import collections
import json
import hashlib
import pathlib
import sys
import uuid

from . import emit, karabas_status, normalize, report
from .agent import Agent, DEFAULT_PROVIDER, PROVIDERS
from .fetch import get
from .geocode import CITY_BBOX, Geocoder
from .pipeline import drop_cross_source_duplicates, harvest, near_miss_pairs
from .sources import by_slug, enabled_sources
from .venues import build_index


# Мінімум розібраних подій, щоб відсутність щось доводила: менше — порожнє місто або зламана сторінка.
RETIRE_MIN_SEEN = 10


def _may_retire(source, items, counters) -> tuple[bool, str]:
    """Чи доводить цей обхід, що зниклі з афіші події скасовано.

    Зняття за відсутністю небезпечне рівно одним: невдалий обхід виглядає як масове скасування.
    Тому воно дозволене лише тоді, коли обхід бачив увесь список джерела й без помилок. Решту
    підстраховує запобіжник на частку в самому SQL (`emit.RETIRE_MAX_SHARE`).
    """
    if source.adapter != "jsonld":
        return False, "адаптер читає вибірку, а не весь список"
    if source.detail_path:
        return False, "картки читаються вибірково"
    if counters.get("error"):
        return False, f"помилка обходу: {counters['error']}"
    if counters.get("catalog_errors"):
        return False, "частина каталогів не відкрилась"
    if counters.get("catalog_capped"):
        return False, "каталог обрізано межею сторінок"
    if len(items) < RETIRE_MIN_SEEN:
        return False, f"розібрано лише {len(items)} подій"
    return True, ""


def run_city(city: str, sources: list, run_id: str, *, agent: Agent | None = None,
             refresh_osm: bool = False, use_photon: bool = True,
             reports: list | None = None, now=None, statement_bytes: int = 0,
             status_by_source: dict[str, list[dict]] | None = None) -> tuple[list, list[str]]:
    """Обхід одного міста всіма його джерелами. Повертає (елементи, частини SQL)."""
    usable = [s for s in sources if city in s.listing_urls]
    if not usable:
        print(f"  {city}: немає ввімкнених джерел", file=sys.stderr)
        return [], []

    print(f"\n{'═' * 62}\n{city}. Джерела: {', '.join(s.slug for s in usable)}")
    index = build_index(city, refresh=refresh_osm)
    print(f"  майданчиків у індексі: {len(index.by_name)}")
    geocoder = Geocoder(city, enabled=use_photon)

    all_items: list = []
    harvested: list[tuple[object, list]] = []
    for source in usable:
        items, counters = harvest(source, city, index, geocoder=geocoder, now=now,
            status_notices=(status_by_source or {}).get(source.slug))
        counters["items"] = len(items)
        if reports is not None:
            counters.update({"city": city, "source": source.slug})
            reports.append(counters)
        all_items += items
        harvested.append((source, items, counters))
        if counters.get("error"):
            print(f"  ── {source.name}: помилка {counters['error']}")
            continue
        matched = sum(1 for i in items if i.latitude is not None)
        pct = f"{100 * matched / len(items):.0f}%" if items else "—"
        print(f"  ── {source.name:<16} у JSON-LD {counters['parsed']:>4}"
              f" · придатних {len(items):>4} · з координатами {matched:>4} ({pct})"
              f" · публікується {counters['published']:>4}")

    if geocoder.calls:
        errs = f", помилок {len(geocoder.errors)}" if geocoder.errors else ""
        print(f"  Photon: {geocoder.calls} запитів{errs}")

    # Агент до дедуплікації: категорія бере участь у виборі канонічної копії.
    if agent is not None:
        changed = agent.classify(all_items)
        if changed or agent.unknown or agent.errors:
            print(f"  Агент: розібрав {changed}, «жодна категорія» {len(agent.unknown)}"
                  f"{', помилок ' + str(len(agent.errors)) if agent.errors else ''}")

    # Дедуплікація до генерації SQL: emit фільтрує за stage у момент виклику.
    all_items = drop_cross_source_duplicates(all_items, {s.slug: s.weight for s in usable}, agent)
    # Після дедуплікації: там агент відповідає про спірні пари.
    if agent is not None and agent.merges:
        merged = sum(1 for *_, same, _ in agent.merges if same)
        print(f"  Агент про пари: злито {merged} із {len(agent.merges)} спірних")
    published = [i for i in all_items if i.stage == "published"]
    duplicates = [i for i in all_items if i.stage == "duplicate"]
    review = [i for i in all_items if i.stage == "review"]
    print(f"  РАЗОМ: {len(published)} до публікації, {len(review)} у черзі, "
          f"{len(duplicates)} злито як дублікати")

    misses = near_miss_pairs(all_items)
    if misses:
        print(f"  ⚠ злито як дублі попри розбіжність координат: {len(misses)}"
              f" — майданчики для aliases.json")
        for a, b, d in misses[:10]:
            print(f"      {d:5.0f} м  «{a.venue_name[:30]}»  {a.venue_how} ↔ {b.venue_how}")

    sql_parts: list[str] = [emit.sources_sql(usable)]
    for source, items, counters in harvested:
        bad = emit.drop_unwritable(items, run_id)
        if bad:
            counters["bad_events"] = counters.get("bad_events", []) + bad
            print(f"  ⚠ {source.slug}: {len(bad)} подій не записати, пропущено (bad_events у звіті)")
        counters["published"] = sum(i.stage == "published" for i in items)
        counters["duplicates"] = sum(i.stage == "duplicate" for i in items)
        if items:
            sql_parts += (emit.bounded_sql(items, lambda rows: emit.venues_sql(rows, city), statement_bytes)
                          + emit.events_sql(items, run_id, max_bytes=statement_bytes))
        sql_parts += emit.withdrawals_sql(source.slug, counters.get("withdrawals", []), run_id)
    sql_parts += emit.duplicates_sql(all_items, run_id)

    # Зняття за відсутністю останнім: вставки вище вже перейменували рядки з новим ключем.
    retired, skipped = [], []
    for source, items, counters in harvested:
        allowed, why = _may_retire(source, items, counters)
        counters["retire"] = "так" if allowed else why
        if allowed:
            sql_parts.append(emit.retire_absent_sql(source.slug, city, [i.source_uid for i in items], run_id))
            retired.append(source.slug)
        else:
            skipped.append(f"{source.slug}: {why}")
    if retired or skipped:
        print(f"  Зняття зниклих з афіші: {', '.join(retired) or 'жодне джерело'}")
        for line in skipped:
            print(f"    не знімаємо, {line}")
    return all_items, sql_parts


# Спад нижче цієї частки від минулого звіту — поломка, а не сезон: у звичний тиждень афіша
# змінюється на відсотки. Малі джерела (менше RETIRE_MIN_SEEN) не порівнюємо — там шум.
DROP_MIN_SHARE = 0.3


def mark_sharp_drops(reports: list[dict], previous: list) -> list[str]:
    """Позначає помилкою джерела, чиїх придатних подій стало менше за DROP_MIN_SHARE від
    минулого звіту (`sources` з нього). Без минулого звіту перевірки немає."""
    was = {(r.get("city"), r.get("source")): r["items"] for r in previous
           if isinstance(r, dict) and isinstance(r.get("items"), int)}
    drops = []
    for r in reports:
        prev = was.get((r.get("city"), r.get("source")))
        if (prev and prev >= RETIRE_MIN_SEEN and "items" in r and not r.get("error")
                and r["items"] < DROP_MIN_SHARE * prev):
            r["error"] = f"SHARP_DROP: {r['items']} придатних проти {prev} минулого разу"
            drops.append(f"{r['city']} · {r['source']}: {r['error']}")
    return drops


def _write_sql(path: pathlib.Path, run_id: str, parts: list[str], count: int,
               max_bytes: int = 0) -> None:
    """Перевіряє цілісність команд і бюджет байтів до запису будь-якого виводу."""
    used = [p for p in parts if p]
    head = (f"-- згенеровано tools.ingest, run_id={run_id}\n"
            "-- Лише підтверджені скасування; відсутність у списку не знімає подію.\n")
    chunks: list[list[str]] = [[]]
    # Запас на обгортки транзакцій і коментарі з номером частини.
    budget = max_bytes - len(head.encode("utf-8")) - 192 if max_bytes else 0
    if max_bytes and (budget <= 0 or any(len(p.encode("utf-8")) > budget for p in used)):
        raise ValueError("SQL-команда з заголовком перевищує --sql-max-bytes")
    size = 0
    for part in used:
        n = len(part.encode("utf-8"))
        if max_bytes and chunks[-1] and size + n > budget:
            chunks.append([])
            size = 0
        chunks[-1].append(part)
        size += n
    outputs = []
    for number, chunk in enumerate(chunks, 1):
        out = path.with_name(f"{path.stem}.{number:02d}{path.suffix}") if max_bytes else path
        comment = f"-- частина {number} з {len(chunks)}. Застосовувати по порядку.\n"
        # Екранування в `_lit` розраховане на стандартні рядки: не покладаємось на налаштування бази.
        content = (head + comment + "begin;\nset local standard_conforming_strings = on;\n"
                   + "".join(chunk) + "commit;\n")
        if max_bytes and len(content.encode("utf-8")) > max_bytes:
            raise ValueError("SQL-файл перевищує --sql-max-bytes")
        outputs.append((out, content))
    path.parent.mkdir(parents=True, exist_ok=True)
    manifest = {"run_id": run_id, "events": count, "files": []}
    for out, content in outputs:
        out.write_text(content, "utf-8")
        manifest["files"].append({"name": out.name, "bytes": len(content.encode("utf-8")),
                                  "sha256": hashlib.sha256(content.encode("utf-8")).hexdigest()})
        print(f"  SQL: {out} ({len(content.encode('utf-8'))} байтів)")
    path.with_suffix(".manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), "utf-8")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="tools.ingest", description="Імпорт подій із зовнішніх джерел")
    ap.add_argument("--city", action="append",
                    help="місто; можна кілька разів. За замовчуванням — усі, які вміють джерела")
    ap.add_argument("--source", action="append", help="slug джерела; можна кілька разів")
    ap.add_argument("--sql", type=pathlib.Path, help="один файл SQL на весь обхід")
    ap.add_argument("--sql-dir", type=pathlib.Path, help="тека для SQL по файлу на місто")
    ap.add_argument("--sql-max-bytes", type=int, default=0,
                    help="різати SQL на частини не більші за N байтів"
                         " (SQL Editor у Supabase не приймає великий запит); 0 — не різати")
    ap.add_argument("--json", type=pathlib.Path, help="куди записати JSON усіх елементів")
    ap.add_argument("--report", type=pathlib.Path, help="JSON-звіт джерел, помилок та скасувань")
    ap.add_argument("--refresh-osm", action="store_true", help="перезавантажити дамп OSM")
    ap.add_argument("--no-photon", action="store_true", help="не геокодувати те, чого немає в OSM")
    ap.add_argument("--agent", action="store_true",
                    help="дати моделі розібрати те, чого не взяли тип і словник")
    ap.add_argument("--agent-provider", choices=sorted(PROVIDERS), default=DEFAULT_PROVIDER,
                    help="постачальник моделі; ключ і модель — зі змінних середовища"
                         " (OPENAI_API_KEY / OPENAI_MODEL)")
    ap.add_argument("--limit", type=int, help="показати не більше N рядків у зведенні")
    ap.add_argument("--no-karabas-status", action="store_true",
                    help="не читати окрему таблицю скасувань/переносів Karabas")
    args = ap.parse_args(argv)
    if args.sql_max_bytes and args.sql_max_bytes < 4096:
        ap.error("--sql-max-bytes має бути 0 або не менше 4096")

    try:
        sources = list(dict.fromkeys(args.source or []))
        sources = [by_slug(s) for s in sources] if sources else enabled_sources()
    except KeyError as exc:
        ap.error(str(exc))
    if not sources:
        print("Немає ввімкнених джерел", file=sys.stderr)
        return 2

    # Міста з самих джерел: додав у sources.py — обходиться. Порядок сталий для порівняння прогонів.
    known = [c for c in dict.fromkeys(c for s in sources for c in s.listing_urls)]
    cities = list(dict.fromkeys(args.city or known))
    unknown = [c for c in cities if c not in known]
    if unknown:
        print(f"Невідомі міста: {unknown}. Доступні: {known}", file=sys.stderr)
        return 2
    # Місто без прямокутника — краще сказати зараз, ніж після обходу.
    missing_bbox = [c for c in cities if c not in CITY_BBOX]
    if missing_bbox:
        print(f"Немає прямокутника в geocode.CITY_BBOX для: {missing_bbox}", file=sys.stderr)
        return 2

    agent = None
    if args.agent:
        agent = Agent(provider=args.agent_provider)
        if not agent.ready:
            print(f"--agent потребує {agent.provider.env_key} у середовищі", file=sys.stderr)
            return 2
        print(f"Агент: {agent.provider.name}, модель {agent.model}")

    # Минулий звіт читається до обходу: цей прогін перезапише файл.
    previous: list = []
    if args.report and args.report.exists():
        try:
            previous = json.loads(args.report.read_text("utf-8")).get("sources") or []
        except (OSError, ValueError, AttributeError):
            print(f"Минулий звіт {args.report} не прочитано: спад не перевіряється", file=sys.stderr)

    run_id = str(uuid.uuid4())
    print(f"Обхід: {', '.join(cities)}\nrun_id={run_id}")

    everything: list = []
    reports: list = []
    per_city: dict[str, tuple[list, list[str]]] = {}
    status_by_source: dict[str, list[dict]] = {}
    if not args.no_karabas_status and any(source.slug == "karabas" for source in sources):
        notices, status_report = karabas_status.collect(get=get, max_pages=3)
        status_by_source["karabas"] = notices
        status_record = {"source": "karabas_status", **status_report,
                         "notices": len(notices)}
        if status_report.get("pages_fetched", 0) == 0:
            status_record["error"] = "STATUS_CHECK_FAILED"
        reports.append(status_record)
        print(f"Karabas status: {len(notices)} точних notices, "
              f"покриття {status_report.get('coverage')}")
    for city in cities:
        items, parts = run_city(city, sources, run_id, agent=agent,
                                refresh_osm=args.refresh_osm, use_photon=not args.no_photon,
                                reports=reports, statement_bytes=max(0, args.sql_max_bytes - 1024),
                                status_by_source=status_by_source)
        per_city[city] = (items, parts)
        everything += items

    for line in mark_sharp_drops(reports, previous):
        print(f"⚠ різкий спад — {line}", file=sys.stderr)

    published = [i for i in everything if i.stage == "published"]
    print("\n" + "═" * 62)
    print(f"УСЬОГО: {len(published)} подій до публікації по {len(cities)} містах")
    print(f"категорії: {dict(collections.Counter(i.category for i in published).most_common())}")
    by_city = collections.Counter(i.city for i in published)
    print(f"по містах: {dict(by_city.most_common())}")

    review = [i for i in everything if i.stage == "review"]
    if review:
        reasons = collections.Counter(i.reject_reason.split()[0] for i in review if i.reject_reason)
        print(f"черга перегляду: {len(review)} — {dict(reasons)}")
        top = collections.Counter(f"{i.city}: {i.venue_name}" for i in review if i.latitude is None)
        print("найчастіші незіставлені майданчики (кандидати в aliases.json):")
        for name, count in top.most_common(args.limit or 6):
            print(f"  {count:3}×  {name[:66]}")

    # Чи вистачає категорій під те, що приносять джерела.
    report.print_category_gaps(report.category_gaps(everything), normalize.CATEGORIES)
    # Чи не бреше джерело про тип: лічильник, не модель.
    report.print_source_health(report.source_health(everything, sources))

    if args.json:
        args.json.write_text(emit.to_json(everything), "utf-8", errors="replace")
        print(f"\nJSON: {args.json}")
    # Завершені події → stale, останньою командою дампу: після upsert, який повернув перенесені.
    # Крок не залежить від міста, тому в кожному файлі по місту він теж є — він ідемпотентний.
    finished = emit.retire_finished_sql()
    if args.sql:
        # Один файл на обхід — одна транзакція. Розбиття по містах лишається для окремих оновлень.
        parts = [p for city in cities for p in per_city[city][1]] + [finished]
        _write_sql(args.sql, run_id, parts, len(published), args.sql_max_bytes)
    elif args.sql_dir:
        args.sql_dir.mkdir(parents=True, exist_ok=True)
        print()
        for city, (items, parts) in per_city.items():
            if not parts:
                continue
            _write_sql(args.sql_dir / f"{city}.sql", run_id, parts + [finished],
                       sum(1 for i in items if i.stage == "published"), args.sql_max_bytes)
    else:
        print("\nСуха проба: нічого не записано. Додайте --sql-dir, щоб отримати SQL.")
    if args.report:
        args.report.write_text(json.dumps({"run_id": run_id, "sources": reports},
                                         ensure_ascii=False, indent=2), "utf-8", errors="replace")
    failed = [r for r in reports if r.get("error")]
    for r in failed:
        print(f"ПОМИЛКА ДЖЕРЕЛА {r.get('city', '—')} · {r.get('source')}: {r['error']}", file=sys.stderr)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
