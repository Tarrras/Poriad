"""Майданчики: дамп OpenStreetMap і зіставлення назв.

Навіщо. Жодне перевірене джерело подій не віддає координат — 0 із 293 записів на сторінках-списках
і 0 із 24 сторінок подій. Для гео-first застосунку це означає, що без майданчиків імпорту не існує.

Звідки. Overpass API повертає ~4 800 іменованих обʼєктів Києва одним запитом під ліцензією ODbL,
яка вимагає лише атрибуції.

Виміряна межа автоматики (52 майданчики, 267 подій concert.ua + karabas):
    вузький набір тегів   22/52 майданчиків -> 32% подій
    широкий набір тегів   28/52 майданчиків -> 48% подій
Незіставленими лишаються внутрішні скорочення афіш — «МЦКМ (Жовтневий палац)», «ORIGIN STAGE»,
«COMEDY SHELTER». І саме вони найбільші за кількістю подій (24, 23, 20). Тобто автоматика бере
довгий хвіст, а голову треба звести руками — година роботи на ~20 записів, після якої більшість
київських подій має точні координати назавжди. Для цього є aliases.json.

Про robots.txt. `overpass-api.de/robots.txt` містить `Disallow: /api/`. Це правило проти пошукових
краулерів, які інакше індексували б дорогі запити; клієнти API керуються окремою usage policy
(https://dev.overpass-api.de/overpass-doc/en/preface/commons.html). Ми її дотримуємось: один запит
на місто, результат кешується на диск, паралельних запитів немає. Для продакшену без жодної
неоднозначності є альтернатива — готові виgрузки Geofabrik, які публікуються саме для масового
завантаження.
"""
from __future__ import annotations

import json
import pathlib
import urllib.parse
import urllib.request

from .geocode import CITY_BBOX
from .normalize import normalize_name

# Overpass тримає ліміт на IP і під навантаженням відмовляє зʼєднанням. Дзеркала віддають ті самі
# дані, тож перебираємо їх по черзі: інакше один зайнятий інстанс блокує підключення цілого міста.
OVERPASS_MIRRORS = (
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
    "https://overpass.osm.ch/api/interpreter",
)
CACHE_DIR = pathlib.Path(__file__).resolve().parent / "cache"
ALIASES_PATH = pathlib.Path(__file__).resolve().parent / "aliases.json"

# Широкий набір тегів — саме він дав 48% замість 32%. Планетарії, галереї та палаци тут не для
# повноти, а тому що в них проходять реальні події з афіш.
#
# Другий захід зроблено, коли зʼясувалось, що «Тераса River Mall» і «Тераса Gulliver» стояли в
# черзі перегляду не через відсутність в OSM, а через відсутність у цьому переліку: обидва ТРЦ
# розмічені як `shop=mall`, якого ми не питали. Перелічений нижче набір — це 489 названих обʼєктів
# у самому лише Києві, яких індекс не бачив. Тег `amenity=concert_hall` окремо показовий: у Києві
# він рівно один, і це «Feels Live».
#
# Чого сюди свідомо НЕ додано, хоч воно й трапилось у тому ж вимірі:
#   leisure=garden (41)  — це садові центри, а не майданчики. І це буквально та пастка, через яку
#                          «Feels Garden» колись зіставився з «Garden»: чим більше в індексі назв
#                          зі словом «garden», тим імовірніший хибний збіг за входженням.
#   amenity=studio (24)  — телестудії, не події.
#   club=* (71)          — тег без сталого значення, від шахового гуртка до художньої школи.
#   shop=art (8)         — крамниці фарб, а не галереї.
# `building=civic` додано третім заходом: у прогоні Києва «Будинок офіцерів» очолив чергу
# перегляду з 32 подіями, і в OSM він є — але тегований саме так. Названих civic-будівель у
# чотирьох містах лише 47, і це рівно потрібний рід: будинки офіцерів, архітектора, палаци
# культури, «Український дім». Дешевий тег із високою часткою влучань.
# Кожна додана назва — це не лише шанс зіставитись, а й шанс зіставитись хибно. Тому набір
# розширено переліком значень, а не зняттям фільтра.
_TAGS = """
  nwr["amenity"~"^(theatre|cinema|arts_centre|community_centre|nightclub|library|bar|pub|restaurant|cafe|planetarium|exhibition_centre|conference_centre|events_venue|music_venue|concert_hall|food_court)$"](area.a);
  nwr["tourism"~"^(gallery|museum|attraction|theme_park|zoo|aquarium)$"](area.a);
  nwr["leisure"~"^(park|sports_centre|fitness_centre|stadium|dance|escape_game|amusement_arcade|bowling_alley)$"](area.a);
  nwr["shop"~"^(mall|books)$"](area.a);
  nwr["office"="coworking"](area.a);
  nwr["building"~"^(palace|civic)$"](area.a);
"""

