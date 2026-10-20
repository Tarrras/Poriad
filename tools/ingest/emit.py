"""Вивід: SQL для застосування й JSON для перегляду.

Нові джерела реєструються перед імпортом. source_id береться за slug, organizer_id
може бути null для імпортованих подій (міграція 20260907130000). Сеанси мають
окремі source_uid; перехід зі старих URL-ключів зберігає ID записів у базі.

Ключ імпорту (джерело, source_uid) — у `public.event_offers` (20261021120000, docs/event-offers.md): подія одна,
пропозицій продавців кілька. Подію й пропозиції пише функція бази `private.ingest_offers`; зняття, усиновлення
нових ключів і артисти — теж на рівні пропозиції.
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
    """Переможці груп: нові ключі наявних пропозицій, місця, пропозиції й події (`private.ingest_offers`), артисти.

    Вимкнене джерело (opt-out, `enabled=false`) функція не пише, ручне зняття пропозиції (`withdrawn` з
    `ingest_run_id is null`, docs/event-ingestion.md) upsert не скасовує; автоматичні зняття несуть run_id, і
    повернута в афішу пропозиція знову `live`."""
    return (_adopt(publishable) + places_sql(publishable)
            + _ingest_call(run_id, [_offer_row(it) for it in publishable])
            + artists_sql(publishable, replace_llm))


def _offer_row(it: Item, winner: tuple | None = None) -> dict:
    """Рядок для `private.ingest_offers`. Копії (`winner`) досить ключа й своєї пропозиції: вміст події пише
    переможець групи."""
    row = {"slug": it.source_slug, "uid": it.source_uid, "url": it.canonical_url, "title": it.title,
           "starts": it.starts_at.isoformat(), "price": it.price_min, "free": it.is_free}
    if winner:
        row.update(winner_slug=winner[0], winner_uid=winner[1], linked=it.linked)
        return row
    row.update(id=str(it.event_id), description=it.description, category=it.category, city=it.city,
               address=it.address, lat=it.latitude, lon=it.longitude, ends=it.ends_at.isoformat(),
               tz=it.time_zone, image=it.image_url, dedupe=it.dedupe_key, quality=it.quality,
               members=[{"slug": slug, "uid": uid} for slug, uid in it.members] or None)
    return row


def _ingest_call(run_id: str, rows: list[dict]) -> str:
    if not rows:
        return ""
    return (f"select private.ingest_offers({_lit(run_id)}::uuid,\n"
            f"  {_lit(json.dumps(rows, ensure_ascii=False))}::jsonb);\n")


# Звідки ім'я артиста: ручний словник > автоматика > модель. Як `place_source_rank` у БД.
_ARTIST_RANK = {"manual": 3, "auto": 2, "llm": 1}


def artists_sql(items: list[Item], replace_llm: bool = False) -> str:
    """Артисти подій партії (20261002120000): словник `artists` і зв'язок `event_artists`.

    Іде в тій самій команді, що й вставка подій, тож зв'язок бачить свою подію. Набір артистів події
    замінюється повністю, щоб зниклий з афіші виконавець не висів. Рядки моделі (`how='llm'`)
    чіпаємо лише в прогоні з моделлю: без неї вони б щоразу губились.

    Подію шукаємо за пропозицією (джерело, source_uid), а не за `event_id`: подія, що пережила перенесення чи
    нове посилання, лишає свій старий id (`_adopt_identity`), і зв'язок за обчисленим id тихо губився
    (2026-10-08: 439 з 2621 подій prod без артистів, серед них МУР у Дніпрі). Два переможці однієї події в
    партії (рідко: пропозиції зведені раніше, а сьогодні правило їх не зводить) — один рядок на артиста.
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
    clear = ("delete from public.event_artists ea using public.event_offers o, public.event_sources s, (values "
             + ",".join(f"({_lit(it.source_slug)},{_lit(it.source_uid)},"
                        f"{_lit(replace_llm and not getattr(it, 'llm_pending', False))})" for it in items)
             + ") v(slug,uid,replace_llm)\n"
             "where ea.event_id = o.event_id and o.source_id = s.id and s.slug = v.slug and o.source_uid = v.uid"
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
        "select distinct on (o.event_id, a.id) o.event_id, a.id, v.role, v.position::smallint, v.how, v.confidence::numeric\n"
        "from (values\n" + ",\n".join(links) + "\n) v(slug,uid,key,role,position,how,confidence)\n"
        "join public.event_sources s on s.slug = v.slug\n"
        "join public.event_offers o on o.source_id = s.id and o.source_uid = v.uid\n"
        "join public.artists a on a.key = v.key\n"
        "order by o.event_id, a.id, v.position::smallint\n"
        "on conflict (event_id,artist_id) do update set\n"
        "  role=excluded.role, position=excluded.position, how=excluded.how, confidence=excluded.confidence;\n")


