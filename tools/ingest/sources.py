"""Реєстр джерел — дзеркало рядків public.event_sources.

Тут описані лише перевірені джерела. Числа в коментарях виміряні
tools/probe_event_sources.py 2026-09-07; вони змінюються, тож перед підключенням
нового міста запускайте пробу, а не довіряйте цим цифрам.
"""
from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(frozen=True)
class Source:
    slug: str
    name: str                      # показуємо як «Афіша · <name>»
    base_url: str
    listing_urls: dict             # місто -> URL сторінки-списку
    weight: float                  # вага в ранжуванні, за виміряною якістю даних
    crawl_delay: float
    licence: str = "jsonld_public"
    # 'source'       — вірити зсуву в даних (concert.ua);
    # 'force_local'  — зсув ігнорувати, цифри читати як локальний час (moemisto);
    # 'utc_is_local' — привести до UTC, а тоді ці цифри читати як локальний час (karabas).
    tz_policy: str = "source"
    # Чи вірити типу schema.org: "trust" або "weak" (concert.ua ставить `MusicEvent` усьому).
    type_policy: str = "trust"
    # Каталоги джерела: сегмент URL -> наша категорія. Відповідь продавця про жанр, точніша за
    # здогад по назві. Обходяться на додачу до головного списку: вони не збігаються.
    catalogs: dict | None = None
    catalog_url: str | None = None          # шаблон із {city} і {slug}
    city_slugs: dict | None = None          # наша назва міста -> сегмент у URL джерела
    time_zone: str = "Europe/Kyiv"
    enabled: bool = True
    note: str = ""
    detail_path: str | None = None
    max_details: int = 100
    # Каталог карток за sitemap: сторінка-список віддає лише 20 посилань, повний перелік — у sitemap.
    # Беруться URL міста `<city_slugs[місто]>/…-РРРР-ММ-ДД` з датою від сьогодні до horizon_days.
    sitemap_url: str | None = None
    sitemap_prefix: str | None = None       # шаблон початку URL карток із {city}
    horizon_days: int = 30
    # >0 — картки (JSON-LD) читаються з диска, поки їм менше стільки діб. Для джерел із сотнями карток
    # на місто: час сеансу й ціна в картці змінюються рідко, а кожен запит коштує crawl_delay.
    # Якщо sitemap віддає lastmod, картка з кешу вірна, доки він не змінився (тоді це лише стеля віку);
    # без lastmod ціна — застарілі дані до ttl. 0 — завжди читати наживо.
    detail_ttl_days: float = 0
    # Події, до яких лишилось не більше `detail_near_days` (за датою в slug), читаються не рідше ніж
    # раз на `detail_near_ttl_days`: біля дати ціна й наявність квитків важать найбільше.
    detail_near_days: int = 7
    detail_near_ttl_days: float = 1
    # Заголовок розділу на сторінці-списку з подіями, що скасували чи перенесли: його картки читаються
    # наживо (поза sitemap-вікном і кешем), бо кеш інакше ховав би свіже скасування до ttl.
    status_heading: str | None = None
    # false — addressLocality джерела ламаний (хвіст вулиці: «З», «Ніжинська»), місто беремо зі списку.
    trust_locality: bool = True
    # true — список не віддає виконавців, їх читаємо з картки події (кеш на диску, щоб повторний
    # прогін не ходив по сотні сторінок): Concert.ua дає `performer[]` і повний опис із лайнапом.
    performer_details: bool = False
    # jsonld — загальний шлях список/сторінка; іменовані адаптери можуть доповнити метадані до нормалізації.
    adapter: str = "jsonld"