_NAME_KEYS = ("name", "name:uk", "name:en", "alt_name", "official_name", "short_name", "brand")


def _query(city: str) -> str:
    """Запит за прямокутником міста, а не за іменованою адмінмежею.

    Раніше тут стояло `area["name"=<місто>]["admin_level"="4"]`. Для Києва це працює випадково:
    він має спецстатус і сидить на обласному рівні. Для решти рівень 4 — це область, і запит
    повертає **нуль обʼєктів, а не помилку**: індекс мовчки виходить порожній, усе тихо
    відкочується на Photon, і виглядає це як «в OSM нічого немає».

    Рівень адмінмежі різниться від міста до міста й від правок у OSM, тож вгадувати його — це
    відтворювати ту саму тиху ваду. Прямокутник же вже потрібен геокодеру (`geocode.CITY_BBOX`),
    він один на місто й перевіряється очима. Одне джерело правди замість двох.
    """
    if city not in CITY_BBOX:
        raise KeyError(
            f"немає прямокутника для міста {city!r}. Додайте його в geocode.CITY_BBOX — "
            f"без нього і дамп OSM, і геокодер мовчки нічого не знайдуть."
        )
    south, west, north, east = CITY_BBOX[city]
    tags = _TAGS.replace("(area.a)", f"({south},{west},{north},{east})")
    return f"[out:json][timeout:180];({tags});out tags center;"


def fetch_osm(city: str, *, refresh: bool = False) -> list[dict]:
    """Дамп майданчиків міста. Кешується: повторний запит до Overpass — марна витрата чужого CPU."""
    CACHE_DIR.mkdir(exist_ok=True)
    cache = CACHE_DIR / f"osm_{normalize_name(city).replace(' ', '_')}.json"
    if cache.exists() and not refresh:
        return json.loads(cache.read_text("utf-8"))["elements"]

    body = urllib.parse.urlencode({"data": _query(city)}).encode()
    problems: list[str] = []
    for endpoint in OVERPASS_MIRRORS:
        req = urllib.request.Request(
            endpoint, data=body,
            headers={"Accept": "application/json",       # без цього Overpass віддає 406
                     "Content-Type": "application/x-www-form-urlencoded",
                     "User-Agent": "PoruchBot/0.1 (+https://poruch.app/bot)"})
        try:
            with urllib.request.urlopen(req, timeout=240) as r:
                payload = json.loads(r.read().decode("utf-8"))
        except Exception as exc:
            problems.append(f"{urllib.parse.urlsplit(endpoint).netloc}: {exc}")
            continue
        elements = payload.get("elements") or []
        # Місто без жодного майданчика — не відповідь, а несправність: або дзеркало віддало
        # порожнечу (буває на старших копіях бази), або прямокутник не там. Кешувати це означає
        # закріпити ваду на диску, тож пробуємо наступне дзеркало.
        if not elements:
            problems.append(f"{urllib.parse.urlsplit(endpoint).netloc}: порожній дамп"
                            + (f" ({payload['remark']})" if payload.get("remark") else ""))
            continue
        cache.write_text(json.dumps(payload, ensure_ascii=False), "utf-8")
        return elements
    # Порожній дамп мовчки — це саме та вада, від якої ми щойно позбулись у _query.
    raise RuntimeError(f"жодне дзеркало Overpass не відповіло для {city!r}: " + "; ".join(problems))


