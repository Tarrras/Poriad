"""Вивід: SQL для застосування й JSON для перегляду.

Нові джерела реєструються перед імпортом. source_id береться за slug, organizer_id
може бути null для імпортованих подій (міграція 20260907130000). Сеанси мають
окремі source_uid; перехід зі старих URL-ключів зберігає ID записів у базі.
"""
from __future__ import annotations

import json
import uuid

from .pipeline import Item, occurrence_uid
from .artists import key as artist_key
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
        row = "  (" + ",".join([
            _lit(key[0]), _lit(key[1]), _lit(it.venue_display or it.venue_name),
            repr(it.latitude), repr(it.longitude), _lit(it.city),
            _lit(_VENUE_SOURCE.get(it.venue_how, "osm")),
            _lit(it.venue_ref), repr(it.geo_confidence)]) + ")"
        try:
            row.encode("utf-8")      # сурогат із відповіді геокодера — пропуск кешу, не падіння дампу
        except UnicodeEncodeError:
            continue
        rows.append(row)
    if not rows:
        return ""
    return ("insert into public.venues"
            " (norm_name,norm_address,display_name,latitude,longitude,city,source,osm_ref,confidence)\nvalues\n"
            + ",\n".join(rows)
            + "\non conflict (norm_name,norm_address) do nothing;\n")


# Подій на одну команду `insert`: межа від SQL Editor у Supabase, а не від Postgres. Ріжемо по
# командах, бо текст SQL різати навпіл не можна.
BATCH = 200


def events_sql(items: list[Item], run_id: str, batch: int = BATCH, max_bytes: int = 0,
               replace_llm: bool = False) -> list[str]:
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
            for part in bounded_sql(publishable[i:i + batch],
                                    lambda rows: _insert(rows, run_id, replace_llm), max_bytes)]


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


def places_sql(items: list[Item]) -> str:
    """Місця (20260925120000): один рядок на точку, назва — з найвищого щабля. Перетираємо назву
    лише щаблем не нижчим за поточний: `manual` з aliases.json дамп із Photon не зіпсує."""
    by_point: dict[tuple, Item] = {}
    for it in items:
        if it.stage != "published" or it.latitude is None:
            continue
        key = (it.latitude, it.longitude)
        if key not in by_point or _PLACE_RANK.get(it.venue_how, 1) > _PLACE_RANK.get(by_point[key].venue_how, 1):
            by_point[key] = it
    rows = []
    for (lat, lon), it in by_point.items():
        name = (it.venue_display or it.venue_name or it.address.split(",")[0]).strip()[:200]
        if not name:
            continue
        row = "  (" + ",".join([_lit(name), _lit(it.city), _lit(it.address), repr(lat), repr(lon),
                                _lit(_PLACE_SOURCE.get(it.venue_how, "source")), _lit(it.venue_ref)]) + ")"
        try:
            row.encode("utf-8")      # сурогат у назві з геокодера — подія без місця, не без дампу
        except UnicodeEncodeError:
            continue
        rows.append(row)
    if not rows:
        return ""
    return ("insert into public.places (name,city,address,latitude,longitude,source,osm_ref)\nvalues\n"
            + ",\n".join(rows)
            + "\non conflict (latitude,longitude) do update set\n"
              "  name=excluded.name, city=excluded.city, address=excluded.address,\n"
              "  source=excluded.source, osm_ref=excluded.osm_ref, updated_at=now()\n"
              "where private.place_source_rank(excluded.source) >= private.place_source_rank(places.source);\n")


# Щабель драбини → джерело назви місця, як у CHECK на places.source.
_PLACE_SOURCE = {"alias": "manual", "exact": "osm", "contains": "osm", "photon": "photon", "detail": "photon"}
_PLACE_RANK = {"alias": 3, "exact": 2, "contains": 2}


