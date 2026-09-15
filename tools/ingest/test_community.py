"""Тести меж публічних календарів; підміняється лише HTTP."""
import datetime as dt
import json
import unittest
from . import community
from .fetch import Response

CITY = "Львів"
DOU = "https://dou.ua/calendar/123/"
YOY = "https://yoy.events/club/breakfast"

def card(**kwargs):
    return {"@type": "Event", "name": "Breakfast", "url": DOU,
            "startDate": "2026-09-12", "location": {"name": "Момент",
            "address": {"addressLocality": CITY, "streetAddress": "Фурманська, 17"}}, **kwargs}

def html(event):
    return '<script type="application/ld+json">' + json.dumps(event) + '</script>'

def ical(extra="", start="DTSTART:20260912T100000"):
    return ("BEGIN:VCALENDAR\nBEGIN:VTIMEZONE\nTZID:Europe/Kiev\n"
            "DTSTART:19990101T000000\nEND:VTIMEZONE\nBEGIN:VEVENT\n"
            + start + "\nUID:123.calendar.dou.ua\nURL:" + DOU + "\n" + extra
            + "END:VEVENT\nEND:VCALENDAR\n")

class CommunityTests(unittest.TestCase):
    def test_ical_uses_event_not_timezone_transition(self):
        value = community.ical_dates(ical(), DOU)
        self.assertEqual(value["startDate"], "2026-09-12T10:00:00+03:00")

    def test_ical_rejects_all_day_recurring_foreign_zone_and_other_event(self):
        cases = [ical(start="DTSTART;VALUE=DATE:20260912"), ical("RRULE:FREQ=DAILY\n"),
                 ical(start="DTSTART;TZID=Australia/Adelaide:20260912T100000"),
                 ical().replace(DOU, "https://dou.ua/calendar/456/")]
        for value in cases:
            with self.subTest(value=value):
                self.assertIsNone(community.ical_dates(value, DOU))

    def test_folded_ical_url_and_utc_end(self):
        value = ical("DTEND:20260912T100000Z\n").replace(DOU, "https://dou.ua/\n calendar/123/")
        self.assertEqual(community.ical_dates(value, DOU)["endDate"], "2026-09-12T10:00:00+00:00")

    def test_dou_detail_gets_time_from_ical_and_enrichment_from_registration(self):
        listing = 'https://dou.ua/calendar/city/Lviv/'
        rows = {listing: '<article class="b-postcard"><a href="'+DOU+'">event</a></article>',
                DOU: html(card()) + '<a href="'+DOU+'calendar.ics">iCal</a><article><a href="'+YOY+'">register</a></article>',
                DOU+'calendar.ics': ical(),
                YOY: html(card(url=YOY, startDate='2026-09-12T07:00:00Z', endDate='2026-09-12T10:00:00Z', image='https://yoy.events/p.jpg'))}
        events, report = community.collect('dou', listing, CITY,
            get=lambda u, **kw: Response(u, 200, rows[u]))
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0]['startDate'], '2026-09-12T10:00:00+03:00')
        self.assertEqual(events[0]['endDate'], '2026-09-12T10:00:00Z')
        self.assertEqual(events[0]['_related_urls'], [YOY])

    def test_yoy_filters_city_and_preserves_street_from_place_name(self):
        listing = 'https://yoy.events/events'
        other = 'https://yoy.events/club/other'
        rows = {listing: '<a href="'+YOY+'">event</a><a href="'+other+'">other</a><a href="/communities/new">add</a>',
                YOY: html(card(url=YOY, startDate='2026-09-12T07:00:00Z', location={'name':'Момент. вулиця Фурманська, 17', 'address':CITY})),
                other: html(card(url=other, startDate='2026-09-12T07:00:00Z', location={'name':'Зал', 'address':'Київ'}))}
        events, report = community.collect('yoy', listing, CITY, get=lambda u, **kw: Response(u, 200, rows[u]))
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0]['location']['address']['streetAddress'], 'вулиця Фурманська, 17')

    def test_date_only_without_calendar_is_reported_not_midnight(self):
        listing = 'https://dou.ua/calendar/city/Lviv/'
        rows = {listing:'<article class="b-postcard"><a href="'+DOU+'">event</a></article>', DOU:html(card())}
        events, report = community.collect('dou', listing, CITY, get=lambda u, **kw: Response(u,200,rows[u]))
        self.assertEqual(events, [])
        self.assertTrue(any('UNKNOWN_TIME' in str(x) for x in report['review']))

    def test_dou_midnight_placeholder_is_not_a_live_time(self):
        listing = 'https://dou.ua/calendar/city/Lviv/'
        midnight = card(startDate='2026-09-12T00:00:00+03:00')
        rows = {listing:'<article class="b-postcard"><a href="'+DOU+'">event</a></article>',
                DOU:html(midnight)}
        events, report = community.collect('dou', listing, CITY,
            get=lambda u, **kw: Response(u, 200, rows[u]))
        self.assertEqual(events, [])
        self.assertEqual(report['review'][0]['reason'], 'UNKNOWN_TIME')

    def test_no_cards_and_failed_detail_are_distinguishable(self):
        for body, status in [('<p>No cards</p>',200), ('<a href="'+YOY+'">event</a>',503)]:
            def get(u, **kwargs):
                return Response(u,200,body) if u.endswith('/events') else Response(u,status,'')
            events, report = community.collect('yoy','https://yoy.events/events',CITY,get=get)
            self.assertTrue(report.get('error'))

    def test_dou_ignores_sidebar_recommendations(self):
        listing = 'https://dou.ua/calendar/city/Lviv/'
        sidebar = 'https://dou.ua/calendar/456/?from=premiumevents'
        rows = {listing:'<article class="b-postcard"><a href="'+DOU+'">event</a></article>'
                        '<div class="adv-event-block"><a href="'+sidebar+'">ad</a></div>',
                DOU:html(card()) + '<a href="'+DOU+'calendar.ics">iCal</a>',
                DOU+'calendar.ics':ical()}
        events, report = community.collect('dou', listing, CITY,
            get=lambda u, **kw: Response(u, 200, rows[u]))
        self.assertEqual(len(events), 1)
        self.assertEqual(report['detail_links'], 1)

    def test_dou_explicit_empty_city_page_is_successful_empty(self):
        events, report = community.collect('dou', 'https://dou.ua/calendar/city/Odesa/',
            'Одеса', get=lambda u, **kw: Response(u, 200, '<div>Подій не знайдено.</div>'))
        self.assertEqual(events, [])
        self.assertTrue(report['valid_empty'])
        self.assertNotIn('error', report)

    def test_all_five_import_city_aliases_match(self):
        for city, locality in [('Київ','Kyiv'), ('Львів','Lviv'), ('Харків','Kharkiv'),
                               ('Одеса','Odesa'), ('Дніпро','Dnipro')]:
            event = card(location={'address': {'addressLocality': locality}})
            self.assertTrue(community._same_city(event, city))

    def test_filtered_populated_feed_is_not_silently_successful_empty(self):
        listing = 'https://dou.ua/calendar/city/Dnipro/'
        rows = {listing:'<article class="b-postcard"><a href="'+DOU+'">event</a></article>',
                DOU:html(card(location={'address': {'addressLocality':'Warsaw'}}))}
        events, report = community.collect('dou', listing, 'Дніпро',
            get=lambda u, **kw: Response(u, 200, rows[u]))
        self.assertEqual(events, [])
        self.assertIn('error', report)

    def test_dou_does_not_enrich_from_different_yoy_start(self):
        listing = 'https://dou.ua/calendar/city/Lviv/'
        wrong = card(url=YOY, startDate='2026-09-12T08:00:00Z',
                     endDate='2026-09-12T11:00:00Z', offers={'price':'99'})
        rows = {listing:'<article class="b-postcard"><a href="'+DOU+'">event</a></article>',
                DOU:html(card())+'<article class="b-typo"><a href="'+YOY+'">register</a></article>',
                DOU+'calendar.ics':ical(), YOY:html(wrong)}
        events, _ = community.collect('dou', listing, CITY,
            get=lambda u, **kw: Response(u, 200, rows[u]))
        self.assertNotIn('endDate', events[0])
        self.assertNotIn('offers', events[0])

if __name__ == '__main__':
    unittest.main()
