"""Адаптери для спільнотних календарів, яким потрібне доповнення зі сторінки події."""
from __future__ import annotations

import datetime as dt
import re
from html.parser import HTMLParser
from urllib.parse import urljoin, urlsplit, urldefrag
from zoneinfo import ZoneInfo

from .extract import events_from_html

_DOU_CARD = re.compile(r"^/calendar/\d+/$")
_YOY_RESERVED = {"signin", "events", "communities", "privacy", "terms", "tickets", "me"}


class _Links(HTMLParser):
    def __init__(self, base: str):
        super().__init__()
        self.base = base
        self.links: list[str] = []

    def handle_starttag(self, tag, attrs):
        if tag != "a":
            return
        href = dict(attrs).get("href")
        if href:
            self.links.append(urldefrag(urljoin(self.base, href))[0])


def _links(html: str, base: str) -> list[str]:
    parser = _Links(base)
    parser.feed(html)
    return list(dict.fromkeys(parser.links))


def _dou_cards(html: str, base: str) -> list[str]:
    """Читає сам список календаря без реклами в сайдбарі й коментарів."""
    cards: list[str] = []
    class Cards(HTMLParser):
        def __init__(self):
            super().__init__()
            self.in_card = False
        def handle_starttag(self, tag, attrs):
            values = dict(attrs)
            if tag == "article" and "b-postcard" in values.get("class", "").split():
                self.in_card = True
            if tag == "a" and self.in_card and values.get("href"):
                url = urljoin(base, values["href"])
                parts = urlsplit(url)
                if parts.netloc == "dou.ua" and _DOU_CARD.match(parts.path):
                    canonical = f"https://dou.ua{parts.path}"
                    if canonical not in cards:
                        cards.append(canonical)
        def handle_endtag(self, tag):
            if tag == "article":
                self.in_card = False
    Cards().feed(html)
    return cards


def _unfold_ical(value: str) -> list[str]:
    unfolded: list[str] = []
    for line in value.replace("\r\n", "\n").split("\n"):
        if line.startswith((" ", "\t")) and unfolded:
            unfolded[-1] += line[1:]
        else:
            unfolded.append(line)
    return unfolded


def _ical_datetime(line: str, default_tz: str) -> str | None:
    head, sep, raw = line.partition(":")
    if not sep or "VALUE=DATE" in head or len(raw.rstrip("Z")) != 15 or raw[8] != "T":
        return None
    tzid = default_tz
    match = re.search(r"(?:^|;)TZID=([^;:]+)", head)
    if match:
        tzid = match.group(1)
    if not raw.endswith("Z") and tzid not in {"Europe/Kiev", "Europe/Kyiv"}:
        return None
    try:
        parsed = dt.datetime.strptime(raw.rstrip("Z"), "%Y%m%dT%H%M%S")
        if raw.endswith("Z"):
            parsed = parsed.replace(tzinfo=dt.timezone.utc)
        else:
            parsed = parsed.replace(tzinfo=ZoneInfo(tzid))
    except (ValueError, KeyError):
        return None
    return parsed.isoformat()


def ical_dates(value: str, event_url: str) -> dict | None:
    """Повертає безпечні DTSTART/DTEND для VEVENT, що відповідає ``event_url``."""
    lines = _unfold_ical(value)
    default_tz = next((x.split(":", 1)[1] for x in lines if x.startswith("TZID:")), "")
    if default_tz not in {"Europe/Kiev", "Europe/Kyiv"}:
        return None
    blocks: list[list[str]] = []
    current: list[str] | None = None
    for line in lines:
        if line == "BEGIN:VEVENT":
            current = []
        elif line == "END:VEVENT" and current is not None:
            blocks.append(current)
            current = None
        elif current is not None:
            current.append(line)
    canonical = urldefrag(event_url)[0]
    for block in blocks:
        if any(line.startswith(("RRULE:", "RECURRENCE-ID")) for line in block):
            continue
        url = next((line.split(":", 1)[1] for line in block if line.startswith("URL:")), "")
        if urldefrag(url)[0] != canonical:
            continue
        start_line = next((line for line in block if line.startswith("DTSTART")), "")
        start = _ical_datetime(start_line, default_tz)
        if not start:
            continue
        result = {"startDate": start}
        end_line = next((line for line in block if line.startswith("DTEND")), "")
        end = _ical_datetime(end_line, default_tz) if end_line else None
        if end:
            result["endDate"] = end
        return result
    return None


def _event_city(event: dict) -> str:
    place = event.get("location")
    if not isinstance(place, dict):
        return ""
    address = place.get("address")
    if isinstance(address, dict):
        return str(address.get("addressLocality") or "")
    return str(address or "")


def _same_city(event: dict, city: str) -> bool:
    actual = _event_city(event).casefold()
    wanted = city.casefold()
    aliases = {
        "київ": {"київ", "киев", "kyiv", "kiev"},
        "львів": {"львів", "львов", "lviv"},
        "харків": {"харків", "харьков", "kharkiv", "kharkov"},
        "одеса": {"одеса", "одесса", "odesa", "odessa"},
        "дніпро": {"дніпро", "днепр", "dnipro", "dnepr"},
    }
    accepted = aliases.get(wanted, {wanted})
    return any(name in actual for name in accepted)