def _insert(publishable: list[Item], run_id: str, replace_llm: bool = False) -> str:
    rows: list[str] = []
    for it in publishable:
        rows.append("  (" + ",".join([
            _lit(str(it.event_id)), _lit(it.source_slug),
            _lit(it.title), _lit(it.description), _lit(it.category),
            _lit(it.city), _lit(it.address),
            repr(it.latitude), repr(it.longitude),
            _lit(it.starts_at.isoformat()), _lit(it.ends_at.isoformat()),
            _lit(it.time_zone), _lit(it.image_url),
            _lit(it.source_uid), _lit(it.canonical_url), _lit(it.dedupe_key),
            repr(it.quality),
            _lit(it.price_min) if it.price_min is not None else "null",
            _lit(it.is_free)]) + ")")

    # Рядки через `select … join event_sources`: вимкнене джерело (opt-out, `enabled=false`) не
    # вставляється й не оновлюється. Типи явно: у `values` без цільової таблиці літерали — текст.
    # Ручне зняття (`withdrawn` з `ingest_run_id is null`, див. docs/event-ingestion.md) upsert
    # не скасовує; автоматичні зняття несуть run_id, і повернута в афішу подія знову `live`.
    return ("".join(_adopt_identity(it) for it in publishable) + _adopt_moved_urls(publishable) +
        places_sql(publishable) +
        "insert into public.events (\n"
        "  id,organizer_id,title,description,category,city,address,latitude,longitude,place_id,\n"
        "  starts_at,ends_at,time_zone,capacity,image_url,\n"
        "  origin,source_id,source_uid,canonical_url,dedupe_key,quality,import_status,\n"
        "  price_min,is_free,ingest_run_id)\n"
        # Обчислений id може вже належати іншому рядку: перенесений сеанс лишає старий id (`_adopt_identity`),
        # а його колишній ключ джерело може віддати знову. Тоді новий рядок отримує випадковий id, інакше
        # `events_pkey` відкотив би весь дамп — і так щодня, поки дані не зміняться.
        "select case when exists (select 1 from public.events x where x.id = v.id::uuid\n"
        "    and (x.source_id is distinct from s.id or x.source_uid is distinct from v.source_uid))\n"
        "  then gen_random_uuid() else v.id::uuid end,\n"
        "  s.organizer_id, v.title, v.description, v.category, v.city, v.address,\n"
        "  v.latitude::float8, v.longitude::float8,\n"
        "  (select p.id from public.places p where p.latitude=v.latitude::float8 and p.longitude=v.longitude::float8),\n"
        "  v.starts_at::timestamptz, v.ends_at::timestamptz,\n"
        "  v.time_zone,\n"
        "  null,                       -- місткості в афіші немає — і колонка може це сказати\n"
        "                              -- (20260907150000): вигадана одиниця малювала «Лишилось 1 місце».\n"
        "  v.image_url, 'import', s.id, v.source_uid, v.canonical_url, v.dedupe_key,\n"
        f"  v.quality::numeric, 'live', v.price_min::numeric, v.is_free::boolean, {_lit(run_id)}::uuid\n"
        "from (values\n"
        + ",\n".join(rows)
        + "\n) v(id,slug,title,description,category,city,address,latitude,longitude,starts_at,ends_at,\n"
          "     time_zone,image_url,source_uid,canonical_url,dedupe_key,quality,price_min,is_free)\n"
          "join public.event_sources s on s.slug=v.slug\n"
          "where s.enabled\n"
          "on conflict (source_id,source_uid) where source_id is not null do update set\n"
          "  title=excluded.title, description=excluded.description, category=excluded.category,\n"
          "  city=excluded.city, address=excluded.address,\n"
          "  latitude=excluded.latitude, longitude=excluded.longitude, place_id=excluded.place_id,\n"
          "  starts_at=excluded.starts_at, ends_at=excluded.ends_at, time_zone=excluded.time_zone,\n"
          "  image_url=excluded.image_url, canonical_url=excluded.canonical_url,\n"
          "  dedupe_key=excluded.dedupe_key, quality=excluded.quality,\n"
          "  import_status=case when events.import_status='withdrawn' and events.ingest_run_id is null\n"
          "                     then 'withdrawn' else 'live' end,\n"
          "  price_min=excluded.price_min, is_free=excluded.is_free,\n"
          "  ingest_run_id=case when events.import_status='withdrawn' and events.ingest_run_id is null\n"
          "                     then null else excluded.ingest_run_id end,\n"
          "  updated_at=now();\n" + artists_sql(publishable, replace_llm))


