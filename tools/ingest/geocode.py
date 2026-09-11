"""Photon — запасний геокодер для майданчиків, яких немає в дампі OSM.

Той самий інстанс, що вже використовує застосунок (PhotonGeoSearchRepository), тож нової
зовнішньої залежності це не додає.

Порядок і чому саме такий:
    1. aliases.json  — звірено людиною, confidence 0.95–0.98
    2. дамп OSM      — точний або частковий збіг назви, 0.7–0.9
    3. Photon        — пошук за адресним рядком, 0.65–0.75
Photon стоїть останнім не з упередження, а тому що він шукає за текстом адреси й повертає
найкращий здогад завжди — навіть коли правильної відповіді не існує. Тому тут два фільтри,
без яких він приносить більше шкоди, ніж користі:

  · **тільки вулична адреса, ніколи назва закладу.** Це найдорожчий урок цього модуля. На запит
    «ORIGIN STAGE, Київ» Photon упевнено віддає кам'яну стелу «Центр Русі» з type=house — тобто
    відповідь, яку фільтр за рівнем точності пропускає, а вона поставила б 20 подій на випадковий
    пам'ятник. Пошук за назвою закладу відкидається як клас: Photon завжди щось знаходить.
  · номер будинку в запиті. Без нього «вул. Хрещатик» дає точку посеред вулиці завдовжки кілометр.
  · рівень результату. `house` беремо, `street` — лише як запасний, `city`/`locality` відкидаємо:
    точка «десь у Києві» для гео-first застосунку гірша за відсутню, бо виглядає як справжня.
  · межі міста. Відповідь за межами bbox відкидається — Photon охоче знаходить «вулицю Січових
    Стрільців» у зовсім іншому місті.

Наслідок, який видно в даних: karabas віддає streetAddress для 147 подій зі 147, тож геокодується;
concert.ua на сторінці-списку не віддає його зовсім (0 зі 116), тож його майданчики лишаються в
черзі перегляду, доки їх не додадуть у aliases.json або доки не з'явиться добір зі сторінок подій.
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

# Межі міст: south, west, north, east.
#
# Використовуються двічі: як фільтр відповідей Photon і як межа запиту до Overpass
# (`venues._query`). Тому місто без прямокутника не має ані дампу майданчиків, ані геокодування —
# `venues._query` про це кричить, а `Geocoder` просто вимикається.
CITY_BBOX = {
    "Київ": (50.21, 30.24, 50.59, 30.83),
    "Львів": (49.75, 23.90, 49.92, 24.15),
    "Харків": (49.88, 36.08, 50.10, 36.45),
    "Одеса": (46.32, 30.60, 46.62, 30.86),
    "Дніпро": (48.35, 34.85, 48.58, 35.15),
}

# Рівень точності, який Photon повертає в properties.type.
_CONFIDENCE = {"house": 0.72, "building": 0.70, "street": 0.6}

# Запит без номера будинку геокодувати немає сенсу — точність буде рівня вулиці.
_HAS_NUMBER = re.compile(r"\d")

_MIN_DELAY = 1.0            # публічний інстанс: ходимо повільно й послідовно
_last_call = 0.0


# Скорочення типу вулиці. Джерела пишуть ту саму адресу по-різному, і поки це доходило до
# геокодера як є, кожне написання ставало окремим ключем кешу, окремим запитом і окремою
# відповіддю. Знайдено на живій парі: «Lely45» в Одесі приходить із karabas як
# «пр-т Небесної Сотні, 4/7», а з internet-bilet як «пр. Небесної сотні, 4/7». Photon віддав дві
# точки за 42.8 м, подія не злилась як дублікат і стояла на мапі двічі.
#
# Порядок у переліку важить: «пров» мусить перевірятись раніше за «пр», інакше провулок стане
# проспектом. Зводимо до повної форми, а не до скорочення: повна однозначна, а «пр» збігається з
# початком інших слів.
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

        # lang: Photon приймає лише default/de/en/fr. `default` віддає локальні назви, тобто
        # українські — саме те, що треба. `uk` дає HTTP 400, і колись це коштувало 206 запитів,
        # які мовчки нічого не знайшли.
        params = urllib.parse.urlencode({
            "q": f"{query}, {self.city}", "limit": 5, "lang": "default",
            "lat": (self.bbox[0] + self.bbox[2]) / 2,
            "lon": (self.bbox[1] + self.bbox[3]) / 2,
        })
        req = urllib.request.Request(
            f"{ENDPOINT}?{params}",
            headers={"User-Agent": "PoruchBot/0.1 (+https://poruch.app/bot)",
                     "Accept": "application/json"})
        self.calls += 1
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                payload = json.loads(r.read().decode("utf-8"))
        except Exception as exc:
            # Помилку видно, а не ковтаємо: геокодер, який мовчки нічого не знаходить,
            # виглядає точно як геокодер, якому нічого не трапилось.
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
            # display навмисно порожній: Photon повертає назву будинку або сусіднього POI за
            # цією адресою, а не назву майданчика. «Арт-студія "ТВОРЧІ", офіс 3» отримала б
            # підпис «Національний музей історії України» — координати правильні, назва бреше.
            return {"lat": lat, "lon": lon,
                    "display": "",
                    "ref": f"photon/{props.get('osm_type','')}{props.get('osm_id','')}",
                    "confidence": confidence, "how": "photon"}
        return None
