"""Оркестрація: сторінка-список -> нормалізовані події -> SQL.

Стадії з docs/event-ingestion.md, стиснуті до тих, що справді потрібні для джерел рівня B:
    S1 fetch -> S2 extract -> S3 normalize -> S4 venue -> S6 score -> S7 emit
S0 discover читає listing_urls і, за потреби, картки подій. S5 dedupe обирає
канонічні сеанси до SQL; SQL прибирає відомі дублікати лише після вставки заміни.
"""
from __future__ import annotations

import dataclasses
import datetime as dt
import math
import uuid

from . import community, culture, extract, normalize
from .fetch import get
from .sources import Source
from .geocode import Geocoder
from .geocode import CITY_BBOX
from .venues import VenueIndex

# Простір імен для детермінованих ідентифікаторів: повторний запуск має давати ті самі UUID,
# інакше кожен обхід створює дублікати замість оновлення.
NAMESPACE = uuid.UUID("8b1f0a2e-6d3c-4a5b-9e7f-2c4d6a8b0e13")

QUALITY_FLOOR = 0.55            # той самий поріг, що в private.is_discoverable

# Скільки може тривати запис, щоб лишатись подією.
#
# Джерела продають квитком і те, що подією не є: «Київський океанаріум», «Музей медуз»,
# VR-екскурсію. У таких `endDate` — це не кінець події, а дата, доки діє квиткова пропозиція;
# у майстер-класі з Tafl вона стояла через 560 днів. Океанаріум працює щодня, і в стрічці
# «триває зараз» він висів би місяцями, витісняючи те, заради чого в неї дивляться.
#
# Межа евристична: у вибірці на пʼять міст реальний прокат виставок і ярмарків укладався в
# 86 днів, а найкоротша постійна пропозиція починалась зі 111. Це підібрано на одній вибірці,
# а не виміряно — наступний, хто побачить тут 90, має знати саме це.
#
# Відсікаємо при імпорті, а не при показі: фільтр у базі ховає рядок, але рядок лишається,
# займає місце в індексі й спливає в кожному новому запиті, який хтось напише пізніше.
PERMANENT_RUN = dt.timedelta(days=90)


@dataclasses.dataclass
class Item:
    source_slug: str
    source_uid: str
    event_id: uuid.UUID
    title: str
    description: str
    category: str
    category_how: str
    source_type: str
    city: str
    address: str
    venue_name: str
    venue_display: str | None
    latitude: float | None
    longitude: float | None
    venue_ref: str | None
    venue_how: str | None
    geo_confidence: float
    starts_at: dt.datetime
    ends_at: dt.datetime
    end_declared: bool
    time_zone: str
    image_url: str | None
    canonical_url: str
    price_min: float | None
    is_free: bool | None
    description_len: int
    quality: float = 0.0
    stage: str = "normalized"
    reject_reason: str | None = None
    duplicate_of: tuple[str, str] | None = None
    previous_start: dt.datetime | None = None

    @property
    def dedupe_key(self) -> str | None:
        if self.latitude is None or self.longitude is None:
            return None
        local = self.starts_at.astimezone(normalize.zone(self.time_zone)).date()
        return f"{local.isoformat()}:{round(self.latitude, 2)},{round(self.longitude, 2)}"


def _quality(item: Item, weight: float, series_size: int) -> float:
    score = 0.0
    if item.latitude is not None:
        score += 0.30 * item.geo_confidence      # найдорожчий складник — і єдиний обов'язковий
    if item.end_declared:
        score += 0.15
    if item.description_len >= 120:
        score += 0.15
    if item.image_url:
        score += 0.10
    score += 0.20 * weight
    if series_size <= 20:
        score += 0.10
    return round(min(score, 1.0), 3)