# Звідки ім'я артиста: ручний словник > автоматика > модель. Як `place_source_rank` у БД.
_ARTIST_RANK = {"manual": 3, "auto": 2, "llm": 1}


def artists_sql(items: list[Item], replace_llm: bool = False) -> str:
    """Артисти подій партії (20261002120000): словник `artists` і зв'язок `event_artists`.

    Іде в тій самій команді, що й вставка подій, тож зв'язок бачить свою подію. Набір артистів події
    замінюється повністю, щоб зниклий з афіші виконавець не висів. Рядки моделі (`how='llm'`)
    чіпаємо лише в прогоні з моделлю: без неї вони б щоразу губились.

    Подію шукаємо за (джерело, source_uid), а не за `event_id`: рядок, що пережив перенесення чи нове
    посилання, лишає свій старий id (`_adopt_identity`), і зв'язок за обчисленим id тихо губився
    (2026-10-08: 439 з 2621 подій prod без артистів, серед них МУР у Дніпрі).
    """
    if not items:
        return ""
    people: dict[str, tuple] = {}              # key -> (ім'я, вид, джерело)
    links: list[str] = []
    for it in items:
        seen: set[str] = set()
        for position, a in enumerate(it.artists):
            k = artist_key(a.name)
            name = a.name.strip()
            if not k or len(k) > 160 or not name or len(name) > 120:
                continue
            try:
                (name + k).encode("utf-8")      # сурогат у назві валить запис усього дампу
            except UnicodeEncodeError:
                continue
            source = "manual" if a.how == "dictionary" else "llm" if a.how == "llm" else "auto"
            if k not in people or _ARTIST_RANK[source] > _ARTIST_RANK[people[k][2]]:
                people[k] = (name, a.kind, source)
            # Повтор артиста в події валить `on conflict do update` («cannot affect row a second time»),
            # а з ним — увесь дамп.
            if k in seen:
                continue
            seen.add(k)
            links.append("  (" + ",".join([_lit(it.source_slug), _lit(it.source_uid), _lit(k), _lit(a.role),
                                           str(position), _lit(a.how), repr(round(a.confidence, 2))]) + ")")
    # Рядки моделі замінюємо лише там, де модель цього разу відповіла (чи відповідь є в кеші): збій
    # транспорту інакше стирав би знайдене минулими прогонами.
    clear = ("delete from public.event_artists ea using public.events e, public.event_sources s, (values "
             + ",".join(f"({_lit(it.source_slug)},{_lit(it.source_uid)},"
                        f"{_lit(replace_llm and not getattr(it, 'llm_pending', False))})" for it in items)
             + ") v(slug,uid,replace_llm)\n"
             "where ea.event_id = e.id and e.source_id = s.id and s.slug = v.slug and e.source_uid = v.uid"
             " and (ea.how <> 'llm' or v.replace_llm);\n")
    if not links:
        return clear
    rows = ["  (" + ",".join([_lit(name), _lit(k), _lit(kind), _lit(source)]) + ")"
            for k, (name, kind, source) in people.items()]
    return (clear +
        "insert into public.artists (name,key,kind,source)\nvalues\n" + ",\n".join(rows) +
        "\non conflict (key) do update set\n"
        "  name=case when private.artist_source_rank(excluded.source) >= private.artist_source_rank(artists.source)\n"
        "            then excluded.name else artists.name end,\n"
        "  source=case when private.artist_source_rank(excluded.source) >= private.artist_source_rank(artists.source)\n"
        "              then excluded.source else artists.source end,\n"
        "  kind=coalesce(excluded.kind, artists.kind), updated_at=now();\n"
        "insert into public.event_artists (event_id,artist_id,role,position,how,confidence)\n"
        "select e.id, a.id, v.role, v.position::smallint, v.how, v.confidence::numeric\n"
        "from (values\n" + ",\n".join(links) + "\n) v(slug,uid,key,role,position,how,confidence)\n"
        "join public.event_sources s on s.slug = v.slug\n"
        "join public.events e on e.source_id = s.id and e.source_uid = v.uid\n"
        "join public.artists a on a.key = v.key\n"
        "on conflict (event_id,artist_id) do update set\n"
        "  role=excluded.role, position=excluded.position, how=excluded.how, confidence=excluded.confidence;\n")


