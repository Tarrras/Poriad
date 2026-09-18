"""Photon — запасний геокодер для майданчиків, яких немає в дампі OSM. Той самий інстанс, що в застосунку.

Порядок: aliases.json (звірено людиною) -> дамп OSM (збіг назви) -> Photon (адресний рядок).
Photon завжди повертає найкращий здогад, навіть коли відповіді не існує, тому фільтри:
  · лише вулична адреса, ніколи назва закладу (на «ORIGIN STAGE» він віддає кам'яну стелу);
  · номер будинку в запиті, інакше точка посеред вулиці;
  · рівень результату: лише `house`/`building`. `street` відкидаємо: на «пр. Глушкова, 1» Photon
    віддає довільний відрізок проспекту, і той самий концерт із двох афіш розʼїжджається на 1,5 км;
  · межі міста: Photon охоче знаходить ту саму вулицю в іншому місті;
  · збіг адреси: номер будинку, вулиця й місто результату мають збігатися із запитом. Без цього
    першим приходить зупинка з назвою вулиці, сусідній бізнес-центр або село з тією самою
    адресою всередині прямокутника міста (на зрізі кешу — 42 адреси з 256);
  · однозначність: дві «Сонячна, 5» в Одесі за 7 км одна від одної — це черга перегляду, а не вибір.
"""
from __future__ import annotations

import json
import math
import pathlib
import re
import time
import urllib.parse
import urllib.request

from .normalize import normalize_name

ENDPOINT = "https://photon.komoot.io/api/"
CACHE_PATH = pathlib.Path(__file__).resolve().parent / "cache" / "photon.json"

# Межі міст (south, west, north, east): фільтр Photon і межа запиту до Overpass. Місто без
# прямокутника не має ні дампу майданчиків, ні геокодування.
CITY_BBOX = {
    "Київ": (50.21, 30.24, 50.59, 30.83),
    "Львів": (49.75, 23.90, 49.92, 24.15),
    "Харків": (49.88, 36.08, 50.10, 36.45),
    "Одеса": (46.32, 30.60, 46.62, 30.86),
    "Дніпро": (48.35, 34.80, 48.58, 35.15),   # захід до 34.80: Ecopark «7 nebo» в Обухівці продають як «Дніпро»
}

# Рівні точності Photon у properties.type.
_CONFIDENCE = {"house": 0.72, "building": 0.70}

# Без номера будинку точність лише рівня вулиці.
_HAS_NUMBER = re.compile(r"\d")

# Номер будинку в адресі: «5», «19А», «23-В», «37/41», «1-3/11». Літера — лише впритул: у
# «Сумська, 25 м. Університет» «м» — це метро, а не корпус.
_HOUSE_NUMBER = re.compile(r"\d+(?:\s?[/-]\s?\d+)*(?:-?[а-яіїєґa-z])?(?![а-яіїєґa-z])", re.I)
# Родові слова, за якими вулиці не розрізнити.
_STREET_KINDS = {"вулиця", "проспект", "площа", "провулок", "бульвар", "шосе", "майдан", "узвіз", "алея"}
# Далі одна від одної точки з тією самою адресою — це вже дві різні адреси.
_AMBIGUOUS_METRES = 500.0
# Версія фільтрів `_pick`. Змінили правила — підняли число, і старі точки перевіряються заново.
_RULES_VERSION = 3


def _squash(text: str | None) -> str:
    return re.sub(r"[^0-9a-zа-яіїєґ]", "", (text or "").lower())


def _same_address(props: dict, query: str, city: str) -> bool:
    """Чи результат Photon — саме та адреса, яку питали, а не найближчий здогад."""
    wanted = _HOUSE_NUMBER.search(query)
    if not wanted or _squash(props.get("housenumber")) != _squash(wanted.group(0)):
        return False
    if normalize_name(props.get("city") or "") != normalize_name(city):
        return False
    words = [w for w in normalize_name(props.get("street") or "").split()
             if len(w) >= 4 and w not in _STREET_KINDS]
    haystack = normalize_name(query)
    return not words or any(w[:5] in haystack for w in words)


def _metres(a: tuple[float, float], b: tuple[float, float]) -> float:
    lat = math.radians((a[0] + b[0]) / 2)
    return 6371000 * math.hypot(math.radians(a[1] - b[1]) * math.cos(lat), math.radians(a[0] - b[0]))

_MIN_DELAY = 1.0            # публічний інстанс: ходимо повільно й послідовно
_last_call = 0.0


# Скорочення типу вулиці зводимо до повної форми, інакше «пр-т» і «пр.» — різні ключі кешу й
# різні точки. Порядок важить: «пров» перевіряємо раніше за «пр».
_STREET_FORMS = (
    (r"пров(?:\.|улок)?", "провулок"),
    (r"просп(?:\.|ект)?|пр[-‑]?кт\.?|пр[-‑]?т\.?|пр\.", "проспект"),
    (r"вул(?:\.|иця|иці)?", "вулиця"),
    (r"пл(?:\.|оща|ощі)?", "площа"),
    (r"б(?:ул(?:\.|ьвар)?|[-‑]р\.?)", "бульвар"),
    (r"наб(?:\.|ережна)?", "набережна"),
    (r"ш(?:\.|осе)", "шосе"),
)
_STREET_RE = tuple((re.compile(rf"(?<![^\W\d_]){pattern}(?![^\W\d_])", re.I), full)
                   for pattern, full in _STREET_FORMS)


