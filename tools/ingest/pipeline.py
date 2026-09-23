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

# Простір імен детермінованих UUID: повторний обхід оновлює, а не дублює.
NAMESPACE = uuid.UUID("8b1f0a2e-6d3c-4a5b-9e7f-2c4d6a8b0e13")

QUALITY_FLOOR = 0.55            # той самий поріг, що в private.is_discoverable

# Найдовший прокат, який ще вважаємо подією. Довше — постійна пропозиція (океанаріум, музей),
# де `endDate` — термін дії квитка. Межа евристична: реальні прокати у вибірці до 86 днів,
# постійні від 111. Відсікаємо при імпорті, а не при показі, щоб рядок не спливав у нових запитах.
PERMANENT_RUN = dt.timedelta(days=90)

# Скільки сторінок каталогу гортати: найбільший каталог закінчується на шостій, вісім дає запас.
CATALOG_PAGES = 8


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
    # Каталоги після головного списку: каталожна копія несе відповідь продавця про жанр.
    if source.catalogs and source.catalog_url and (source.city_slugs or {}).get(city):
        counters["catalogs"] = 0
        counters["catalog_errors"] = []
        city_slug = source.city_slugs[city]
        for slug, category in source.catalogs.items():
            base = source.catalog_url.format(city=city_slug, slug=slug)
            seen: set = set()
            for page_number in range(1, CATALOG_PAGES + 1):
                link = base if page_number == 1 else f"{base}?page={page_number}"
                try:
                    page = get(link, delay=source.crawl_delay)
                    if page.status != 200 or not page.body:
                        raise ValueError(f"HTTP {page.status}")
                    counters["fetched"] += 1
                    found = extract.events_from_html(page.body)
                except (PermissionError, OSError, ValueError) as exc:
                    counters["catalog_errors"].append(f"{slug} с.{page_number}: {exc}")
                    break
                # Зупинка за відсутністю нового: після останньої сторінки джерело віддає першу заново.
                fresh = [r for r in found
                         if isinstance(r, dict) and str(r.get("url") or "") not in seen]
                if not fresh:
                    break
                seen.update(str(r.get("url") or "") for r in fresh)
                for raw in fresh:
                    raw["_poruch_category"] = category
                counters["catalogs"] += len(fresh)
                raw_events.extend(fresh)
            else:
                # Межа сторінок, а нове ще йшло: список обрізаний, зняття за відсутністю вимикаємо.
                counters["catalog_capped"] = counters.get("catalog_capped", 0) + 1

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
            canonical = normalize.clean_url(raw.get("url") or raw.get("@id"))
            if canonical.startswith("https://"):
                start = normalize.parse_datetime(raw.get("startDate"), source.tz_policy, source.time_zone)
                counters["withdrawals"].append({"url": canonical,
                    "starts_at": start.isoformat() if start else None, "reason": status})
            counters["rejected"] += 1
            counters["reasons"][status] = counters["reasons"].get(status, 0) + 1
            continue
        try:
            item = _build(raw, source, city, index, now, geocoder)
        except Exception as exc:
            # Одна дивна подія не зупиняє джерело: пропуск і рядок у звіті.
            counters.setdefault("bad_events", []).append(
                f"{str(raw.get('url') or raw.get('@id') or '?')[:200]}: {type(exc).__name__}: {exc}")
            item = None
        if item is None:
            counters["rejected"] += 1
            continue
        if item.ends_at - item.starts_at > PERMANENT_RUN:
            counters["rejected"] += 1
            counters["reasons"]["PERMANENT_OFFER"] = counters["reasons"].get("PERMANENT_OFFER", 0) + 1
            continue
        items.append(item)

    # Тихий нуль: розмітка є, а придатних подій немає — майже завжди зміна верстки, не порожня афіша.
    if not items and not counters["withdrawals"]:
        return [], {**counters, "error": f"NO_USABLE_EVENTS: розібрано {counters['parsed']}, придатних 0"}

    _rescue_addresses(items, source, city, geocoder, counters)

    if status_notices:
        items, withdrawals = apply_status_notices(items, status_notices, city=city)
        counters["withdrawals"].extend(withdrawals)

    # Сеанс може бути і в списку, і в кількох сторінках: зливаємо до INSERT, бо PostgreSQL
    # не оновить той самий ключ конфлікту двічі в одній команді.
    unique: dict[str, Item] = {}
    previous_dates: dict[str, set] = {}
    for item in items:
        if item.previous_start:
            previous_dates.setdefault(item.source_uid, set()).add(item.previous_start)
        previous = unique.get(item.source_uid)
        # Каталожна копія перемагає явно, а не порядком обходу.
        if previous is not None and previous.category_how == "catalog" != item.category_how:
            continue
        if (previous is None or item.category_how == "catalog"
                or _quality(item, source.weight, 1) >= _quality(previous, source.weight, 1)):
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

    # Серія — та сама назва на тому ж майданчику багато разів: знижує якість, бо заповнює мапу однаковим.
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
    _fold_same_source_copies(items, counters)
    return items, counters