def harvest(source: Source, city: str, index: VenueIndex,
            *, now: dt.datetime | None = None,
            geocoder: Geocoder | None = None,
            status_notices: list[dict] | None = None) -> tuple[list[Item], dict]:
    """Обхід однієї сторінки-списку. Повертає (елементи, лічильники запуску)."""
    now = now or dt.datetime.now(dt.timezone.utc)
    url = source.listing_urls[city]
    counters = {"fetched": 0, "parsed": 0, "geocoded": 0,
                "published": 0, "rejected": 0, "review": 0,
                "withdrawals": [], "reasons": {}, "coverage": "listing"}

    if source.adapter in {"dou", "yoy"}:
        try:
            raw_events, adapter_report = community.collect(
                source.adapter, url, city, get=get, delay=source.crawl_delay,
                max_details=source.max_details)
        except (PermissionError, OSError, ValueError) as exc:
            return [], {**counters, "error": str(exc)}
        counters.update({key: value for key, value in adapter_report.items() if key != "review"})
        counters["adapter_review"] = adapter_report.get("review", [])
    elif source.adapter.startswith("culture:"):
        try:
            raw_events, adapter_report = culture.collect(
                source.adapter.split(":", 1)[1], url, city, get=get,
                delay=source.crawl_delay, max_details=source.max_details)
        except (PermissionError, OSError, ValueError) as exc:
            return [], {**counters, "error": str(exc)}
        counters.update({key: value for key, value in adapter_report.items()
                         if key not in {"review", "errors"}})
        counters["adapter_review"] = adapter_report.get("review", [])
        counters["detail_errors"] = adapter_report.get("errors", [])
        if adapter_report.get("errors"):
            counters["error"] = "PARTIAL_DETAILS"
    else:
        try:
            response = get(url, delay=source.crawl_delay)
        except (PermissionError, OSError) as exc:
            return [], {**counters, "error": str(exc)}
        if response.status != 200 or not response.body:
            return [], {**counters, "error": f"HTTP {response.status}"}
        counters["fetched"] = 1
        raw_events = extract.events_from_html(response.body)
    if source.adapter == "jsonld" and source.detail_path:
        links = extract.detail_links(response.body, url, source.detail_path)
        counters["detail_links"] = len(links)
        counters["detail_errors"] = []
        if len(links) > source.max_details:
            counters["detail_errors"].append("DETAIL_LIMIT")
        for link in links[:source.max_details]:
            try:
                detail = get(link, delay=source.crawl_delay)
                if detail.status != 200 or not detail.body:
                    raise ValueError(f"HTTP {detail.status}")
                counters["fetched"] += 1
                events = extract.events_from_html(detail.body)
                if not events:
                    raise ValueError("NO_EVENTS")
                raw_events.extend(events)
            except (PermissionError, OSError, ValueError) as exc:
                counters["detail_errors"].append(f"{link}: {exc}")
        if counters["detail_errors"]:
            counters["error"] = "PARTIAL_DETAILS"
    if source.slug == "karabas" and status_notices:
        counters["status_detail_errors"] = []
        candidates = [notice for notice in status_notices
                      if notice.get("city") == city
                      and notice.get("status") == "EventRescheduled"
                      and str(notice.get("canonical_url") or "").startswith("https://")]
        for notice in candidates[:20]:
            detail_url = notice["canonical_url"]
            try:
                detail = get(detail_url, delay=source.crawl_delay)
                if detail.status != 200 or not detail.body:
                    raise ValueError(f"HTTP {detail.status}")
                events = extract.events_from_html(detail.body)
                if not events:
                    raise ValueError("NO_EVENTS")
                raw_events.extend(events)
                counters["fetched"] += 1
            except (PermissionError, OSError, ValueError) as exc:
                counters["status_detail_errors"].append(f"{detail_url}: {exc}")
    counters["parsed"] = len(raw_events)
    if not raw_events:
        if counters.get("valid_empty"):
            return [], counters
        return [], {**counters, "error": "NO_EVENTS: порожня афіша або зміна розмітки"}

    items: list[Item] = []
    for raw in raw_events:
        status = str(raw.get("eventStatus") or "EventScheduled").rsplit("/", 1)[-1]
        if status in {"EventCancelled", "EventPostponed"}:
            canonical = str(raw.get("url") or raw.get("@id") or "").strip()
            if canonical.startswith("https://"):
                start = normalize.parse_datetime(raw.get("startDate"), source.tz_policy, source.time_zone)
                counters["withdrawals"].append({"url": canonical,
                    "starts_at": start.isoformat() if start else None, "reason": status})
            counters["rejected"] += 1
            counters["reasons"][status] = counters["reasons"].get(status, 0) + 1
            continue
        item = _build(raw, source, city, index, now, geocoder)
        if item is None:
            counters["rejected"] += 1
            continue
        if item.ends_at - item.starts_at > PERMANENT_RUN:
            counters["rejected"] += 1
            counters["reasons"]["PERMANENT_OFFER"] = counters["reasons"].get("PERMANENT_OFFER", 0) + 1
            continue
        items.append(item)

    if status_notices:
        items, withdrawals = apply_status_notices(items, status_notices, city=city)
        counters["withdrawals"].extend(withdrawals)

    # A session may occur in a listing and in multiple detail pages. Merge before INSERT:
    # PostgreSQL cannot update the same conflict key twice in one command.
    unique: dict[str, Item] = {}
    previous_dates: dict[str, set] = {}
    for item in items:
        if item.previous_start:
            previous_dates.setdefault(item.source_uid, set()).add(item.previous_start)
        previous = unique.get(item.source_uid)
        if previous is None or _quality(item, source.weight, 1) >= _quality(previous, source.weight, 1):
            unique[item.source_uid] = item
    counters["repeated_occurrences"] = len(items) - len(unique)
    items = list(unique.values())
    for item in items:
        dates = previous_dates.get(item.source_uid, set())
        if len(dates) == 1:
            item.previous_start = next(iter(dates))
        elif len(dates) > 1:
            item.previous_start = None
            item.reject_reason = "CONFLICTING_PREVIOUS_START"

    # Серія — та сама назва на тому самому майданчику багато разів. Довгі серії сеансів
    # заповнюють мапу однаковими пінами, тому знижують якість, а не підвищують.
    series: dict[tuple[str, str], int] = {}
    for it in items:
        key = (normalize.normalize_name(it.title), normalize.normalize_name(it.venue_name))
        series[key] = series.get(key, 0) + 1

    for it in items:
        key = (normalize.normalize_name(it.title), normalize.normalize_name(it.venue_name))
        it.quality = _quality(it, source.weight, series[key])
        if it.reject_reason or it.latitude is None:
            it.stage, it.reject_reason = "review", it.reject_reason or "NO_GEO"
            counters["review"] += 1
        elif it.quality < QUALITY_FLOOR:
            it.stage, it.reject_reason = "review", f"LOW_QUALITY {it.quality}"
            counters["review"] += 1
        else:
            it.stage = "published"
            counters["published"] += 1
            counters["geocoded"] += 1
    return items, counters


