"""Тести конвеєра: кожен закріплює одну виміряну пастку.

    python3 -m tools.ingest.test_ingest

Без мережі: усі входи — це фрагменти реальної розмітки, знятої з джерел 2026-09-07.
Тести навмисно перевіряють не «код працює», а «поправка на конкретну ваду джерела тримається»,
бо саме ці поправки ламаються найтихіше.
"""
from __future__ import annotations

import datetime as dt
import json
import sys

from . import extract, normalize
from .venues import VenueIndex

FAILURES: list[str] = []


def check(name: str, got, want) -> None:
    if got == want:
        print(f"  ✓ {name}")
    else:
        FAILURES.append(name)
        print(f"  ✗ {name}\n      очікувано: {want!r}\n      отримано : {got!r}")


# ---- Пастка A: час

def test_timezone_trap() -> None:
    print("\nПастка A — moemisto віддає локальний київський час зі зсувом +0000")
    raw = "2026-07-09T19:00:00+0000"      # реальне значення зі сторінки moemisto

    naive = normalize.parse_datetime(raw, "source", "Europe/Kyiv")
    check("без поправки подія о 19:00 читається як 22:00 за Києвом",
          naive.astimezone(normalize.zone("Europe/Kyiv")).strftime("%H:%M"), "22:00")

    fixed = normalize.parse_datetime(raw, "force_local", "Europe/Kyiv")
    check("з force_local лишається 19:00",
          fixed.astimezone(normalize.zone("Europe/Kyiv")).strftime("%H:%M"), "19:00")
    check("зсув влітку — +3 години (EEST)",
          fixed.utcoffset(), dt.timedelta(hours=3))

    winter = normalize.parse_datetime("2026-12-19T16:30:00+0000", "force_local", "Europe/Kyiv")
    check("взимку — +2 години (EET), а не той самий зсув",
          winter.utcoffset(), dt.timedelta(hours=2))

    # karabas: зсув коректний, але момент зсунуто вперед на нього (сторінка 18:00, JSON-LD 21:00+03:00).
    k1 = normalize.parse_datetime("2026-10-17T21:00:00+03:00", "utc_is_local", "Europe/Kyiv")
    check("karabas: 21:00+03:00 насправді 18:00 (літо)",
          k1.astimezone(normalize.zone("Europe/Kyiv")).strftime("%H:%M"), "18:00")
    k2 = normalize.parse_datetime("2026-12-15T21:00:00+02:00", "utc_is_local", "Europe/Kyiv")
    check("karabas: 21:00+02:00 насправді 19:00 (зима)",
          k2.astimezone(normalize.zone("Europe/Kyiv")).strftime("%H:%M"), "19:00")

    # concert.ua віддає правильний зсув: поправка іншого джерела не має його ламати.
    ok = normalize.parse_datetime("2026-09-12T21:00:00+03:00", "source", "Europe/Kyiv")
    check("джерело з коректним зсувом читається як є",
          ok.astimezone(normalize.zone("Europe/Kyiv")).strftime("%H:%M"), "21:00")


# ---- Пастка B: місто

def test_city_trap() -> None:
    print("\nПастка B — місто береться з розмітки, а не зі сторінки, де знайшли подію")
    event = json.loads("""{"@type":"MusicEvent","name":"Шоу історій",
      "location":{"@type":"Place","name":"Довгі бурхливі оплески",
      "address":{"@type":"PostalAddress","streetAddress":"вулиця Січових Стрільців, 3",
      "addressLocality":"Львів","addressCountry":"Україна"}}}""")
    address, city, street = normalize.address_of(event)
    check("addressLocality виграє у сторінки /uk/kyiv", city, "Львів")
    check("адреса склеєна без повторів",
          address, "Довгі бурхливі оплески, вулиця Січових Стрільців, 3, Львів")
    check("вулиця віддається окремо — тільки її можна геокодувати",
          street, "вулиця Січових Стрільців, 3")


# ---- Пастка C: опис

def test_description_trap() -> None:
    print("\nПастка C — опис джерела охороняється, тож обрізається")
    long_text = "Шоу історій — це вечір реальних, дивних і трохи крінжових історій з життя. " * 6
    clipped = normalize.clip(normalize.clean_text(long_text), normalize.DESCRIPTION_LIMIT)
    check("довжина в межах ліміту", len(clipped) <= normalize.DESCRIPTION_LIMIT + 1, True)
    check("обрив не посеред слова", clipped.rstrip("…").endswith(" ") is False, True)
    check("HTML-сутності розгорнуто",
          normalize.clean_text("&laquo;Брати&nbsp;Гадюкіни&raquo;"), "«Брати Гадюкіни»")
    check("переноси рядків прибрано",
          normalize.clean_text("рядок\r\n\r\n\r\nдругий"), "рядок\n\nдругий")


# ---- Заголовок і категорія

