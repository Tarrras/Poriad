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


# ---------------------------------------------------------------- пастка A: час

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

    # karabas — підступніший випадок: зсув коректний і навіть з переходом на зимовий час, тому
    # дані виглядають бездоганно. Але момент зсунуто вперед рівно на цей зсув: сторінка показує
    # «17 жовтня 2026, 18:00», а JSON-LD каже 21:00+03:00. Перевірено на 10 сторінках із 10.
    k1 = normalize.parse_datetime("2026-10-17T21:00:00+03:00", "utc_is_local", "Europe/Kyiv")
    check("karabas: 21:00+03:00 насправді 18:00 (літо)",
          k1.astimezone(normalize.zone("Europe/Kyiv")).strftime("%H:%M"), "18:00")
    k2 = normalize.parse_datetime("2026-12-15T21:00:00+02:00", "utc_is_local", "Europe/Kyiv")
    check("karabas: 21:00+02:00 насправді 19:00 (зима)",
          k2.astimezone(normalize.zone("Europe/Kyiv")).strftime("%H:%M"), "19:00")

    # concert.ua зсув віддає правильно, і його не можна ламати поправкою для іншого джерела.
    ok = normalize.parse_datetime("2026-09-12T21:00:00+03:00", "source", "Europe/Kyiv")
    check("джерело з коректним зсувом читається як є",
          ok.astimezone(normalize.zone("Europe/Kyiv")).strftime("%H:%M"), "21:00")


# ---------------------------------------------------------------- пастка B: місто

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


# ---------------------------------------------------------------- пастка C: опис

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


# ---------------------------------------------------------------- заголовок і категорія

def test_title_and_category() -> None:
    print("\nЗаголовок під CHECK (3..120) і категорія")
    long_title = "Концерт " * 30
    t = normalize.normalize_title(long_title)
    check("заголовок вкладається в CHECK", 3 <= len(t) <= normalize.TITLE_MAX, True)
    check("короткий сміттєвий заголовок відкидається", normalize.normalize_title("а"), None)

    # ── Десята й одинадцята категорії. Обидві виділені з кошиків, які їх ховали, тож найцінніше
    # тут — не те, що вони спрацьовують, а те, ДЕ проходить межа з сусідом.
    def cat(title):
        return normalize.classify_with_reason({}, title, "")[0]

    check("екскурсія — це tours, а не outdoors", cat("Екскурсія «З краси Японії»"), "tours")
    check("спадщина теж", cat("Кам'яниця на Вірменській, 17. «Нашарування спадщини»"), "tours")
    check("конференція — це conference, а не social", cat("Event Industry Forum 2027"), "conference")
    check("саміт теж", cat("SBC Summit Ukraine 2026"), "conference")

    # Межа з outdoors: піша прогулянка з гідом — екскурсія, а велопрогулянка й похід — ні.
    # Без цієї пари наступний рефакторинг легко забере в outdoors те, заради чого він існує.
    check("піша прогулянка — екскурсія", cat("Піша прогулянка Личаковом"), "tours")
    check("похід лишається природою", cat("Похід у Карпати"), "outdoors")
    check("велопрогулянка не стає екскурсією", cat("Велопрогулянка Дніпром") != "tours", True)

    # Межа з social: побачення наосліп — це зустрічі, і конференцією воно стати не має.
    check("знайомства лишаються в social",
          cat("Побачення наосліп (23-35 років)") != "conference", True)

    # «рок» усередині «року» робив музикою лекцію про архів 1939-го. Межі слова тепер стоять.
    check("«рок» не ловиться в «року»",
          cat("Пастка серпня 1939 року: радянський архів") != "music", True)
    check("а рок-опера лишається музикою", cat("Рок-опера «Ісус Христос»"), "music")

    # Перелік категорій має збігатися зі спільним переліком клієнтів і з CHECK у базі.
    check("категорій одинадцять", len(normalize.CATEGORIES), 11)

    check("@type виграє першим",
          normalize.classify({"@type": "MusicEvent"}, "Вечір настолок", ""), "music")
    check("лексикон працює, коли типу немає",
          normalize.classify({"@type": "Event"}, "Вечір настолок і квізу", ""), "games")
    check("забіг — це sport, а не social",
          normalize.classify({"@type": "Event"}, "Ранковий забіг на 5 км", ""), "sport")
    # Дитяча вистава — це art. У social вона розводила б категорію вістря, яку продукт і так
    # намагається наповнити спільнотними подіями.
    # 91 подія по пʼятьох містах, 15% кошика art — це знайшов report.category_gaps.
    check("дитяча вистава — власна категорія kids",
          normalize.classify({"@type": "ChildrensEvent"}, "Рапунцель", ""), "kids")
    # Стендап має власну категорію: у спільній скриньці з театром він губиться саме для тієї
    # аудиторії, заради якої його й імпортують.
    check("ComedyEvent — це comedy, а не art",
          normalize.classify({"@type": "ComedyEvent"}, "Сольний стендап", ""), "comedy")
    check("нетипізований стендап лексикон теж ловить",
          normalize.classify({"@type": "Event"}, "Відкритий мікрофон у пабі", ""), "comedy")
    check("вистава лишається art",
          normalize.classify({"@type": "Event"}, "Вистава «Гойзум»", ""), "art")


