"""Розклад кінотеатрів (cinema.py) на зразках розмітки Planeta Kino 2026-10-28."""
import dataclasses
import datetime as dt
import unittest

from tools.ingest import cinema, pipeline
from tools.ingest.fetch import Response
from tools.ingest.normalize import zone
from tools.ingest.sources import by_slug
from tools.ingest.venues import VenueIndex

KYIV = zone("Europe/Kyiv")
NOW = dt.datetime(2026, 10, 28, 9, 0, tzinfo=dt.timezone.utc)


def pk_session(sid, time, fmt="2D"):
    return (f'<div id="{sid}-session-slide-item" data-component-name="SessionItem"><div class="time"><span>\n'
            f'            {time}\n          </span> <div>{fmt}</div></div></div>')


PK_DAY = f'''<div class="absolute bottom-2 right-2">
        12+
      </div></div> <div class="hidden sm:block"><a href="/movie/forgotten-island/">
          ЗАБУТИЙ ОСТРІВ
        </a>{pk_session("Z2lkOi8vc2Vzc2lvbi8x", "18:00", "3D")}{pk_session("Z2lkOi8vc2Vzc2lvbi8y", "18:30")}</div>
<div class="sm:hidden"><a href="/movie/forgotten-island/">ЗАБУТИЙ ОСТРІВ</a>{pk_session("Z2lkOi8vc2Vzc2lvbi8x", "18:00", "3D")}</div>
<script>window.__NUXT__=(function(a,b){{return {{sessions:[{{startSessionAt:"2026-10-29T16:00:00.000Z",id:"Z2lkOi8vc2Vzc2lvbi8x"}},
{{startSessionAt:a,id:"Z2lkOi8vc2Vzc2lvbi8y"}}]}}}}("x"))</script>'''

PK_MOVIE = '''<title>Забутий острів (2026) — квитки та сеанси | Планета Кіно</title>
<script type="application/ld+json">{"@context":"https://schema.org","@type":"Movie","name":"ЗАБУТИЙ ОСТРІВ",
"description":"Твоя найкраща дружба варта того, щоб за неї боротися. ","image":["https://cdn.planetakino.ua/p.webp"],
"duration":"PT1H49M"}</script>'''

PK_CINEMAS = '''<script type="application/ld+json">{"@type":"MovieTheater","name":"Планета Кіно","department":[
{"@type":"MovieTheater","name":"Планета Кіно Блокбастер","address":{"streetAddress":"проспект Степана Бандери, 34В, РЦ «Блокбастер»"}}]}</script>'''


class PlanetaTests(unittest.TestCase):
    day = dt.date(2026, 10, 29)

    def test_desktop_and_mobile_copies_are_one_session(self):
        events = cinema.planeta_sessions(PK_DAY, "Київ", "Планета Кіно Блокбастер", "просп. Бандери, 34В", "blokbaster", self.day)
        self.assertEqual([e["startDate"] for e in events], ["2026-10-29T18:00:00+02:00", "2026-10-29T18:30:00+02:00"])
        self.assertEqual(events[0]["name"], "ЗАБУТИЙ ОСТРІВ")
        self.assertEqual(events[0]["url"], "https://planetakino.ua/movie/forgotten-island/?cinema=blokbaster")
        self.assertEqual(events[0]["description"], "12+.")

    def test_page_of_another_day_is_an_error(self):
        with self.assertRaisesRegex(ValueError, "PAGE_DAY_MISMATCH"):
            cinema.planeta_sessions(PK_DAY, "Київ", "x", "", "blokbaster", dt.date(2026, 10, 28))

    def test_movie_page(self):
        movie = cinema.planeta_movie(PK_MOVIE)
        self.assertEqual(movie["title"], "Забутий острів", "назва з <title>, а не капсом")
        self.assertEqual(movie["duration"], dt.timedelta(hours=1, minutes=49))


def fake_get(pages, redirects=None):
    def get(url, **kw):
        target = (redirects or {}).get(url, url)
        body = pages.get(target)
        return Response(url, 200 if body else 404, body or "", final_url=target)
    return get


