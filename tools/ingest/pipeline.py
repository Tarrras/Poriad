"""Оркестрація: сторінка-список -> нормалізовані події -> SQL.

Стадії з docs/event-ingestion.md, стиснуті до тих, що справді потрібні для джерел рівня B:
    S1 fetch -> S2 extract -> S3 normalize -> S4 venue -> S6 score -> S7 emit
S0 discover зводиться до списку listing_urls (сторінка-список сама є точкою входу), S5 dedupe
рахує ключ блокування, але злиття лишається на боці бази, де видно вже опубліковані події.
"""
from __future__ import annotations

import dataclasses
import datetime as dt
import math
import uuid

from . import extract, normalize
from .fetch import get
from .sources import Source
from .geocode import Geocoder
from .venues import VenueIndex

# Простір імен для детермінованих ідентифікаторів: повторний запуск має давати ті самі UUID,
# інакше кожен обхід створює дублікати замість оновлення.
NAMESPACE = uuid.UUID("8b1f0a2e-6d3c-4a5b-9e7f-2c4d6a8b0e13")

QUALITY_FLOOR = 0.55            # той самий поріг, що в private.is_discoverable


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
            geocoder: Geocoder | None = None) -> tuple[list[Item], dict]:
    """Обхід однієї сторінки-списку. Повертає (елементи, лічильники запуску)."""
    now = now or dt.datetime.now(dt.timezone.utc)
    url = source.listing_urls[city]
    counters = {"fetched": 0, "parsed": 0, "geocoded": 0,
                "published": 0, "rejected": 0, "review": 0}

    response = get(url, delay=source.crawl_delay)
    if response.status != 200 or not response.body:
        return [], {**counters, "error": f"HTTP {response.status}"}
    counters["fetched"] = 1

    raw_events = extract.events_from_html(response.body)
    counters["parsed"] = len(raw_events)

    items: list[Item] = []
    for raw in raw_events:
        item = _build(raw, source, city, index, now, geocoder)
        if item is None:
            counters["rejected"] += 1
            continue
        items.append(item)

    # Серія — та сама назва на тому самому майданчику багато разів. Довгі серії сеансів
    # заповнюють мапу однаковими пінами, тому знижують якість, а не підвищують.
    series: dict[tuple[str, str], int] = {}
    for it in items:
        key = (normalize.normalize_name(it.title), normalize.normalize_name(it.venue_name))
        series[key] = series.get(key, 0) + 1

    for it in items:
        key = (normalize.normalize_name(it.title), normalize.normalize_name(it.venue_name))
        it.quality = _quality(it, source.weight, series[key])
        if it.latitude is None:
            it.stage, it.reject_reason = "review", "NO_GEO"
            counters["review"] += 1
        elif it.quality < QUALITY_FLOOR:
            it.stage, it.reject_reason = "review", f"LOW_QUALITY {it.quality}"
            counters["review"] += 1
        else:
            it.stage = "published"
            counters["published"] += 1
            counters["geocoded"] += 1
    return items, counters


def _build(raw: dict, source: Source, city: str, index: VenueIndex,
           now: dt.datetime, geocoder: Geocoder | None = None) -> Item | None:
    title = normalize.normalize_title(raw.get("name"))
    if not title:
        return None

    start = normalize.parse_datetime(raw.get("startDate"), source.tz_policy, source.time_zone)
    if not start or start <= now:
        return None                                    # минулі події на мапу не потрапляють

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

    full_description = normalize.clean_text(raw.get("description"))
    price_min, is_free = normalize.parse_price(raw)

    # Порядок навмисний: звірене людиною -> дамп OSM -> Photon. Кожен наступний щабель менш
    # надійний, і confidence це відображає, тож слабка точка сама опускає quality до порога.
    hit = index.match(venue_name) or index.match(address.split(",")[0])
    if hit is None and geocoder is not None:
        hit = geocoder.lookup_street(street)
    image = raw.get("image")
    if isinstance(image, dict):
        image = image.get("url")
    if isinstance(image, list):
        image = next((i for i in image if isinstance(i, str)), None)
    image = image if isinstance(image, str) and image.startswith("https://") else None

    return Item(
        source_slug=source.slug,
        source_uid=canonical,
        event_id=uuid.uuid5(NAMESPACE, f"{source.slug}|{canonical}"),
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
    )

# ------------------------------------------------------------------ дедуплікація між джерелами

# Слова, які нічого не розрізняють: вони є в половині афіші.
_NOISE = {"концерт", "вистава", "шоу", "квитки", "київ", "гурт", "театр", "премʼєра",
          "прем'єра", "нового", "альбому", "тур", "презентація", "the", "band"}


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
    """Чи називають дві назви ту саму подію.

    Раніше тут стояло входження множин: одна назва мусила бути підмножиною іншої. На перевірці
    проти бази це правило зловило **нуль** із 46 справжніх дублікатів, які лишились у базі після
    обходу пʼяти міст. Причина в тому, що джерела прикрашають назву кожне по-своєму, і жодна
    сторона не є підмножиною іншої:

        karabas        «Карміна Бурана (ДАТОБ)»        — дописує абревіатуру театру
        internet-bilet «Кантата «Карміна Бурана»»      — дописує жанр

    Кожна сторона має слово, якого немає в другої, тож входження провалюється в обидва боки.

    Нове правило вимагає спільних слів, а скільки саме — залежить від довжини коротшої назви.
    Одного спільного слова досить, коли назва й складається з одного-двох значущих слів: «Вій»,
    «Баядерка», «Брехуха» — це і є вся її суть. Довша назва має збігтися щонайменше двома, бо в
    ній одне випадкове спільне слово важить менше.

    Межу перевірено на 49 парах із бази, які збіглися хвилиною початку й стоять у межах 25 м —
    тобто на всій сукупності, а не на вибірці. Серед них 46 справжніх дублікатів і 3 різні події
    в тому самому залі: «Дванадцята ніч» проти «Лісової пісні», стендап Шумка проти симфонічного
    концерту, KLER проти вечора Іздрика. Усі три мають НУЛЬОВЕ перекриття слів, тож проміжок між
    класами чистий, а не підігнаний. Правило бере 44 з 46 і не зливає жодної з трьох.

    Два, яких воно свідомо не бере:
      «ATTACK ON TITAN…» проти «Атака титанів…» — переклад, спільних слів немає взагалі; жодне
      правило на словах його не візьме.
      «Н. Могилевська на фестивалі…» проти «Наталія Могилевська та Дмитро Коляденко…» — день
      фестивалю, який джерела підписали різними хедлайнерами. Пропустити такий випадок безпечніше,
      ніж послабити межу.
    """
    if not ta or not tb:
        return False
    shared = len(ta & tb)
    shorter = min(len(ta), len(tb))
    return shared >= (1 if shorter <= 3 else 2)


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
    published = [i for i in items if i.stage == "published"]
    dropped: set[str] = set()
    for idx, a in enumerate(published):
        if a.source_uid in dropped:
            continue
        for b in published[idx + 1:]:
            if b.source_uid in dropped or not same_event(a, b):
                continue
            loser = b if weights.get(a.source_slug, 0) >= weights.get(b.source_slug, 0) else a
            loser.stage = "duplicate"
            loser.reject_reason = f"DUPLICATE_OF {(a if loser is b else b).source_slug}"
            dropped.add(loser.source_uid)
    return items
