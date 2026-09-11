"""Вивід: SQL для застосування й JSON для перегляду.

SQL навмисно не містить ані source_id, ані organizer_id літералами — вони беруться підзапитом за
slug. Якщо джерело не заведене в public.event_sources або не має синтетичного акаунта, вставка
впаде з зрозумілою помилкою замість того, щоб тихо створити подію-сироту.
"""
from __future__ import annotations

import json

from .pipeline import Item


# Звідки взялася точка — це не косметика: за нею видно, які майданчики варто звірити руками,
# і які з них можна довірливо показувати.
_VENUE_SOURCE = {"alias": "manual", "photon": "photon", "exact": "osm", "contains": "osm"}


def _lit(value) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value)
    return "'" + str(value).replace("'", "''") + "'"


def venues_sql(items: list[Item], city: str) -> str:
    """Кеш майданчиків. ON CONFLICT DO NOTHING: ручна вивірка не перетирається дампом."""
    seen: set[str] = set()
    rows: list[str] = []
    for it in items:
        if it.latitude is None or it.venue_name in seen:
            continue
        seen.add(it.venue_name)
        rows.append(
            "  (" + ",".join([
                _lit(it.venue_name.lower()), "''", _lit(it.venue_display or it.venue_name),
                repr(it.latitude), repr(it.longitude), _lit(city),
                _lit(_VENUE_SOURCE.get(it.venue_how, "osm")),
                _lit(it.venue_ref), repr(it.geo_confidence)]) + ")")
    if not rows:
        return ""
    return ("insert into public.venues"
            " (norm_name,norm_address,display_name,latitude,longitude,city,source,osm_ref,confidence)\nvalues\n"
            + ",\n".join(rows)
            + "\non conflict (norm_name,norm_address) do nothing;\n")


# Скільки подій в одну команду `insert`. Межа не від бази — Postgres проковтне й тисячу — а від
# SQL Editor у Supabase, який відмовляє великому запиту: «Query is too large to be run via the SQL
# Editor». Нарізка по командах дає файли, які можна вставляти в редактор по черзі, і кожна команда
# лишається цілою: різати текст SQL навпіл не можна, бо в описах трапляються і крапка з комою, і
# переноси рядка.
BATCH = 200


def events_sql(items: list[Item], run_id: str, batch: int = BATCH) -> list[str]:
    """Команди `insert` для подій, по `batch` рядків у кожній.

    Повертає список, а не рядок, свідомо: той, хто ділить файл на частини, має різати між
    командами, а не всередині них. Список цю межу зберігає, суцільний текст її втрачає.
    """
    publishable = [i for i in items if i.stage == "published"]
    if not publishable:
        return []
    return [_insert(publishable[i:i + batch], run_id)
            for i in range(0, len(publishable), batch)]


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
                                       # (20260907150000). Раніше тут стояла вигадана одиниця, і
                                       # клієнт чесно малював «Лишилось 1 місце» під чужим концертом.
            _lit(it.image_url),
            _lit("import"),
            f"(select id from public.event_sources where slug={_lit(it.source_slug)})",
            _lit(it.source_uid), _lit(it.canonical_url), _lit(it.dedupe_key),
            repr(it.quality), _lit("live"),
            _lit(it.price_min) if it.price_min is not None else "null",
            _lit(it.is_free), _lit(run_id)]) + ")")

    return (
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
          "  starts_at=excluded.starts_at, ends_at=excluded.ends_at,\n"
          "  image_url=excluded.image_url, canonical_url=excluded.canonical_url,\n"
          "  dedupe_key=excluded.dedupe_key, quality=excluded.quality,\n"
          "  import_status='live', price_min=excluded.price_min, is_free=excluded.is_free,\n"
          "  ingest_run_id=excluded.ingest_run_id, updated_at=now();\n")


def retire_sql(slug: str, run_id: str, city: str) -> str:
    """Подія, якої цей запуск не побачив, більше не проводиться — але не видаляється.

    Її могли зберегти, і порожній збережений запис гірший за позначку «більше не проводиться».

    Чому обмеження за містом обовʼязкове. «Цей запуск не побачив» — твердження рівно про ту
    ділянку, яку запуск обходив. Без `city` умова читається як «усе, чого немає в цьому run_id»,
    і обхід самого Києва знімає з публікації Львів, Харків, Одесу й Дніпро: їхні рядки живі, але
    несуть інший run_id. Помилка тиха — жодного винятку, просто події зникають із застосунку.

    Вада була латентна, бо в базі поки лежить одне місто. Вона спрацювала б рівно тоді, коли
    зʼявилось би друге, тобто на першому ж застосуванні SQL по пʼятьох містах.

    Обмеження звужує ще й у корисний бік: файл одного міста стає самодостатнім. Його можна
    застосувати окремо, і він не чіпає нічого поза своїм містом.
    """
    return (
        "update public.events set import_status='withdrawn', updated_at=now()\n"
        f"where source_id=(select id from public.event_sources where slug={_lit(slug)})\n"
        f"  and city={_lit(city)}\n"
        f"  and import_status='live' and ingest_run_id is distinct from {_lit(run_id)}\n"
        "  and starts_at > now();\n")


def to_json(items: list[Item]) -> str:
    return json.dumps([{
        "title": i.title, "category": i.category, "city": i.city,
        "starts_at": i.starts_at.isoformat(), "ends_at": i.ends_at.isoformat(),
        "venue": i.venue_name, "lat": i.latitude, "lon": i.longitude,
        "venue_match": i.venue_how, "quality": i.quality, "stage": i.stage,
        "reject_reason": i.reject_reason, "price_min": i.price_min, "is_free": i.is_free,
        "url": i.canonical_url,
    } for i in items], ensure_ascii=False, indent=1)
