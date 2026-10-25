"""Межі районів і місцевостей п'яти міст з OpenStreetMap → SQL для `public.districts` (міграція 20261107120000_districts).

    python3 tools/districts.py --fetch      # Overpass → tools/districts.json (спрощені межі, лежать у git)
    python3 tools/districts.py              # tools/districts.json → out/districts.sql
    supabase db query --linked --project-ref <ref> -f out/districts.sql

Джерело — адміністративні межі `admin_level=10` (райони в містах), © учасники OpenStreetMap, ODbL. Атрибуцію OSM
застосунок уже показує на мапі. Межі спрощуємо по кожному шляху OSM окремо: сусідні райони ділять ті самі шляхи, тож
спільна межа спрощується однаково і між районами не лишається щілин. JSON у git, щоб dev і prod отримали однакові межі,
а зміну меж було видно в diff. Оновлювати, коли місто перейменує чи перекроїть райони: `--fetch`, переглянути diff,
залити на обидві бази. Файл повністю замінює таблицю.

Місцевості (Аркадія, Великий Фонтан, Троєщина) — `place=suburb`: в OSM це лише точки, без меж. Тож місцевість — коло
`LOCALITY_RADIUS` навколо точки, і клієнт каже про неї «1,5 км навколо», а не «в Аркадії». Беремо лише точки всередині
районів міста: так передмістя з тією самою рамкою не стають місцевостями.
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
# ponytail: один радіус для Аркадії й Троєщини; свій радіус для місцевості, якщо коло виявиться замалим чи завеликим.
LOCALITY_RADIUS = 1500
# Вершин у колі місцевості: на масштабі міста коло, а не многокутник.
CIRCLE_POINTS = 32
METERS_PER_DEGREE = 111_195
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


def overpass(query: str) -> list[dict]:
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


def inside(lon: float, lat: float, rings: list) -> bool:
    """Парність перетинів, як `District.contains` на клієнті: дірки й анклави без ролей."""
    result = False
    for ring in rings:
        for (x1, y1), (x2, y2) in zip(ring, ring[1:]):
            if (y1 > lat) != (y2 > lat) and lon < (x2 - x1) * (lat - y1) / (y2 - y1) + x1:
                result = not result
    return result


def circle(lon: float, lat: float, radius: float) -> list[list[float]]:
    """Коло навколо точки кільцем `[lon, lat]`, перша точка повторена в кінці."""
    dy = radius / METERS_PER_DEGREE
    dx = dy / math.cos(math.radians(lat))
    ring = [[round(lon + dx * math.cos(2 * math.pi * i / CIRCLE_POINTS), 5),
             round(lat + dy * math.sin(2 * math.pi * i / CIRCLE_POINTS), 5)] for i in range(CIRCLE_POINTS)]
    return ring + [ring[0]]


def localities(city: str, nodes: list[dict], districts: list[dict]) -> list[dict]:
    """Місцевості міста: точки `place=suburb` усередині його районів, одна на назву."""
    found = {}
    for node in nodes:
        name = (node["tags"].get("name:uk") or node["tags"].get("name") or "").strip()
        if not name or name.lower() in found or not any(inside(node["lon"], node["lat"], d["rings"]) for d in districts):
            continue
        # Id вузла OSM зі знаком мінус: вузли й відношення нумеруються окремо й можуть збігтися з id району.
        found[name.lower()] = {"id": -node["id"], "city": city, "name": name, "former": None, "aliases": [],
                               "radius": LOCALITY_RADIUS, "rings": [circle(node["lon"], node["lat"], LOCALITY_RADIUS)]}
    return sorted(found.values(), key=lambda d: d["name"])


def fetch() -> int:
    districts = []
    for city, ((south, west, north, east), expected) in CITIES.items():
        bbox = f"({south},{west},{north},{east})"
        # Один запит на місто: райони й точки місцевостей разом — Overpass не любить, коли часто.
        elements = overpass(f'[out:json][timeout:180];(rel["boundary"="administrative"]["admin_level"="10"]'
                            f'["name"~"район$"]{bbox};node["place"="suburb"]{bbox};);out geom;')
        found = sorted((district(city, e) for e in elements if e["type"] == "relation"), key=lambda d: d["name"])
        # Частковий список стер би райони міста з таблиці.
        if len(found) != expected:
            print(f"{city}: {len(found)} районів замість {expected}, файл не записано", file=sys.stderr)
            return 1
        places = localities(city, [e for e in elements if e["type"] == "node"], found)
        print(f"{city}: {len(found)} районів, {len(places)} місцевостей", flush=True)
        districts += found + places
        time.sleep(2)  # Overpass просить не частити
    DATA.write_text(json.dumps(districts, ensure_ascii=False, separators=(",", ":")) + "\n", "utf-8")
    points = sum(len(ring) for d in districts for ring in d["rings"])
    print(f"{DATA}: {len(districts)} районів і місцевостей, {points} точок, {DATA.stat().st_size // 1024} КБ")
    return 0


def sql(districts: list[dict]) -> str:
    def lit(value) -> str:
        if value is None:
            return "null"
        return str(value) if isinstance(value, int) else "'" + str(value).replace("'", "''") + "'"

    def lines(rings) -> str:
        return ",".join("(" + ",".join(f"{x} {y}" for x, y in ring) + ")" for ring in rings)

    values = ",\n".join(
        f"({d['id']},{lit(d['city'])},{lit(d['name'])},{lit(d['former'])},"
        f"array[{','.join(lit(a) for a in d['aliases'])}]::text[],{lit(d.get('radius'))},"
        f"gis.st_multi(gis.st_buildarea(gis.st_geomfromtext('MULTILINESTRING({lines(d['rings'])})',4326))))"
        for d in districts)
    return f"""begin;
delete from public.districts;
insert into public.districts (id, city, name, former_name, aliases, radius_m, boundary) values
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
    d = {**district("Одеса", relation), "radius": None}
    assert d["former"] == "Суворовський район" and d["aliases"] == [] and len(d["rings"]) == 1, d
    assert "'Солом''янка'" in sql([{**d, "aliases": ["Солом'янка"]}])
    # Число в SQL без лапок, а місцевість — лише всередині районів, одна на назву.
    square = [[[0, 0], [1, 0], [1, 1], [0, 1], [0, 0]]]
    assert inside(0.5, 0.5, square) and not inside(1.5, 0.5, square)
    ring = circle(30.0, 46.0, 1500)
    assert ring[0] == ring[-1] and len(ring) == CIRCLE_POINTS + 1
    assert abs(max(y for _, y in ring) - 46.0 - 1500 / METERS_PER_DEGREE) < 0.0001
    nodes = [{"id": 7, "lat": 0.5, "lon": 0.5, "tags": {"name": "Аркадія"}},
             {"id": 8, "lat": 0.6, "lon": 0.6, "tags": {"name": "аркадія"}},
             {"id": 9, "lat": 5.0, "lon": 5.0, "tags": {"name": "Передмістя"}}]
    places = localities("Одеса", nodes, [{"rings": square}])
    assert [(p["id"], p["name"], p["radius"]) for p in places] == [(-7, "Аркадія", LOCALITY_RADIUS)], places
    assert ",1500," in sql(places) and ",null," in sql([d])


if __name__ == "__main__":
    _self_check()
    sys.exit(main())
