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

    seen: set[str] = set()
    unique: list[dict] = []
    for e in found:
        key = str(e.get("url") or e.get("@id") or e.get("name") or "")
        if key and key in seen:
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