def test_title_and_category() -> None:
    print("\nЗаголовок під CHECK (3..120) і категорія")
    long_title = "Концерт " * 30
    t = normalize.normalize_title(long_title)
    check("заголовок вкладається в CHECK", 3 <= len(t) <= normalize.TITLE_MAX, True)
    check("короткий сміттєвий заголовок відкидається", normalize.normalize_title("а"), None)

    # tours і conference: найцінніше — де проходить межа з сусідньою категорією.
    def cat(title):
        return normalize.classify_with_reason({}, title, "")[0]

    check("екскурсія — це tours, а не outdoors", cat("Екскурсія «З краси Японії»"), "tours")
    check("спадщина теж", cat("Кам'яниця на Вірменській, 17. «Нашарування спадщини»"), "tours")
    check("конференція — це conference, а не social", cat("Event Industry Forum 2027"), "conference")
    check("саміт теж", cat("SBC Summit Ukraine 2026"), "conference")

    # Межа з outdoors: піша прогулянка з гідом — екскурсія, велопрогулянка й похід — ні.
    check("піша прогулянка — екскурсія", cat("Піша прогулянка Личаковом"), "tours")
    check("похід лишається природою", cat("Похід у Карпати"), "outdoors")
    check("велопрогулянка не стає екскурсією", cat("Велопрогулянка Дніпром") != "tours", True)

    # Межа з social: побачення наосліп — зустріч, не конференція.
    check("знайомства лишаються в social",
          cat("Побачення наосліп (23-35 років)") != "conference", True)

    # «рок» усередині «року» робив лекцію музикою: межі слова.
    check("«рок» не ловиться в «року»",
          cat("Пастка серпня 1939 року: радянський архів") != "music", True)
    check("а рок-опера лишається музикою", cat("Рок-опера «Ісус Христос»"), "music")

    # Перелік категорій збігається з клієнтами і CHECK у базі.
    check("категорій одинадцять", len(normalize.CATEGORIES), 11)

    # concert.ua ставить `MusicEvent` усьому: щабель типу для нього вимкнено.
    standup = {"@type": "MusicEvent"}
    check("слабкому типу не вірять",
          normalize.classify_with_reason(standup, "Суботній Стендап", "", "weak"),
          ("comedy", "lexicon"))
    check("а сильному вірять",
          normalize.classify_with_reason(standup, "Суботній Стендап", "")[1], "type")
    # Без слів-підказок подія зі слабким типом падає у fallback, де її побачить агент.
    check("слабкий тип без лексикону дає fallback",
          normalize.classify_with_reason(standup, "Закритий Мікрофон", "Бочка PUB", "weak"),
          ("social", "fallback"))

    check("@type виграє першим",
          normalize.classify({"@type": "MusicEvent"}, "Вечір настолок", ""), "music")
    check("лексикон працює, коли типу немає",
          normalize.classify({"@type": "Event"}, "Вечір настолок і квізу", ""), "games")
    check("забіг — це sport, а не social",
          normalize.classify({"@type": "Event"}, "Ранковий забіг на 5 км", ""), "sport")
    # Дитяча вистава — kids, не art і не social.
    check("дитяча вистава — власна категорія kids",
          normalize.classify({"@type": "ChildrensEvent"}, "Рапунцель", ""), "kids")
    # Стендап — власна категорія.
    check("ComedyEvent — це comedy, а не art",
          normalize.classify({"@type": "ComedyEvent"}, "Сольний стендап", ""), "comedy")
    check("нетипізований стендап лексикон теж ловить",
          normalize.classify({"@type": "Event"}, "Відкритий мікрофон у пабі", ""), "comedy")
    check("вистава лишається art",
          normalize.classify({"@type": "Event"}, "Вистава «Гойзум»", ""), "art")


# ---- Ціна

def test_price() -> None:
    print("\nЦіна й безкоштовність")
    check("мінімальна з кількох пропозицій",
          normalize.parse_price({"offers": [{"price": "450"}, {"price": "250"}]}), (250.0, False))
    check("нуль означає безкоштовно",
          normalize.parse_price({"offers": {"price": 0}}), (0.0, True))
    check("«вхід вільний» у тексті, коли offers немає",
          normalize.parse_price({"description": "Вхід вільний, реєстрація не потрібна"}), (0.0, True))
    check("нічого не відомо — не вигадуємо",
          normalize.parse_price({"description": "Концерт"}), (None, None))


# ---- Майданчики

def test_venue_matching() -> None:
    print("\nЗіставлення майданчиків")
    osm = [
        {"type": "way", "id": 1, "lat": 50.4499, "lon": 30.5278,
         "tags": {"name": "Міжнародний центр культури і мистецтв", "amenity": "arts_centre"}},
        {"type": "node", "id": 2, "lat": 50.4083, "lon": 30.5130,
         "tags": {"name": "Stereo Plaza", "amenity": "nightclub"}},
        {"type": "node", "id": 3, "lat": 50.4600, "lon": 30.5200,
         "tags": {"name": "Atlas Coffee", "amenity": "cafe"}},
    ]
    index = VenueIndex(osm, "Київ", {
        "МЦКМ (Жовтневий палац)": "Міжнародний центр культури і мистецтв",
        "ORIGIN STAGE": {"lat": 50.45, "lon": 30.52, "name": "ORIGIN STAGE"},
    })
    check("точний збіг", index.match("Stereo Plaza")["how"], "exact")
    check("псевдонім через назву в OSM", index.match("МЦКМ (Жовтневий палац)")["how"], "alias")
    check("псевдонім координатами для відсутнього в OSM",
          index.match("ORIGIN STAGE")["lat"], 50.45)
    check("невідомий майданчик не вгадується", index.match("COMEDY SHELTER"), None)
    # «Клуб ATLAS» — не «Atlas Coffee»: хибна точка гірша за відсутню.
    check("схожа назва іншого закладу не приймається", index.match("Клуб ATLAS"), None)

    # Однослівна назва — найпідступніший клас: «Feels Garden» знаходив «Garden» за 10 км.
    loose = VenueIndex([
        {"type": "node", "id": 4, "lat": 50.45, "lon": 30.63, "tags": {"name": "Garden"}},
        {"type": "node", "id": 5, "lat": 50.43, "lon": 30.52, "tags": {"name": "Палац спорту"}},
    ], "Київ", {})
    check("однослівна загальна назва відкидається", loose.match("Feels Garden"), None)

    # Правильний збіг під порогом (0.480) розв'язано псевдонімом, а не зниженням порога для всіх.
    kino = VenueIndex([{"type": "way", "id": 9, "lat": 50.4363, "lon": 30.5196,
                        "tags": {"name": "Будинок кіно", "amenity": "cinema"}}], "Київ", {})
    check("«Будинок Кіно. Червоний зал» поріг відхиляє",
          kino.match("Будинок Кіно. Червоний зал"), None)
    kino_aliased = VenueIndex([{"type": "way", "id": 9, "lat": 50.4363, "lon": 30.5196,
                                "tags": {"name": "Будинок кіно", "amenity": "cinema"}}], "Київ",
                              {"Будинок Кіно. Червоний зал": "Будинок кіно"})
    check("а псевдонім його розвʼязує",
          kino_aliased.match("Будинок Кіно. Червоний зал")["how"], "alias")
    check("двослівна назва з нижчим score приймається",
          loose.match("Київський Палац спорту")["how"], "contains")

    # Назва міста — не назва майданчика: «Київ» зіставлявся з «Київська Русь».
    city_trap = VenueIndex([{"type": "way", "id": 7, "lat": 50.52, "lon": 30.50,
                             "tags": {"name": "Київська Русь", "tourism": "attraction"}}], "Київ", {})
    check("місто як назва майданчика не зіставляється", city_trap.match("Київ"), None)
    check("а справжня назва в тому ж індексі зіставляється",
          city_trap.match("Київська Русь")["how"], "exact")