def apply_status_notices(items: list[Item], notices: list[dict],
                         city: str | None = None) -> tuple[list[Item], list[dict]]:
    """Apply explicit evidence to one exact URL/session, preserving rescheduled IDs."""
    kept: list[Item] = []
    withdrawals: list[dict] = []
    used: set[tuple[str, str, str]] = set()
    parsed = []
    for notice in notices:
        try:
            old = dt.datetime.fromisoformat(notice["starts_at"])
            new = dt.datetime.fromisoformat(notice["new_start"]) if notice.get("new_start") else None
        except (KeyError, TypeError, ValueError):
            continue
        parsed.append((notice, old, new))
        if city is not None and normalize.normalize_name(str(notice.get("city") or "")) == normalize.normalize_name(city):
            key = (str(notice.get("canonical_url") or ""), old.isoformat(), str(notice.get("status")))
            if key[0].startswith("https://") and key not in used:
                withdrawals.append({"url": key[0], "starts_at": old.isoformat(),
                                    "reason": notice.get("status")})
                used.add(key)
    for item in items:
        matching = [(notice, old, new) for notice, old, new in parsed
                    if notice.get("canonical_url") == item.canonical_url
                    and normalize.normalize_name(str(notice.get("city") or "")) ==
                        normalize.normalize_name(item.city)]
        drop = False
        for notice, old, new in matching:
            status = notice.get("status")
            key = (item.canonical_url, old.isoformat(), str(status))
            if item.starts_at == old and status in {"EventCancelled", "EventPostponed", "EventRescheduled"}:
                drop = True
                if key not in used:
                    withdrawals.append({"url": item.canonical_url,
                        "starts_at": old.isoformat(), "reason": status})
                    used.add(key)
            elif status == "EventRescheduled" and new is not None and item.starts_at == new:
                item.previous_start = old
                if key not in used:
                    withdrawals.append({"url": item.canonical_url,
                        "starts_at": old.isoformat(), "reason": status})
                    used.add(key)
        if not drop:
            kept.append(item)
    return kept, withdrawals


