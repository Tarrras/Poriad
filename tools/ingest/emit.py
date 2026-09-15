"""Вивід: SQL для застосування й JSON для перегляду.

Нові джерела реєструються перед імпортом. source_id береться за slug, organizer_id
може бути null для імпортованих подій (міграція 20260907130000). Сеанси мають
окремі source_uid; перехід зі старих URL-ключів зберігає ID записів у базі.
"""
from __future__ import annotations

import json

from .pipeline import Item, occurrence_uid
from .normalize import normalize_name


# Джерело точки показує, які майданчики варто звірити руками.
_VENUE_SOURCE = {"alias": "manual", "photon": "photon", "exact": "osm", "contains": "osm"}


def _lit(value) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value)
    return "'" + str(value).replace("'", "''") + "'"


def sources_sql(sources: list) -> str:
    """Реєструє відсутні джерела, зберігаючи наявні налаштування адміністратора."""
    rows = []
    for source in sources:
        urls = "array[" + ",".join(_lit(u) for u in source.listing_urls.values()) + "]::text[]"
        rows.append("(" + ",".join([_lit(source.slug), _lit(source.name), "'listing_jsonld'",
                    _lit(source.base_url), urls, _lit(source.weight),
                    str(int(source.crawl_delay)), _lit(source.tz_policy),
                    _lit(source.time_zone), _lit(source.enabled)]) + ")")
    return ("insert into public.event_sources "
            "(slug,name,kind,base_url,listing_urls,weight,crawl_delay_seconds,tz_policy,default_time_zone,enabled)\nvalues\n"
            + ",\n".join(rows) + "\non conflict (slug) do nothing;\n") if rows else ""


def venues_sql(items: list[Item], city: str) -> str:
    """Кеш майданчиків. ON CONFLICT DO NOTHING: ручна вивірка не перетирається дампом."""
    seen: set[tuple] = set()
    rows: list[str] = []
    for it in items:
        key = (normalize_name(it.venue_name), normalize_name(it.city + ", " + it.address))
        if it.latitude is None or key in seen or it.venue_how == "source":
            continue
        seen.add(key)
        rows.append(
            "  (" + ",".join([
                _lit(key[0]), _lit(key[1]), _lit(it.venue_display or it.venue_name),
                repr(it.latitude), repr(it.longitude), _lit(it.city),
                _lit(_VENUE_SOURCE.get(it.venue_how, "osm")),
                _lit(it.venue_ref), repr(it.geo_confidence)]) + ")")
    if not rows:
        return ""
    return ("insert into public.venues"
            " (norm_name,norm_address,display_name,latitude,longitude,city,source,osm_ref,confidence)\nvalues\n"
            + ",\n".join(rows)
            + "\non conflict (norm_name,norm_address) do nothing;\n")


# Подій на одну команду `insert`: межа від SQL Editor у Supabase, а не від Postgres. Ріжемо по
# командах, бо текст SQL різати навпіл не можна.
BATCH = 200


def events_sql(items: list[Item], run_id: str, batch: int = BATCH, max_bytes: int = 0) -> list[str]:
    """Команди `insert` для подій, по `batch` рядків у кожній.

    Повертає список, а не рядок, свідомо: той, хто ділить файл на частини, має різати між
    командами, а не всередині них. Список цю межу зберігає, суцільний текст її втрачає.
    """
    publishable = [i for i in items if i.stage == "published"]
    if not publishable:
        return []
    if batch < 1:
        raise ValueError("batch must be positive")
    return [part for i in range(0, len(publishable), batch)
            for part in bounded_sql(publishable[i:i + batch], lambda rows: _insert(rows, run_id), max_bytes)]


def bounded_sql(items: list, render, max_bytes: int) -> list[str]:
    """Ділить записи до рендеру; SQL-рядки з текстом користувача не різати."""
    if not items:
        return []
    sql = render(items)
    if not max_bytes or len(sql.encode("utf-8")) <= max_bytes:
        return [sql] if sql else []
    if len(items) == 1:
        raise ValueError("Один запис SQL перевищує ліміт; збільште --sql-max-bytes")
    middle = len(items) // 2
    return bounded_sql(items[:middle], render, max_bytes) + bounded_sql(items[middle:], render, max_bytes)


