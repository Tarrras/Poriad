#!/usr/bin/env python3
"""Перевірка зовнішніх джерел подій: robots.txt, structured data, покриття полів.

Запуск: python3 tools/probe_event_sources.py [--sample N]

Скрипт нічого не публікує — лише читає публічні сторінки й друкує зведення,
на якому будується docs/event-discovery.md. Числа в тому документі треба
перечитувати цим скриптом, а не довіряти знімку.
"""
import argparse, collections, json, random, re, subprocess, sys, time

UA = "Mozilla/5.0 (compatible; PoruchBot/0.1; +https://poruch.app/bot)"

LISTINGS = [
    ("concert.ua", "https://concert.ua/uk/kyiv"),
    ("karabas (kyiv)", "https://kyiv.karabas.com/"),
    ("moemisto.ua", "https://moemisto.ua/kiev"),
    ("guide.kyivcity.gov.ua", "https://guide.kyivcity.gov.ua/poster"),
]
SITEMAPS = [
    ("moemisto.ua (Kyiv)", "https://moemisto.ua/sitemap-event-kiev.xml"),
    ("concert.ua", "https://concert.ua/uk/sitemap/eventpages.xml"),
]


def get(url, timeout=40):
    r = subprocess.run(["curl", "-sS", "-m", str(timeout), "-A", UA, "-L", url],
                       capture_output=True, text=True)
    return r.stdout


def events_in(html):
    """Усі JSON-LD вузли типу *Event на сторінці."""
    found = []
    for m in re.finditer(r'<script[^>]*application/ld\+json[^>]*>(.*?)</script>', html, re.S):
        try:
            data = json.loads(m.group(1))
        except Exception:
            continue
        for node in (data if isinstance(data, list) else [data]):
            if isinstance(node, dict) and "Event" in str(node.get("@type", "")):
                found.append(node)
    return found


def place_of(event):
    loc = event.get("location") or {}
    return loc[0] if isinstance(loc, list) and loc else (loc if isinstance(loc, dict) else {})


def probe_listings():
    print("\n" + "=" * 72)
    print("СТОРІНКИ-СПИСКИ: скільки подій дає ОДИН запит")
    print("=" * 72)
    for name, url in LISTINGS:
        evs = events_in(get(url))
        venues = collections.Counter(place_of(e).get("name", "?") for e in evs)
        geo = sum(1 for e in evs if place_of(e).get("geo"))
        types = collections.Counter(str(e.get("@type")) for e in evs)
        ratio = f"{len(evs)/len(venues):.1f}" if venues else "—"
        print(f"\n{name}  <{url}>")
        print(f"  подій за 1 запит : {len(evs)}")
        print(f"  унікальних місць : {len(venues)}  (подій на місце: {ratio})")
        print(f"  з координатами   : {geo}/{len(evs)}")
        if types:
            print(f"  типи             : {dict(types.most_common(6))}")
        time.sleep(1)


def probe_fields(sample):
    print("\n" + "=" * 72)
    print("ПОКРИТТЯ ПОЛІВ на сторінках окремих подій")
    print("=" * 72)
    for name, sm in SITEMAPS:
        urls = re.findall(r"<loc>([^<]+)</loc>", get(sm, 60))
        random.seed(7)
        random.shuffle(urls)
        stat = collections.Counter()
        offsets = collections.Counter()
        total = 0
        for url in urls[:sample]:
            evs = events_in(get(url))
            if not evs:
                continue
            e = evs[0]
            total += 1
            place = place_of(e)
            stat["geo"] += bool(place.get("geo"))
            stat["endDate"] += bool(e.get("endDate"))
            stat["image"] += bool(e.get("image"))
            stat["offers"] += bool(e.get("offers"))
            stat["address"] += bool(place.get("address"))
            m = re.search(r"([+-]\d{2}:?\d{2}|Z)$", str(e.get("startDate", "")))
            offsets[m.group(1) if m else "none"] += 1
            time.sleep(1)
        print(f"\n{name}  (вибірка {total} сторінок)")
        for key in ("geo", "endDate", "image", "offers", "address"):
            pct = 100 * stat[key] / total if total else 0
            print(f"  {key:9} {stat[key]:3}/{total}  {pct:5.1f}%")
        print(f"  зсуви startDate: {dict(offsets)}")


def probe_sitemap_freshness():
    print("\n" + "=" * 72)
    print("СВІЖІСТЬ SITEMAP (архів чи жива пропозиція)")
    print("=" * 72)
    for name, sm in SITEMAPS:
        years = collections.Counter(
            v[:4] for v in re.findall(r"<lastmod>([0-9-]+)", get(sm, 60)))
        if not years:
            print(f"\n{name}: без <lastmod>")
            continue
        total = sum(years.values())
        recent = sum(c for y, c in years.items() if y >= "2026")
        print(f"\n{name}: {total} URL, з них lastmod ≥ 2026 — {recent} ({100*recent/total:.0f}%)")
        print("  ", dict(sorted(years.items())))


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--sample", type=int, default=12,
                    help="скільки сторінок подій перевіряти на джерело")
    args = ap.parse_args()
    probe_listings()
    probe_sitemap_freshness()
    probe_fields(args.sample)
    print("\nГотово. Джерела змінюють розмітку — перезапускайте перед рішеннями.\n")
