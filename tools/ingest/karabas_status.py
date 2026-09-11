"""Read Karabas' explicit status table, with bounded, non-authoritative coverage.

Dates here are visible Kyiv wall times, NOT Karabas JSON-LD's utc_is_local.
Only exact URL/session notices are returned. Absence never means cancellation.
"""
from __future__ import annotations

import datetime as dt
from html.parser import HTMLParser
import re
from urllib.parse import parse_qs, urljoin, urlsplit, urlunsplit

from .normalize import zone

CITIES = frozenset({'Київ', 'Дніпро', 'Харків', 'Львів', 'Одеса'})
STATUSES = {'Скасовано': 'EventCancelled', 'Перенесено': 'EventRescheduled',
            'Перенесено з відкритою датою': 'EventPostponed'}


class _Node:
    def __init__(self, tag='', attrs=()):
        self.tag, self.attrs, self.children = tag, dict(attrs), []

    def has(self, cls):
        return cls in self.attrs.get('class', '').split()

    def text(self):
        return ' '.join(' '.join(c.text() if isinstance(c, _Node) else c
                                 for c in self.children).split())

    def nodes(self):
        for child in self.children:
            if isinstance(child, _Node):
                yield child
                yield from child.nodes()


class _Document(HTMLParser):
    def __init__(self, html):
        super().__init__(convert_charrefs=True)
        self.root = _Node()
        self.stack = [self.root]
        self.feed(html)

    def handle_starttag(self, tag, attrs):
        node = _Node(tag, attrs)
        self.stack[-1].children.append(node)
        if tag not in {'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input',
                       'link', 'meta', 'param', 'source', 'track', 'wbr'}:
            self.stack.append(node)

    def handle_endtag(self, tag):
        for i in range(len(self.stack) - 1, 0, -1):
            if self.stack[i].tag == tag:
                del self.stack[i:]
                break

    def handle_data(self, data):
        self.stack[-1].children.append(data)


def _date(value):
    if value in {'', '-'}:
        return None
    if not re.fullmatch(r'\d{4}-\d{2}-\d{2} \d{2}:\d{2}', value):
        raise ValueError('missing exact date/time')
    parsed = dt.datetime.strptime(value, '%Y-%m-%d %H:%M').replace(tzinfo=zone('Europe/Kyiv'))
    if parsed.utcoffset() != parsed.replace(fold=1).utcoffset():
        raise ValueError('ambiguous or nonexistent Kyiv wall time')
    return parsed.isoformat()


def _event_url(value, base):
    url = urljoin(base, value)
    parts = urlsplit(url)
    if (parts.scheme not in {'http', 'https'} or not parts.hostname or
            not (parts.hostname == 'karabas.com' or parts.hostname.endswith('.karabas.com')) or
            parts.username or parts.password or parts.path in {'', '/', '/info/'}):
        raise ValueError('invalid event URL')
    return urlunsplit((parts.scheme, parts.netloc, parts.path, parts.query, ''))


def _fields(row, mobile):
    nodes = list(row.nodes())
    links = [n.attrs['href'] for n in nodes if n.tag == 'a' and n.attrs.get('href', '').startswith(('http', '/'))]
    badges = [n.text() for n in nodes if n.has('badge')]
    city, old, new = '', '', ''
    if mobile:
        for n in nodes:
            if n.has('t-value'):
                text = n.text()
                for label, field in [('Місто:', 'city'), ('Попередня дата:', 'old'), ('Поточна/Нова дата:', 'new')]:
                    if text.startswith(label):
                        value = text[len(label):].strip()
                        if field == 'city': city = value
                        elif field == 'old': old = value
                        else: new = value
    else:
        cells = [n for n in row.children if isinstance(n, _Node) and n.tag == 'td']
        if len(cells) != 4:
            raise ValueError('unexpected status column count')
        city_nodes = [n for n in cells[0].nodes() if n.tag == 'span' and n.text().startswith('Місто:')]
        city = city_nodes[0].text()[len('Місто:'):].strip() if city_nodes else ''
        old, new = cells[2].text(), cells[3].text()
    if len(links) != 1 or len(badges) != 1 or not city:
        raise ValueError('missing unique event URL, city or status')
    return links[0], city, badges[0], old, new


def _notice(fields, evidence_url):
    url, city, status_text, old, new = fields
    status = STATUSES.get(status_text)
    if not status:
        raise ValueError('unknown status')
    old_date, current_date = _date(old), _date(new)
    affected = old_date if status == 'EventRescheduled' else current_date or old_date
    if not affected or (status == 'EventRescheduled' and (not current_date or current_date == affected)):
        raise ValueError('missing distinct exact affected/new session')
    notice = dict(canonical_url=_event_url(url, evidence_url), city=city, status=status,
                  starts_at=affected, evidence_url=evidence_url)
    if status == 'EventRescheduled':
        notice['new_start'] = current_date
    return notice