def _insert(publishable: list[Item], run_id: str) -> str:
    rows: list[str] = []
    for it in publishable:
        rows.append("  (" + ",".join([
            _lit(str(it.event_id)),
            f"(select organizer_id from public.event_sources where slug={_lit(it.source_slug)})",
            _lit(it.title), _lit(it.description), _lit(it.category),
            _lit(it.city), _lit(it.address),
            repr(it.latitude), repr(it.longitude),
            _lit(it.starts_at.isoformat()), _lit(it.ends_at.isoformat()),
            _lit(it.time_zone),
            "null",                    # місткості в афіші немає — і тепер колонка може це сказати
                                       # (20260907150000): вигадана одиниця малювала «Лишилось 1 місце».
            _lit(it.image_url),
            _lit("import"),
            f"(select id from public.event_sources where slug={_lit(it.source_slug)})",
            _lit(it.source_uid), _lit(it.canonical_url), _lit(it.dedupe_key),
            repr(it.quality), _lit("live"),
            _lit(it.price_min) if it.price_min is not None else "null",
            _lit(it.is_free), _lit(run_id)]) + ")")

    return ("".join(_adopt_identity(it) for it in publishable) + _adopt_moved_urls(publishable) +
        "insert into public.events (\n"
        "  id,organizer_id,title,description,category,city,address,latitude,longitude,\n"
        "  starts_at,ends_at,time_zone,capacity,image_url,\n"
        "  origin,source_id,source_uid,canonical_url,dedupe_key,quality,import_status,\n"
        "  price_min,is_free,ingest_run_id)\nvalues\n"
        + ",\n".join(rows)
        + "\non conflict (source_id,source_uid) where source_id is not null do update set\n"
          "  title=excluded.title, description=excluded.description, category=excluded.category,\n"
          "  city=excluded.city, address=excluded.address,\n"
          "  latitude=excluded.latitude, longitude=excluded.longitude,\n"
          "  starts_at=excluded.starts_at, ends_at=excluded.ends_at, time_zone=excluded.time_zone,\n"
          "  image_url=excluded.image_url, canonical_url=excluded.canonical_url,\n"
          "  dedupe_key=excluded.dedupe_key, quality=excluded.quality,\n"
          "  import_status='live', price_min=excluded.price_min, is_free=excluded.is_free,\n"
          "  ingest_run_id=excluded.ingest_run_id, updated_at=now();\n")


def _adopt_identity(it: Item) -> str:
    """Зберігає id подій у базі (і посилання збережених) при зміні UID."""
    old_uid = occurrence_uid(it.canonical_url, it.previous_start) if it.previous_start else it.canonical_url
    old_start = it.previous_start or it.starts_at
    same_key = (
        "update public.events e set source_uid=" + _lit(it.source_uid) + "\n"
        f"where e.source_id=(select id from public.event_sources where slug={_lit(it.source_slug)})\n"
        f"  and e.source_uid in ({_lit(old_uid)},{_lit(it.canonical_url)})\n"
        f"  and e.starts_at={_lit(old_start.isoformat())}::timestamptz\n"
        "  and not exists (select 1 from public.events n where n.source_id=e.source_id\n"
        f"    and n.source_uid={_lit(it.source_uid)});\n")
    return same_key


def _adopt_moved_urls(publishable: list[Item]) -> str:
    """Сеанс, у якого джерело змінило посилання, лишається тим самим рядком: інакше старий
    знімається як зниклий, і збережена людиною подія виглядає скасованою.

    Старий рядок переймає новий ключ за тим самим продавцем, містом, хвилиною, назвою й точкою
    до 30 м; `id` не змінюється. Одна команда на пачку (окремий UPDATE на подію подвоював SQL).
    Обидва `distinct on` обов'язкові, інакше два рядки отримають той самий ключ. Назва через
    `lower()`, а не регекс: класи символів залежать від локалі бази.
    """
    by_source: dict[str, list[Item]] = {}
    for it in publishable:
        if it.latitude is not None and it.longitude is not None:
            by_source.setdefault(it.source_slug, []).append(it)
    parts = []
    for slug, items in by_source.items():
        rows = ",\n".join(
            f"  ({_lit(it.source_uid)}, {_lit(it.canonical_url)}, {_lit(it.city)}, {_lit(it.title)},"
            f" {_lit(it.starts_at.isoformat())}::timestamptz, {it.latitude!r}::float8, {it.longitude!r}::float8)"
            for it in items)
        parts.append(
            "with incoming(uid, url, city, title, starts, lat, lon) as (values\n" + rows + "\n"
            "), matched as (\n"
            "  select distinct on (i.uid) x.id, i.uid from incoming i\n"
            "  join public.events x\n"
            f"    on x.source_id=(select id from public.event_sources where slug={_lit(slug)})\n"
            "   and x.origin='import' and x.import_status='live'\n"
            "   and x.city=i.city and x.starts_at=i.starts\n"
            "   and x.canonical_url <> i.url\n"
            "   and lower(x.title) = lower(i.title)\n"
            "   and abs(x.latitude - i.lat) < 0.0003 and abs(x.longitude - i.lon) < 0.0003\n"
            "  where not exists (select 1 from public.events n\n"
            "                    where n.source_id=x.source_id and n.source_uid=i.uid)\n"
            "  order by i.uid, x.updated_at desc, x.id\n"
            "), picked as (\n"
            "  select distinct on (id) id, uid from matched order by id, uid\n"
            ")\n"
            "update public.events e set source_uid=p.uid from picked p where e.id=p.id;\n")
    return "".join(parts)