def canonical_street(address: str) -> str:
    """Одне написання типу вулиці, щоб два джерела зійшлись на одному ключі кешу."""
    out = address
    for pattern, full in _STREET_RE:
        out = pattern.sub(full, out)
    return out


class Geocoder:
    """Кешований клієнт Photon. Кеш на диску: та сама адреса не питається двічі ніколи."""

    def __init__(self, city: str, *, enabled: bool = True):
        self.city = city
        self.enabled = enabled and city in CITY_BBOX
        self.bbox = CITY_BBOX.get(city)
        self.calls = 0
        self.errors: list[str] = []
        CACHE_PATH.parent.mkdir(exist_ok=True)
        self._cache: dict = json.loads(CACHE_PATH.read_text("utf-8")) if CACHE_PATH.exists() else {}

    def _save(self) -> None:
        CACHE_PATH.write_text(json.dumps(self._cache, ensure_ascii=False), "utf-8")

    def _in_bbox(self, lat: float, lon: float) -> bool:
        s, w, n, e = self.bbox
        return s <= lat <= n and w <= lon <= e

    def lookup_street(self, street: str) -> dict | None:
        """Геокодує ВУЛИЧНУ АДРЕСУ. Назву закладу сюди передавати не можна — див. шапку модуля."""
        query = canonical_street((street or "").strip())
        if not self.enabled or not query or not _HAS_NUMBER.search(query):
            return None
        key = f"{self.city}|{normalize_name(query)}"
        if key in self._cache:
            hit = self._cache[key]
            # Запис без поточної версії правил питаємо заново: кеш не має права обходити фільтр,
            # якого не було, коли його записали. Запис без точки = «шукали, не знайшли».
            if hit.get("v") == _RULES_VERSION:
                return hit if "lat" in hit else None

        global _last_call
        wait = _MIN_DELAY - (time.monotonic() - _last_call)
        if wait > 0:
            time.sleep(wait)
        _last_call = time.monotonic()

        # Photon приймає лише default/de/en/fr; `default` віддає українські назви, `uk` дає 400.
        params = urllib.parse.urlencode({
            "q": f"{query}, {self.city}", "limit": 5, "lang": "default",
            "lat": (self.bbox[0] + self.bbox[2]) / 2,
            "lon": (self.bbox[1] + self.bbox[3]) / 2,
        })
        req = urllib.request.Request(
            f"{ENDPOINT}?{params}",
            headers={"User-Agent": "PoriadBot/0.1 (+https://poriad.app/bot)",
                     "Accept": "application/json"})
        self.calls += 1
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                payload = json.loads(r.read().decode("utf-8"))
        except Exception as exc:
            # Помилку не ковтаємо: мовчазний геокодер невідрізнений від порожнього результату.
            self.errors.append(f"{query}: {exc}")
            return None

        result = self._pick(payload.get("features") or [], query)
        self._cache[key] = result or {"v": _RULES_VERSION}
        self._save()
        return result

    def _pick(self, features: list[dict], query: str = "") -> dict | None:
        hits = []
        for feature in features:
            props = feature.get("properties") or {}
            confidence = _CONFIDENCE.get(props.get("type"))
            if not confidence:
                continue                       # надто грубий рівень — відкидаємо мовчки
            coords = (feature.get("geometry") or {}).get("coordinates") or []
            if len(coords) != 2:
                continue
            lon, lat = float(coords[0]), float(coords[1])
            if not self._in_bbox(lat, lon):
                continue                       # інше місто
            if query and not _same_address(props, query, self.city):
                continue                       # зупинка, сусідній будинок або село з тією самою вулицею
            # display порожній: Photon віддає назву сусіднього POI, а не майданчика.
            hits.append({"lat": lat, "lon": lon,
                         "display": "",
                         "ref": f"photon/{props.get('osm_type','')}{props.get('osm_id','')}",
                         "confidence": confidence, "how": "photon", "v": _RULES_VERSION,
                         "_building": props.get("osm_key") == "building"})
        # Дві однакові адреси в місті. Будівлі з адресою віримо більше, ніж закладу, якому адресу
        # вписав автор точки: «Сонячна, 5» в Одесі — це будівля в Аркадії, а не косметолог у
        # «Дружному». Якщо й будівлі розходяться — вибирати нема за чим, у чергу перегляду.
        buildings = [h for h in hits if h.pop("_building")]      # службове поле далі не йде
        for pool in (hits, buildings):
            if pool and all(_metres((pool[0]["lat"], pool[0]["lon"]), (h["lat"], h["lon"]))
                            <= _AMBIGUOUS_METRES for h in pool[1:]):
                return pool[0]
        return None