def unwritable(it: Item, run_id: str) -> str | None:
    """Чому подію не можна записати, або None. Перевірка до дампу: одна погана подія інакше
    валить або запис файлу (сурогат у UTF-8), або всю транзакцію (CHECK у events). Копія пише лише свою
    пропозицію, тож її назва й адреса CHECK подій не проходять."""
    copy = it.stage == "duplicate"
    checks = [(it.canonical_url.startswith("https://") and len(it.canonical_url) <= 2048, "canonical_url")]
    if not copy:
        checks += [
            (3 <= len(it.title.strip()) <= 120, "title"),
            (len(it.description or "") <= 5000, "description"),
            (1 <= len(it.city.strip()) <= 160, "city"),
            (1 <= len((it.address or "").strip()) <= 300, "address"),
            (it.image_url is None or (it.image_url.startswith("https://") and len(it.image_url) <= 2048),
             "image_url"),
        ]
    for ok, field in checks:
        if not ok:
            return field
    try:
        ("".join(duplicates_sql([it], run_id)) if copy else _insert([it], run_id)).encode("utf-8")
    except (UnicodeEncodeError, TypeError, ValueError, AttributeError) as exc:
        return f"{type(exc).__name__}: {exc}"[:200]
    return None


def drop_unwritable(items: list[Item], run_id: str) -> list[str]:
    """Незаписувані опубліковані події → черга перегляду. Повертає рядки для звіту."""
    bad = []
    for it in items:
        if it.stage not in ("published", "duplicate"):
            continue
        why = unwritable(it, run_id)
        if why:
            it.stage, it.reject_reason = "review", f"UNWRITABLE {why}"
            bad.append(f"{it.canonical_url[:200]}: {why}")
    return bad


def _adopt(items: list[Item]) -> str:
    """Нові ключі наявних пропозицій — до запису: інакше сеанс із новим ключем став би новою подією."""
    return "".join(_adopt_identity(it) for it in items) + _adopt_moved_urls(items) + _adopt_silent_moves(items)


def _adopt_identity(it: Item) -> str:
    """Зберігає пропозицію (і подію з її збереженими) при зміні UID: старий URL-ключ і явний перенос Karabas."""
    old_uid = occurrence_uid(it.canonical_url, it.previous_start) if it.previous_start else it.canonical_url
    old_start = it.previous_start or it.starts_at
    return (
        "update public.event_offers o set source_uid=" + _lit(it.source_uid) + ", updated_at=now()\n"
        # Лише ввімкнене джерело: вимкнене (opt-out) дамп не чіпає, як і запис.
        f"where o.source_id=(select id from public.event_sources where slug={_lit(it.source_slug)} and enabled)\n"
        f"  and o.source_uid in ({_lit(old_uid)},{_lit(it.canonical_url)})\n"
        f"  and o.starts_at={_lit(old_start.isoformat())}::timestamptz\n"
        "  and not exists (select 1 from public.event_offers n where n.source_id=o.source_id\n"
        f"    and n.source_uid={_lit(it.source_uid)});\n")


def _title_key_sql(column: str) -> str:
    """Назва для зіставлення переїздів: `private.title_key` (20261021120000) — без хвоста в дужках («Гедда Габлер
    (Театр на Подолі)» — badseller ~2026-10-06 прибрав зал із назв і посилань), лапок, розділових і пробілів.
    Різні вистави одного театру в ту саму хвилину (зали «Колеса», Театру на Подолі) так не зливаються: виміряно
    на prod, 31 пара з 245."""
    return f"private.title_key({column})"


# Найбільший зсув тихого переносу, який ще вважаємо тим самим сеансом (docs/event-offers.md, R1).
SILENT_MOVE_DAYS = 90