SOURCES: list[Source] = [
    Source(
        slug="dou", name="DOU", base_url="https://dou.ua",
        listing_urls={"Київ": "https://dou.ua/calendar/city/Kyiv/",
                      "Львів": "https://dou.ua/calendar/city/Lviv/",
                      "Харків": "https://dou.ua/calendar/city/Kharkiv/",
                      "Одеса": "https://dou.ua/calendar/city/Odesa/",
                      "Дніпро": "https://dou.ua/calendar/city/Dnipro/"},
        weight=0.72, crawl_delay=2.0, adapter="dou", max_details=60,
        note="2026-09-11: картки мають JSON-LD; date-only початок доповнюється iCal. "
             "Онлайн та події іншого міста не імпортуються.",
    ),
    Source(
        slug="yoy", name="йой!", base_url="https://yoy.events",
        listing_urls={"Львів": "https://yoy.events/events"},
        weight=0.72, crawl_delay=2.0, adapter="yoy", max_details=60,
        note="2026-09-11: точні UTC start/end, статус і offers у JSON-LD. "
             "Інші міста додавати після окремої живої проби.",
    ),
    Source(
        slug="lviv_travel", name="lviv.travel", base_url="https://lviv.travel",
        listing_urls={"Львів": "https://lviv.travel/ua/events"},
        weight=0.78, crawl_delay=2.0, adapter="culture:lviv-travel", max_details=40,
        note="Офіційний туристичний портал; приймаються лише картки з точним часом або "
             "явні сеанси програм із адресою.",
    ),
    Source(
        slug="artsvit", name="Артсвіт", base_url="https://artsvit.dp.ua",
        listing_urls={"Дніпро": "https://artsvit.dp.ua/"},
        weight=0.75, crawl_delay=2.0, adapter="culture:artsvit", max_details=30,
        enabled=False,
        note="Адаптер готовий до точного Event JSON-LD; поточні відносні дати й періоди "
             "програм лишаються review, тому джерело поки вимкнено.",
    ),
    Source(
        slug="yermilovcentre", name="YermilovCentre", base_url="https://yermilovcentre.org",
        listing_urls={"Харків": "https://yermilovcentre.org/"},
        weight=0.75, crawl_delay=2.0, adapter="culture:yermilovcentre", max_details=30,
        enabled=False,
        note="Адаптер не вгадує години виставок; штатна robots-перевірка наразі блокує обхід.",
    ),
    Source(
        slug="run_ukraine", name="Run Ukraine", base_url="https://runukraine.org",
        listing_urls={"Київ": "https://recruitrun.runukraine.org/kalendar-podij/"},
        weight=0.8, crawl_delay=2.0, adapter="culture:run-ukraine", max_details=30,
        enabled=False,
        note="Адаптер приймає лише точні SportsEvent; календар без підтверджених стартів "
             "залишається review.",
    ),
    Source(
        slug="ticketsbox", name="TicketsBox", base_url="https://ticketsbox.com",
        listing_urls={"Київ": "https://kyiv.ticketsbox.com/",
                      "Львів": "https://lviv.ticketsbox.com/",
                      "Одеса": "https://odesa.ticketsbox.com/"},
        weight=0.7, crawl_delay=2.0, detail_path="/event/",
        note="2026-09-11: Event JSON-LD у картках, адреси й іноді geo; список дає посилання. "
             "Обхід обмежено 100 картками/місто.",
    ),
    Source(
        slug="badseller",
        name="Badseller",
        base_url="https://badseller.net",
        # Список віддає 20 посилань і пагінації не має; повний перелік — sitemap (див. sitemap_url).
        listing_urls={"Київ": "https://badseller.net/afisha/kyiv",
                      "Львів": "https://badseller.net/afisha/lviv",
                      "Харків": "https://badseller.net/afisha/kharkiv",
                      "Одеса": "https://badseller.net/afisha/odesa",
                      "Дніпро": "https://badseller.net/afisha/dnipro"},
        city_slugs={"Київ": "kyiv", "Львів": "lviv", "Харків": "kharkiv",
                    "Одеса": "odesa", "Дніпро": "dnipro"},
        sitemap_url="https://badseller.net/sitemaps/afisha.xml",
        sitemap_prefix="https://badseller.net/afisha/{city}/",
        # Агрегатор квитків: дані з Kontramarka, Karabas, Concert.ua. Вага трохи нижча за оригінали
        # (0.7+), щоб канонічною лишалась їхня копія. Нижче 0.69 події з Photon-адресою падають
        # під QUALITY_FLOOR: опис шаблонний, endDate лише датою.
        weight=0.69, crawl_delay=1.5, max_details=1200, trust_locality=False,
        status_heading="Скасовано й перенесено",   # на /afisha/{місто}: «щоночі звіряємо всіх операторів»
        # 1720 карток × 1,5 с = 43 хв — основна частина всього обходу. lastmod зі sitemap ловить зміну
        # статусу й часу, але не ціни (аудит 2026-10-04: 15 зі 150 карток, серед них 1290 → 1690 грн),
        # тож вік карток обмежено: ціна застаріває щонайбільше на стільки діб.
        detail_ttl_days=3,
        note="2026-10-01: Event JSON-LD у кожній картці (час зі зсувом, місце з адресою, ціна, фото); "
             "endDate лише датою → тривалість за категорією. Дата в URL старіша за сеанс на застарілих "
             "посиланнях — їх не беремо. Опис шаблонний («… — вистава, 2 жовтня о 18:00 …»).",
    ),
    Source(
        slug="karabas",
        name="Karabas",
        base_url="https://karabas.com",
        listing_urls={"Київ": "https://kyiv.karabas.com/",
                      "Львів": "https://lviv.karabas.com/",
                      "Харків": "https://kharkiv.karabas.com/",
                      "Одеса": "https://odesa.karabas.com/",
                      "Дніпро": "https://dnipro.karabas.com/"},
        weight=0.7,
        crawl_delay=1.0,                     # robots.txt: Crawl-delay: 1
        # Зсув коректний, але момент зсунуто вперед на нього: сторінка 18:00, JSON-LD 21:00+03:00.
        tz_policy="utc_is_local",
        note="147 подій за один запит, 8 типів schema.org, streetAddress у 147 зі 147.",
    ),
    Source(
        slug="concert_ua",
        name="Concert.ua",
        base_url="https://concert.ua",
        listing_urls={"Київ": "https://concert.ua/uk/kyiv",
                      "Львів": "https://concert.ua/uk/lviv",
                      "Харків": "https://concert.ua/uk/kharkiv",
                      "Одеса": "https://concert.ua/uk/odesa",
                      "Дніпро": "https://concert.ua/uk/dnipro"},
        weight=0.8, type_policy="weak", performer_details=True,
        crawl_delay=2.0,                     # robots.txt без Crawl-delay; беремо стриманий власний
        note="Найчистіші дані: endDate 100%, offers 100%, коректний перехід на зимовий час.",
        catalog_url="https://concert.ua/uk/catalog/{city}/{slug}",
        city_slugs={"Київ": "kyiv", "Львів": "lviv", "Харків": "kharkiv",
                    "Одеса": "odesa", "Дніпро": "dnipro"},
        # Лише однозначні каталоги. `festivals`, `gifts`, `other`, `new-year` пропущено: привід, а не рід.
        catalogs={"concerts": "music", "electronic": "music",
                  "humor": "comedy", "kids": "kids", "sport": "sport",
                  "theater": "art", "cinema": "art", "dance": "art", "circus": "art",
                  "show": "art", "tvorchii-vechir": "art",
                  "business": "conference", "excursions": "tours"},
    ),
    Source(
        slug="internet_bilet",
        name="Internet-Bilet",
        base_url="https://internet-bilet.ua",
        # Як karabas: субдомен на місто, JSON-LD на сторінці-списку.
        listing_urls={"Київ": "https://kyiv.internet-bilet.ua/uk",
                      "Львів": "https://lviv.internet-bilet.ua/uk",
                      "Харків": "https://kharkiv.internet-bilet.ua/uk",
                      "Одеса": "https://odesa.internet-bilet.ua/uk",
                      "Дніпро": "https://dnipro.internet-bilet.ua/uk"},
        # Вище за karabas, нижче за concert.ua: вага вирішує канонічну копію при дедуплікації,
        # і прихована вада має проявитись дублем, а не тихою заміною.
        weight=0.75, performer_details=True,    # виконавці лише в тексті картки (`descr-unified`)
        crawl_delay=2.0,                     # robots.txt без Crawl-delay; беремо стриманий власний
        # Явно, а не дефолтом: час звірено зі сторінкою, це виміряно.
        tz_policy="source",
        note="270 подій за один запит у Києві; endDate/offers/image/streetAddress по 100%. "
             "244 із 270 відсутні в karabas і concert.ua. Головне джерело стендапу.",
    ),
    Source(
        slug="moemisto",
        name="Моє місто",
        base_url="https://moemisto.ua",
        listing_urls={"Київ": "https://moemisto.ua/kiev",
                      "Львів": "https://moemisto.ua/lviv"},
        weight=0.5,
        crawl_delay=3.0,
        tz_policy="force_local",             # віддає локальний київський час зі зсувом +0000
        enabled=False,                       # вмикати після кроку 5 плану: потребує найбільше поправок
        note="endDate 0%, offers 33%, зсув часу зламано. Підключати третім, не першим.",
    ),
]


def enabled_sources() -> list[Source]:
    return [s for s in SOURCES if s.enabled]


def by_slug(slug: str) -> Source:
    for s in SOURCES:
        if s.slug == slug:
            return s
    raise KeyError(f"невідоме джерело: {slug}")