def _same_start(left: str, right: str) -> bool:
    try:
        a = dt.datetime.fromisoformat(left.replace("Z", "+00:00"))
        b = dt.datetime.fromisoformat(right.replace("Z", "+00:00"))
    except (AttributeError, ValueError):
        return False
    return a.tzinfo is not None and b.tzinfo is not None and a == b


def _normalize_yoy_location(event: dict, city: str) -> None:
    place = event.get("location")
    if not isinstance(place, dict) or not isinstance(place.get("address"), str):
        return
    name = str(place.get("name") or "")
    match = re.search(r"((?:вулиця|вул\.)\s+[^,]+,\s*\d+[\w/-]*)", name, re.I)
    place["address"] = {"@type": "PostalAddress", "addressLocality": city,
                        "streetAddress": match.group(1) if match else ""}


def collect(slug: str, listing_url: str, city: str, *, get, delay: float = 2.0,
            max_details: int = 60) -> tuple[list[dict], dict]:
    """Збирає безпечні події у формі schema.org зі списків DOU або yoy!."""
    report = {"fetched": 0, "detail_links": 0, "detail_errors": [], "review": [],
              "coverage": "listing"}
    response = get(listing_url, delay=delay)
    if response.status != 200 or not response.body:
        report["error"] = f"HTTP {response.status}"
        return [], report
    report["fetched"] = 1
    discovered = _links(response.body, listing_url)
    if slug == "dou":
        cards = _dou_cards(response.body, listing_url)
    elif slug == "yoy":
        cards = []
        host = urlsplit(listing_url).netloc
        for url in discovered:
            parts = [p for p in urlsplit(url).path.split("/") if p]
            if urlsplit(url).netloc == host and len(parts) == 2 and parts[0] not in _YOY_RESERVED:
                cards.append(url)
    else:
        raise ValueError(f"unsupported community source: {slug}")
    cards = list(dict.fromkeys(cards))
    report["detail_links"] = len(cards)
    if not cards:
        if slug == "dou" and "Подій не знайдено" in response.body:
            report["valid_empty"] = True
            return [], report
        report["error"] = "NO_DETAIL_LINKS"
        return [], report
    if len(cards) > max_details:
        report["detail_errors"].append("DETAIL_LIMIT")
        report["coverage"] = "partial"
    result: list[dict] = []
    for card_url in cards[:max_details]:
        detail = get(card_url, delay=delay)
        if detail.status != 200 or not detail.body:
            report["detail_errors"].append(f"{card_url}: HTTP {detail.status}")
            continue
        report["fetched"] += 1
        events = events_from_html(detail.body)
        if not events:
            report["detail_errors"].append(f"{card_url}: NO_EVENTS")
            continue
        for event in events:
            if not _same_city(event, city):
                continue
            if slug == "yoy":
                _normalize_yoy_location(event, city)
            raw_start = str(event.get("startDate") or "")
            placeholder_midnight = bool(re.search(r"T00:00(?::00)?(?:Z|[+-]\d\d:?\d\d)?$", raw_start))
            if slug == "dou" and (re.fullmatch(r"\d{4}-\d{2}-\d{2}", raw_start) or placeholder_midnight):
                calendar_url = card_url.rstrip("/") + "/calendar.ics"
                try:
                    calendar = get(calendar_url, delay=delay)
                except (KeyError, PermissionError, OSError):
                    calendar = None
                report["fetched"] += int(calendar is not None and calendar.status == 200)
                dates = (ical_dates(calendar.body, card_url)
                         if calendar is not None and calendar.status == 200 else None)
                if not dates:
                    report["review"].append({"url": card_url, "reason": "UNKNOWN_TIME"})
                    continue
                event.update(dates)
                if re.search(r"T00:00(?::00)?(?:Z|[+-]\d\d:?\d\d)?$", event["startDate"]):
                    report["review"].append({"url": card_url, "reason": "UNKNOWN_TIME"})
                    continue
                related: list[str] = []
                for link in _links(detail.body, card_url):
                    if urlsplit(link).netloc == "yoy.events":
                        enrichment = get(link, delay=delay)
                        if enrichment.status != 200:
                            continue
                        candidates = events_from_html(enrichment.body)
                        matching = next((item for item in candidates
                                         if _same_city(item, city)
                                         and _same_start(str(event.get("startDate") or ""),
                                                         str(item.get("startDate") or ""))), None)
                        if matching:
                            if matching.get("endDate"):
                                event["endDate"] = matching["endDate"]
                            if matching.get("image") and not event.get("image"):
                                event["image"] = matching["image"]
                            if matching.get("offers") and not event.get("offers"):
                                event["offers"] = matching["offers"]
                            related.append(link)
                            report["fetched"] += 1
                            break
                if related:
                    event["_related_urls"] = related
            result.append(event)
    if report["detail_errors"] and report["coverage"] != "partial":
        report["error"] = "PARTIAL_DETAILS"
    if not result and "error" not in report:
        report["error"] = "NO_LOCAL_EVENTS: populated listing yielded no safe city events"
    return result, report
