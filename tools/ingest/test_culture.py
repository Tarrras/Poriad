"""Межі безпеки для витягу програм і обмеженого обходу офіційних джерел."""
import json
import unittest
from tools.ingest import culture
from tools.ingest.fetch import Response

PROGRAM = '''<h1>Дні спадщини 2027</h1><h3>12 вересня</h3>
<h4>Екскурсія</h4><p>вул. Зелена, 22</p>
<p>12 вересня, 10:00–11:30</p><p>12 вересня, 12:00–13:30</p>
<h4>Невідомий час</h4><p>вул. Інша, 4</p><p>12 вересня</p>'''

class CultureTests(unittest.TestCase):
    def test_program_separates_sessions_and_uses_title_year(self):
        events = culture.lviv_program(PROGRAM, 'https://lviv.travel/ua/news/program', 'Львів')
        self.assertEqual(len(events), 2)
        self.assertEqual(events[0]['startDate'], '2027-09-12T10:00:00+03:00')
        self.assertEqual(events[1]['endDate'], '2027-09-12T13:30:00+03:00')
        self.assertEqual(events[0]['location']['address']['streetAddress'], 'вул. Зелена, 22')

    def test_program_accepts_weekday_prefix_used_by_live_portal(self):
        body = PROGRAM.replace('12 вересня, 10:00', 'Субота, 12 вересня 10:00')
        events = culture.lviv_program(body, 'https://lviv.travel/ua/events/program', 'Львів')
        self.assertEqual(events[0]['startDate'], '2027-09-12T10:00:00+03:00')

    def test_parallel_programme_events_have_distinct_source_urls(self):
        other = '<h4>Інша екскурсія</h4><p>вул. Інша, 4</p><p>12 вересня, 10:00–11:00</p>'
        events = culture.lviv_program(PROGRAM + other,
            'https://lviv.travel/ua/events/program', 'Львів')
        same_time = [event for event in events if event['startDate'].endswith('10:00:00+03:00')]
        self.assertEqual(len(same_time), 2)
        self.assertEqual(len({event['url'] for event in same_time}), 2)

    def test_missing_title_year_does_not_borrow_copyright_year(self):
        self.assertEqual(culture.lviv_program(PROGRAM.replace('2027','')+'<footer>2027</footer>', 'https://lviv.travel/a', 'Львів'), [])

    def test_range_or_missing_address_is_not_a_session(self):
        for body in [PROGRAM.replace('12 вересня,','11–12 вересня,'), PROGRAM.replace('вул. Зелена, 22', '')]:
            self.assertEqual(culture.lviv_program(body, 'https://lviv.travel/a','Львів'), [])

    def test_bounded_discovery_excludes_categories_and_external_links(self):
        url='https://lviv.travel/ua/news'
        html='<a href="/ua/news/c-art">category</a><a href="/ua/news/a">a</a><a href="/ua/news/b">b</a><a href="https://evil.test/ua/news/c">c</a>'
        pages={url:html,url+'/a':PROGRAM,url+'/b':PROGRAM}
        events,diag=culture.collect('lviv-travel',url,'Львів',get=lambda u,**kw:Response(u,200,pages[u]),max_details=1)
        self.assertEqual(len(events),2)
        self.assertEqual(diag['fetched'],2)
        self.assertEqual(diag['coverage'],'partial')
        self.assertIn('max_details',diag['stop_reason'])

    def test_robots_failure_is_reported(self):
        def blocked(*a,**k): raise PermissionError('robots unavailable')
        events,diag=culture.collect('yermilovcentre','https://yermilovcentre.org/','Харків',get=blocked)
        self.assertEqual(events,[])
        self.assertTrue(diag['errors'])
        self.assertNotEqual(diag['coverage'],'complete')

    def test_relative_date_and_opening_hours_are_not_events(self):
        url='https://artsvit.dp.ua/'
        html='<a href="news/workshop/">Workshop</a>'
        detail='<h1>Майстерня</h1><p>07/09/2026</p><p>цієї суботи, 11:00</p><footer>Галерея працює 12:00–19:00</footer>'
        events,diag=culture.collect('artsvit',url,'Дніпро',get=lambda u,**kw:Response(u,200,html if u==url else detail))
        self.assertEqual(events,[])
        self.assertEqual(diag['review'][0]['reason'],'no_verified_session')

    def test_structured_event_needs_own_city_and_exact_datetime(self):
        url='https://artsvit.dp.ua/'
        e={'@type':'Event','name':'Talk','startDate':'2027-01-12T17:00','location':{'address':{'addressLocality':'Дніпро','streetAddress':'вул. Тест, 1'}}}
        def run(event):
            return culture.collect('artsvit',url,'Дніпро',get=lambda u,**kw:Response(u,200,'<script type="application/ld+json">'+json.dumps(event)+'</script>'))[0]
        self.assertEqual(run(e)[0]['startDate'],'2027-01-12T17:00:00+02:00')
        self.assertEqual(run(dict(e,startDate='2027-01-12')),[])
        self.assertEqual(run(dict(e,location={'address':{'addressLocality':'Київ'}})),[])

if __name__=='__main__': unittest.main()