class VenueIndex:
    """Пошук координат за назвою майданчика з афіші."""

    def __init__(self, elements: list[dict], city: str, aliases: dict[str, str] | None = None):
        self.city = city
        self.aliases = {normalize_name(k): v for k, v in (aliases or {}).items()
                        if not k.startswith("_")}
        self.by_name: dict[str, dict] = {}
        for el in elements:
            tags = el.get("tags") or {}
            lat = el.get("lat") or (el.get("center") or {}).get("lat")
            lon = el.get("lon") or (el.get("center") or {}).get("lon")
            if lat is None or lon is None:
                continue
            record = {"lat": float(lat), "lon": float(lon),
                      "display": tags.get("name") or tags.get("name:uk") or "",
                      "ref": f"{el.get('type')}/{el.get('id')}"}
            for key in _NAME_KEYS:
                if tags.get(key):
                    self.by_name.setdefault(normalize_name(tags[key]), record)

    def match(self, raw_name: str) -> dict | None:
        """Три щаблі за спаданням надійності. confidence чесно відображає, яким саме спрацювало."""
        key = normalize_name(raw_name)
        if not key:
            return None

        # 0. Ручний псевдонім — найнадійніше, бо його звірила людина. Дві форми: назва в OSM,
        #    або прямі координати для майданчиків, яких в OSM немає взагалі (ORIGIN STAGE,
        #    COMEDY SHELTER). Вигадувати координати не можна: подія на чужій точці гірша за
        #    подію в черзі перегляду.
        alias = self.aliases.get(key)
        if isinstance(alias, dict):
            return {"lat": float(alias["lat"]), "lon": float(alias["lon"]),
                    "display": alias.get("name", raw_name), "ref": alias.get("ref"),
                    "confidence": 0.95, "how": "alias"}
        if isinstance(alias, str):
            hit = self.by_name.get(normalize_name(alias))
            if hit:
                return {**hit, "confidence": 0.98, "how": "alias"}

        # 1. Точний збіг нормалізованих назв.
        if key in self.by_name:
            return {**self.by_name[key], "confidence": 0.9, "how": "exact"}

        # 2. Входження — «жовтневий палац» усередині «мцкм жовтневий палац».
        best = None
        for name, record in self.by_name.items():
            if len(name) < 6:
                continue
            if name in key or key in name:
                score = len(name) / max(len(key), len(name))
                if not best or score > best[0]:
                    best = (score, name, record)
        if best and _accept_contains(best[0], best[1]):
            return {**best[2], "confidence": 0.7, "how": "contains"}
        return None


def _accept_contains(score: float, osm_name: str) -> bool:
    """Чи приймати збіг за входженням.

    Самого порога score недостатньо, і це видно на реальних даних:

        «Київський Палац спорту» → «Палац спорту»       0.55  правильно
        «Music Pub "Pepper\'s Club"» → «Pepper\'s Club»  0.57  правильно
        «Dorothy pub» → «Dorothy»                       0.64  правильно
        «Feels Garden» → «Garden»                       0.50  ПОМИЛКА, інший заклад за 10 км
        «Будинок Кіно. Червоний зал» → «Будинок кіно»   0.480 правильно, але ВІДХИЛЕНО

    Поріг 0.6 відсік би помилку, але разом із нею й «Палац спорту» з 23 подіями. Розрізняє їх не
    score, а те, що хибний збіг — одне загальне слово. Тому однослівна назва в OSM вимагає вищої
    впевненості, ніж двослівна.

    Шостий приклад додано, коли зʼявилось джерело internet-bilet, — і він показує межу цієї
    евристики. «Будинок Кіно. Червоний зал» промахується повз поріг на 0.02, хоч збіг правильний.
    Поріг тут навмисно НЕ знижено до 0.45: поріг — це неперевірене твердження про всі 4835 назв
    індексу, а псевдонім у aliases.json — перевірене твердження про один заклад. Дешевше й
    безпечніше додати запис, ніж посунути межу для всіх.

    Це евристика, підібрана на прикладах, а не закон. З кожним новим джерелом перевіряйте її
    знову, а не довіряйте їй.
    """
    tokens = len(osm_name.split())
    return score >= (0.6 if tokens < 2 else 0.5)


def load_aliases() -> dict[str, str]:
    if ALIASES_PATH.exists():
        return json.loads(ALIASES_PATH.read_text("utf-8"))
    return {}


def build_index(city: str, *, refresh: bool = False) -> VenueIndex:
    return VenueIndex(fetch_osm(city, refresh=refresh), city, load_aliases())
