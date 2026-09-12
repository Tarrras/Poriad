"""Нормалізація: тут гине більшість сміття.

Три пастки, кожна виміряна на живих даних (docs/event-discovery.md, розділ 1.3), і кожна має
точну поправку:

A. Час, якому не можна вірити, — і двома різними способами:

   · moemisto.ua позначає локальний київський час зсувом +0000 (12 сторінок із 12);
   · karabas.com робить гірше, бо непомітніше: він віддає **коректний зсув із урахуванням
     переходу на зимовий час**, тому виглядає бездоганно, але сам момент зсунуто вперед рівно
     на цей зсув. Його сторінка показує «17 жовтня 2026, 18:00», а JSON-LD каже
     `2026-10-17T21:00:00+03:00`. Правило, перевірене на 10 сторінках із 10: **UTC-момент
     karabas дорівнює правильному локальному часу**.

   Наївний парсинг зсуває кожну подію на 2–3 години; для застосунку про «сьогодні ввечері
   поруч» це гірше за відсутню подію. Поправка — tz_policy джерела, а не if у парсері.
B. Місто в URL не означає місто події: у загальному sitemap concert.ua друга ж перевірена подія
   виявилась львівською. Місто береться з addressLocality.
C. Опис із джерела — охороняється авторським правом, на відміну від фактів. Тому він обрізається
   до DESCRIPTION_LIMIT, а повний текст лишається за canonical_url.
"""
from __future__ import annotations

import datetime as dt
import hashlib
import html
import math
import re
import unicodedata

from .extract import offers_of, place_of

TITLE_MIN, TITLE_MAX = 3, 120          # CHECK на public.events.title

# Дзеркало CHECK на public.events.category і Rules.categories у спільному домені. Тримається тут,
# щоб конвеєр міг сказати «цієї категорії не існує», а не тихо записати вигадану.
CATEGORIES = ("music", "sport", "art", "food", "games", "outdoors", "social", "comedy", "kids",
              "tours", "conference")
DESCRIPTION_LIMIT = 200                # межа з docs/event-ingestion.md, розділ 8, пункт 2

try:
    from zoneinfo import ZoneInfo

    def _tz(name: str):
        return ZoneInfo(name)
except Exception:                      # pragma: no cover
    _tz = None


class _KyivFallback(dt.tzinfo):
    """EET/EEST без бази tzdata: остання неділя березня — остання неділя жовтня.

    Потрібен лише там, де в системі немає tzdata. Для інших поясів не годиться, тому
    використовується виключно як запасний варіант для Europe/Kyiv.
    """

    @staticmethod
    def _last_sunday(year: int, month: int) -> dt.datetime:
        d = dt.date(year, month, 31) if month != 4 else dt.date(year, month, 30)
        while d.month != month:
            d -= dt.timedelta(days=1)
        d -= dt.timedelta(days=(d.weekday() + 1) % 7)
        return dt.datetime(d.year, d.month, d.day, 3)

    def _dst_on(self, d: dt.datetime) -> bool:
        naive = d.replace(tzinfo=None)
        return self._last_sunday(d.year, 3) <= naive < self._last_sunday(d.year, 10)

    def utcoffset(self, d):
        return dt.timedelta(hours=3 if d and self._dst_on(d) else 2)

    def dst(self, d):
        return dt.timedelta(hours=1) if d and self._dst_on(d) else dt.timedelta(0)

    def tzname(self, d):
        return "EEST" if d and self._dst_on(d) else "EET"


def zone(name: str):
    if _tz is not None:
        try:
            return _tz(name)
        except Exception:
            pass
    return _KyivFallback()


# ------------------------------------------------------------------ текст

def clean_text(value) -> str:
    if not value:
        return ""
    if isinstance(value, (list, tuple)):
        value = next((v for v in value if v), "")
    s = html.unescape(str(value))
    s = re.sub(r"<[^>]+>", " ", s)                 # у описах трапляється розмітка
    s = s.replace("\r\n", "\n").replace("\r", "\n")
    s = unicodedata.normalize("NFC", s)
    s = re.sub(r"[ \t ]+", " ", s)
    return re.sub(r"\n{3,}", "\n\n", s).strip()