def unwritable(it: Item, run_id: str) -> str | None:
    """Чому подію не можна записати, або None. Перевірка до дампу: одна погана подія інакше
    валить або запис файлу (сурогат у UTF-8), або всю транзакцію (CHECK у events)."""
    checks = [
        (3 <= len(it.title.strip()) <= 120, "title"),
        (len(it.description or "") <= 5000, "description"),
        (1 <= len(it.city.strip()) <= 160, "city"),
        (1 <= len((it.address or "").strip()) <= 300, "address"),
        (it.canonical_url.startswith("https://") and len(it.canonical_url) <= 2048, "canonical_url"),
        (it.image_url is None or (it.image_url.startswith("https://") and len(it.image_url) <= 2048),
         "image_url"),
    ]
    for ok, field in checks:
        if not ok:
            return field
    try:
        _insert([it], run_id).encode("utf-8")
    except (UnicodeEncodeError, TypeError, ValueError, AttributeError) as exc:
        return f"{type(exc).__name__}: {exc}"[:200]
    return None


def drop_unwritable(items: list[Item], run_id: str) -> list[str]:
    """Незаписувані опубліковані події → черга перегляду. Повертає рядки для звіту."""
    bad = []
    for it in items:
        if it.stage != "published":
            continue
        why = unwritable(it, run_id)
        if why:
            it.stage, it.reject_reason = "review", f"UNWRITABLE {why}"
            bad.append(f"{it.canonical_url[:200]}: {why}")
    return bad


def _adopt_identity(it: Item) -> str:
    """Зберігає id подій у базі (і посилання збережених) при зміні UID."""
    old_uid = occurrence_uid(it.canonical_url, it.previous_start) if it.previous_start else it.canonical_url
    old_start = it.previous_start or it.starts_at
    same_key = (
        "update public.events e set source_uid=" + _lit(it.source_uid) + "\n"
        # Лише ввімкнене джерело: вимкнене (opt-out) дамп не чіпає, як і в upsert.
        f"where e.source_id=(select id from public.event_sources where slug={_lit(it.source_slug)} and enabled)\n"
        f"  and e.source_uid in ({_lit(old_uid)},{_lit(it.canonical_url)})\n"
        f"  and e.starts_at={_lit(old_start.isoformat())}::timestamptz\n"
        "  and not exists (select 1 from public.events n where n.source_id=e.source_id\n"
        f"    and n.source_uid={_lit(it.source_uid)});\n")
    return same_key


def _title_key_sql(column: str) -> str:
    """Назва для зіставлення переїздів у SQL: без хвоста в дужках («Гедда Габлер (Театр на Подолі)» —
    badseller ~2026-10-06 прибрав зал із назв і посилань), лапок, розділових знаків і пробілів. Символи
    перелічено явно, а не класом: класи залежать від локалі бази. Різні вистави одного театру в ту саму
    хвилину (зали «Колеса», Театру на Подолі) так не зливаються: виміряно на prod, 31 пара з 245."""
    return (f"regexp_replace(regexp_replace(lower({column}), '\\s*\\([^()]*\\)\\s*$', ''),"
            " '[\\s«»\"“”„''`ʼ’‘!?.,:;…–—-]+', '', 'g')")