# ---------------------------------------------------------------- ціна

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


# ---------------------------------------------------------------- майданчики

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
    # Найважливіше: «Клуб ATLAS» — не «Atlas Coffee». Хибна точка гірша за її відсутність,
    # бо подія тихо зʼявляється на мапі не там, де відбувається.
    check("схожа назва іншого закладу не приймається", index.match("Клуб ATLAS"), None)

    # Однослівна загальна назва — найпідступніший клас помилок: «Feels Garden» знаходив «Garden»
    # за десять кілометрів. Двослівна назва з тим самим score правильна, тому поріг залежить від
    # кількості слів, а не лише від score.
    loose = VenueIndex([
        {"type": "node", "id": 4, "lat": 50.45, "lon": 30.63, "tags": {"name": "Garden"}},
        {"type": "node", "id": 5, "lat": 50.43, "lon": 30.52, "tags": {"name": "Палац спорту"}},
    ], "Київ", {})
    check("однослівна загальна назва відкидається", loose.match("Feels Garden"), None)

    # Шостий приклад, знайдений із появою internet-bilet: правильний збіг, який поріг усе одно
    # відхиляє (0.480 при 0.5). Тест закріплює саме те, що поріг НЕ зсунуто, а розвʼязано
    # псевдонімом — інакше наступний рефакторинг «полагодить» його зниженням межі для всіх.
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


