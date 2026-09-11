"""Реєстр джерел — дзеркало рядків public.event_sources.

Тут описані лише перевірені джерела. Числа в коментарях виміряні
tools/probe_event_sources.py 2026-09-07; вони змінюються, тож перед підключенням
нового міста запускайте пробу, а не довіряйте цим цифрам.
"""
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
    time_zone: str = "Europe/Kyiv"
    enabled: bool = True
    note: str = ""


SOURCES: list[Source] = [
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
        # Зсув віддає коректний, з урахуванням переходу на зимовий час, — і саме тому вада
        # непомітна. Але момент зсунуто вперед рівно на цей зсув: сторінка показує 18:00,
        # JSON-LD каже 21:00+03:00. Перевірено на 10 сторінках із 10.
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
        weight=0.8,
        crawl_delay=2.0,                     # robots.txt без Crawl-delay; беремо стриманий власний
        note="Найчистіші дані: endDate 100%, offers 100%, коректний перехід на зимовий час.",
    ),
    Source(
        slug="internet_bilet",
        name="Internet-Bilet",
        base_url="https://internet-bilet.ua",
        # Той самий шаблон, що в karabas: субдомен на місто, JSON-LD просто на сторінці-списку.
        listing_urls={"Київ": "https://kyiv.internet-bilet.ua/uk",
                      "Львів": "https://lviv.internet-bilet.ua/uk",
                      "Харків": "https://kharkiv.internet-bilet.ua/uk",
                      "Одеса": "https://odesa.internet-bilet.ua/uk",
                      "Дніпро": "https://dnipro.internet-bilet.ua/uk"},
        # Вище за karabas (у нього доведена вада часу), нижче за concert.ua. Вага тут майже не
        # впливає на поріг якості — вона вирішує, чия копія лишається канонічною при дедуплікації.
        # Тримати нижче за найдовіренішого навмисно: прихована вада тоді проявиться як видимий
        # дубль, а не як тиха заміна добрих даних. Саме так свого часу знайшлась вада karabas.
        weight=0.75,
        crawl_delay=2.0,                     # robots.txt без Crawl-delay; беремо стриманий власний
        # Зсуви DST-коректні, і — головне — звірені з часом на самій сторінці: 8 із 8 збіглись.
        # Вказано явно, а не лишено дефолтом, щоб було видно, що це виміряно, а не припущено.
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