def _fold_same_source_copies(items: list[Item], counters: dict) -> None:
    """Зводить копії одного сеансу, які одне джерело віддало під різними посиланнями: злиття за
    `source_uid` їх не бачить (ключ включає посилання), злиття між джерелами теж (один продавець).

    Назва має збігатися точно після зведення: один продавець у ту саму хвилину на тій самій точці
    справді показує різне в сусідніх залах. Зайва копія стає `duplicate` з посиланням на
    переможця, і `emit.duplicates_sql` зніме її рядок у базі.
    """
    groups: dict[tuple, list[Item]] = {}
    for item in items:
        if item.stage != "published":
            continue
        key = (normalize.normalize_name(item.title), item.starts_at,
               round(item.latitude, 4), round(item.longitude, 4))
        groups.setdefault(key, []).append(item)
    for copies in groups.values():
        if len(copies) < 2:
            continue
        # Той самий порядок, що при злитті за ключем: каталог, якість, посилання для стабільності.
        copies.sort(key=lambda i: (i.category_how != "catalog", -i.quality, i.source_uid))
        winner = copies[0]
        for loser in copies[1:]:
            loser.stage = "duplicate"
            loser.duplicate_of = (winner.source_slug, winner.source_uid)
            loser.reject_reason = f"DUPLICATE_OF {winner.source_slug} (same source)"
            counters["published"] -= 1
            counters["geocoded"] -= 1
            counters["same_source_copies"] = counters.get("same_source_copies", 0) + 1