def clip(text: str, limit: int) -> str:
    """Обрізання по межі слова: обрив посеред слова читається як помилка застосунку."""
    text = text.strip()
    if len(text) <= limit:
        return text
    cut = text[:max(0, limit - 1)].rstrip()
    space = cut.rfind(" ")
    if space > limit * 0.6:
        cut = cut[:space]
    return cut.rstrip(" ,.;:—-") + "…"


def normalize_title(raw) -> str | None:
    t = clean_text(raw)
    t = re.sub(r"\s*\|\s*$", "", t)
    if len(t) < TITLE_MIN:
        return None
    return clip(t, TITLE_MAX) if len(t) > TITLE_MAX else t


def normalize_name(raw: str) -> str:
    """Ключ зіставлення майданчиків: регістр, пунктуація й службові слова прибрані."""
    s = clean_text(raw).lower().replace("ʼ", "'").replace("’", "'")
    s = re.sub(r"^\s*місце проведення\s*:?\s*", "", s)
    s = re.sub(r"[«»\"'`()\[\]{}.,:;!?/\\_—–-]", " ", s)
    s = re.sub(r"\s+", " ", s).strip()
    # «ім.» і «імені» — те саме слово, але після зняття крапки це два різні токени, і заклад із
    # повною назвою не зіставляється сам із собою. Розкол є з обох боків: в OSM Одеси 34 назви
    # пишуть «ім» і 4 «імені», в Києві 79 проти 65. Театр Франка стояв у черзі перегляду з пʼятьма
    # подіями саме через це — в дампі він є під тією ж назвою, слово в слово, крім цього скорочення.
    # Розгортаємо коротку форму в повну, а не навпаки: «імені» однозначне, а «ім» збігається з
    # початком інших слів.
    return re.sub(r"\bім\b", "імені", s)


# ------------------------------------------------------------------ час

_ISO = re.compile(
    r"(?P<date>\d{4}-\d{2}-\d{2})[T ](?P<time>\d{2}:\d{2}(:\d{2})?)"
    r"(?P<off>Z|[+-]\d{2}:?\d{2})?")


def parse_datetime(raw, tz_policy: str, tz_name: str) -> dt.datetime | None:
    """Повертає aware-datetime згідно з політикою джерела.

    `source`       — вірити зсуву як є (concert.ua);
    `force_local`  — зсув ігнорувати, цифри читати як локальний час (moemisto);
    `utc_is_local` — привести до UTC, а тоді ці цифри прочитати як локальний час (karabas).
    """
    if not raw:
        return None
    m = _ISO.search(str(raw))
    if not m:
        return None
    time_part = m.group("time")
    if len(time_part) == 5:
        time_part += ":00"
    try:
        naive = dt.datetime.fromisoformat(f"{m.group('date')}T{time_part}")
    except ValueError:
        return None

    off = m.group("off")
    if tz_policy == "force_local" or not off:
        return naive.replace(tzinfo=zone(tz_name))
    if off == "Z":
        delta = dt.timedelta(0)
    else:
        sign = 1 if off[0] == "+" else -1
        digits = off[1:].replace(":", "")
        delta = sign * dt.timedelta(hours=int(digits[:2]), minutes=int(digits[2:4]))
    if off != "Z" and (int(digits[:2]) > 23 or int(digits[2:4]) > 59):
        return None
    aware = naive.replace(tzinfo=dt.timezone(delta))
    if tz_policy == "utc_is_local":
        # Момент за UTC несе правильні цифри стінного годинника — лишається прочитати їх
        # як локальний час міста.
        return aware.astimezone(dt.timezone.utc).replace(tzinfo=None).replace(tzinfo=zone(tz_name))
    return aware