def test_aliases_resolve() -> None:
    """Кожен псевдонім за назвою має знаходити щось хоча б в одному місті: після правки назви
    в OSM псевдонім перестає діяти мовчки. Читає закомітовані дампи; місто без дампу пропускається.
    """
    print("\nПсевдоніми майданчиків розвʼязуються")
    from .venues import CACHE_DIR, build_index, load_aliases
    aliases = {k: v for k, v in load_aliases().items() if not k.startswith("_")}
    cities = [c for c in ("Київ", "Львів", "Харків", "Одеса", "Дніпро")
              if (CACHE_DIR / f"osm_{c.lower()}.json").exists()]
    if not cities:
        check("дампи OSM на місці", bool(cities), True)
        return
    indexes = [build_index(c) for c in cities]
    dead = sorted(k for k in aliases if not any(i.match(k) for i in indexes))
    check(f"усі {len(aliases)} псевдонімів дають координати", dead, [])

    # «ім.» і «імені» — одне слово.
    check("«ім.» зводиться з «імені»",
          normalize.normalize_name("Театр ім. Івана Франка"),
          normalize.normalize_name("Театр імені Івана Франка"))
    # Але не будь-яке слово, що починається на «ім».
    check("«імперія» не чіпається", normalize.normalize_name("Імперія"), "імперія")


# ---- Геокодер

def test_osm_dump_fallback() -> None:
    """Свіжого дампу немає: беремо найновіше із застарілих, а не зупиняємо обхід. Без мережі."""
    print("\nДамп OSM — запасний варіант")
    import io, json as _json, tempfile
    from unittest.mock import patch
    from . import venues
    fresh = "2026-09-25T00:00:00Z"
    old = {"osm3s": {"timestamp_osm_base": "2026-07-15T00:00:00Z"}, "elements": [{"id": 1, "tags": {"name": "старий"}}]}
    older = {"osm3s": {"timestamp_osm_base": "2026-05-01T00:00:00Z"}, "elements": [{"id": 2, "tags": {"name": "ще старіший"}}]}

    class _Resp(io.BytesIO):
        def __enter__(self): return self
        def __exit__(self, *a): return False

    def urlopen(req, timeout=0):
        host = req.full_url.split("/")[2]
        if host.startswith("overpass-api"): raise OSError("504")
        if host.startswith("overpass.kumi"): return _Resp(_json.dumps(old).encode())
        return _Resp(_json.dumps({"elements": []}).encode())

    with tempfile.TemporaryDirectory() as tmp, \
         patch.object(venues, "CACHE_DIR", venues.pathlib.Path(tmp)), \
         patch.object(venues.urllib.request, "urlopen", urlopen), \
         patch.object(venues, "dt", venues.dt):
        (venues.pathlib.Path(tmp) / "osm_київ.json").write_text(_json.dumps(older), "utf-8")
        elements = venues.fetch_osm("Київ", refresh=True)
        check("узято найновіше із застарілого (дзеркало, не кеш)", elements[0]["id"], 1)
        saved = _json.loads((venues.pathlib.Path(tmp) / "osm_київ.json").read_text("utf-8"))
        check("кеш оновлено новішим застарілим", saved["osm3s"]["timestamp_osm_base"], "2026-07-15T00:00:00Z")

        def all_down(req, timeout=0): raise OSError("down")
        with patch.object(venues.urllib.request, "urlopen", all_down):
            check("усі дзеркала мовчать — живемо з кешу", venues.fetch_osm("Київ", refresh=True)[0]["id"], 1)
        (venues.pathlib.Path(tmp) / "osm_київ.json").unlink()
        with patch.object(venues.urllib.request, "urlopen", all_down):
            try:
                venues.fetch_osm("Київ", refresh=True); check("без жодного дампу — помилка", True, False)
            except RuntimeError:
                check("без жодного дампу — помилка", True, True)


