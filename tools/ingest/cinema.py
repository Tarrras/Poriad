"""Розклад кінотеатрів (docs/cinema-import.md): Planeta Kino. Multiplex 30.10.2026 не погодив показ свого розкладу —
його адаптера тут нема й не буде без письмової згоди мережі.

Мережа не віддає сеансів у JSON-LD, тож розклад читається з HTML: сторінка кінотеатру на день. З кожного сеансу адаптер складає вузол `ScreeningEvent`,
і далі він іде тим самим шляхом, що JSON-LD інших джерел (`pipeline._build`). Тривалість і опис — зі сторінки
фільму (`Movie` JSON-LD), один запит на фільм за обхід. Постер не беремо: це твір дистриб'ютора, а письмового
дозволу мереж ще нема (docs/cinema-import.md, «Право»), тож сеанс малює обкладинка категорії.

Координати кінотеатрів — лише з aliases.json (`_кіно`): назви мереж в OSM збігаються за входженням не з тим залом, а
координати самих мереж трапляються хибні. Кінотеатр без псевдоніма отримує
точку Photon за адресою з будинком або йде в чергу перегляду, але не стає на збіг назви мережі в OSM (`pipeline._build`).
"""
from __future__ import annotations

import datetime as dt
import json
import re
from html import unescape

from .normalize import zone

CATEGORY = "cinema"
# Комендантська з 00:00 до 05:00: сеанс «00:30» на сторінці дня — або наступна доба, або помилка верстки. Не вгадуємо.
EARLIEST_HOUR = 5

_ATTR = re.compile(r'([\w-]+)=(?:"([^"]*)"|\'([^\']*)\')')


def _attrs(tag: str) -> dict:
    return {m.group(1): m.group(2) if m.group(2) is not None else m.group(3) for m in _ATTR.finditer(tag)}


def _days(now: dt.datetime, horizon_days: int, tz: str) -> list[dt.date]:
    today = now.astimezone(zone(tz)).date()
    return [today + dt.timedelta(days=i) for i in range(horizon_days + 1)]


def _session(title, url, start, venue, address, city, about) -> dict:
    """Сеанс як вузол schema.org. `about` — вік і формат сеансу (LUX, SDH): у базі для них поля нема, тож вони
    починають опис. Тривалість і опис фільму дописує `collect` зі сторінки фільму."""
    about = ", ".join(x for x in about if x)
    return {
        "@type": "ScreeningEvent", "name": title, "url": url, "startDate": start.isoformat(),
        "location": {"@type": "MovieTheater", "name": venue,
                     "address": {"@type": "PostalAddress", "streetAddress": address,
                                 "addressLocality": city, "addressCountry": "UA"}},
        "description": f"{about}." if about else "",
        "_poruch_category": CATEGORY,
    }


# ---- Planeta Kino: сторінка кінотеатру на день, час звіряється з даними сторінки

_PK_TITLE = re.compile(r'<a href="/movie/([^/"]+)/?">\s*([^<]*?)\s*</a>')
_PK_SESSION = re.compile(r'id="([A-Za-z0-9+/=]+)-session-slide-item".*?<span>\s*(\d{1,2}):(\d\d)\s*</span>', re.S)
_PK_STATE = re.compile(r'startSessionAt:"([0-9T:.\-]+Z)",id:"([A-Za-z0-9+/=]+)"')
_PK_AGE = re.compile(r'>\s*(\d{1,2}\+)\s*</div>')


def planeta_sessions(html: str, city: str, venue: str, address: str, cinema: str, day: dt.date,
                     tz: str = "Europe/Kyiv") -> list[dict]:
    """Сеанси сторінки `?cinema=…&date=…`. ValueError — сторінка показує не той день: час сеансу в DOM розходиться з
    `startSessionAt` у стані сторінки (там, де він записаний літералом)."""
    body = html.split("window.__NUXT__", 1)[0]
    state = {sid: dt.datetime.fromisoformat(at.replace("Z", "+00:00")) for at, sid in _PK_STATE.findall(html)}
    titles = list(_PK_TITLE.finditer(body))
    out, seen = [], set()
    for m in _PK_SESSION.finditer(body):
        sid, hour, minute = m.group(1), int(m.group(2)), int(m.group(3))
        film = next((t for t in reversed(titles) if t.start() < m.start()), None)
        if film is None or sid in seen:
            continue
        seen.add(sid)
        if hour < EARLIEST_HOUR:
            continue
        start = dt.datetime(day.year, day.month, day.day, hour, minute, tzinfo=zone(tz))
        if sid in state and state[sid] != start:
            raise ValueError(f"PAGE_DAY_MISMATCH {sid}: {state[sid].isoformat()} ≠ {start.isoformat()}")
        age = _PK_AGE.findall(body[max(0, film.start() - 3000):film.start()])
        slug = film.group(1)
        event = _session(" ".join(unescape(film.group(2)).split()),
                         f"https://planetakino.ua/movie/{slug}/?cinema={cinema}", start, venue, address, city,
                         [age[-1] if age else None])
        event["_movie"] = f"https://planetakino.ua/movie/{slug}/"
        out.append(event)
    return out