def apply_status_notices(items: list[Item], notices: list[dict],
                         city: str | None = None) -> tuple[list[Item], list[dict]]:
    """Застосовує явне свідчення до одного URL/сеансу, зберігаючи id перенесених."""
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

    canonical = normalize.clean_url(raw.get("url") or raw.get("@id"))
    if not canonical.startswith("https://"):
        return None                                    # без посилання на джерело атрибуція неможлива

    place = extract.place_of(raw)
    venue_name = normalize.clean_text(place.get("name"))
    address, addr_city, street = normalize.address_of(raw)
    # Місто з розмітки, а не зі сторінки, де знайшли подію.
    event_city = addr_city or city

    # Верхній щабель — жанр з каталогу продавця: сильніший за тип schema.org і словник.
    stamped = raw.get("_poruch_category")
    if stamped in normalize.CATEGORIES:
        category, category_how = stamped, "catalog"
    else:
        category, category_how = normalize.classify_with_reason(
            raw, title, venue_name, getattr(source, "type_policy", "trust"))
    end, end_declared = normalize.resolve_end(
        start, raw.get("endDate"), category, source.tz_policy, source.time_zone)
    if end <= now or (start <= now and not end_declared):
        return None

    full_description = normalize.clean_text(raw.get("description"))
    price_min, is_free = normalize.parse_price(raw)

    # Порядок за надійністю: звірене людиною -> дамп OSM -> Photon; confidence це відображає.
    city_matches = normalize.normalize_name(event_city) == normalize.normalize_name(city)
    online = (status == "EventMovedOnline" or
              str(raw.get("eventAttendanceMode") or "").endswith("OnlineEventAttendanceMode") or
              place.get("@type") == "VirtualLocation")
    # Перший сегмент адреси — запасний ключ, але не назва міста: «Київ» зіставився б з будь-чим.
    first_segment = address.split(",")[0].strip()
    if normalize.normalize_name(first_segment) == normalize.normalize_name(event_city):
        first_segment = ""
    hit = (index.match(venue_name) or (index.match(first_segment) if first_segment else None)) \
        if city_matches and not online else None
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
    image = normalize.clean_url(image) if isinstance(image, str) else ""
    image = image if image.startswith("https://") else None

    source_uid = occurrence_uid(canonical, start)
    return Item(
        source_slug=source.slug,
        source_uid=source_uid,
        event_id=uuid.uuid5(NAMESPACE, f"{source.slug}|{source_uid}"),
        title=title,
        # Зберігаємо факти й короткий уривок; повний текст лишається за canonical_url.
        description=normalize.clip(full_description, normalize.DESCRIPTION_LIMIT),
        category=category,
        category_how=category_how,
        source_type=normalize.schema_type(raw),
        city=event_city[:160] or city,
        address=(address or venue_name or event_city)[:300],   # CHECK у events
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


# Скільки майданчиків геокодити за місто. Один запит на майданчик, не на подію.
RESCUE_VENUES = 25


def _rescue_addresses(items, source, city, geocoder, counters) -> None:
    """Добирає адресу зі сторінки самої події для майданчиків, яких немає в індексі. Адресу
    вже опублікувало те саме джерело, просто в картці, а не в списку. Координату однаково рахує
    Photon з перевіркою за прямокутником міста: координати не вигадуються. Один запит на майданчик.
    """
    if geocoder is None:
        return
    blind = [i for i in items if i.latitude is None and i.canonical_url.startswith("https://")]
    if not blind:
        return
    by_venue: dict[str, list] = {}
    for item in blind:
        by_venue.setdefault(normalize.normalize_name(item.venue_name) or item.canonical_url,
                            []).append(item)
    counters["rescued_venues"] = 0
    counters["rescued_events"] = 0
    for venue_items in sorted(by_venue.values(), key=lambda v: -len(v))[:RESCUE_VENUES]:
        street = _street_from_detail(venue_items[0].canonical_url, source, counters)
        if not street:
            continue
        hit = geocoder.lookup_street(street)
        if not hit:
            continue
        south, west, north, east = CITY_BBOX[city]
        if not (south <= hit["lat"] <= north and west <= hit["lon"] <= east):
            continue
        counters["rescued_venues"] += 1
        for item in venue_items:
            item.latitude, item.longitude = hit["lat"], hit["lon"]
            item.venue_ref = hit.get("ref")
            # Щабель чесний: адреса зі сторінки події, а не збіг з OSM.
            item.venue_how = "detail"
            item.geo_confidence = 0.8
            item.address = item.address or street
            item.quality = _quality(item, source.weight, 1)
            if item.quality >= QUALITY_FLOOR:
                item.stage, item.reject_reason = "published", None
            counters["rescued_events"] += 1


def _street_from_detail(url: str, source, counters) -> str | None:
    try:
        page = get(url, delay=source.crawl_delay)
        if page.status != 200 or not page.body:
            return None
        counters["fetched"] = counters.get("fetched", 0) + 1
        for raw in extract.events_from_html(page.body):
            if not isinstance(raw, dict):
                continue
            _, _, street = normalize.address_of(raw)
            if street and any(ch.isdigit() for ch in street):
                return street
    except (PermissionError, OSError, ValueError):
        return None
    return None


def occurrence_uid(canonical: str, start: dt.datetime) -> str:
    """Розділяє сеанси, навіть коли джерело повторює той самий URL продажу."""
    return canonical + "#poruch-start=" + start.astimezone(dt.timezone.utc).isoformat()

# ---- Дедуплікація між джерелами

# Слова, що нічого не розрізняють.
_NOISE = {"концерт", "вистава", "шоу", "квитки", "київ", "гурт", "театр", "премʼєра",
          "прем'єра", "нового", "альбому", "тур", "презентація", "the", "band",
          "мюзикл", "музична", "комедія", "комедійне", "гумористичне",
          "amazing", "circus", "show", "неймовірне", "циркове"}


def _tokens(title: str) -> set[str]:
    words = normalize.normalize_name(title).split()
    return {w for w in words if len(w) >= 3 and w not in _NOISE}


# Допуск координат того самого майданчика. Один заклад з двох джерел бере точку з OSM і з
# Photon, і вони розходяться на 2–7 м; різні відповіді Photon на одну адресу — на 43–211 м.
# 25 м накриває перше; друге зливається лише в межах міста й потрапляє в `near_miss_pairs`. Від хибного злиття
# боронить перевірка слів у назві, а два різні заклади в межах однієї будівлі з однаковою
# афішею на ту саму хвилину неправдоподібні.
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
    if a.starts_at != b.starts_at:
        return False
    # Далі за `SAME_PLACE_METRES` зливаємо лише в межах міста: той самий концерт із двох афіш
    # роз'їжджається на кілометри через геокодинг (Feels Garden — 1,5 км, ATLAS — 3,5 км). На зрізі
    # бази це 29 пар із 441 і жодної хибної; без умови про місто — п'ять хибних із п'яти, бо
    # «сольний стендап» о 19:00 є і в Одесі, і в Харкові.
    if _metres(a, b) > SAME_PLACE_METRES and \
            normalize.normalize_name(a.city) != normalize.normalize_name(b.city):
        return False
    return _titles_agree(_tokens(a.title), _tokens(b.title))


def _titles_agree(ta: set[str], tb: set[str]) -> bool:
    """Вкладеність або два спільні значущі слова. Одного спільного слова у двох коротких назвах
    замало («вечір джазу» проти «вечір поезії»). Жанрові слова знімає _tokens.
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


def near_miss_pairs(items: list[Item]) -> list[tuple[Item, Item, float]]:
    """Пари, злиті попри розбіжність координат: (переможець, дубль, метри), найдальші перші.

    `same_event` зводить їх за містом, хвилиною й назвою, але принаймні одна з двох точок хибна.
    Дубль зник, хибна точка — ні. Функція нічого не змінює: це список майданчиків для
    aliases.json, щоб обидва джерела приходили до однієї точки.
    """
    by_key = {(i.source_slug, i.source_uid): i for i in items}
    out: list[tuple[Item, Item, float]] = []
    for item in items:
        winner = by_key.get(item.duplicate_of) if item.stage == "duplicate" else None
        if winner is None or None in (item.latitude, winner.latitude):
            continue
        d = _metres(winner, item)
        if d > SAME_PLACE_METRES:
            out.append((winner, item, d))
    return sorted(out, key=lambda p: -p[2])


def undecided_pairs(items: list[Item]) -> list[tuple[Item, Item]]:
    """Пари, які збіглися хвилиною й місцем, але не назвою — тобто де правило за словами пасує.

    Саме тут живуть переклади: «Львів Стартап Сніданок» від DOU і «Lviv Startup Breakfast» від
    йой! — нуль метрів, та сама хвилина, жодного спільного слова. Те саме з «ATTACK ON TITAN»
    проти «Атака титанів». Жодне правило на словах їх не зведе, бо слова різні за визначенням.

    Функція нічого не вирішує: вона лише називає питання, на яке відповідає агент.
    """
    live = [i for i in items if i.stage == "published" and i.latitude is not None]
    out: list[tuple[Item, Item]] = []
    for index, a in enumerate(live):
        for b in live[index + 1:]:
            if a.source_slug == b.source_slug or a.starts_at != b.starts_at:
                continue
            if _metres(a, b) > SAME_PLACE_METRES:
                continue
            if not _titles_agree(_tokens(a.title), _tokens(b.title)):
                out.append((a, b))
    return out


def drop_cross_source_duplicates(items: list[Item], weights: dict[str, float],
                                 agent=None) -> list[Item]:
    """Лишає канонічну копію — з джерела з вищою вагою — і прибирає решту.

    Канонічність за вагою джерела, а не за порядком обходу: інакше результат залежав би від того,
    яке джерело сьогодні відповіло першим.

    `agent` необовʼязковий. Якщо він є, після звичайного проходу в нього питають про пари, яких
    правило за словами не бере, — і тільки про них. Питати про решту немає сенсу: там відповідь
    уже відома й дешева.
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
        # Переможець за вагою джерела, але точка — за довірою до геокодингу: інакше на мапі
        # лишилась би гірша з двох.
        if _metres(winner, candidate) > SAME_PLACE_METRES and candidate.geo_confidence > winner.geo_confidence:
            for field in ("latitude", "longitude", "venue_ref", "venue_how", "venue_display", "geo_confidence"):
                setattr(winner, field, getattr(candidate, field))

    if agent is not None:
        pairs = undecided_pairs(items)
        for (a, b), same in zip(pairs, agent.judge_pairs(pairs)):
            if not same or a.stage != "published" or b.stage != "published":
                continue
            # Переможець за правилом (вага джерела, якість), а не за моделлю: та лише каже, чи це одна подія.
            keep, drop = ((a, b) if (weights.get(a.source_slug, 0), a.quality)
                          >= (weights.get(b.source_slug, 0), b.quality) else (b, a))
            drop.stage = "duplicate"
            drop.duplicate_of = (keep.source_slug, keep.source_uid)
            drop.reject_reason = f"DUPLICATE_OF {keep.source_slug} (agent)"
    return items