def test_geocoder_guards() -> None:
    print("\nГеокодер — запобіжники, без яких він шкодить")
    from .geocode import Geocoder
    g = Geocoder("Київ", enabled=True)

    # На «ORIGIN STAGE» Photon віддає кам'яну стелу з type=house: назви закладів у геокодер не йдуть.
    check("метод пошуку за назвою закладу відсутній як клас",
          hasattr(g, "lookup"), False)
    check("адреса без номера будинку не геокодується",
          g.lookup_street("вул. Хрещатик"), None)
    check("порожня адреса не геокодується", g.lookup_street(""), None)

    # Фільтри точності й меж міста на синтетичних відповідях.
    coarse = [{"properties": {"type": "city", "name": "Київ"},
               "geometry": {"coordinates": [30.52, 50.45]}}]
    check("рівень «місто» відкидається", g._pick(coarse), None)

    # «пр. Глушкова, 1»: будинку в Photon немає, він віддає відрізок траси. Краще черга перегляду.
    road = [{"properties": {"type": "street", "name": "проспект Академіка Глушкова"},
             "geometry": {"coordinates": [30.4644336, 50.3739621]}}]
    check("рівень «вулиця» відкидається", g._pick(road), None)

    # Бізнес-центр «Сонячний» в Одесі: Photon першим віддав косметолога з тією самою адресою за 7 км.
    def house(lat, lon, number="5", street="Сонячна вулиця", city="Одеса", name=None, key="shop"):
        return {"properties": {"type": "house", "housenumber": number, "street": street,
                               "city": city, "name": name, "osm_key": key},
                "geometry": {"coordinates": [lon, lat]}}
    o = Geocoder("Одеса", enabled=True)
    arcadia, druzhnyi = house(46.4368, 30.7495), house(46.3772, 30.7106, street="вулиця Сонячна")
    check("єдиний збіг адреси приймається", o._pick([arcadia], "вулиця Сонячна, 5")["lat"], 46.4368)
    check("дві однакові адреси за 7 км — неоднозначно, у чергу перегляду",
          o._pick([druzhnyi, arcadia], "вулиця Сонячна, 5"), None)
    building = house(46.4368, 30.7495, key="building")
    picked = o._pick([druzhnyi, building, arcadia], "вулиця Сонячна, 5")
    check("будівля з адресою переважує заклад з тією самою адресою за 7 км", picked["lat"], 46.4368)
    check("службове поле в результат не потрапляє", "_building" in picked, False)
    check("дві будівлі з однією адресою за 7 км — знову неоднозначно",
          o._pick([house(46.3772, 30.7106, key="building"), building], "вулиця Сонячна, 5"), None)
    check("зупинка з назвою вулиці без номера будинку — не адреса",
          o._pick([house(46.4827, 30.7325, number=None, name="Вул. Грецька")], "вулиця Грецька, 48а"), None)
    check("інший номер будинку — не та адреса",
          o._pick([house(46.4368, 30.7495, number="13/5")], "вулиця Сонячна, 5"), None)
    check("та сама адреса в селі всередині прямокутника — не та адреса",
          o._pick([house(46.4368, 30.7495, city="Фонтанка")], "вулиця Сонячна, 5"), None)
    check("«37/41» і «37-41» — один номер",
          o._pick([house(46.47, 30.73, number="37-41")], "вулиця Сонячна, 37/41") is not None, True)
    check("«м.» після номера — метро, а не літера будинку",
          o._pick([house(46.47, 30.73, number="25")], "вулиця Сонячна, 25 м. Університет") is not None, True)

    # Nominatim — запасний: Photon не знає «Верхній Вал, 66-А», Nominatim знає. Фільтри ті самі.
    from unittest.mock import patch
    from . import geocode as _geocode
    row = {"lat": "50.470901", "lon": "30.520205", "category": "building", "osm_type": "way",
           "osm_id": 45341077, "addresstype": "building",
           "address": {"house_number": "66-А", "road": "вулиця Верхній Вал", "city": "Київ"}}
    stop = {"lat": "50.4699", "lon": "30.5190", "category": "highway", "osm_type": "node",
            "osm_id": 1, "addresstype": "road", "address": {"road": "вулиця Верхній Вал", "city": "Київ"}}
    calls = []

    def fake_get(self, endpoint, query, params):
        calls.append(endpoint)
        return {"features": []} if endpoint == _geocode.ENDPOINT else [stop, row]

    with patch.object(_geocode.Geocoder, "_get", fake_get), \
         patch.object(_geocode.Geocoder, "_save", lambda self: None):
        k = Geocoder("Київ", enabled=True)
        k._cache = {}
        hit = k.lookup_street("вул. Верхній Вал, 66а")
        check("Photon промовчав — питаємо Nominatim", calls, [_geocode.ENDPOINT, _geocode.NOMINATIM])
        check("будинок з Nominatim проходить ті самі фільтри", (hit["lat"], hit["ref"]),
              (50.470901, "nominatim/W45341077"))
        check("щабель лишається «геокодер»: на ньому CHECK у public.venues", hit["how"], "photon")
        k.lookup_street("вул. Верхній Вал, 66а")
        check("друга спроба — з кешу, без мережі", len(calls), 2)


    far = [{"properties": {"type": "house", "name": "десь"},
            "geometry": {"coordinates": [24.03, 49.84]}}]      # Львів у київському запиті
    check("точка за межами міста відкидається", g._pick(far), None)

    # Одне написання типу вулиці: «пр-т» і «пр.» давали різні ключі кешу й різні точки.
    from .geocode import canonical_street
    check("«пр.» і «пр-т» дають один ключ",
          normalize.normalize_name(canonical_street("пр. Небесної сотні, 4/7")),
          normalize.normalize_name(canonical_street("пр-т Небесної Сотні, 4/7")))
    check("«просп.» теж", canonical_street("просп. Берестейський, 37"),
          "проспект Берестейський, 37")
    check("«вул.» розгортається", canonical_street("вул. Хрещатик, 19А"), "вулиця Хрещатик, 19А")
    # Провулок не має стати проспектом: «пров» раніше за «пр».
    check("провулок лишається провулком", canonical_street("пров. Тараса Шевченка, 5"),
          "провулок Тараса Шевченка, 5")
    # І скорочення всередині слова чіпати не можна.
    check("слово, що починається на «пл», не чіпається",
          canonical_street("Пластова вулиця, 7"), "Пластова вулиця, 7")

    good = [{"properties": {"type": "house", "name": "Палац спорту", "osm_id": 1},
             "geometry": {"coordinates": [30.5223, 50.4371]}}]
    hit = g._pick(good)
    check("коректна точка приймається", hit["how"], "photon")
    check("довіра нижча за OSM і за ручну вивірку", hit["confidence"] < 0.9, True)


