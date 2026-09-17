"""Photon — запасний геокодер для майданчиків, яких немає в дампі OSM. Той самий інстанс, що в застосунку.

Порядок: aliases.json (звірено людиною) -> дамп OSM (збіг назви) -> Photon (адресний рядок).
Photon завжди повертає найкращий здогад, навіть коли відповіді не існує, тому фільтри:
  · лише вулична адреса, ніколи назва закладу (на «ORIGIN STAGE» він віддає кам'яну стелу);
  · номер будинку в запиті, інакше точка посеред вулиці;
  · рівень результату: `house`, `street` як запасний, `city`/`locality` відкидаємо;
  · межі міста: Photon охоче знаходить ту саму вулицю в іншому місті.
"""
from __future__ import annotations

import json
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
    "Дніпро": (48.35, 34.85, 48.58, 35.15),
}

# Рівні точності Photon у properties.type.
_CONFIDENCE = {"house": 0.72, "building": 0.70, "street": 0.6}

# Без номера будинку точність лише рівня вулиці.
_HAS_NUMBER = re.compile(r"\d")

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
            return hit if hit else None       # порожній запис = «шукали, не знайшли»

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

        result = self._pick(payload.get("features") or [])
        self._cache[key] = result or {}
        self._save()
        return result

    def _pick(self, features: list[dict]) -> dict | None:
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
            # display порожній: Photon віддає назву сусіднього POI, а не майданчика.
            return {"lat": lat, "lon": lon,
                    "display": "",
                    "ref": f"photon/{props.get('osm_type','')}{props.get('osm_id','')}",
                    "confidence": confidence, "how": "photon"}
        return None
