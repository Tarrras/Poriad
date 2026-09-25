"""Майданчики: дамп OpenStreetMap і зіставлення назв.

Джерела подій не віддають координат, тож без майданчиків імпорту не існує. Overpass API віддає
іменовані об'єкти міста одним запитом (ODbL, лише атрибуція). Автоматика бере довгий хвіст;
внутрішні скорочення афіш («МЦКМ», «ORIGIN STAGE») зводяться руками в aliases.json.

`Disallow: /api/` у robots.txt Overpass стосується пошукових краулерів; клієнти API керуються
usage policy, якої дотримуємось: один запит на місто, кеш на диску, без паралельних запитів.
"""
from __future__ import annotations

import datetime as dt
import json
import pathlib
import sys
import urllib.parse
import urllib.request

from .geocode import CITY_BBOX
from .fetch import USER_AGENT
from .normalize import normalize_name

# Дзеркала Overpass перебираємо по черзі: один зайнятий інстанс не має блокувати ціле місто.
OVERPASS_MIRRORS = (
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
    "https://overpass.osm.ch/api/interpreter",
)
# Скільки дзеркало може відставати від OSM. Здорове відстає на хвилини.
MAX_DUMP_AGE = dt.timedelta(days=7)
CACHE_DIR = pathlib.Path(__file__).resolve().parent / "cache"
ALIASES_PATH = pathlib.Path(__file__).resolve().parent / "aliases.json"

# Теги OSM, де проходять реальні події з афіш. «Немає в OSM» зазвичай означало «немає в цьому
# переліку» (ТРЦ як `shop=mall`, будинки офіцерів як `building=civic`). Свідомо не додано:
# leisure=garden (садові центри, і джерело хибних збігів за словом «garden»), amenity=studio
# (телестудії), club=* (без сталого значення), shop=art (крамниці фарб). Кожна зайва назва —
# шанс хибного збігу, тому розширюємо переліком, а не зняттям фільтра.
_TAGS = """
  nwr["amenity"~"^(theatre|cinema|arts_centre|community_centre|nightclub|library|bar|pub|restaurant|cafe|planetarium|exhibition_centre|conference_centre|events_venue|music_venue|concert_hall|food_court)$"](area.a);
  nwr["tourism"~"^(gallery|museum|attraction|theme_park|zoo|aquarium)$"](area.a);
  nwr["leisure"~"^(park|sports_centre|fitness_centre|stadium|dance|escape_game|amusement_arcade|bowling_alley|events)$"](area.a);
  nwr["shop"~"^(mall|books)$"](area.a);
  nwr["office"="coworking"](area.a);
  nwr["building"~"^(palace|civic)$"](area.a);
"""

_NAME_KEYS = ("name", "name:uk", "name:en", "alt_name", "official_name", "short_name", "brand")


def _query(city: str) -> str:
    """Запит за прямокутником міста, а не за адмінмежею: `admin_level=4` працює лише для Києва,
    для решти мовчки повертає нуль об'єктів. Прямокутник уже є в `geocode.CITY_BBOX`.
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
    stale: list[tuple[dt.datetime, dict]] = []      # запасний варіант: найновіше з застарілого
    for endpoint in OVERPASS_MIRRORS:
        host = urllib.parse.urlsplit(endpoint).netloc
        req = urllib.request.Request(
            endpoint, data=body,
            headers={"Accept": "application/json",       # без цього Overpass віддає 406
                     "Content-Type": "application/x-www-form-urlencoded",
                     "User-Agent": USER_AGENT})
        try:
            with urllib.request.urlopen(req, timeout=240) as r:
                payload = json.loads(r.read().decode("utf-8"))
        except Exception as exc:
            problems.append(f"{host}: {exc}")
            continue
        elements = payload.get("elements") or []
        # Порожнє місто — несправність дзеркала або прямокутника, не відповідь: не кешуємо, пробуємо далі.
        if not elements:
            problems.append(f"{host}: порожній дамп"
                            + (f" ({payload['remark']})" if payload.get("remark") else ""))
            continue
        # Дзеркала відстають мовчки: одне віддало Київ станом на чотири місяці тому, і псевдонім
        # «Feels Garden → Feels Live» перестав зводитись, бо назву обʼєкту дали пізніше.
        based = _dump_time(payload)
        if based is None or dt.datetime.now(dt.timezone.utc) - based > MAX_DUMP_AGE:
            problems.append(f"{host}: застарілі дані ({based or 'без дати'})")
            if based is not None:
                stale.append((based, payload))
            continue
        cache.write_text(json.dumps(payload, ensure_ascii=False), "utf-8")
        return elements
    # Свіжого немає. Застарілий дамп гірший за свіжий, але кращий за зупинку всього обходу:
    # беремо найновіше із застарілих дзеркал і старого кешу, кажемо про це вголос і не кешуємо
    # застаріле поверх новішого.
    if cache.exists():
        cached = json.loads(cache.read_text("utf-8"))
        based = _dump_time(cached)
        if based is not None:
            stale.append((based, cached))
    if stale:
        based, payload = max(stale, key=lambda pair: pair[0])
        print(f"  ⚠ OSM для {city}: свіжого дампу немає ({'; '.join(problems)}); "
              f"беремо застарілий станом на {based:%Y-%m-%d}", file=sys.stderr)
        if not cache.exists() or _dump_time(json.loads(cache.read_text("utf-8"))) != based:
            cache.write_text(json.dumps(payload, ensure_ascii=False), "utf-8")
        return payload["elements"]
    # Порожній дамп не має проходити мовчки.
    raise RuntimeError(f"жодне дзеркало Overpass не відповіло для {city!r}: " + "; ".join(problems))


def _dump_time(payload: dict) -> dt.datetime | None:
    stamp = (payload.get("osm3s") or {}).get("timestamp_osm_base") or ""
    try:
        return dt.datetime.fromisoformat(stamp.replace("Z", "+00:00"))
    except ValueError:
        return None


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
        # Назва міста — не назва майданчика: «Київ» зіставлявся з «Київська Русь» за входженням.
        if key == normalize_name(self.city):
            return None

        # 0. Ручний псевдонім: назва в OSM або прямі координати для майданчиків, яких в OSM нема.
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

    Самого score замало: «Feels Garden» → «Garden» (0.50) — помилка за 10 км, а «Київський
    Палац спорту» → «Палац спорту» (0.55) — правильно. Розрізняє кількість слів: однослівна
    назва в OSM вимагає вищої впевненості. Правильні збіги під порогом розв'язуються псевдонімом
    у aliases.json, а не зниженням порога для всіх. Евристика, перевіряйте з кожним новим джерелом.
    """
    tokens = len(osm_name.split())
    return score >= (0.6 if tokens < 2 else 0.5)


def load_aliases() -> dict[str, str]:
    if ALIASES_PATH.exists():
        return json.loads(ALIASES_PATH.read_text("utf-8"))
    return {}


def build_index(city: str, *, refresh: bool = False) -> VenueIndex:
    return VenueIndex(fetch_osm(city, refresh=refresh), city, load_aliases())