# ---- Дедуплікація

def _item(slug, title, start="2026-10-17T18:00:00+03:00", lat=50.45, lon=30.53):
    import datetime as _dt
    from .pipeline import Item
    at = normalize.parse_datetime(start, "source", "Europe/Kyiv")
    return Item(source_slug=slug, source_uid=f"https://x/{slug}/{title}",
                event_id=__import__("uuid").uuid4(), title=title, description="", category="music",
                category_how="type", source_type="MusicEvent",
                city="Київ", address="а", venue_name="в", venue_display=None,
                latitude=lat, longitude=lon, venue_ref=None, venue_how="exact", geo_confidence=0.9,
                starts_at=at, ends_at=at + _dt.timedelta(hours=3), end_declared=False,
                time_zone="Europe/Kyiv", image_url=None, canonical_url="https://x",
                price_min=None, is_free=None, description_len=0, stage="published")


def test_dedupe() -> None:
    print("\nДедуплікація між джерелами")
    from .pipeline import drop_cross_source_duplicates, same_event
    w = {"concert_ua": 0.8, "karabas": 0.7}

    check("та сама назва у двох джерелах — дубль",
          same_event(_item("karabas", "ДахаБраха"), _item("concert_ua", "ДахаБраха")), True)
    check("оздоблена назва теж дубль",
          same_event(_item("karabas", "Ніно Катамадзе"),
                     _item("concert_ua", "Ніно Катамадзе. Премʼєра нового альбому")), True)

    # Найдорожча помилка — злити різні події на одній точці в одну годину.
    check("різні події на одній точці й у той самий час не зливаються",
          same_event(_item("karabas", "Відео-галерея: кращі імпресіоністи"),
                     _item("concert_ua", "Відкритий Клуб «Бувальщина»")), False)
    check("та сама назва в одному джерелі — це серія сеансів, не дубль",
          same_event(_item("karabas", "ДахаБраха"), _item("karabas", "ДахаБраха")), False)
    check("інший час — інша подія",
          same_event(_item("karabas", "ДахаБраха"),
                     _item("concert_ua", "ДахаБраха", start="2026-10-18T18:00:00+03:00")), False)

    # Допуск координат 25 м: той самий заклад двома щаблями давав точки за 2–7 м. Обидві межі закріплено.
    check("той самий заклад двома щаблями драбини — дубль",
          same_event(_item("karabas", "ДахаБраха"),
                     _item("concert_ua", "ДахаБраха", lat=50.45004, lon=30.53003)), True)
    # Feels Garden: три афіші — три точки до 1,5 км. У межах міста місце більше не розводить дубль.
    check("те саме місто, та сама хвилина й назва, півтора кілометра — дубль",
          same_event(_item("karabas", "ДахаБраха"),
                     _item("concert_ua", "ДахаБраха", lat=50.4635, lon=30.53)), True)
    far = _item("concert_ua", "Сольний стендап концерт", lat=46.48, lon=30.73)
    far.city = "Одеса"
    check("інше місто — інша подія, хоч назва й хвилина ті самі",
          same_event(_item("karabas", "Сольний стендап концерт"), far), False)
    check("різні назви далеко одна від одної не зливаються",
          same_event(_item("karabas", "Вечір джазу"),
                     _item("concert_ua", "Вечір поезії", lat=50.4635, lon=30.53)), False)

    # Точку злитої картки дає копія з кращим геокодингом, а пара лишається у звіті для aliases.json.
    from .pipeline import near_miss_pairs
    strong, weak = _item("concert_ua", "ДахаБраха"), _item("karabas", "ДахаБраха", lat=50.4635, lon=30.53)
    strong.geo_confidence, weak.geo_confidence = 0.6, 0.98
    drop_cross_source_duplicates([strong, weak], w)
    check("переможець — джерело з вищою вагою", (strong.stage, weak.stage), ("published", "duplicate"))
    check("але точка — з надійнішого геокодингу", (strong.latitude, strong.geo_confidence), (50.4635, 0.98))
    strong2, weak2 = _item("concert_ua", "ДахаБраха"), _item("karabas", "ДахаБраха", lat=50.4635, lon=30.53)
    drop_cross_source_duplicates([strong2, weak2], w)
    check("далеке злиття лишається у звіті near_miss", len(near_miss_pairs([strong2, weak2])), 1)
    # Захист від різних подій на одній точці тримається на словах у назві, не на координатах.
    check("різні події за десять метрів теж не зливаються",
          same_event(_item("karabas", "Відео-галерея: кращі імпресіоністи"),
                     _item("concert_ua", "Відкритий Клуб «Бувальщина»", lat=50.45009)), False)
    check("подія без координат не зливається ні з чим",
          same_event(_item("karabas", "ДахаБраха", lat=None, lon=None),
                     _item("concert_ua", "ДахаБраха")), False)

    # Справжні пари з бази: дві назви тієї самої події від двох джерел.
    from .pipeline import _titles_agree, _tokens

    def agree(a, b):
        return _titles_agree(_tokens(a), _tokens(b))

    for left, right in [
        ("Карміна Бурана (ДАТОБ)", "Кантата «Карміна Бурана»"),
        ("Вій (ООАДТ)", "Мюзикл \"Вій\""),
        ("«Дон Паскуалє» (ОНАТОБ)", "Опера \"Дон Паскуалє\""),
        ("Брехуха (ОАТМК ім. М. Водяного)", "Музична комедія \"Брехуха\""),
        ("Комедійне шоу «Не проблема»", "Гумористичне шоу \"Не Проблема\""),
        ("ALICE Amazing Circus Show", "Неймовірне циркове шоу \"Alice\""),
        ("Батя 2. Сольний стендап концерт Богдана Боярина",
         "Богдан Боярин \"Батя 2\". Сольний стендап концерт"),
    ]:
        check(f"дубль: {left[:26]}", agree(left, right), True)

    # І три пари з тієї ж зали й хвилини, які є різними подіями: нульове перекриття слів задає межу.
    for left, right in [
        ("Дванадцята ніч, або Що захочете (ТЮГ Одеса)", "Вистава \"Лісова пісня\""),
        ("Стендап Володимира Шумко «Шо ти клоун?»", "Концерт \"New Symphonic Vibes\""),
        ("KLER", "Іздрик. Поетичний вечір"),
    ]:
        check(f"різні: {left[:26]}", agree(left, right), False)

    # Довга назва вимагає двох спільних слів.
    check("одне спільне слово в довгих назвах не досить",
          agree("Осінній фестиваль джазу в Парку Шевченка",
                "Зимовий ярмарок ремесел у Парку Франка"), False)

    items = [_item("karabas", "СКАЙ"), _item("concert_ua", "СКАЙ")]
    drop_cross_source_duplicates(items, w)
    kept = [i for i in items if i.stage == "published"]
    check("лишається копія з джерела з вищою вагою", kept[0].source_slug, "concert_ua")
    check("лишається рівно одна", len(kept), 1)