# Джерела масово не віддають endDate (moemisto — 0 із 12), а ends_at у нас NOT NULL і має бути
# більшим за starts_at. Тривалість за замовчуванням — з категорії, а не одна на всіх.
DEFAULT_HOURS = {"music": 3.0, "art": 2.0, "sport": 1.5, "games": 3.0,
                 "food": 2.0, "outdoors": 2.0, "social": 2.0,
                 "comedy": 2.0,          # сет зазвичай година-півтори плюс антракт
                 "kids": 1.5}            # дитяча вистава коротша за дорослу


def resolve_end(start: dt.datetime, raw_end, category: str,
                tz_policy: str, tz_name: str) -> tuple[dt.datetime, bool]:
    end = parse_datetime(raw_end, tz_policy, tz_name)
    if end and end > start:
        return end, True
    return start + dt.timedelta(hours=DEFAULT_HOURS.get(category, 2.0)), False


# ------------------------------------------------------------------ категорія

_BY_TYPE = {
    "MusicEvent": "music", "Festival": "music",
    # Стендап — окрема категорія, а не різновид мистецтва: саме на нього йде
    # цільова аудиторія продукту, і в спільній скриньці з театром він губиться.
    "ComedyEvent": "comedy",
    "TheaterEvent": "art", "ExhibitionEvent": "art", "ScreeningEvent": "art",
    "LiteraryEvent": "art", "DanceEvent": "art",
    "VisualArtsEvent": "art",
    "SportsEvent": "sport", "FoodEvent": "food",
    # 91 подія по пʼятьох містах — 15% кошика art. Це знайшов report.category_gaps: дитяча
    # програма має свою аудиторію (батьки шукають саме її) і в спільній скриньці з драмою
    # губиться так само, як губився стендап.
    "ChildrensEvent": "kids",
    # Ділова подія — не «зустріч». Конференції, форуми й воркшопи мають власну аудиторію,
    # яка шукає саме їх, і в кошику `social` вони губилися разом із побаченнями наосліп.
    "BusinessEvent": "conference", "EducationEvent": "conference",
    "SocialEvent": "social",
}

# Лексикон іде другим щаблем — після @type, але до будь-якої моделі. Українською й російською,
# бо джерела двомовні.
_LEXICON = [
    # Екскурсії стоять ПЕРЕД outdoors навмисно: «прогулянка» й «екскурсія» трапляються в обох
    # описах, і без цього порядку кожна міська прогулянка з гідом лишалась би «природою».
    # Детектор прогалин показав це прямо: «екскурсія» займала 50% кошика outdoors.
    # «Піша прогулянка» — екскурсія, «велопрогулянка» — природа. Тому саме піша, а не будь-яка:
    # бере «прогулянку» цілком означало б забрати в outdoors те, заради чого він існує.
    ("tours", r"екскурс|оглядов[аі]|квест|спадщин|кам.?яниц|вежа|катедр|гімназі|дендрарій|"
              r"піш[аоі][^|]{0,3}прогулянк|прогулянка містом|"
              r"каплиц|садиб|вілла|палац[уі]\b|старе місто|підземелл"),
    ("sport", r"забіг|марафон|пробіжк|бігов|велопрогулянк|воркаут|йог[аи]|тренуванн|фітнес|заплив|турнір"),
    ("outdoors", r"похід|прогулянк|треккінг|сплав|пікнік|на природі|парк[уі]\b"),
    ("games", r"настолк|настільн|квіз|мафі[яї]|покер|турнір з|кіберспорт|гейм"),
    ("food", r"дегустац|кулінарн|винн|гастро|вечер[яі]|сніданок|пікнік|фудкорт"),
    ("comedy", r"стендап|стенд-ап|stand.?up|імпровіз|импровиз|комік|гуморист|відкритий мікрофон|open ?mic"),
    ("art", r"вистав|театр|галере|вернісаж|виставк|кіно|фільм|поез|лекц|музе"),
    # «рок» і «реп» — з межами слова. Без них «рок» ловився в «рокУ» і «рокІВ», і лекція
    # «Пастка серпня 1939 року» ставала музикою. Дефіс лишаємо: «рок-опера» це музика.
    ("music", r"концерт|музичн|джаз|\bрок\b|рок-|\bреп\b|реп-|діджей|dj\b|акустичн|сольник|"
              r"гурт|оркестр|orchestra|симфон|філармон|вокальн"),
    ("conference", r"конференц|конфереnc|форум|\bforum\b|\bexpo\b|\bsummit\b|саміт|конфа|нетворк|мітап|meetup|\\bday 20\\d\\d|marketing|startup|стартап|e.?commerce"),
    ("social", r"розмовн клуб|воркшоп|майстер.?клас|знайомств|спілкуванн"),
]