def collect(url='https://karabas.com/info/', *, get, delay=1.0, max_pages=3):
    """Return (notices, diagnostics); get is the production robots-aware fetch.

    diagnostics.coverage is partial at pagination limits/errors, unknown for an
    unrecognized page, complete only when the observed pagination is exhausted.
    review contains malformed/conflicting records; those URLs are withheld.
    """
    diag = dict(coverage='unknown', stop_reason='max_pages', pages_fetched=0,
                visited_urls=[], errors=[], review=[], duplicates=0, rows_seen=0)
    pending, visited, notices, blocked = [url], set(), {}, set()
    while pending and len(visited) < max_pages:
        page_url = pending.pop(0)
        if page_url in visited:
            continue
        visited.add(page_url)
        diag['visited_urls'].append(page_url)
        try:
            response = get(page_url, delay=delay)
            if response.status != 200 or not response.body:
                raise ValueError(f'HTTP {response.status}: {getattr(response, "error", None) or "empty response"}')
        except Exception as exc:
            diag['errors'].append(dict(url=page_url, error=str(exc)))
            diag['stop_reason'] = 'fetch_error'
            break
        diag['pages_fetched'] += 1
        document = _Document(response.body)
        nodes = list(document.root.nodes())
        tables = [n for n in nodes if n.has('infoTable')]
        mobile_tables = [n for n in nodes if n.has('mobile-table')]
        if not tables and not mobile_tables:
            diag['errors'].append(dict(url=page_url, error='unrecognized status layout'))
            diag['stop_reason'] = 'unrecognized_layout'
            break
        groups = {}
        for containers, mobile in [(tables, False), (mobile_tables, True)]:
            rows = [n for container in containers for n in container.nodes()
                    if (n.has('t-row') if mobile else n.tag == 'tr' and any(c.tag == 'td' for c in n.children if isinstance(c, _Node)))]
            for row in rows:
                diag['rows_seen'] += 1
                key = None
                try:
                    fields = _fields(row, mobile)
                    key = _event_url(fields[0], page_url)
                    groups.setdefault(key, {}).setdefault(mobile, []).append(fields[1:])
                    notice = _notice(fields, page_url)
                    if notice['city'] not in CITIES:
                        continue
                    identity = (key, notice['starts_at'])
                    previous = notices.get(identity)
                    if previous:
                        if any(previous.get(k) != notice.get(k) for k in ['city', 'status', 'new_start']):
                            blocked.add(key)
                            diag['review'].append(dict(url=key, reason='conflicting session status/date', evidence_url=page_url))
                        else:
                            diag['duplicates'] += 1
                    else:
                        notices[identity] = notice
                except ValueError as exc:
                    if key:
                        blocked.add(key)
                    diag['review'].append(dict(url=key or page_url, reason=str(exc), evidence_url=page_url))
        for key, copies in groups.items():
            if False in copies and True in copies and set(copies[False]) != set(copies[True]):
                blocked.add(key)
                diag['review'].append(dict(url=key, reason='desktop/mobile conflict', evidence_url=page_url))
        current_page = int(parse_qs(urlsplit(page_url).query).get('page', ['1'])[0])
        page_links = []
        for container in [n for n in nodes if n.has('pagination')]:
            for link in container.nodes():
                if link.tag != 'a' or not link.attrs.get('href'):
                    continue
                candidate = urljoin(page_url, link.attrs['href'])
                parts = urlsplit(candidate)
                original = urlsplit(url)
                page_number = parse_qs(parts.query).get('page', [''])[0]
                if (parts.scheme == original.scheme and parts.netloc == original.netloc and
                        parts.path == original.path and page_number.isdigit() and int(page_number) > current_page):
                    page_links.append((int(page_number), candidate))
        if page_links:
            # Follow the next numbered page, never jump directly to the last page.
            next_number, next_url = min(page_links)
            if next_number != current_page + 1:
                diag['errors'].append(dict(url=page_url, error='pagination gap'))
                diag['stop_reason'] = 'pagination_gap'
                break
            if next_url not in visited and next_url not in pending:
                pending.append(next_url)
        if not pending:
            diag['coverage'], diag['stop_reason'] = 'complete', 'pagination_exhausted'
    if diag['coverage'] != 'complete':
        diag['coverage'] = 'partial' if diag['pages_fetched'] else 'unknown'
    if diag['review'] and diag['coverage'] == 'complete':
        diag['coverage'] = 'partial'
        diag['stop_reason'] = 'records_need_review'
    return [n for (key, _), n in notices.items() if key not in blocked], diag
