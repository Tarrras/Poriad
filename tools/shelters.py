"""Укриття з відкритих даних міста → SQL для `public.shelters` (міграція 20260928100000_shelters).

    python3 tools/shelters.py                                   # out/shelters.sql
    python3 tools/apply_sql.py dump out/shelters.sql --env dev --apply
    python3 tools/apply_sql.py dump out/shelters.sql --env prod --apply

Поки лише Київ: «Дані про розташування захисних споруд цивільного захисту», портал відкритих даних
КМДА, CC BY (data.gov.ua/dataset/16026e7a-65dc-48cb-98ec-51fd702b8ef8). Основний сервер gisserver
закритий WAF-ом для запитів не з браузера, stage-сервер з того ж порталу віддає той самий шар.
Оновлювати раз на місяць: файл повністю замінює рядки свого джерела.
"""
from __future__ import annotations

import json
import math
import pathlib
import sys
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = "kyiv-opendata"
# Станції метро Києва з OpenStreetMap (© учасники OSM, ODbL): у міських даних 112 входів у метро
# підписані лише «Вхід в станцію метро», без назви. Оновити: Overpass
# node["railway"="station"]["station"="subway"](50.3,30.3,50.6,30.8) → [назва, lat, lon].
METRO = json.loads((ROOT / "tools" / "kyiv_metro.json").read_text("utf-8"))
URL = ("https://gisserver-stage.kyivcity.gov.ua/mayno/rest/services/KYIV_API/Public_protection/MapServer/0/query"
       "?where=1%3D1&outFields=*&returnGeometry=true&outSR=4326&f=geojson")


def shelter(props: dict) -> dict | None:
    """Рядок таблиці з властивостей точки або None, якщо стороннім туди не можна."""
    hours = (props.get("working_time") or "").strip()
    # Укриття шкіл і садків у навчальний час — лише для дітей і персоналу: учасникам події не радимо.
    if "освітнього процесу" in hours:
        return None
    lat, lon = props.get("lat"), props.get("long")
    address = (props.get("address") or "").strip()
    if not isinstance(lat, (int, float)) or not isinstance(lon, (int, float)) or not address:
        return None
    kind_text = f"{props.get('type') or ''} {props.get('kind') or ''}".lower()
    # «Вхід в станцію метро «Поштова площа»» місто часом позначає переходом: для людини це метро.
    kind = ("metro" if "метро" in kind_text or "станці" in address.lower() else "underpass" if "перехід" in kind_text
            else "parking" if "паркінг" in kind_text else "basement")
    if kind == "metro" and address.lower() == "вхід в станцію метро":
        address = metro_name(lat, lon) or "Вхід у метро"
    guid = (props.get("guid") or props.get("globalid") or str(props.get("objectid"))).strip("{}")
    return {
        "id": f"{SOURCE}:{guid}",
        "kind": kind,
        "address": address[:300],
        "latitude": round(lat, 7),
        "longitude": round(lon, 7),
        "accessible": (props.get("invalid") or "").strip().lower() == "в наявності" or "пандус" in kind_text,
        "hours": None if hours in ("", "Цілодобово") else hours[:100],
    }


def metro_name(lat: float, lon: float) -> str | None:
    """«ст. м. «Назва»» найближчої станції в межах 400 м: довга станція має входи за кілька сотень метрів."""
    def metres(station):
        dy = (station[1] - lat) * 111_320
        dx = (station[2] - lon) * 111_320 * math.cos(math.radians(lat))
        return math.hypot(dx, dy)
    nearest = min(METRO, key=metres)
    return f"ст. м. «{nearest[0]}»" if metres(nearest) <= 400 else None


def sql(rows: list[dict]) -> str:
    def lit(value) -> str:
        if value is None:
            return "null"
        if isinstance(value, bool):
            return "true" if value else "false"
        if isinstance(value, (int, float)):
            return repr(value)
        return "'" + str(value).replace("'", "''") + "'"

    values = ",\n".join(
        f"({lit(r['id'])},'Київ',{lit(r['kind'])},{lit(r['address'])},{lit(r['latitude'])},"
        f"{lit(r['longitude'])},{lit(r['accessible'])},{lit(r['hours'])},'{SOURCE}')" for r in rows)
    return f"""begin;
delete from public.shelters where source = '{SOURCE}';
insert into public.shelters (id, city, kind, address, latitude, longitude, accessible, hours, source) values
{values};
commit;
"""


def main() -> int:
    request = urllib.request.Request(URL, headers={"User-Agent": "PoriadBot/0.1 (+https://poriad.app/bot)"})
    with urllib.request.urlopen(request, timeout=120) as response:
        features = json.load(response)["features"]
    # Кілька укриттів одного будинку місто дає окремими рядками з тією самою адресою й точкою.
    rows = list({(r["address"].lower(), round(r["latitude"], 4), round(r["longitude"], 4)): r
                 for r in (shelter(f["properties"]) for f in features) if r}.values())
    # Порожня чи обрізана відповідь стерла б усі укриття міста.
    if len(rows) < 1000:
        print(f"підозріло мало укриттів: {len(rows)} з {len(features)}, файл не записано", file=sys.stderr)
        return 1
    out = ROOT / "out" / "shelters.sql"
    out.parent.mkdir(exist_ok=True)
    out.write_text(sql(rows), "utf-8")
    kinds = {k: sum(r["kind"] == k for r in rows) for k in ("metro", "underpass", "parking", "basement")}
    print(f"{out}: {len(rows)} з {len(features)} ({kinds})")
    return 0


def _self_check() -> None:
    school = {"working_time": "Укриття доступне лише для учасників освітнього процесу", "lat": 50.4, "long": 30.5, "address": "x"}
    assert shelter(school) is None
    metro = shelter({"type": "Вхід в станцію метро", "kind": "Вхід в станцію метро", "working_time": "Цілодобово",
                     "lat": 50.4, "long": 30.5, "address": "ст. м. Либідська", "guid": "{AB}", "invalid": "Відсутній"})
    assert metro == {"id": "kyiv-opendata:AB", "kind": "metro", "address": "ст. м. Либідська", "latitude": 50.4,
                     "longitude": 30.5, "accessible": False, "hours": None}
    ramp = shelter({"type": "Найпростіше укриття", "kind": "Підземний перехід з пандусом", "working_time": "10:00–18:00",
                    "lat": 50.4, "long": 30.5, "address": "пл. Льва Толстого", "objectid": 7})
    assert ramp["kind"] == "underpass" and ramp["accessible"] and ramp["hours"] == "10:00–18:00" and ramp["id"].endswith(":7")
    unnamed = shelter({"type": "Вхід в станцію метро", "kind": "Вхід в станцію метро", "lat": METRO[0][1] + 0.001,
                       "long": METRO[0][2], "address": "вхід в станцію метро", "objectid": 1})
    assert unnamed["address"] == f"ст. м. «{METRO[0][0]}»", unnamed
    assert metro_name(50.0, 31.5) is None
    named = shelter({"type": "Найпростіше укриття", "kind": "Підземний перехід", "lat": 50.4, "long": 30.5,
                     "address": "Вхід в станцію метро «Поштова площа»", "objectid": 2})
    assert named["kind"] == "metro" and named["address"] == "Вхід в станцію метро «Поштова площа»"
    assert "'O''Brien'" in sql([{**ramp, "address": "O'Brien"}])


if __name__ == "__main__":
    _self_check()
    sys.exit(main())
