"""Межі районів п'яти міст з OpenStreetMap → SQL для `public.districts` (міграція 20261107120000_districts).

    python3 tools/districts.py --fetch      # Overpass → tools/districts.json (спрощені межі, лежать у git)
    python3 tools/districts.py              # tools/districts.json → out/districts.sql
    supabase db query --linked --project-ref <ref> -f out/districts.sql

Джерело — адміністративні межі `admin_level=10` (райони в містах), © учасники OpenStreetMap, ODbL. Атрибуцію OSM
застосунок уже показує на мапі. Межі спрощуємо по кожному шляху OSM окремо: сусідні райони ділять ті самі шляхи, тож
спільна межа спрощується однаково і між районами не лишається щілин. JSON у git, щоб dev і prod отримали однакові межі,
а зміну меж було видно в diff. Оновлювати, коли місто перейменує чи перекроїть райони: `--fetch`, переглянути diff,
залити на обидві бази. Файл повністю замінює таблицю.
"""
from __future__ import annotations

import json
import math
import pathlib
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
DATA = ROOT / "tools" / "districts.json"
OVERPASS = ("https://overpass-api.de/api/interpreter", "https://overpass.private.coffee/api/interpreter")
# Південь, захід, північ, схід — з запасом навколо міста — і скільки районів у ньому має бути.
CITIES = {
    "Київ": ((50.20, 30.15, 50.65, 30.95), 10),
    "Львів": ((49.70, 23.85, 49.95, 24.25), 6),
    "Одеса": ((46.30, 30.45, 46.70, 30.90), 4),
    "Дніпро": ((48.30, 34.75, 48.65, 35.30), 8),
    "Харків": ((49.85, 36.05, 50.15, 36.50), 9),
}
# ~10 м: подія на вулиці-межі лишається у своєму районі, а місто важить десятки КБ.
TOLERANCE = 0.0001
# Центральний район Дніпра в OSM підписано просто «район».
NAMES = {1209154: "Центральний район"}
# Нещодавні перейменування (2022–2024): людина ще шукає за старою назвою, і рядок пошуку нагадує «раніше …».
FORMER = {
    ("Одеса", "Хаджибейський район"): "Малиновський район",
    ("Одеса", "Пересипський район"): "Суворовський район",
    ("Харків", "Салтівський район"): "Московський район",
}
# Лише для пошуку, не показуємо: назви до 2016 року, яких немає в OSM, і звичні назви, коли район названо за місцевістю
# і вона в ньому. Ті, що вже є префіксом назви («Поділ», «Сихів»), не потрібні. Масиви на кшталт «Троєщина» — не район.
ALIASES = {
    ("Київ", "Оболонський район"): ["Оболонь"],
    ("Київ", "Солом’янський район"): ["Солом'янка"],
    ("Харків", "Шевченківський район"): ["Дзержинський район"],
    ("Харків", "Холодногірський район"): ["Ленінський район", "Холодна гора"],
    ("Харків", "Основ’янський район"): ["Основа"],
    ("Харків", "Слобідський район"): ["Комінтернівський район"],
    ("Харків", "Індустріальний район"): ["Орджонікідзевський район"],
    ("Харків", "Немишлянський район"): ["Фрунзенський район"],
    ("Дніпро", "Чечелівський район"): ["Чечелівка"],
}


def overpass(south: float, west: float, north: float, east: float) -> list[dict]:
    query = (f'[out:json][timeout:120];rel["boundary"="administrative"]["admin_level"="10"]["name"~"район$"]'
             f'({south},{west},{north},{east});out geom;')
    # Перевантажений Overpass відповідає 502/504 чи мовчить — тоді дзеркало, а потім знову по колу.
    for attempt in range(6):
        request = urllib.request.Request(OVERPASS[attempt % len(OVERPASS)],
                                         data=urllib.parse.urlencode({"data": query}).encode(),
                                         headers={"User-Agent": "PoriadBot/0.1 (+https://poriad.app/bot)"})
        try:
            with urllib.request.urlopen(request, timeout=180) as response:
                return json.load(response)["elements"]
        except (urllib.error.URLError, TimeoutError) as e:
            if isinstance(e, urllib.error.HTTPError) and e.code not in (429, 502, 503, 504) or attempt == 5:
                raise
            time.sleep(15)
    raise AssertionError("недосяжно")


def simplify(points: list[tuple[float, float]], tolerance: float) -> list[tuple[float, float]]:
    """Дуглас — Пекер. Кінці лишаються: на них шлях стикується з сусідніми."""
    if len(points) < 3:
        return points
    (ax, ay), (bx, by) = points[0], points[-1]
    dx, dy = bx - ax, by - ay
    length = math.hypot(dx, dy)

    def distance(p):
        if length == 0:
            return math.hypot(p[0] - ax, p[1] - ay)
        return abs(dy * p[0] - dx * p[1] + bx * ay - by * ax) / length

    far = max(range(1, len(points) - 1), key=lambda i: distance(points[i]))
    if distance(points[far]) <= tolerance:
        return [points[0], points[-1]]
    return simplify(points[:far + 1], tolerance)[:-1] + simplify(points[far:], tolerance)


