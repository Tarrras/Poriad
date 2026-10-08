"""Витяг подій зі schema.org JSON-LD.

Драбина пріоритетів із docs/event-ingestion.md, розділ S2, починається саме тут: структуровані
дані завжди виграють у LLM-екстракції — вона і дорожча, і нестабільніша. Для перевірених джерел
рівня B четвертий щабель драбини не потрібен взагалі.

Головне вимірювання, на якому це тримається: сторінка-СПИСОК несе той самий JSON-LD, що й
сторінка події. Один запит до concert.ua/uk/kyiv — 118 подій, до kyiv.karabas.com — 149.
"""
from __future__ import annotations

import json
import re
from html.parser import HTMLParser
from urllib.parse import urljoin, urlsplit, urldefrag

_SCRIPT = re.compile(
    r'<script[^>]*type\s*=\s*["\']application/ld\+json["\'][^>]*>(.*?)</script>',
    re.S | re.I)

EVENT_TYPES = {
    "Event", "MusicEvent", "TheaterEvent", "ComedyEvent", "ScreeningEvent",
    "ExhibitionEvent", "LiteraryEvent", "ChildrensEvent", "SportsEvent",
    "DanceEvent", "FoodEvent", "EducationEvent", "SocialEvent", "Festival",
    "BusinessEvent", "VisualArtsEvent",
}


def _types(node: dict) -> set[str]:
    t = node.get("@type")
    if isinstance(t, str):
        return {t}
    if isinstance(t, list):
        return {x for x in t if isinstance(x, str)}
    return set()


def _walk(node, out: list[dict]) -> None:
    """JSON-LD трапляється вкладеним у @graph, itemListElement і просто в масиви."""
    if isinstance(node, dict):
        if _types(node) & EVENT_TYPES:
            out.append(node)
        for key in ("@graph", "itemListElement", "subEvent", "item"):
            if key in node:
                _walk(node[key], out)
    elif isinstance(node, list):
        for item in node:
            _walk(item, out)


def events_from_html(html: str) -> list[dict]:
    """Усі вузли *Event з усіх блоків ld+json сторінки, без дублікатів за url."""
    found: list[dict] = []
    for m in _SCRIPT.finditer(html):
        raw = m.group(1).strip()
        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            # Трапляються блоки з керуючими символами всередині рядків.
            try:
                data = json.loads(re.sub(r"[\x00-\x1f]", " ", raw))
            except json.JSONDecodeError:
                continue
        _walk(data, found)

    seen: set[tuple] = set()
    unique: list[dict] = []
    for e in found:
        key = (str(e.get("url") or e.get("@id") or e.get("name") or ""),
               str(e.get("startDate") or ""), str(e.get("eventStatus") or ""))
        if key in seen:
            continue
        seen.add(key)
        unique.append(e)
    return unique


def place_of(event: dict) -> dict:
    loc = event.get("location")
    if isinstance(loc, list):
        loc = next((x for x in loc if isinstance(x, dict)), {})
    return loc if isinstance(loc, dict) else {}


def offers_of(event: dict) -> list[dict]:
    off = event.get("offers")
    if isinstance(off, dict):
        return [off]
    if isinstance(off, list):
        return [o for o in off if isinstance(o, dict)]
    return []


def detail_links(html: str, listing_url: str, path_prefix: str) -> list[str]:
    """Шукає картки подій лише на хості налаштованого міста."""
    links: dict[str, None] = {}
    host = urlsplit(listing_url).netloc

    class Links(HTMLParser):
        def handle_starttag(self, tag, attrs):
            if tag != "a":
                return
            href = dict(attrs).get("href")
            if not href:
                return
            url = urldefrag(urljoin(listing_url, href))[0]
            parts = urlsplit(url)
            if parts.scheme == "https" and parts.netloc == host and parts.path.startswith(path_prefix):
                links[url] = None

    Links().feed(html)
    return list(links)


def section_links(html: str, heading: str, listing_url: str) -> list[str]:
    """Посилання з розділу сторінки за його заголовком (badseller: «Скасовано й перенесено»).
    Розділ — від заголовка до закриття `</section>`; немає заголовка — порожньо."""
    start = html.find(heading)
    if start < 0:
        return []
    end = html.find("</section>", start)
    hrefs = re.findall(r'<a\s[^>]*href="([^"]+)"', html[start:end if end > 0 else None])
    return list(dict.fromkeys(urldefrag(urljoin(listing_url, h))[0] for h in hrefs))


def sitemap_lastmods(xml: str) -> dict[str, str]:
    """URL -> `<lastmod>` зі sitemap. Записи без lastmod у словник не потрапляють."""
    return {m.group(1): m.group(2) for m in re.finditer(
        r"<loc>\s*([^<\s]+)\s*</loc>\s*<lastmod>\s*([^<\s]+)\s*</lastmod>", xml)}


# Дата в кінці slug; другий сеанс того ж дня має ще й час (`…-2026-10-23-1800`, буває `…-1900-2`):
# 161 таку картку badseller (2026-10-08) ми не брали зовсім.
_SLUG_DATE = re.compile(r"-(\d{4}-\d\d-\d\d)(?:-\d{4}(?:-\d+)?)?$")


def sitemap_links(xml: str, prefix: str, first, last) -> list[str]:
    """Картки з sitemap: URL починається з `prefix`, а датою в кінці slug — з `first` до `last`.
    Дата в slug старша за сеанс на застарілих посиланнях, тому минулі slug не беремо: сеанс має
    власне посилання."""
    links = []
    for loc in re.findall(r"<loc>\s*([^<\s]+)\s*</loc>", xml):
        m = _SLUG_DATE.search(loc)
        if m and loc.startswith(prefix) and "/" not in loc[len(prefix):] \
                and first.isoformat() <= m.group(1) <= last.isoformat():
            links.append(loc)
    return sorted(links, key=lambda u: _SLUG_DATE.search(u).group(1))


_CARD_TEXT = re.compile(r'class="descr-unified[^"]*"[^>]*>', re.I)
_CARD_END = re.compile(r"Придбати квиток на|Сервіс\s*(?:&quot;|\")?Інтернет", re.I)


def card_text(html: str) -> str:
    """Опис із тіла картки там, де JSON-LD його не віддає (Internet-Bilet: `descr-unified`).
    Порожній рядок, якщо контейнера нема: розмітка чужа, вгадувати нічого."""
    m = _CARD_TEXT.search(html)
    if not m:
        return ""
    body = html[m.end():]
    end = _CARD_END.search(body)
    body = body[:end.start()] if end else body[:6000]
    import html as _html
    return re.sub(r"\s+", " ", _html.unescape(re.sub(r"<[^>]+>", " ", body))).strip()