def schema_type(event: dict) -> str:
    """Тип schema.org як рядок. Саме він, а не слова в заголовку, розрізняє РІД події."""
    t = event.get("@type")
    if isinstance(t, list):
        t = next((x for x in t if isinstance(x, str)), None)
    return t if isinstance(t, str) else "—"


def classify_with_reason(event: dict, title: str, venue: str) -> tuple[str, str]:
    """Категорія і **щабель**, який її обрав: `type`, `lexicon` або `fallback`.

    Щабель потрібен не для налагодження, а щоб прогалина в категоріях була видимою. Останній
    рядок цієї функції — `social` за замовчуванням — тихо ковтає все, чого ми не розпізнали:
    подія отримує категорію, виглядає обробленою, і ніхто ніколи не дізнається, що для неї
    просто не було скриньки. Саме так довго ховався стендап.

    Хто рахує ці щаблі — `report.category_gaps`.
    """
    types = event.get("@type") if isinstance(event.get("@type"), list) else [event.get("@type")]
    for t in types:
        if t in _BY_TYPE:
            return _BY_TYPE[t], "type"
    haystack = f"{title} {venue}".lower()
    for category, pattern in _LEXICON:
        if re.search(pattern, haystack):
            return category, "lexicon"
    return "social", "fallback"


def classify(event: dict, title: str, venue: str) -> str:
    return classify_with_reason(event, title, venue)[0]


# ------------------------------------------------------------------ ціна

def parse_price(event: dict) -> tuple[float | None, bool | None]:
    prices: list[float] = []
    for offer in offers_of(event):
        if str(offer.get("priceCurrency") or "UAH").upper() != "UAH":
            continue
        for key in ("price", "lowPrice", "minPrice"):
            raw = offer.get(key)
            if raw in (None, ""):
                continue
            try:
                value = float(str(raw).replace(",", ".").replace(" ", ""))
                if math.isfinite(value) and value >= 0:
                    prices.append(value)
            except ValueError:
                continue
    if prices:
        low = min(prices)
        return low, low == 0
    text = clean_text(event.get("description")).lower()
    if re.search(r"безкоштовн|вхід вільний|free entry|бесплатн", text):
        return 0.0, True
    return None, None


# ------------------------------------------------------------------ адреса й місто

def address_of(event: dict) -> tuple[str, str, str]:
    """Повертає (повна адреса, місто, вулична адреса).

    Вулична адреса віддається окремо, бо геокодувати можна тільки її: назва закладу, віддана
    геокодеру, повертає впевнено неправильну точку (див. шапку geocode.py).
    Місто — з addressLocality, ніколи з URL (пастка B).
    """
    place = place_of(event)
    addr = place.get("address")
    if isinstance(addr, str):
        return clean_text(addr), "", ""
    if not isinstance(addr, dict):
        return clean_text(place.get("name")), "", ""
    street = clean_text(addr.get("streetAddress"))
    city = clean_text(addr.get("addressLocality"))
    venue = clean_text(place.get("name"))
    parts = [p for p in (venue, street, city) if p]
    seen, ordered = set(), []
    for p in parts:
        if p.lower() not in seen:
            seen.add(p.lower())
            ordered.append(p)
    return ", ".join(ordered)[:300], city, street


def content_hash(*parts) -> str:
    return hashlib.sha256("|".join(str(p) for p in parts).encode()).hexdigest()
