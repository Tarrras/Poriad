"""Офіційні культурні стрічки з обмеженим обходом; неоднозначна проза йде на перевірку, а не в опівніч.

lviv.travel має заголовок, адресу й явні рядки сеансів. Інші джерела віддають неповні прозові
розклади: беремо лише самодостатні метадані Event, решту карток — на перевірку.
"""
from __future__ import annotations

import datetime as dt
import hashlib
import re
from html import unescape
from html.parser import HTMLParser
from urllib.parse import urljoin, urlsplit, urldefrag
from zoneinfo import ZoneInfo
from .extract import events_from_html

KYIV = ZoneInfo('Europe/Kyiv')
MONTHS = dict(zip(('січня лютого березня квітня травня червня липня серпня вересня жовтня листопада грудня').split(), range(1,13)))


def _text(html):
    return ' '.join(unescape(re.sub(r'<[^>]+>', ' ', html)).split())


def lviv_program(html, url, city):
    """Лише явні рядки з часом під заголовком події; рік має бути в назві сторінки."""
    title = re.search(r'<h1\b[^>]*>(.*?)</h1>', html, re.S | re.I)
    years = set(re.findall(r'\b20\d{2}\b', _text(title.group(1)))) if title else set()
    if len(years) != 1:
        return []
    year = int(next(iter(years)))
    events = []
    for block in re.finditer(r'<h4\b[^>]*>(.*?)</h4>(.*?)(?=<h[1-4]\b|\Z)', html, re.S | re.I):
        name = _text(block.group(1))
        if not name:
            continue
        rows = [_text(p) for p in re.findall(r'<p\b[^>]*>(.*?)</p>', block.group(2), re.S | re.I)]
        address = next((r for r in rows if re.match(r'^(?:вул\.|пл\.|просп\.|кут вул\.)', r)), None)
        if not address:
            continue
        for row in rows:
            m = re.fullmatch(r'(?:[^,]+,\s*)?(\d{1,2}) ('+'|'.join(MONTHS)+r'),?\s*(\d{1,2}):(\d{2})\s*[–—-]\s*(\d{1,2})[:.](\d{2})', row)
            if not m:
                continue
            day,month,hour,minute,end_hour,end_minute=m.groups()
            try:
                start=dt.datetime(year,MONTHS[month],int(day),int(hour),int(minute),tzinfo=KYIV)
                end=start.replace(hour=int(end_hour),minute=int(end_minute))
            except ValueError:
                continue
            if end <= start:
                continue
            token = hashlib.sha256(f'{name.casefold()}|{address.casefold()}'.encode()).hexdigest()[:16]
            event_url = urldefrag(url)[0] + '#poruch-program=' + token
            events.append({'@type':'Event','name':name,'url':event_url,
                           'startDate':start.isoformat(),'endDate':end.isoformat(),
                           'location':{'@type':'Place','name':address,'address':{
                               '@type':'PostalAddress','addressLocality':city,
                               'streetAddress':address,'addressCountry':'UA'}}})
    return events


def _links(html, url, slug):
    found = []
    class Links(HTMLParser):
        def handle_starttag(self,tag,attrs):
            if tag!='a': return
            target=urldefrag(urljoin(url,dict(attrs).get('href','')))[0]
            p=urlsplit(target)
            if p.scheme!='https' or p.netloc!=urlsplit(url).netloc or target==url:
                return
            if slug=='lviv-travel':
                accept=bool(re.match(r'^/ua/(news|events)/[^/]+/?$',p.path)) and not p.path.split('/')[-1].startswith('c-')
            elif slug=='artsvit':
                accept=bool(re.match(r'^/(news|projects|exhibitions)/.+',p.path))
            elif slug=='yermilovcentre':
                accept=bool(re.match(r'^/announcements/\d+/?$',p.path))
            else:
                accept=bool(re.match(r'^/race/[^/]+/?$',p.path)) and 'online' not in p.path
            if accept and target not in found: found.append(target)
    Links().feed(html)
    return found


def _structured(html, url, city):
    accepted=[]
    for original in events_from_html(html):
        e=dict(original)
        loc=e.get('location',{})
        address=loc.get('address',{}) if isinstance(loc,dict) else {}
        if not isinstance(address,dict) or address.get('addressLocality')!=city:
            continue
        if 'OnlineEventAttendanceMode' in str(e.get('eventAttendanceMode','')):
            continue
        valid=True
        for field in ('startDate','endDate'):
            value=e.get(field)
            if not value and field=='endDate': continue
            if not isinstance(value,str) or not re.match(r'^\d{4}-\d\d-\d\dT\d\d:\d\d',value):
                valid=False; break
            try:
                parsed=dt.datetime.fromisoformat(value.replace('Z','+00:00'))
                if parsed.tzinfo is None: parsed=parsed.replace(tzinfo=KYIV)
                e[field]=parsed.isoformat()
            except ValueError:
                valid=False; break
        if valid:
            e['url']=e.get('url') or url
            accepted.append(e)
    return accepted


def collect(slug, url, city, *, get, delay=2.0, max_details=40):
    """GET викликача з урахуванням robots. Один список, до max_details карток.

    Покриття часткове: головні й новинні сторінки не доводять повноти. Записи на перевірку —
    діагностика, не кандидати на публікацію.
    """
    slug={'lviv.travel':'lviv-travel','runukraine':'run-ukraine','yermilov':'yermilovcentre'}.get(slug,slug)
    if slug not in {'lviv-travel','artsvit','yermilovcentre','run-ukraine'}:
        raise ValueError('Unsupported culture source: '+slug)
    diag={'fetched':0,'errors':[],'coverage':'partial','stop_reason':'listing_scope',
          'discovered':0,'review':[]}
    def fetch(target):
        try:
            response=get(target,delay=delay)
            diag['fetched']+=1
            if response.status!=200 or not response.body:
                diag['errors'].append({'url':target,'error':response.error or f'HTTP {response.status}'})
                return None
            return response.body
        except Exception as exc:
            diag['errors'].append({'url':target,'error':str(exc)})
            return None
    html=fetch(url)
    if html is None:
        diag['coverage']='unknown'; diag['stop_reason']='listing_fetch_failed'
        return [],diag
    links=_links(html,url,slug)
    diag['discovered']=len(links)
    if len(links)>max(0,max_details): diag['stop_reason']='max_details'
    pages=[(url,html)]
    for link in links[:max(0,max_details)]:
        body=fetch(link)
        if body is not None: pages.append((link,body))
    events=[]
    for target,body in pages:
        extracted=_structured(body,target,city)
        if slug=='lviv-travel': extracted+=lviv_program(body,target,city)
        if not extracted and (target!=url or not links):
            diag['review'].append({'url':target,'reason':'no_verified_session'})
        events.extend(extracted)
    unique={}
    for e in events:
        unique[(e.get('name'),e['startDate'],e['url'])]=e
    if not unique:
        diag['errors'].append({'url':url,'error':'No verified timed sessions; inspect review evidence before enabling'})
    return list(unique.values()),diag