def planeta_movie(html: str) -> dict:
    """`Movie` JSON-LD: тривалість ISO 8601 і опис; назва — з <title>, бо в JSON-LD і на сторінці дня вона капсом."""
    out = {}
    for node in (n for n in _ld(html) if n.get("@type") == "Movie"):
        if d := re.fullmatch(r"PT(?:(\d+)H)?(?:(\d+)M)?", str(node.get("duration") or "")):
            if any(d.groups()):
                out["duration"] = dt.timedelta(hours=int(d.group(1) or 0), minutes=int(d.group(2) or 0))
        out["description"] = " ".join(str(node.get("description") or "").split())
    if t := re.search(r"<title>([^<]*?)\s*(?:\(\d{4}\))?\s*—", html):
        out["title"] = " ".join(unescape(t.group(1)).split())
    return out


def planeta_cinemas(html: str) -> dict[str, str]:
    """Назва кінотеатру -> вулична адреса з `MovieTheater.department` сторінки /cinemas/."""
    return {d.get("name"): (d.get("address") or {}).get("streetAddress", "")
            for n in _ld(html) for d in (n.get("department") or []) if isinstance(d, dict)}


def _ld(html: str) -> list[dict]:
    out = []
    for raw in re.findall(r'<script[^>]*ld\+json[^>]*>(.*?)</script>', html, re.S):
        try:
            data = json.loads(raw)
        except ValueError:
            continue
        out.extend(x for x in (data if isinstance(data, list) else [data]) if isinstance(x, dict))
    return out


# ---- Обхід

def collect(chain: str, source, city: str, *, get, now: dt.datetime) -> tuple[list[dict], dict]:
    """Усі кінотеатри міста з `source.venues[city]` на дні від сьогодні до `horizon_days`. Повний, якщо `errors`
    порожній: тоді відсутній сеанс справді зник із розкладу (`__main__._may_retire`)."""
    report = {"fetched": 0, "errors": [], "venues": 0, "sessions": 0, "movies": 0, "empty_days": 0}
    venues = (source.venues or {}).get(city) or {}
    days = _days(now, source.horizon_days, source.time_zone)

    def fetch(url, *, landed=None):
        try:
            response = get(url, delay=source.crawl_delay)
            if response.status != 200 or not response.body:
                raise ValueError(response.error or f"HTTP {response.status}")
            report["fetched"] += 1
            if landed and landed not in (response.final_url or url):
                return ""                      # переадресовано деінде: тут нічого нема, і це не збій
            return response.body
        except (PermissionError, OSError, ValueError) as exc:
            report["errors"].append(f"{url}: {exc}")
            return None

    events: list[dict] = []
    if chain == "planeta":
        addresses = planeta_cinemas(fetch(f"{source.base_url}/cinemas/") or "")
        for slug, venue in venues.items():
            # День без сеансів Planeta переадресовує на сьогодні (302 → `date=<сьогодні>`, Dream Yellow 03.11.2026):
            # прочитаний як свій, він поставив би сьогоднішні сеанси на інший день.
            pages = [(day, fetch(f"{source.listing_urls[city]}?cinema={slug}&date={day.isoformat()}",
                                 landed=f"date={day.isoformat()}")) for day in days]
            for day, body in pages:
                if not body:
                    report["empty_days"] += body == ""
                    continue
                try:
                    events += planeta_sessions(body, city, venue, addresses.get(venue, ""), slug, day, source.time_zone)
                except ValueError as exc:
                    report["errors"].append(f"{slug} {day}: {exc}")
            report["venues"] += any(body is not None for _, body in pages)
        read_movie = planeta_movie
    else:
        raise ValueError(f"невідома мережа: {chain}")

    movies = {}
    for url in dict.fromkeys(e["_movie"] for e in events if e.get("_movie")):
        body = fetch(url)
        movies[url] = read_movie(body) if body else {}
    report["movies"] = len(movies)
    for event in events:
        movie = movies.get(event.pop("_movie", None)) or {}
        event["name"] = movie.get("title") or event["name"]
        if movie.get("duration"):
            event["endDate"] = (dt.datetime.fromisoformat(event["startDate"]) + movie["duration"]).isoformat()
        if movie.get("description"):
            event["description"] = " ".join(x for x in (event["description"], movie["description"]) if x)
    report["sessions"] = len(events)
    if not events and not report["errors"]:
        report["errors"].append("NO_SESSIONS: розклад порожній або змінилась розмітка")
    return events, report