def _adopt_moved_urls(publishable: list[Item]) -> str:
    """Сеанс, у якого джерело змінило посилання, лишається тією самою пропозицією: інакше стара знімається як
    зникла, а сеанс з новим посиланням став би новою подією.

    Стара пропозиція переймає новий ключ за тим самим продавцем, хвилиною, назвою продавця (`_title_key_sql`),
    містом і точкою події до 30 м; подія та сама. Стара може бути й автоматично знятою: badseller кладе дату в
    посилання, і після перенесення старе посилання випадає з вибірки раніше, ніж з'являється нове («Allegretto»
    2026-10: знято 04.10, новий рядок з новим id 06.10). Ручне зняття (без run_id) не чіпаємо. Одна команда на
    пачку (окремий UPDATE на подію подвоював SQL). Обидва `distinct on` обов'язкові, інакше дві пропозиції
    отримають той самий ключ.
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
            "  join public.event_offers x\n"
            f"    on x.source_id=(select id from public.event_sources where slug={_lit(slug)} and enabled)\n"
            "   and (x.status='live' or x.ingest_run_id is not null)\n"
            "   and x.starts_at=i.starts and x.canonical_url <> i.url\n"
            f"   and {_title_key_sql('x.title')} = {_title_key_sql('i.title')}\n"
            "  join public.events e on e.id=x.event_id and e.city=i.city\n"
            "   and abs(e.latitude - i.lat) < 0.0003 and abs(e.longitude - i.lon) < 0.0003\n"
            "  where not exists (select 1 from public.event_offers n\n"
            "                    where n.source_id=x.source_id and n.source_uid=i.uid)\n"
            "  order by i.uid, x.status='live' desc, x.updated_at desc, x.id\n"
            "), picked as (\n"
            "  select distinct on (id) id, uid from matched order by id, uid\n"
            ")\n"
            "update public.event_offers o set source_uid=p.uid, updated_at=now() from picked p where o.id=p.id;\n")
    return "".join(parts)


def _adopt_silent_moves(items: list[Item]) -> str:
    """Тихий перенос (R1): продавець пересунув час сеансу на тій самій сторінці без жодної позначки (Іво Бобул,
    Дніпро, 23.11: Concert.ua 19:00 → 18:00). Ключ — посилання + час, тож без цього з'являлась нова подія, а
    збережена людиною показувала «Більше не проводиться».

    Пропозиція переймає новий ключ, лише коли на сторінці в обході один сеанс (`single_session`), у базі в цього
    посилання рівно одна майбутня пропозиція, назва продавця та сама, а зсув не більше `SILENT_MOVE_DAYS`. Сторінка
    з кількома сеансами так не зливається: зниклий сеанс — не перенесений."""
    by_source: dict[str, list[Item]] = {}
    for it in items:
        if it.single_session:
            by_source.setdefault(it.source_slug, []).append(it)
    parts = []
    for slug, group in by_source.items():
        rows = ",\n".join(f"  ({_lit(it.source_uid)}, {_lit(it.canonical_url)}, {_lit(it.title)},"
                          f" {_lit(it.starts_at.isoformat())}::timestamptz)" for it in group)
        alive = "(c.status='live' or c.ingest_run_id is not null)"
        parts.append(
            "with incoming(uid, url, title, starts) as (values\n" + rows + "\n"
            "), matched as (\n"
            "  select x.id, i.uid from incoming i\n"
            "  join public.event_offers x\n"
            f"    on x.source_id=(select id from public.event_sources where slug={_lit(slug)} and enabled)\n"
            "   and x.canonical_url=i.url and x.starts_at <> i.starts and x.starts_at > now()\n"
            f"   and abs(extract(epoch from x.starts_at - i.starts)) <= {SILENT_MOVE_DAYS} * 86400\n"
            f"   and {alive.replace('c.', 'x.')}\n"
            f"   and {_title_key_sql('x.title')} = {_title_key_sql('i.title')}\n"
            "  where not exists (select 1 from public.event_offers n where n.source_id=x.source_id and n.source_uid=i.uid)\n"
            "    and (select count(*) from public.event_offers c where c.source_id=x.source_id and c.canonical_url=i.url\n"
            f"         and c.starts_at > now() and {alive}) = 1\n"
            ")\n"
            "update public.event_offers o set source_uid=m.uid, updated_at=now() from matched m where o.id=m.id;\n")
    return "".join(parts)


def withdrawals_sql(slug: str, notices: list[dict], run_id: str) -> list[str]:
    """Лише явне скасування чи перенесення, ніколи не відсутність у списку."""
    parts = []
    for notice in notices:
        url, start = notice["url"], notice["starts_at"]
        # Без дати сеансу чіпаємо лише старий ключ за URL: не можна скасувати всі сеанси сторінки.
        target = (f"canonical_url={_lit(url)} and starts_at={_lit(start)}::timestamptz"
                  if start else f"source_uid={_lit(url)}")
        # Ручне зняття (без run_id) не перезаписуємо: з run_id воно стало б автоматичним, і дамп його повернув би.
        parts.append(
            "update public.event_offers set status='withdrawn', updated_at=now(),\n"
            f"  ingest_run_id={_lit(run_id)}\n"
            f"where source_id=(select id from public.event_sources where slug={_lit(slug)})\n"
            f"  and ({target}) and not (status='withdrawn' and ingest_run_id is null);\n")
    return parts


def duplicates_sql(items: list[Item], run_id: str, max_bytes: int = 0) -> list[str]:
    """Копії (між джерелами й одного продавця) — пропозиції події переможця, а не зняті рядки (R1). Після
    записів усіх переможців міста: переможець часто з іншого джерела. Копія, що досі жила окремою подією,
    зливається в подію переможця разом зі збереженнями (`private.merge_event`)."""
    copies = [i for i in items if i.stage == "duplicate" and i.duplicate_of]
    render = lambda rows: _adopt(rows) + _ingest_call(run_id, [_offer_row(it, tuple(it.duplicate_of)) for it in rows])
    return [part for start in range(0, len(copies), BATCH)
            for part in bounded_sql(copies[start:start + BATCH], render, max_bytes)]


# Скільки подій джерела в місті можна зняти за відсутністю за обхід. Звична плинність до 4%;
# зламаний парсер дає майже 100%, і зняття не відбувається. П'ять дозволено завжди для малих міст.
RETIRE_MAX_SHARE = 0.3
RETIRE_ALLOWANCE = 5


def demote_sql(items: list[Item], run_id: str, published: set | frozenset = frozenset()) -> list[str]:
    """Знімає живу пропозицію, яку цей обхід бачив, але більше не публікує: пішла в чергу
    перегляду (без координат, низька якість, конфлікт дат). Без цього стара лишалась
    `live` зі старою точкою, доки подія не закінчиться. Зняття несе run_id, тож наступний обхід,
    де подія знову проходить фільтри, повертає її в `live` (`private.ingest_offers`).

    `published` — (джерело, uid), опубліковані в будь-якому місті прогону: Karabas показує дніпровську подію
    й на сторінці іншого міста, там вона йде в чергу як CITY_MISMATCH, і зняття за нею знімало б рядок,
    щойно записаний своїм містом (рятував лише порядок міст у дампі).
    """
    parts = []
    for it in items:
        if it.stage != "review" or (it.source_slug, it.source_uid) in published:
            continue
        parts.append(
            "update public.event_offers o set status='withdrawn', updated_at=now(),\n"
            f"  ingest_run_id={_lit(run_id)}\n"
            f"where o.source_id=(select id from public.event_sources where slug={_lit(it.source_slug)})\n"
            f"  and o.source_uid={_lit(it.source_uid)} and o.status='live';\n")
    return parts


def retire_absent_sql(slug: str, city: str, seen_uids: list[str], run_id: str, until=None) -> str:
    """Знімає живі майбутні пропозиції, яких цей обхід не бачив (ні опублікованих, ні на перевірці, ні
    дублікатів). Команда після вставок міста: перехід на новий ключ уже перейменував пропозиції.
    Знімається, а не видаляється; подія знята, лише коли живих пропозицій не лишилось.

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
    scope = (f"o.source_id=(select id from public.event_sources where slug={_lit(slug)})\n"
             f"    and e.id=o.event_id and e.city={_lit(city)} and o.status='live'\n"
             "    and o.starts_at > now()"
             + (f" and o.starts_at < {_lit(until.isoformat())}::date" if until else ""))
    return (
        "do $retire$\n"
        "declare\n"
        f"  v_seen text[] := array[{seen}]::text[];\n"
        "  v_scope integer; v_gone integer; v_done integer := 0; v_blocked boolean;\n"
        "begin\n"
        "  select count(*), count(*) filter (where o.source_uid <> all (v_seen)) into v_scope, v_gone\n"
        f"  from public.event_offers o, public.events e where {scope};\n"
        f"  v_blocked := v_gone > greatest({RETIRE_ALLOWANCE}, {RETIRE_MAX_SHARE} * v_scope);\n"
        "  if v_blocked then\n"
        f"    raise warning 'retire_absent %/%: зникло % з %, понад {round(RETIRE_MAX_SHARE * 100)}%% — нічого не знято',\n"
        f"      {_lit(slug)}, {_lit(city)}, v_gone, v_scope;\n"
        "  else\n"
        f"    update public.event_offers o set status='withdrawn', updated_at=now(), ingest_run_id={_lit(run_id)}\n"
        f"    from public.events e where {scope} and o.source_uid <> all (v_seen);\n"
        "    get diagnostics v_done = row_count;\n"
        "  end if;\n"
        "  if to_regclass('private.ingest_runs') is not null then\n"
        "    update private.ingest_runs set report = coalesce(report, '{}'::jsonb) || jsonb_build_object(\n"
        "      'retire_scope', v_scope, 'retire_gone', v_gone, 'retired', v_done, 'retire_blocked', v_blocked)\n"
        f"    where id = {_lit(stats_run_id(run_id, slug, city))}::uuid;\n"
        "  end if;\n"
        "end $retire$;\n")