# ---- Витяг

def test_extract() -> None:
    print("\nВитяг JSON-LD")
    html = """<html><script type="application/ld+json">
      {"@context":"http://schema.org","@type":"MusicEvent","name":"A","url":"https://x/a"}
      </script><script type="application/ld+json">
      {"@graph":[{"@type":"TheaterEvent","name":"B","url":"https://x/b"},
                 {"@type":"Organization","name":"не подія"}]}
      </script><script type="application/ld+json">{"зламаний json</script></html>"""
    events = extract.events_from_html(html)
    check("знайдено обидві події, вкладену теж", [e["name"] for e in events], ["A", "B"])
    check("зламаний блок не валить розбір", len(events), 2)


# ---- Реєстр джерел

def test_source_registry() -> None:
    print("\nРеєстр джерел")
    import re as _re
    from .sources import SOURCES, by_slug

    ib = by_slug("internet_bilet")
    # Політика часу джерела виміряна, а не успадкована.
    check("internet_bilet читає час як є (8 із 8 сторінок звірено)", ib.tz_policy, "source")
    check("internet_bilet увімкнено", ib.enabled, True)
    check("покриває пʼять міст", len(ib.listing_urls), 5)

    # Порядок ваг вирішує, чия копія переживе дедуплікацію.
    check("karabas < internet_bilet < concert_ua",
          by_slug("karabas").weight < ib.weight < by_slug("concert_ua").weight, True)

    # Slug, який не пройде CHECK у базі, падає тут, а не при вставці.
    bad = [s.slug for s in SOURCES if not _re.fullmatch(r"[a-z0-9_]{2,40}", s.slug)]
    check("усі slug відповідають CHECK у event_sources", bad, [])


def test_build_internet_bilet() -> None:
    """`_build` — стик, через який проходить кожна подія, і досі не покритий жодним тестом."""
    print("\nЗбирання події з реального JSON-LD internet-bilet")
    import datetime as _dt
    from .pipeline import _build
    from .sources import by_slug
    from .venues import VenueIndex

    # Знято зі сторінки 2026-09-10, скорочено лише в описі.
    raw = json.loads("""{
      "@context":"https://schema.org","@type":"ComedyEvent","name":"Фрайдейс Стендап",
      "image":"https://internet-bilet.ua/images/events_header/size2/eh_1.png",
      "startDate":"2026-09-11T18:00:00+03:00","endDate":"2026-09-11T22:00:00+03:00",
      "url":"https://kyiv.internet-bilet.ua/uk/events/101729/brodyachiy-standup",
      "eventStatus":"EventScheduled",
      "location":{"@type":"Place","name":"Бочка Pub","address":{"@type":"PostalAddress",
        "streetAddress":"вул. Хрещатик, 19А","addressLocality":"Київ","addressCountry":"Україна"}},
      "offers":{"@type":"AggregateOffer","price":"250","lowPrice":"250","highPrice":"350",
        "priceCurrency":"UAH","availability":"https://schema.org/InStock"}}""")

    index = VenueIndex([{"type": "node", "id": 1, "lat": 50.4428, "lon": 30.5205,
                         "tags": {"name": "Бочка Pub"}}], "Київ", {})
    now = _dt.datetime(2026, 9, 1, tzinfo=_dt.timezone.utc)
    item = _build(raw, by_slug("internet_bilet"), "Київ", index, now, None)

    check("подія зібралась", item is not None, True)
    check("ComedyEvent лягає в comedy", item.category, "comedy")
    check("місто з розмітки, не зі сторінки", item.city, "Київ")
    check("час читається як є", item.starts_at.strftime("%H:%M"), "18:00")
    check("кінець оголошений джерелом", item.end_declared, True)
    check("ціна з offers", item.price_min, 250.0)
    check("не безкоштовна", item.is_free, False)
    check("посилання на джерело — https", item.canonical_url.startswith("https://"), True)
    check("опис не довший за правовий ліміт",
          len(item.description) <= normalize.DESCRIPTION_LIMIT + 1, True)

    # Детермінізм uuid5: повторний обхід оновлює подію, а не створює другу.
    again = _build(raw, by_slug("internet_bilet"), "Київ", index, now, None)
    check("той самий ідентифікатор при повторному обході", item.event_id, again.event_id)