def withdrawals_sql(slug: str, notices: list[dict], run_id: str) -> list[str]:
    """Лише явне скасування чи перенесення, ніколи не відсутність у списку."""
    parts = []
    for notice in notices:
        url, start = notice["url"], notice["starts_at"]
        # Без дати сеансу чіпаємо лише старий ключ за URL: не можна скасувати всі сеанси сторінки.
        target = (f"canonical_url={_lit(url)} and starts_at={_lit(start)}::timestamptz"
                  if start else f"source_uid={_lit(url)}")
        parts.append(
            "update public.events set import_status='withdrawn', updated_at=now(),\n"
            f"  ingest_run_id={_lit(run_id)}\n"
            f"where source_id=(select id from public.event_sources where slug={_lit(slug)})\n"
            f"  and origin='import' and ({target});\n")
    return parts


def duplicates_sql(items: list[Item], run_id: str) -> list[str]:
    """Знімає старий дублікат лише після вставки обраної заміни."""
    parts = []
    for it in items:
        if not it.duplicate_of:
            continue
        slug, uid = it.duplicate_of
        starts = [it.starts_at]
        if it.previous_start:
            starts.append(it.previous_start)
        time_condition = " or ".join(f"e.starts_at={_lit(t.isoformat())}::timestamptz" for t in starts)
        parts.append(
            "update public.events e set import_status='withdrawn', updated_at=now()\n"
            f"where e.source_id=(select id from public.event_sources where slug={_lit(it.source_slug)})\n"
            f"  and e.canonical_url={_lit(it.canonical_url)} and ({time_condition})\n"
            "  and exists (select 1 from public.events w\n"
            f"    where w.source_id=(select id from public.event_sources where slug={_lit(slug)})\n"
            f"    and w.source_uid={_lit(uid)} and w.import_status='live'\n"
            f"    and w.ingest_run_id={_lit(run_id)});\n")
    return parts


# Скільки подій джерела в місті можна зняти за відсутністю за обхід. Звична плинність до 4%;
# зламаний парсер дає майже 100%, і зняття не відбувається. П'ять дозволено завжди для малих міст.
RETIRE_MAX_SHARE = 0.3
RETIRE_ALLOWANCE = 5


def retire_absent_sql(slug: str, city: str, seen_uids: list[str]) -> str:
    """Знімає живі майбутні події, яких цей обхід не бачив (ні опублікованих, ні на перевірці, ні
    дублікатів). Команда після вставок міста: перехід на новий ключ уже перейменував рядки.
    Знімається, а не видаляється: збережена подія лишається з позначкою.
    """
    if not seen_uids:
        return ""
    seen = ",".join(_lit(uid) for uid in sorted(set(seen_uids)))
    return (
        "with scope as (\n"
        "  select e.id, e.source_uid from public.events e\n"
        f"  where e.source_id=(select id from public.event_sources where slug={_lit(slug)})\n"
        f"    and e.city={_lit(city)} and e.origin='import' and e.import_status='live'\n"
        "    and e.ends_at > now()\n"
        "), gone as (\n"
        f"  select id from scope where source_uid <> all (array[{seen}]::text[])\n"
        ")\n"
        "update public.events set import_status='withdrawn', updated_at=now()\n"
        "where id in (select id from gone)\n"
        f"  and (select count(*) from gone) <= greatest({RETIRE_ALLOWANCE},"
        f" {RETIRE_MAX_SHARE} * (select count(*) from scope));\n")


def to_json(items: list[Item]) -> str:
    return json.dumps([{
        "source": i.source_slug, "source_uid": i.source_uid, "event_id": str(i.event_id),
        "category_how": i.category_how,
        "duplicate_of": i.duplicate_of,
        "title": i.title, "category": i.category, "city": i.city,
        "starts_at": i.starts_at.isoformat(), "ends_at": i.ends_at.isoformat(),
        "venue": i.venue_name,
        # З чим зіставили: без цього рецензію збігів не зробити.
        "venue_display": i.venue_display,
        "address": i.address, "lat": i.latitude, "lon": i.longitude,
        "venue_match": i.venue_how, "quality": i.quality, "stage": i.stage,
        "reject_reason": i.reject_reason, "price_min": i.price_min, "is_free": i.is_free,
        "url": i.canonical_url,
    } for i in items], ensure_ascii=False, indent=1)