def _build(raw: dict, source: Source, city: str, index: VenueIndex,
           now: dt.datetime, geocoder: Geocoder | None = None) -> Item | None:
    title = normalize.normalize_title(raw.get("name"))
    if not title:
        return None

    start = normalize.parse_datetime(raw.get("startDate"), source.tz_policy, source.time_zone)
    if not start:
        return None                                    # минулі події на мапу не потрапляють
    status = str(raw.get("eventStatus") or "EventScheduled").rsplit("/", 1)[-1]
    if status not in {"EventScheduled", "EventRescheduled", "EventMovedOnline"}:
        return None

    canonical = str(raw.get("url") or raw.get("@id") or "").strip()
    if not canonical.startswith("https://"):
        return None                                    # без посилання на джерело атрибуція неможлива

    place = extract.place_of(raw)
    venue_name = normalize.clean_text(place.get("name"))
    address, addr_city, street = normalize.address_of(raw)
    # Пастка B: місто беремо з розмітки, а не зі сторінки, на якій знайшли подію.
    event_city = addr_city or city

    category, category_how = normalize.classify_with_reason(raw, title, venue_name)
    end, end_declared = normalize.resolve_end(
        start, raw.get("endDate"), category, source.tz_policy, source.time_zone)
    if end <= now or (start <= now and not end_declared):
        return None

    full_description = normalize.clean_text(raw.get("description"))
    price_min, is_free = normalize.parse_price(raw)

    # Порядок навмисний: звірене людиною -> дамп OSM -> Photon. Кожен наступний щабель менш
    # надійний, і confidence це відображає, тож слабка точка сама опускає quality до порога.
    city_matches = normalize.normalize_name(event_city) == normalize.normalize_name(city)
    online = (status == "EventMovedOnline" or
              str(raw.get("eventAttendanceMode") or "").endswith("OnlineEventAttendanceMode") or
              place.get("@type") == "VirtualLocation")
    hit = (index.match(venue_name) or index.match(address.split(",")[0])) if city_matches and not online else None
    if hit is None and city_matches and not online:
        geo = place.get("geo")
        if isinstance(geo, dict):
            try:
                lat, lon = float(geo["latitude"]), float(geo["longitude"])
                south, west, north, east = CITY_BBOX[city]
                if south <= lat <= north and west <= lon <= east:
                    hit = {"lat": lat, "lon": lon, "ref": None, "how": "source", "confidence": 0.85}
            except (KeyError, TypeError, ValueError):
                pass
    if hit is None and geocoder is not None and city_matches and not online:
        hit = geocoder.lookup_street(street)
    if hit:
        south, west, north, east = CITY_BBOX[city]
        if not (south <= hit["lat"] <= north and west <= hit["lon"] <= east):
            hit = None
    image = raw.get("image")
    if isinstance(image, dict):
        image = image.get("url")
    if isinstance(image, list):
        image = next((i for i in image if isinstance(i, str)), None)
    image = image if isinstance(image, str) and image.startswith("https://") else None

    source_uid = occurrence_uid(canonical, start)
    return Item(
        source_slug=source.slug,
        source_uid=source_uid,
        event_id=uuid.uuid5(NAMESPACE, f"{source.slug}|{source_uid}"),
        title=title,
        # Пастка C: зберігаємо факти й короткий уривок, повний текст лишається за canonical_url.
        description=normalize.clip(full_description, normalize.DESCRIPTION_LIMIT),
        category=category,
        category_how=category_how,
        source_type=normalize.schema_type(raw),
        city=event_city[:160] or city,
        address=address or venue_name or event_city,
        venue_name=venue_name,
        venue_display=(hit.get("display") or None) if hit else None,
        latitude=hit["lat"] if hit else None,
        longitude=hit["lon"] if hit else None,
        venue_ref=hit["ref"] if hit else None,
        venue_how=hit["how"] if hit else None,
        geo_confidence=hit["confidence"] if hit else 0.0,
        starts_at=start,
        ends_at=end,
        end_declared=end_declared,
        time_zone=source.time_zone,
        image_url=image,
        canonical_url=canonical,
        price_min=price_min,
        is_free=is_free,
        description_len=len(full_description),
        reject_reason="ONLINE" if online else ("CITY_MISMATCH" if not city_matches else None),
        previous_start=normalize.parse_datetime(raw.get("previousStartDate"), source.tz_policy, source.time_zone),
    )