def test_internet_bilet_timezone() -> None:
    print("\nЧас internet-bilet — політика 'source'")
    summer = normalize.parse_datetime("2026-09-15T19:00:00+03:00", "source", "Europe/Kyiv")
    check("влітку 19:00+03:00 лишається 19:00",
          summer.astimezone(normalize.zone("Europe/Kyiv")).strftime("%H:%M"), "19:00")
    winter = normalize.parse_datetime("2026-12-15T19:00:00+02:00", "source", "Europe/Kyiv")
    check("взимку 19:00+02:00 лишається 19:00",
          winter.astimezone(normalize.zone("Europe/Kyiv")).strftime("%H:%M"), "19:00")

    # Негативне твердження: політика karabas тут зсунула б кожну подію назад.
    wrong = normalize.parse_datetime("2026-09-15T19:00:00+03:00", "utc_is_local", "Europe/Kyiv")
    check("політика karabas зсунула б цей час на 16:00",
          wrong.astimezone(normalize.zone("Europe/Kyiv")).strftime("%H:%M"), "16:00")


def test_category_gaps() -> None:
    """Детектор прогалин: чи бачить він групу, яка визріла на власну категорію."""
    print("\nПрогалини в категоріях")
    from . import report as rep

    class _Fake:
        def __init__(self, title, category, how, source_type="Event"):
            self.title, self.category, self.category_how = title, category, how
            self.source_type, self.stage = source_type, "published"

    # Дев'ять із дванадцяти заголовків в art про один тип: так виглядав стендап до виділення.
    items = [_Fake(f"Вечір імпровізації №{i}", "art", "type") for i in range(9)]
    items += [_Fake(f"Виставка живопису №{i}", "art", "type") for i in range(9)]
    gaps = rep.category_gaps(items)
    inside = dict(gaps["inside"]).get("art", [])
    words = {w for w, _, _ in inside}
    check("групу видно як кандидата", "імпровізації" in words, True)
    check("щабель класифікації порахований", gaps["how"], {"type": 18})

    # Місто й місяць — не тип події.
    noisy = [_Fake(f"Концерт у Львові {i} вересня", "music", "type") for i in range(8)]
    noisy += [_Fake(f"Опера у Львові {i} вересня", "music", "type") for i in range(8)]
    g2 = rep.category_gaps(noisy)
    w2 = {w for w, _, _ in dict(g2["inside"]).get("music", [])}
    check("місто не потрапляє в кандидати", "львові" in w2, False)
    check("місяць не потрапляє в кандидати", "вересня" in w2, False)

    # fallback окремо: він каже, що словник відстав.
    fb = [_Fake(f"Щось незнайоме {i}", "social", "fallback") for i in range(4)]
    check("fallback видно в зведенні", rep.category_gaps(fb)["how"], {"fallback": 4})

    # Тип, а не слова, ловить прихований рід події.
    mixed = [_Fake(f"Вистава {i}", "art", "type", "TheaterEvent") for i in range(20)]
    mixed += [_Fake(f"Батя {i}", "art", "type", "ComedyEvent") for i in range(6)]
    types = rep.category_gaps(mixed)["types"]["art"]
    check("склад кошика за типами видно", types, {"TheaterEvent": 20, "ComedyEvent": 6})
    check("чужий тип займає помітну частку", round(100 * 6 / 26), 23)
    # Щабель агента у зведенні окремо.
    import contextlib
    import io
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        rep.print_category_gaps(rep.category_gaps([_Fake("Вілла Айва", "tours", "agent")]),
                                list(normalize.CATEGORIES))
    check("щабель агента видно у звіті", "агент" in out.getvalue(), True)

    # Детектор джерела, яке ставить один тип усьому.
    class _Src:
        def __init__(self, slug, policy="trust"):
            self.slug, self.type_policy = slug, policy

    uniform = [_Fake(f"Подія {i}", "music", "type", "MusicEvent") for i in range(40)]
    for item in uniform:
        item.source_slug = "liar"
    rows = rep.source_health(uniform, [_Src("liar")])
    check("однаковий тип у всіх подій — позначено", rows[0]["useless"], True)
    check("частка головного типу порахована", rows[0]["share"], 100.0)

    # Уже вимкнений тип не позначається вдруге.
    quiet = rep.source_health(uniform, [_Src("liar", "weak")])
    check("вимкнений тип більше не турбує", quiet[0]["useless"], False)

    # Здорове джерело мовчить.
    mixed = [_Fake(f"Подія {i}", "art", "type", t)
             for i, t in enumerate(["TheaterEvent", "MusicEvent", "ComedyEvent"] * 14)]
    for item in mixed:
        item.source_slug = "honest"
    check("різні типи не позначаються", rep.source_health(mixed, [_Src("honest")])[0]["useless"],
          False)

    # Мала вибірка — не привід робити висновок про джерело.
    few = [_Fake(f"Подія {i}", "music", "type", "MusicEvent") for i in range(5)]
    for item in few:
        item.source_slug = "tiny"
    check("на пʼятьох подіях висновку не роблять", rep.source_health(few, [_Src("tiny")]), [])