class CollectTests(unittest.TestCase):
    def test_planeta_takes_title_and_address_from_its_pages(self):
        source = by_slug("planeta_kino")
        pages = {"https://planetakino.ua/cinemas/": PK_CINEMAS,
                 "https://planetakino.ua/schedule/?cinema=blokbaster&date=2026-10-29": PK_DAY,
                 "https://planetakino.ua/movie/forgotten-island/": PK_MOVIE}
        events, report = cinema.collect("planeta", source, "Київ", get=fake_get(pages), now=NOW)
        self.assertEqual({e["name"] for e in events}, {"Забутий острів"})
        self.assertEqual(events[0]["location"]["address"]["streetAddress"], "проспект Степана Бандери, 34В, РЦ «Блокбастер»")
        self.assertEqual(events[0]["endDate"], "2026-10-29T19:49:00+02:00")
        self.assertTrue(report["errors"], "інші дні й кінотеатри не відкрились")

    def test_planeta_day_without_sessions_redirects_to_today(self):
        """Planeta віддає 302 на сьогоднішню дату, коли дня в розкладі нема: це порожній день, а не сеанси того дня."""
        source = by_slug("planeta_kino")
        day = "https://planetakino.ua/schedule/?cinema=blokbaster&date="
        pages = {"https://planetakino.ua/cinemas/": PK_CINEMAS, day + "2026-10-29": PK_DAY,
                 "https://planetakino.ua/movie/forgotten-island/": PK_MOVIE}
        events, report = cinema.collect("planeta", source, "Київ", now=NOW,
                                        get=fake_get(pages, {day + "2026-11-03": day + "2026-10-29"}))
        self.assertEqual({e["startDate"][:10] for e in events}, {"2026-10-29"})
        self.assertEqual(report["empty_days"], 1)
        self.assertFalse([e for e in report["errors"] if "blokbaster" in e and "2026-11-03" in e],
                         "переадресація — не збій сторінки")


class VenueTests(unittest.TestCase):
    def test_every_cinema_has_a_verified_point_in_its_city(self):
        """Без псевдоніма зал іде в чергу, а псевдонім спільний для всіх міст: «Дафі» є і в Харкові, і в Дніпрі."""
        from tools.ingest.geocode import CITY_BBOX
        from tools.ingest.venues import load_aliases
        from tools.ingest.normalize import normalize_name
        aliases = {normalize_name(k): v for k, v in load_aliases().items() if not k.startswith("_")}
        names = [(city, name) for city, venues in by_slug("planeta_kino").venues.items() for name in venues.values()]
        self.assertEqual(len(names), len({normalize_name(n) for _, n in names}), "одна назва — один зал")
        for city, name in names:
            point = aliases.get(normalize_name(name))
            self.assertIsInstance(point, dict, name)
            south, west, north, east = CITY_BBOX[city]
            self.assertTrue(south <= point["lat"] <= north and west <= point["lon"] <= east, f"{name} поза {city}")
        self.assertEqual(set(by_slug("planeta_kino").listing_urls), set(by_slug("planeta_kino").venues))

    def test_multiplex_is_not_a_source(self):
        """Multiplex 30.10.2026 не погодив показ свого розкладу: ні джерела, ні точок, поки нема письмової згоди."""
        from tools.ingest.sources import SOURCES
        from tools.ingest.venues import load_aliases
        self.assertFalse([s.slug for s in SOURCES if "multiplex" in s.slug or "multiplex" in s.base_url])
        self.assertFalse([k for k in load_aliases() if "multiplex" in k.lower()])


class BuildTests(unittest.TestCase):
    """Сеанс проходить звичайний `_build`: категорія від адаптера, точка — лише псевдонім."""
    source = by_slug("planeta_kino")
    raw = cinema.planeta_sessions(PK_DAY, "Київ", "Планета Кіно Блокбастер", "проспект Степана Бандери, 34В",
                                  "blokbaster", dt.date(2026, 10, 29))[0]

    def test_alias_gives_the_point(self):
        index = VenueIndex([], "Київ", {"Планета Кіно Блокбастер": {"lat": 50.4862, "lon": 30.5191}})
        item = pipeline._build(dict(self.raw), self.source, "Київ", index, NOW)
        self.assertEqual((item.category, item.category_how), ("cinema", "catalog"))
        self.assertEqual((item.latitude, item.venue_how), (50.4862, "alias"))

    def test_same_film_same_minute_in_another_cinema_is_another_session(self):
        aliases = {"Планета Кіно Блокбастер": {"lat": 50.4862, "lon": 30.5191},
                   "Планета Кіно River Mall": {"lat": 50.3986, "lon": 30.6189}}
        index = VenueIndex([], "Київ", aliases)
        a = pipeline._build(dict(self.raw), self.source, "Київ", index, NOW)
        other = dict(self.raw, location=dict(self.raw["location"], name="Планета Кіно River Mall"))
        b = pipeline._build(other, self.source, "Київ", index, NOW)
        self.assertFalse(pipeline.same_event(a, b), "12 км — інший зал, хоч місто, хвилина й назва ті самі")
        # Той самий сеанс від іншого продавця (агент, каталог) — у тій самій будівлі зливається.
        twin = pipeline._build(dict(self.raw), dataclasses.replace(self.source, slug="test_seller"), "Київ", index, NOW)
        self.assertTrue(pipeline.same_event(a, twin), "та сама будівля — та сама подія")

    def test_chain_name_in_osm_is_not_a_point(self):
        # Старий вузол «Планета Кіно» в OSM: «Планета Кіно Блокбастер» за входженням став би туди.
        osm = [{"type": "node", "id": 1, "lat": 50.4535, "lon": 30.5989, "tags": {"name": "Планета Кіно"}}]
        item = pipeline._build(dict(self.raw), self.source, "Київ", VenueIndex(osm, "Київ", {}), NOW)
        self.assertIsNone(item.latitude)


if __name__ == "__main__":
    unittest.main()