def occurrence_uid(canonical: str, start: dt.datetime) -> str:
    """Separate sessions even when a source reuses the same booking URL."""
    return canonical + "#poruch-start=" + start.astimezone(dt.timezone.utc).isoformat()

# ------------------------------------------------------------------ дедуплікація між джерелами

# Слова, які нічого не розрізняють: вони є в половині афіші.
_NOISE = {"концерт", "вистава", "шоу", "квитки", "київ", "гурт", "театр", "премʼєра",
          "прем'єра", "нового", "альбому", "тур", "презентація", "the", "band",
          "мюзикл", "музична", "комедія", "комедійне", "гумористичне",
          "amazing", "circus", "show", "неймовірне", "циркове"}


def _tokens(title: str) -> set[str]:
    words = normalize.normalize_name(title).split()
    return {w for w in words if len(w) >= 3 and w not in _NOISE}


# Наскільки можуть розійтись координати того самого майданчика, щоб це все ще була та сама подія.
#
# Раніше тут була побітова рівність, і вона коштувала 45 подій на прогоні пʼяти міст: заклад
# приходив із двох джерел у двох написаннях, одне мало псевдонім і брало точку з OSM, друге йшло
# в Photon — і точки розходились на 2–7 м. Дублікат не зливався, `MapPins` теж не зводив його в
# один пін, і на мапі стояли два піни за три метри.
#
# Чому саме 25 м, а не більше. Виміряні розбіжності діляться на дві купи: 2–7 м — те саме місце
# двома щаблями драбини, і 43–211 м — дві різні відповіді Photon на одну адресу. Допуск накриває
# першу купу з великим запасом і навмисно не чіпає другу: там точка сама по собі ненадійна, і
# зливати за нею небезпечно. Друга купа лишається в `near_miss_pairs` як робота для псевдонімів.
#
# Чому це не послаблює захист від хибного злиття. Від MODI (дві різні події на одній точці о тій
# самій годині) боронять НЕ координати — вони там і так рівні — а перевірка слів у назві нижче.
# Допуск не чіпає її взагалі. Ризик, який він додає, інший: два РІЗНІ майданчики за 25 м з тією
# самою назвою й хвилиною початку. Двадцять пʼять метрів — це одна будівля, тож два різні заклади
# в такому радіусі з однаковою афішею на ту саму хвилину неправдоподібні. Ширший допуск ламався б
# уже на реальному випадку: два кінотеатри за сто метрів справді крутять той самий фільм о 19:00.
SAME_PLACE_METRES = 25.0


