"""Status notices must target a known session, never an entire event URL."""
import unittest
from .fetch import Response
from . import karabas_status

URL = 'https://karabas.com/info/'
EVENT = 'https://lviv.karabas.com/concert/'


def row(status='Перенесено', old='2026-09-11 18:30', new='2026-09-20 18:30', city='Львів', mobile=False):
    link = f'<a href="{EVENT}">Концерт</a>'
    if mobile:
        return f'''<div class="t-row"><div class="t-value">{link}</div>
        <div class="t-value"><em>Місто:</em><span>{city}</span></div>
        <span class="badge">{status}</span>
        <div class="t-value"><em>Попередня дата:</em><span>{old}</span></div>
        <div class="t-value"><em>Поточна/Нова дата:</em><span>{new}</span></div></div>'''
    return f'<tr><td>{link}<span>Місто: <em>{city}</em></span></td><td><span class="badge">{status}</span></td><td>{old}</td><td>{new}</td></tr>'


def page(desktop='', mobile='', next_page=None):
    return '<table class="infoTable"><tbody>' + desktop + '</tbody></table><div class="mobile-table">' + mobile + '</div>' + (f'<div class="pagination"><a href="?page={next_page}">{next_page}</a></div>' if next_page else '')


class StatusTests(unittest.TestCase):
    def collect(self, body):
        return karabas_status.collect(get=lambda url, **kw: Response(url, 200, body), max_pages=1)

    def test_reschedule_uses_visible_local_dates_and_deduplicates_mobile(self):
        notices, diag = self.collect(page(row(), row(mobile=True)))
        self.assertEqual(len(notices), 1)
        self.assertEqual(notices[0]['starts_at'], '2026-09-11T18:30:00+03:00')
        self.assertEqual(notices[0]['new_start'], '2026-09-20T18:30:00+03:00')
        self.assertEqual(notices[0]['canonical_url'], EVENT)
        self.assertEqual(diag['duplicates'], 1)

    def test_cancelled_current_date_not_historical_previous_date(self):
        notices, _ = self.collect(page(row('Скасовано', '2026-09-11 18:30', '2026-12-20 18:30')))
        self.assertEqual(notices[0]['starts_at'], '2026-12-20T18:30:00+02:00')
        self.assertEqual(notices[0]['status'], 'EventCancelled')

    def test_open_date_current_date_is_affected_session(self):
        notices, _ = self.collect(page(row('Перенесено з відкритою датою', '-', '2026-09-15 18:30')))
        self.assertEqual(notices[0]['status'], 'EventPostponed')
        self.assertEqual(notices[0]['starts_at'], '2026-09-15T18:30:00+03:00')
        self.assertNotIn('new_start', notices[0])

    def test_conflicting_mobile_dates_quarantine_whole_url(self):
        notices, diag = self.collect(page(row(), row(old='2026-09-12 18:30', mobile=True)))
        self.assertEqual(notices, [])
        self.assertTrue(diag['review'])

    def test_same_url_different_sessions_on_desktop_are_allowed(self):
        notices, _ = self.collect(page(row() + row(old='2026-09-12 18:30', new='2026-09-21 18:30')))
        self.assertEqual(len(notices), 2)

    def test_unrelated_city_and_missing_exact_date_are_not_notices(self):
        for r in [row(city='Чернівці'), row(old='-'), row('Скасовано', '-', '-')]:
            self.assertEqual(self.collect(page(r))[0], [])

    def test_pagination_is_bounded_and_reports_partial(self):
        notices, diag = self.collect(page(row(), next_page=2))
        self.assertEqual(len(notices), 1)
        self.assertEqual(diag['coverage'], 'partial')
        self.assertEqual(diag['stop_reason'], 'max_pages')

    def test_errors_and_unrecognized_layout_are_never_complete(self):
        for response in [Response(URL, 503, ''), Response(URL, 200, '<h1>Oops</h1>')]:
            notices, diag = karabas_status.collect(get=lambda url, **kw: response)
            self.assertEqual(notices, [])
            self.assertNotEqual(diag['coverage'], 'complete')
            self.assertTrue(diag['errors'])

    def test_conflict_across_pages_quarantines_same_exact_session(self):
        pages = {URL: page(row(), next_page=2), URL + '?page=2': page(row(new='2026-09-22 18:30'))}
        notices, diag = karabas_status.collect(get=lambda url, **kw: Response(url, 200, pages[url]))
        self.assertEqual(notices, [])
        self.assertTrue(diag['review'])


if __name__ == '__main__':
    unittest.main()