def retire_replaced_sql(slug: str, items: list[Item], run_id: str) -> str:
    """Картка з одним сеансом (TicketsBox: кожна картка — один сеанс, звірено 2026-10-08) показує його
    теперішній час: інші майбутні сеанси того ж посилання — старий час, якого вже нема. Без цього
    перенесення без `previousStartDate` лишало обидва рядки живими назавжди (Могилевська 9.10 → 14.05.2027,
    «В неділю рано согрішили» 14:00 → 15:00): TicketsBox за відсутністю не знімається, бо список неповний.
    Судимо лише картки, прочитані цим прогоном, тож неповний список тут нічого не знімає."""
    seen = sorted({(it.canonical_url, it.source_uid) for it in items if it.canonical_url})
    if not seen:
        return ""
    rows = ",".join(f"({_lit(url)},{_lit(uid)})" for url, uid in seen)
    return (
        f"with seen(url, uid) as (values {rows})\n"
        f"update public.event_offers o set status='withdrawn', updated_at=now(), ingest_run_id={_lit(run_id)}\n"
        f"where o.source_id=(select id from public.event_sources where slug={_lit(slug)})\n"
        "  and o.status='live' and o.starts_at > now()\n"
        "  and o.canonical_url in (select url from seen)\n"
        "  and not exists (select 1 from seen s where s.uid = o.source_uid);\n")