def same_event(a: Item, b: Item) -> bool:
    """Чи це та сама подія у двох джерелах.

    Момент має збігатися точно — після поправки часових поясів він і збігається. Місце має
    збігатися з точністю до будівлі, див. `SAME_PLACE_METRES`. Назви ж порівнюються множинами
    значущих слів, див. `_titles_agree`.

    Обережність тут дорожча за повноту: у MODI о 19:00 того самого дня йдуть «Відео-галерея» і
    «Відкритий клуб» — різні події на одній точці, і злити їх було б гірше, ніж лишити дубль.
    """
    if a.source_slug == b.source_slug:
        return False
    if None in (a.latitude, a.longitude, b.latitude, b.longitude):
        return False
    if _metres(a, b) > SAME_PLACE_METRES:
        return False
    if a.starts_at != b.starts_at:
        return False
    return _titles_agree(_tokens(a.title), _tokens(b.title))


def _titles_agree(ta: set[str], tb: set[str]) -> bool:
    """Require containment or two shared meaningful words.

    One shared word in two short titles is insufficient (evening of jazz vs poetry).
    Genre decorations are removed by _tokens; genuine one-word titles still match.
    """
    if not ta or not tb:
        return False
    shared = len(ta & tb)
    shorter = min(len(ta), len(tb))
    return shared == shorter or shared >= 2


def _metres(a: Item, b: Item) -> float:
    """Приблизна відстань. Рівнокутне наближення: на масштабі міста похибка мізерна."""
    lat = math.radians((a.latitude + b.latitude) / 2)
    dx = math.radians(a.longitude - b.longitude) * math.cos(lat)
    dy = math.radians(a.latitude - b.latitude)
    return 6371000 * math.hypot(dx, dy)


def near_miss_pairs(items: list[Item], limit_metres: float = 400.0) -> list[tuple[Item, Item, float]]:
    """Пари, які схожі на ту саму подію, але НЕ злились через розбіжність координат.

    `same_event` тепер має допуск `SAME_PLACE_METRES`, тож дрібні розходження зливаються самі.
    Лишається те, що за нього виходить: дві різні відповіді Photon на одну адресу, від сорока
    метрів до двохсот. Там точка ненадійна сама по собі, і зливати за нею небезпечно — тому
    поріг навмисно не піднято, а такі пари виводяться як робота для псевдонімів.

    Ця функція нічого не змінює. Вона лише перетворює ризик на список, за яким видно, які
    майданчики варто занести в aliases.json, щоб обидва джерела приходили до однієї точки.
    """
    out: list[tuple[Item, Item, float]] = []
    live = [i for i in items if i.stage == "published" and i.latitude is not None]
    for idx, a in enumerate(live):
        for b in live[idx + 1:]:
            if a.source_slug == b.source_slug or a.starts_at != b.starts_at:
                continue
            if _metres(a, b) <= SAME_PLACE_METRES:
                continue                      # це вже зловить same_event
            if not _titles_agree(_tokens(a.title), _tokens(b.title)):
                continue
            d = _metres(a, b)
            if d <= limit_metres:
                out.append((a, b, d))
    return sorted(out, key=lambda p: p[2])


def drop_cross_source_duplicates(items: list[Item], weights: dict[str, float]) -> list[Item]:
    """Лишає канонічну копію — з джерела з вищою вагою — і прибирає решту.

    Канонічність за вагою джерела, а не за порядком обходу: інакше результат залежав би від того,
    яке джерело сьогодні відповіло першим.
    """
    published = sorted((i for i in items if i.stage == "published"),
                       key=lambda i: (-weights.get(i.source_slug, 0), -i.quality,
                                      i.source_slug, i.source_uid))
    winners: list[Item] = []
    for candidate in published:
        winner = next((w for w in winners if same_event(w, candidate)), None)
        if winner is None:
            winners.append(candidate)
            continue
        candidate.stage = "duplicate"
        candidate.duplicate_of = (winner.source_slug, winner.source_uid)
        candidate.reject_reason = f"DUPLICATE_OF {winner.source_slug}"
    return items