def rings(ways: list[list[tuple[float, float]]]) -> list[list[tuple[float, float]]]:
    """Шляхи межі → замкнені кільця. Кожен кінець шляху стикується рівно з одним іншим, напрям буває будь-який."""
    left = [list(way) for way in ways]
    closed = []
    while left:
        ring = left.pop()
        while ring[0] != ring[-1]:
            for i, way in enumerate(left):
                if way[0] == ring[-1]:
                    ring += way[1:]
                elif way[-1] == ring[-1]:
                    ring += way[-2::-1]
                else:
                    continue
                left.pop(i)
                break
            else:
                raise ValueError(f"кільце не замкнулось біля {ring[-1]}")
        closed.append(ring)
    return closed


def district(city: str, relation: dict) -> dict:
    tags = relation["tags"]
    name = NAMES.get(relation["id"], tags.get("name:uk") or tags["name"])
    ways = [[(round(p["lon"], 5), round(p["lat"], 5)) for p in member["geometry"]]
            for member in relation["members"]
            if member["type"] == "way" and member.get("role", "") in ("outer", "inner", "") and member.get("geometry")]
    # Простий перебір: шляхів одного міста кілька сотень, а один шлях дає однакове спрощення в обох районах.
    shaped = [ring for ring in rings([simplify(way, TOLERANCE) for way in ways]) if len(ring) >= 4]
    # Російських назв (`name:ru`) не беремо: інтерфейс і пошук — українською.
    aliases = [*ALIASES.get((city, name), []),
               *(value.strip() for value in (tags.get("old_name") or "").split(";") if value.strip())]
    former = FORMER.get((city, name))
    return {
        "id": relation["id"], "city": city, "name": name, "former": former,
        "aliases": sorted({a for a in aliases if a not in (name, former)}),
        "rings": [[list(point) for point in ring] for ring in shaped],
    }


def fetch() -> int:
    districts = []
    for city, (bounds, expected) in CITIES.items():
        found = [district(city, relation) for relation in overpass(*bounds)]
        # Частковий список стер би райони міста з таблиці.
        if len(found) != expected:
            print(f"{city}: {len(found)} районів замість {expected}, файл не записано", file=sys.stderr)
            return 1
        districts += sorted(found, key=lambda d: d["name"])
        time.sleep(2)  # Overpass просить не частити
    DATA.write_text(json.dumps(districts, ensure_ascii=False, separators=(",", ":")) + "\n", "utf-8")
    points = sum(len(ring) for d in districts for ring in d["rings"])
    print(f"{DATA}: {len(districts)} районів, {points} точок, {DATA.stat().st_size // 1024} КБ")
    return 0


def sql(districts: list[dict]) -> str:
    def lit(value) -> str:
        return "null" if value is None else "'" + str(value).replace("'", "''") + "'"

    def lines(rings) -> str:
        return ",".join("(" + ",".join(f"{x} {y}" for x, y in ring) + ")" for ring in rings)

    values = ",\n".join(
        f"({d['id']},{lit(d['city'])},{lit(d['name'])},{lit(d['former'])},"
        f"array[{','.join(lit(a) for a in d['aliases'])}]::text[],"
        f"gis.st_multi(gis.st_buildarea(gis.st_geomfromtext('MULTILINESTRING({lines(d['rings'])})',4326))))"
        for d in districts)
    return f"""begin;
delete from public.districts;
insert into public.districts (id, city, name, former_name, aliases, boundary) values
{values};
commit;
"""


def main() -> int:
    if "--fetch" in sys.argv:
        return fetch()
    districts = json.loads(DATA.read_text("utf-8"))
    out = ROOT / "out" / "districts.sql"
    out.parent.mkdir(exist_ok=True)
    out.write_text(sql(districts), "utf-8")
    print(f"{out}: {len(districts)} районів")
    return 0


def _self_check() -> None:
    # Квадрат із двох шляхів, другий — у зворотному напрямі.
    assert rings([[(0, 0), (1, 0), (1, 1)], [(0, 0), (0, 1), (1, 1)]]) == [[(0, 0), (0, 1), (1, 1), (1, 0), (0, 0)]]
    try:
        rings([[(0, 0), (1, 0)]])
        raise AssertionError("незамкнене кільце")
    except ValueError:
        pass
    assert simplify([(0, 0), (1, 0.00005), (2, 0)], TOLERANCE) == [(0, 0), (2, 0)]
    assert simplify([(0, 0), (1, 0.5), (2, 0)], TOLERANCE) == [(0, 0), (1, 0.5), (2, 0)]
    relation = {"id": 1, "tags": {"name": "Пересипський район", "name:ru": "Пересыпский район"},
                "members": [{"type": "node", "role": "admin_centre"},
                            {"type": "way", "role": "outer", "geometry": [{"lat": 0, "lon": 0}, {"lat": 0, "lon": 1},
                                                                          {"lat": 1, "lon": 1}]},
                            {"type": "way", "role": "outer", "geometry": [{"lat": 1, "lon": 1}, {"lat": 0, "lon": 0}]}]}
    d = district("Одеса", relation)
    assert d["former"] == "Суворовський район" and d["aliases"] == [] and len(d["rings"]) == 1, d
    assert "'Солом''янка'" in sql([{**d, "aliases": ["Солом'янка"]}])


if __name__ == "__main__":
    _self_check()
    sys.exit(main())