# Скільки днів після кінця подія ще вважається живою: перенесення під тим самим ключем повертають
# її в `live` наступним дампом, а тиждень покриває типовий зсув афіші.
FINISHED_GRACE_DAYS = 7


def retire_finished_sql(grace_days: int = FINISHED_GRACE_DAYS) -> str:
    """Завершені імпортовані події → `stale` (міграція 20260915120000). Один виклик на дамп,
    останньою командою: до нього upsert уже повернув у `live` те, що джерело перенесло."""
    if grace_days < 0:
        raise ValueError("grace_days must be non-negative")
    return f"select private.retire_finished_imports(interval '{grace_days} days');\n"


def merge_artist_follows_sql(merges: list[tuple[str, str]]) -> str:
    """Підписка на псевдонім переходить на канонічного артиста (до `prune_artists_sql`). Без цього людина,
    що стежила за «Олена Тополь», після злиття з «Олена Тополя» лишалась на артисті без подій — його тримав
    живим лише її підпис — і пушів більше не отримувала. Дата підписки зберігається: пуш рахує «нове» від
    неї, і давні події канонічного артиста не прийдуть як нові. Під перевіркою таблиці, як і prune."""
    pairs = sorted(set(merges))
    if not pairs:
        return ""
    rows = ",".join(f"({_lit(a)},{_lit(c)})" for a, c in pairs)
    return ("do $$ begin\n"
            "  if to_regclass('public.artists') is not null then\n"
            f"    with m(alias_key, canon_key) as (values {rows}),\n"
            "    pairs as (select a.id as old_id, c.id as new_id from m\n"
            "              join public.artists a on a.key = m.alias_key join public.artists c on c.key = m.canon_key\n"
            "              where a.id <> c.id),\n"
            "    moved as (insert into public.follows (user_id, target_kind, target_id, created_at)\n"
            "              select f.user_id, 'artist', p.new_id, f.created_at from public.follows f\n"
            "              join pairs p on f.target_kind = 'artist' and f.target_id = p.old_id\n"
            "              on conflict do nothing returning 1)\n"
            "    delete from public.follows f using pairs p where f.target_kind = 'artist' and f.target_id = p.old_id;\n"
            "  end if;\n"
            "end $$;\n")


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