def _adopt_moved_urls(publishable: list[Item]) -> str:
    """Сеанс, у якого джерело змінило посилання, лишається тим самим рядком: інакше старий
    знімається як зниклий, і збережена людиною подія виглядає скасованою.

    Старий рядок переймає новий ключ за тим самим продавцем, містом, хвилиною, назвою (`_title_key_sql`)
    й точкою до 30 м; `id` не змінюється. Старий рядок може бути й автоматично знятим: badseller кладе
    дату в посилання, і після перенесення старе посилання випадає з вибірки раніше, ніж з'являється нове
    («Allegretto» 2026-10: знято 04.10, новий рядок з новим id 06.10). Ручне зняття (без run_id) не
    чіпаємо. Одна команда на пачку (окремий UPDATE на подію подвоював SQL). Обидва `distinct on`
    обов'язкові, інакше два рядки отримають той самий ключ.
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
            f"    on x.source_id=(select id from public.event_sources where slug={_lit(slug)} and enabled)\n"
            "   and x.origin='import'\n"
            "   and (x.import_status='live' or (x.import_status='withdrawn' and x.ingest_run_id is not null))\n"
            "   and x.city=i.city and x.starts_at=i.starts\n"
            "   and x.canonical_url <> i.url\n"
            f"   and {_title_key_sql('x.title')} = {_title_key_sql('i.title')}\n"
            "   and abs(x.latitude - i.lat) < 0.0003 and abs(x.longitude - i.lon) < 0.0003\n"
            "  where not exists (select 1 from public.events n\n"
            "                    where n.source_id=x.source_id and n.source_uid=i.uid)\n"
            "  order by i.uid, x.import_status='live' desc, x.updated_at desc, x.id\n"
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
            "update public.events e set import_status='withdrawn', updated_at=now(),\n"
            f"  ingest_run_id={_lit(run_id)}\n"
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


def demote_sql(items: list[Item], run_id: str) -> list[str]:
    """Знімає живий рядок події, яку цей обхід бачив, але більше не публікує: пішла в чергу
    перегляду (без координат, низька якість, конфлікт дат). Без цього старий рядок лишався
    `live` зі старою точкою, доки подія не закінчиться. Зняття несе run_id, тож наступний обхід,
    де подія знову проходить фільтри, повертає її в `live` (див. upsert у `_insert`).
    """
    parts = []
    for it in items:
        if it.stage != "review":
            continue
        parts.append(
            "update public.events e set import_status='withdrawn', updated_at=now(),\n"
            f"  ingest_run_id={_lit(run_id)}\n"
            f"where e.source_id=(select id from public.event_sources where slug={_lit(it.source_slug)})\n"
            f"  and e.source_uid={_lit(it.source_uid)} and e.origin='import' and e.import_status='live';\n")
    return parts


def retire_absent_sql(slug: str, city: str, seen_uids: list[str], run_id: str, until=None) -> str:
    """Знімає живі майбутні події, яких цей обхід не бачив (ні опублікованих, ні на перевірці, ні
    дублікатів). Команда після вставок міста: перехід на новий ключ уже перейменував рядки.
    Знімається, а не видаляється: збережена подія лишається з позначкою.

    Лише ще не початі: почату подію джерело зі списку прибирає саме (а конвеєр без кінця в даних
    її відкидає), і зняття посеред показу показувало б людям «скасовано». `until` — межа обходу
    (sitemap до horizon_days): далі нього відсутність нічого не доводить.

    Запобіжник на частку — все або нічого, бо часткове зняття при зламаному обході теж шкода. Але
    не мовчки: скільки зникло, скільки знято й чи спрацював він — у звіт прогону (`ingest_runs.report`,
    рядок уже вставлено статистикою) і попередженням у лог застосування.
    """
    if not seen_uids:
        return ""
    seen = ",".join(_lit(uid) for uid in sorted(set(seen_uids)))
    scope = (f"e.source_id=(select id from public.event_sources where slug={_lit(slug)})\n"
             f"    and e.city={_lit(city)} and e.origin='import' and e.import_status='live'\n"
             "    and e.starts_at > now()"
             + (f" and e.starts_at < {_lit(until.isoformat())}::date" if until else ""))
    return (
        "do $retire$\n"
        "declare\n"
        f"  v_seen text[] := array[{seen}]::text[];\n"
        "  v_scope integer; v_gone integer; v_done integer := 0; v_blocked boolean;\n"
        "begin\n"
        "  select count(*), count(*) filter (where e.source_uid <> all (v_seen)) into v_scope, v_gone\n"
        f"  from public.events e where {scope};\n"
        f"  v_blocked := v_gone > greatest({RETIRE_ALLOWANCE}, {RETIRE_MAX_SHARE} * v_scope);\n"
        "  if v_blocked then\n"
        f"    raise warning 'retire_absent %/%: зникло % з %, понад {round(RETIRE_MAX_SHARE * 100)}%% — нічого не знято',\n"
        f"      {_lit(slug)}, {_lit(city)}, v_gone, v_scope;\n"
        "  else\n"
        f"    update public.events e set import_status='withdrawn', updated_at=now(), ingest_run_id={_lit(run_id)}\n"
        f"    where {scope} and e.source_uid <> all (v_seen);\n"
        "    get diagnostics v_done = row_count;\n"
        "  end if;\n"
        "  if to_regclass('private.ingest_runs') is not null then\n"
        "    update private.ingest_runs set report = coalesce(report, '{}'::jsonb) || jsonb_build_object(\n"
        "      'retire_scope', v_scope, 'retire_gone', v_gone, 'retired', v_done, 'retire_blocked', v_blocked)\n"
        f"    where id = {_lit(stats_run_id(run_id, slug, city))}::uuid;\n"
        "  end if;\n"
        "end $retire$;\n")


# Скільки днів після кінця подія ще вважається живою: перенесення під тим самим ключем повертають
# її в `live` наступним дампом, а тиждень покриває типовий зсув афіші.
FINISHED_GRACE_DAYS = 7


def retire_finished_sql(grace_days: int = FINISHED_GRACE_DAYS) -> str:
    """Завершені імпортовані події → `stale` (міграція 20260915120000). Один виклик на дамп,
    останньою командою: до нього upsert уже повернув у `live` те, що джерело перенесло."""
    if grace_days < 0:
        raise ValueError("grace_days must be non-negative")
    return f"select private.retire_finished_imports(interval '{grace_days} days');\n"


def prune_artists_sql() -> str:
    """Артисти без жодної події й без підписника (20261002120000): лишаються після злиття дублів («Київський
    Mozart Orchestra» -> «Kyiv Mozart Orchestra») і зміни правил. Підписник утримує артиста навіть без подій:
    людина не мусить втратити підписку, бо афіша на тиждень спорожніла. Ідемпотентна й під перевіркою
    наявності таблиці, як пуш: дамп, застосований до бази без міграції, не має впасти."""
    return ("do $$ begin\n"
            "  if to_regclass('public.artists') is not null then\n"
            "    delete from public.artists a\n"
            "    where not exists (select 1 from public.event_artists ea where ea.artist_id = a.id)\n"
            "      and not exists (select 1 from public.follows f where f.target_kind = 'artist' and f.target_id = a.id);\n"
            "  end if;\n"
            "end $$;\n")


def notify_follows_sql() -> str:
    """Пуш підписникам артистів і закладів про нові події (20260928160000, 20261002130000): одна команда
    на дамп, перед `retire_finished_sql`. Артисти першими: у них спільний із закладами добовий ліміт, і
    особистіша підписка забирає слот. Ідемпотентна, як і вона: функція сама пам'ятає, кому вже казала, і
    не частіше ніж раз на добу на людину. Ні відсутня функція (`to_regprocedure`: дамп, застосований до
    бази без міграції), ні її збій не мають відкотити всю транзакцію дампу заради пуша: збій — лише
    попередження, зведення відкотиться саме, а нове дочекається наступного прогону."""
    return "".join(
        "do $$ begin\n"
        f"  if to_regprocedure('private.{name}()') is not null then\n"
        "    begin\n"
        f"      perform private.{name}();\n"
        "    exception when others then\n"
        f"      raise warning '{name}: %', sqlerrm;\n"
        "    end;\n"
        "  end if;\n"
        "end $$;\n"
        for name in ("notify_artist_follows", "notify_place_follows"))


def _item_dict(i: Item) -> dict:
    return {
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
        "artists": [{"name": a.name, "role": a.role, "how": a.how} for a in i.artists],
    }


def to_json(items: list[Item]) -> str:
    return json.dumps([_item_dict(i) for i in items], ensure_ascii=False, indent=1)


# Скільки днів тримати статистику прогонів (private.ingest_runs/_items). Елемент ~0,7 КБ, ~3600 за
# обхід: місяць — ~75 МБ, вистачає на порівняння тижнів без роздування бази.
STATS_KEEP_DAYS = 30
_STATS_NS = uuid.UUID("5b0f4c1e-6a43-4f53-9d0a-6f2b1c7e9a10")


def stats_run_id(run_id: str, source: str, city: str | None) -> str:
    """Стабільний id рядка ingest_runs: елементи посилаються на нього в тому ж дампі."""
    return str(uuid.uuid5(_STATS_NS, f"{run_id}|{source}|{city or ''}"))


def _count(value) -> int:
    return value if isinstance(value, int) else len(value) if isinstance(value, (list, dict)) else 0


def stats_sql(reports: list[dict], items: list[Item], run_id: str, max_bytes: int = 0) -> list[str]:
    """Статистика прогону для агента-аналітика: рядок на джерело+місто з повним звітом і всі
    елементи з тим, як їх розібрано. Останніми командами дампу — після даних, у тій самій
    транзакції. Джерело без рядка в event_sources (karabas_status) прив'язується до свого сайту."""
    runs: dict[tuple, dict] = {}
    for r in reports:
        source = r.get("source")
        if source:
            runs[(source, r.get("city"))] = r
    for it in items:
        runs.setdefault((it.source_slug, it.city), {"source": it.source_slug, "city": it.city})

    rows = []
    for (source, city), r in runs.items():
        slug = "karabas" if source == "karabas_status" else source
        rows.append("select " + ",".join([
            _lit(stats_run_id(run_id, source, city)) + "::uuid", "s.id", _lit(run_id) + "::uuid", _lit(city) + "::text", "now()",
            *(str(_count(r.get(k))) for k in ("fetched", "parsed", "geocoded", "published",
                                             "duplicates", "rejected", "review")),
            _lit(r.get("error")) + "::text", _lit(json.dumps(r, ensure_ascii=False, default=str)) + "::jsonb",
        ]) + f" from public.event_sources s where s.slug={_lit(slug)}")
    parts = [f"delete from private.ingest_runs where finished_at < now() - interval '{STATS_KEEP_DAYS} days';\n"]
    if rows:
        parts.append("insert into private.ingest_runs (id,source_id,run_id,city,finished_at,fetched,parsed,geocoded,"
                     "published,merged,rejected,review,error,report)\n" + "\nunion all ".join(rows)
                     + "\non conflict (id) do nothing;\n")

    def render(chunk: list[Item]) -> str:
        values = []
        for it in chunk:
            w_slug, w_uid = it.duplicate_of or (None, None)
            values.append("(" + ",".join([
                _lit(stats_run_id(run_id, it.source_slug, it.city)), _lit(it.source_slug),
                _lit(it.source_uid), _lit(it.canonical_url),
                _lit(json.dumps(_item_dict(it), ensure_ascii=False, default=str)), _lit(it.stage),
                _lit(it.reject_reason), _lit(w_slug), _lit(w_uid)]) + ")")
        # Переможця — за ключем, а не за `event_id`: перенесений рядок лишає старий id (див. artists_sql).
        return ("insert into private.ingest_items (run_id,source_id,source_uid,url,raw,stage,reject_reason,"
                "candidate_event_id)\nselect v.run_id::uuid, s.id, v.uid, v.url, v.raw::jsonb, v.stage, v.reason, "
                "w.id\nfrom (values\n" + ",\n".join(values)
                + "\n) v(run_id,slug,uid,url,raw,stage,reason,w_slug,w_uid)\n"
                "join public.event_sources s on s.slug=v.slug\n"
                "left join lateral (select e.id from public.events e join public.event_sources ws on ws.id=e.source_id\n"
                "  where ws.slug=v.w_slug and e.source_uid=v.w_uid) w on true\n"
                "where exists (select 1 from private.ingest_runs r where r.id=v.run_id::uuid);\n")
    for start in range(0, len(items), BATCH):
        parts += bounded_sql(items[start:start + BATCH], render, max_bytes)
    return parts