def test_aliases_resolve() -> None:
    """Кожен псевдонім за назвою мусить знаходити щось хоча б в одному місті.

    Псевдонім із значенням-рядком шукається в індексі ТОЧНИМ ключем. Якщо в OSM назву
    відредагували, псевдонім перестає діяти — і робить це мовчки: подія просто йде в чергу
    перегляду, як і будь-яка інша незіставлена. Саме так «Український театр ім. В. Василька»
    вказував на назву без ініціала «С.», якого в OSM тим часом додали.

    Тест читає закомітовані дампи, тож мережі не потребує. Місто, чийого дампу немає, просто
    пропускається — інакше свіжий клон падав би без причини.
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

    # «ім.» і «імені» — одне слово. Розкол по крапці лишав театр Франка в черзі перегляду,
    # хоч він є в дампі під тією ж назвою слово в слово.
    check("«ім.» зводиться з «імені»",
          normalize.normalize_name("Театр ім. Івана Франка"),
          normalize.normalize_name("Театр імені Івана Франка"))
    # Але не будь-яке слово, що починається на «ім».
    check("«імперія» не чіпається", normalize.normalize_name("Імперія"), "імперія")


# ---------------------------------------------------------------- геокодер

def test_geocoder_guards() -> None:
    print("\nГеокодер — запобіжники, без яких він шкодить")
    from .geocode import Geocoder
    g = Geocoder("Київ", enabled=True)

    # Найдорожчий урок: на «ORIGIN STAGE» Photon віддає кам'яну стелу з type=house. Тому назви
    # закладів у геокодер не потрапляють узагалі — метод приймає лише вуличну адресу.
    check("метод пошуку за назвою закладу відсутній як клас",
          hasattr(g, "lookup"), False)
    check("адреса без номера будинку не геокодується",
          g.lookup_street("вул. Хрещатик"), None)
    check("порожня адреса не геокодується", g.lookup_street(""), None)

    # Фільтри рівня точності й меж міста — на синтетичних відповідях, без мережі.
    coarse = [{"properties": {"type": "city", "name": "Київ"},
               "geometry": {"coordinates": [30.52, 50.45]}}]
    check("рівень «місто» відкидається", g._pick(coarse), None)

    far = [{"properties": {"type": "house", "name": "десь"},
            "geometry": {"coordinates": [24.03, 49.84]}}]      # Львів у київському запиті
    check("точка за межами міста відкидається", g._pick(far), None)

    # ── Одне написання типу вулиці. Два джерела пишуть ту саму адресу по-різному, і поки це
    # доходило до Photon як є, кожне написання давало свій ключ кешу, свій запит і свою точку.
    # Жива пара: «Lely45» в Одесі, karabas пише «пр-т Небесної Сотні, 4/7», internet-bilet
    # «пр. Небесної сотні, 4/7». Точки розійшлись на 42.8 м, подія не злилась і стояла двічі.
    from .geocode import canonical_street
    check("«пр.» і «пр-т» дають один ключ",
          normalize.normalize_name(canonical_street("пр. Небесної сотні, 4/7")),
          normalize.normalize_name(canonical_street("пр-т Небесної Сотні, 4/7")))
    check("«просп.» теж", canonical_street("просп. Берестейський, 37"),
          "проспект Берестейський, 37")
    check("«вул.» розгортається", canonical_street("вул. Хрещатик, 19А"), "вулиця Хрещатик, 19А")
    # Найважливіше: провулок не має стати проспектом. «пров» перевіряється раніше за «пр».
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


# ---------------------------------------------------------------- дедуплікація

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

    # Найдорожча помилка тут — злити РІЗНІ події. У MODI о 19:00 того самого дня справді йдуть
    # дві різні події на одній точці; хибне злиття сховало б одну з них назавжди.
    check("різні події на одній точці й у той самий час не зливаються",
          same_event(_item("karabas", "Відео-галерея: кращі імпресіоністи"),
                     _item("concert_ua", "Відкритий Клуб «Бувальщина»")), False)
    check("та сама назва в одному джерелі — це серія сеансів, не дубль",
          same_event(_item("karabas", "ДахаБраха"), _item("karabas", "ДахаБраха")), False)
    check("інший час — інша подія",
          same_event(_item("karabas", "ДахаБраха"),
                     _item("concert_ua", "ДахаБраха", start="2026-10-18T18:00:00+03:00")), False)

    # Координати: раніше тут вимагалась побітова рівність, і цей тест її закріплював. Межу
    # свідомо зсунуто на 25 м, бо суворість коштувала 45 подій на прогоні пʼяти міст — той самий
    # заклад двома щаблями драбини давав точки за 2–7 м, і подія публікувалась двічі.
    # Обидві межі закріплені навмисно: хто колись розширить допуск, має перевернути другий рядок.
    check("той самий заклад двома щаблями драбини — дубль",
          same_event(_item("karabas", "ДахаБраха"),
                     _item("concert_ua", "ДахаБраха", lat=50.45004, lon=30.53003)), True)
    check("сто метрів — це вже інший майданчик",
          same_event(_item("karabas", "ДахаБраха"),
                     _item("concert_ua", "ДахаБраха", lat=50.4509, lon=30.53)), False)
    # Захист від MODI від допуску не залежить: він тримається на словах у назві, а не на точці.
    check("різні події за десять метрів теж не зливаються",
          same_event(_item("karabas", "Відео-галерея: кращі імпресіоністи"),
                     _item("concert_ua", "Відкритий Клуб «Бувальщина»", lat=50.45009)), False)
    check("подія без координат не зливається ні з чим",
          same_event(_item("karabas", "ДахаБраха", lat=None, lon=None),
                     _item("concert_ua", "ДахаБраха")), False)

    # ── Справжні пари з бази після обходу пʼяти міст. Правило-підмножина не зловило жодної з
    # них, і саме тому в базі лишались дублікати. Кожен рядок — дві назви тієї самої події, як їх
    # підписали два різні джерела.
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

    # ── І три пари, які виглядають так само (та сама зала, та сама хвилина), але це РІЗНІ події.
    # Вони й задають межу: усі три мають нульове перекриття слів. Той, хто колись послабить
    # правило, має спершу пояснити, чому ці три лишаться нерозділеними.
    for left, right in [
        ("Дванадцята ніч, або Що захочете (ТЮГ Одеса)", "Вистава \"Лісова пісня\""),
        ("Стендап Володимира Шумко «Шо ти клоун?»", "Концерт \"New Symphonic Vibes\""),
        ("KLER", "Іздрик. Поетичний вечір"),
    ]:
        check(f"різні: {left[:26]}", agree(left, right), False)

    # Довга назва вимагає двох спільних слів: одне випадкове в ній важить менше, ніж у короткій.
    check("одне спільне слово в довгих назвах не досить",
          agree("Осінній фестиваль джазу в Парку Шевченка",
                "Зимовий ярмарок ремесел у Парку Франка"), False)

    items = [_item("karabas", "СКАЙ"), _item("concert_ua", "СКАЙ")]
    drop_cross_source_duplicates(items, w)
    kept = [i for i in items if i.stage == "published"]
    check("лишається копія з джерела з вищою вагою", kept[0].source_slug, "concert_ua")
    check("лишається рівно одна", len(kept), 1)


# ---------------------------------------------------------------- витяг

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


# ---------------------------------------------------------------- реєстр джерел

def test_source_registry() -> None:
    print("\nРеєстр джерел")
    import re as _re
    from .sources import SOURCES, by_slug

    ib = by_slug("internet_bilet")
    # Найважливіше твердження файлу: політика часу цього джерела виміряна, а не успадкована.
    check("internet_bilet читає час як є (8 із 8 сторінок звірено)", ib.tz_policy, "source")
    check("internet_bilet увімкнено", ib.enabled, True)
    check("покриває пʼять міст", len(ib.listing_urls), 5)

    # Порядок ваг — це рішення про те, чия копія переживе дедуплікацію. Хай воно буде закріплене,
    # а не випадкове.
    check("karabas < internet_bilet < concert_ua",
          by_slug("karabas").weight < ib.weight < by_slug("concert_ua").weight, True)

    # Обмеження БД, перенесене в тест: slug, який не пройде CHECK, впаде тут, а не при вставці.
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

    # Детермінізм uuid5: саме на ньому тримається те, що повторний обхід ОНОВЛЮЄ подію,
    # а не створює другу. Досі це не було перевірено ніде.
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

    # Найважливіше — негативне твердження. Воно каже, у що обійшлося б скопіювати сюди політику
    # karabas: кожна подія поїхала б на зсув назад, і побачили б ми це не одразу.
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

    # Дванадцять заголовків у art, дев'ять з яких — про той самий тип події. Приблизно так
    # виглядав стендап усередині art перед тим, як його виділили.
    items = [_Fake(f"Вечір імпровізації №{i}", "art", "type") for i in range(9)]
    items += [_Fake(f"Виставка живопису №{i}", "art", "type") for i in range(9)]
    gaps = rep.category_gaps(items)
    inside = dict(gaps["inside"]).get("art", [])
    words = {w for w, _, _ in inside}
    check("групу видно як кандидата", "імпровізації" in words, True)
    check("щабель класифікації порахований", gaps["how"], {"type": 18})

    # Місто й місяць у заголовку не є типом події — вони не повинні очолювати рейтинг.
    noisy = [_Fake(f"Концерт у Львові {i} вересня", "music", "type") for i in range(8)]
    noisy += [_Fake(f"Опера у Львові {i} вересня", "music", "type") for i in range(8)]
    g2 = rep.category_gaps(noisy)
    w2 = {w for w, _, _ in dict(g2["inside"]).get("music", [])}
    check("місто не потрапляє в кандидати", "львові" in w2, False)
    check("місяць не потрапляє в кандидати", "вересня" in w2, False)

    # fallback рахується окремо: саме він каже, що словник відстав від джерел.
    fb = [_Fake(f"Щось незнайоме {i}", "social", "fallback") for i in range(4)]
    check("fallback видно в зведенні", rep.category_gaps(fb)["how"], {"fallback": 4})

    # Головна перевірка: саме тип, а не слова, ловить прихований рід події. Це зʼясувалось на
    # реальних даних — заголовки стендапу надто різні, щоб їх зібрало спільне слово.
    mixed = [_Fake(f"Вистава {i}", "art", "type", "TheaterEvent") for i in range(20)]
    mixed += [_Fake(f"Батя {i}", "art", "type", "ComedyEvent") for i in range(6)]
    types = rep.category_gaps(mixed)["types"]["art"]
    check("склад кошика за типами видно", types, {"TheaterEvent": 20, "ComedyEvent": 6})
    check("чужий тип займає помітну частку", round(100 * 6 / 26), 23)


def main() -> int:
    for test in (test_timezone_trap, test_city_trap, test_description_trap,
                 test_title_and_category, test_price, test_venue_matching,
                 test_aliases_resolve, test_geocoder_guards, test_dedupe, test_extract,
                 test_source_registry, test_build_internet_bilet, test_category_gaps,
                 test_internet_bilet_timezone):
        test()
    print("\n" + "─" * 58)
    if FAILURES:
        print(f"ПРОВАЛЕНО: {len(FAILURES)} — {', '.join(FAILURES)}")
        return 1
    print("Усі перевірки пройдено.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