# Скільки днів тримати статистику прогонів. Звіти (ingest_runs) малі й потрібні для SHARP_DROP і
# порівняння тижнів — місяць. Елементи (ingest_items) — ~1,4 КБ, ~3700 за обхід, тобто ~5 МБ на дамп,
# а читається лише останній обхід (run_stats.py, запити README) — тиждень, ~40 МБ.
STATS_KEEP_DAYS = 30
ITEMS_KEEP_DAYS = 7
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
    real = set(runs)
    # Заглушка для пари без звіту (копія з чужого міста, CITY_MISMATCH): елементам потрібен рядок, на який
    # посилатись. Справжній звіт заглушку перезаписує, а не навпаки: у `--sql-dir` файл іншого міста з
    # заглушкою міг застосуватись раніше, і справжній звіт губився (`do nothing`), а з ним база SHARP_DROP.
    for it in items:
        runs.setdefault((it.source_slug, it.city), {"source": it.source_slug, "city": it.city})

    def row(source, city, r) -> str:
        slug = "karabas" if source == "karabas_status" else source
        return "select " + ",".join([
            _lit(stats_run_id(run_id, source, city)) + "::uuid", "s.id", _lit(run_id) + "::uuid", _lit(city) + "::text", "now()",
            *(str(_count(r.get(k))) for k in ("fetched", "parsed", "geocoded", "published",
                                             "duplicates", "rejected", "review")),
            _lit(r.get("error")) + "::text", _lit(json.dumps(r, ensure_ascii=False, default=str)) + "::jsonb",
        ]) + f" from public.event_sources s where s.slug={_lit(slug)}"
    columns = ("insert into private.ingest_runs (id,source_id,run_id,city,finished_at,fetched,parsed,geocoded,"
               "published,merged,rejected,review,error,report)\n")
    parts = [f"delete from private.ingest_runs where finished_at < now() - interval '{STATS_KEEP_DAYS} days';\n"
             f"delete from private.ingest_items where created_at < now() - interval '{ITEMS_KEEP_DAYS} days';\n"]
    reported = [row(s, c, r) for (s, c), r in runs.items() if (s, c) in real]
    stubs = [row(s, c, r) for (s, c), r in runs.items() if (s, c) not in real]
    if reported:
        parts.append(columns + "\nunion all ".join(reported) + "\non conflict (id) do update set\n"
                     "  source_id=excluded.source_id, finished_at=excluded.finished_at, fetched=excluded.fetched,\n"
                     "  parsed=excluded.parsed, geocoded=excluded.geocoded, published=excluded.published,\n"
                     "  merged=excluded.merged, rejected=excluded.rejected, review=excluded.review,\n"
                     "  error=excluded.error, report=excluded.report;\n")
    if stubs:
        parts.append(columns + "\nunion all ".join(stubs) + "\non conflict (id) do nothing;\n")

    def render(chunk: list[Item]) -> str:
        values = []
        for it in chunk:
            w_slug, w_uid = it.duplicate_of or (None, None)
            values.append("(" + ",".join([
                _lit(stats_run_id(run_id, it.source_slug, it.city)), _lit(it.source_slug),
                _lit(it.source_uid), _lit(it.canonical_url),
                _lit(json.dumps(_item_dict(it), ensure_ascii=False, default=str)), _lit(it.stage),
                _lit(it.reject_reason), _lit(w_slug), _lit(w_uid)]) + ")")
        # Переможця — за ключем його пропозиції, а не за `event_id`: подія лишає старий id (див. artists_sql).
        return ("insert into private.ingest_items (run_id,source_id,source_uid,url,raw,stage,reject_reason,"
                "candidate_event_id)\nselect v.run_id::uuid, s.id, v.uid, v.url, v.raw::jsonb, v.stage, v.reason, "
                "w.id\nfrom (values\n" + ",\n".join(values)
                + "\n) v(run_id,slug,uid,url,raw,stage,reason,w_slug,w_uid)\n"
                "join public.event_sources s on s.slug=v.slug\n"
                "left join lateral (select o.event_id as id from public.event_offers o join public.event_sources ws\n"
                "  on ws.id=o.source_id where ws.slug=v.w_slug and o.source_uid=v.w_uid) w on true\n"
                "where exists (select 1 from private.ingest_runs r where r.id=v.run_id::uuid);\n")
    for start in range(0, len(items), BATCH):
        parts += bounded_sql(items[start:start + BATCH], render, max_bytes)
    return parts