def test_address_rescue() -> None:
    """Адреса зі сторінки події рятує майданчик, якого немає в індексі.

    Найважливіше тут не те, що рятує, а те, ЗВІДКИ береться точка: адресу знайшли в розмітці
    джерела, а координату дав геокодер із перевіркою за прямокутником міста. Модель у цьому
    ланцюжку не бере участі, і правило «координати вигадувати не можна» лишається незрушним.
    """
    print("\nАдреса зі сторінки події")
    import dataclasses as _dc
    from unittest.mock import patch

    from .pipeline import harvest
    from .sources import by_slug
    from .venues import VenueIndex

    source = _dc.replace(by_slug("concert_ua"), catalogs=None)
    index = VenueIndex([], "Київ", {})          # порожній індекс: збігтися нема з чим
    listed = {"@type": "MusicEvent", "name": "Стендап у підвалі",
              "startDate": "2090-06-01T19:00:00+03:00", "endDate": "2090-06-01T21:00:00+03:00",
              "url": "https://concert.ua/uk/event/x",
              "location": {"name": "Komediant", "address": {"addressLocality": "Київ"}}}
    detail = {**listed, "location": {"name": "Komediant",
              "address": {"addressLocality": "Київ", "streetAddress": "вул. Велика Житомирська, 16"}}}

    class _R:
        status, body = 200, "<html></html>"

    class _Geo:
        """Відповідає лише на адресу зі сторінки: зі списку її взяти нізвідки."""
        calls, errors = 0, []
        seen: list = []
        def lookup_street(self, street):
            self.seen.append(street)
            if "Житомирська" not in (street or ""):
                return None
            return {"lat": 50.4556, "lon": 30.5140, "ref": None, "how": "photon", "confidence": 0.8}

    with patch("tools.ingest.pipeline.get", return_value=_R()), \
         patch("tools.ingest.extract.events_from_html", side_effect=[[listed], [detail]]):
        items, counters = harvest(source, "Київ", index, geocoder=_Geo())

    check("подія врятована", len(items), 1)
    check("координата з геокодера", (items[0].latitude, items[0].longitude), (50.4556, 30.5140))
    check("щабель названо чесно", items[0].venue_how, "detail")
    check("порахований у лічильниках", counters.get("rescued_events"), 1)
    check("у геокодер пішла адреса зі сторінки",
          any("Житомирська" in (x or "") for x in _Geo.seen), True)

    # Точка за межами міста не приймається навіть із правильної адреси.
    class _Far:
        calls, errors = 0, []
        def lookup_street(self, street):
            if "Житомирська" not in (street or ""):
                return None
            return {"lat": 49.84, "lon": 24.03, "ref": None, "how": "photon", "confidence": 0.8}

    with patch("tools.ingest.pipeline.get", return_value=_R()), \
         patch("tools.ingest.extract.events_from_html", side_effect=[[listed], [detail]]):
        far, _ = harvest(source, "Київ", index, geocoder=_Far())
    check("чужа точка відхиляється", far[0].latitude, None)


def test_catalog_rung() -> None:
    """Каталог джерела — верхній щабель: це не наш здогад, а вивіска, під якою продають квиток."""
    print("\nКаталог джерела")
    import dataclasses as _dc

    from .pipeline import harvest
    from .sources import by_slug
    from .venues import VenueIndex

    source = by_slug("concert_ua")
    check("каталоги оголошені", bool(source.catalogs), True)
    check("жоден каталог не мапиться в неіснуючу категорію",
          [c for c in source.catalogs.values() if c not in normalize.CATEGORIES], [])
    check("привід — не рід події: festivals і gifts не мапляться",
          any(k in source.catalogs for k in ("festivals", "gifts", "other", "new-year")), False)

    # Каталог перемагає і тип, і словник: тип каже MusicEvent, каталог — humor.
    index = VenueIndex([], "Київ", {"Зал": {"lat": 50.45, "lon": 30.53}})
    raw = {"@type": "MusicEvent", "name": "Закритий Мікрофон",
           "startDate": "2090-06-01T19:00:00+03:00", "endDate": "2090-06-01T21:00:00+03:00",
           "url": "https://concert.ua/uk/event/x",
           "location": {"name": "Зал", "address": {"addressLocality": "Київ"}},
           "_poruch_category": "comedy"}
    one = _dc.replace(source, catalogs=None)
    from unittest.mock import patch

    class _R:
        # Тіло має бути непорожнім: harvest відкидає порожню відповідь як помилку джерела.
        status, body = 200, "<html></html>"
    with patch("tools.ingest.pipeline.get", return_value=_R()), \
         patch("tools.ingest.extract.events_from_html", return_value=[raw]):
        items, _ = harvest(one, "Київ", index)
    check("подія з каталогу побудувалась", len(items), 1)
    check("категорія взята з каталогу", items[0].category, "comedy")
    check("щабель названо catalog", items[0].category_how, "catalog")

    # Вигадана категорія з каталогу не приймається, як і від агента.
    with patch("tools.ingest.pipeline.get", return_value=_R()), \
         patch("tools.ingest.extract.events_from_html",
               return_value=[{**raw, "_poruch_category": "вигадане"}]):
        items, _ = harvest(one, "Київ", index)
    check("невідома категорія зі стампу відкидається", items[0].category_how != "catalog", True)


def main() -> int:
    for test in (test_timezone_trap, test_city_trap, test_description_trap,
                 test_title_and_category, test_price, test_venue_matching,
                 test_aliases_resolve, test_osm_dump_fallback, test_geocoder_guards, test_dedupe, test_extract,
                 test_source_registry, test_build_internet_bilet, test_category_gaps,
                 test_internet_bilet_timezone, test_catalog_rung, test_address_rescue):
        test()
    print("\n" + "─" * 58)
    if FAILURES:
        print(f"ПРОВАЛЕНО: {len(FAILURES)} — {', '.join(FAILURES)}")
        return 1
    print("Усі перевірки пройдено.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
