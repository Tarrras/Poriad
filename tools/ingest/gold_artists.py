"""Золотий набір артистів без ручної розмітки.

Розмітка тримається на трьох незалежних голосах, а людині лишаються лише розбіжності:
  A. модель, якій дано ПОВНИЙ текст сторінки події (екстрактор бачить лише назву й опис);
  B. друга розмітка того ж тексту іншою моделлю (`label-extra`, пише Claude у файл);
  C. структурований `performer` самого джерела (щабель 1).
Золото — набір, за який проголосували щонайменше двоє. Кожне ім'я моделі А мусить мати
дослівну цитату в тексті сторінки: інакше його відкинуто.

    python3 -m tools.ingest.gold_artists corpus      # обхід Києва -> cache/artists_corpus.json
    python3 -m tools.ingest.gold_artists sample      # стратифікована вибірка
    python3 -m tools.ingest.gold_artists snapshot    # повні сторінки -> cache/gold_snapshots/
    python3 -m tools.ingest.gold_artists label       # розмітка A (OpenAI)
    python3 -m tools.ingest.gold_artists merge       # золото + черга для людини

Проміжні файли лежать у cache/ (не в git); підсумок `gold_artists.json` — у git.
"""
from __future__ import annotations

import argparse
import collections
import concurrent.futures
import dataclasses
import datetime as dt
import html as htmllib
import json
import pathlib
import random
import re
import sys

from . import artists as art
from .agent import Agent
from .artist_prompt import RULES
from .extract import events_from_html
from .fetch import get
from .normalize import clean_text
from .pipeline import harvest
from .sources import by_slug
from .venues import VenueIndex

HERE = pathlib.Path(__file__).resolve().parent
CACHE = HERE / "cache"
CORPUS, SAMPLE = CACHE / "artists_corpus.json", CACHE / "gold_sample.json"
SNAPSHOTS, LABELS_A = CACHE / "gold_snapshots", CACHE / "gold_labels_openai.json"
LABELS_B = CACHE / "gold_labels_claude.json"
GOLD = HERE / "gold_artists.json"

SOURCES = (("karabas", 0), ("internet_bilet", 0), ("concert_ua", 0), ("ticketsbox", 40), ("badseller", 150))
# Скільки подій узяти по категорії. Артистів не мають конференції й екскурсії, але «жодного»
# теж відповідь, яку треба міряти.
QUOTA = {"music": 45, "comedy": 30, "art": 40, "kids": 12, "other": 15}
# Складні випадки беремо навмисно: трибʼюти, «при свічках», бренди стендапу. Позначаємо `hard`,
# щоб випадкову частину міряти окремо.
HARD = re.compile(r"(?i)триб.?ют|tribute|при свічках|стендап|stand.?up|гурт|шоу")
TEXT_LIMIT = 7000


def _read(path: pathlib.Path):
    return json.loads(path.read_text("utf-8"))


def _write(path: pathlib.Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=1), "utf-8")


# ---- 1. Корпус

def build_corpus() -> list[dict]:
    now = dt.datetime.now(dt.timezone.utc)
    dictionary = art.Dictionary.load()
    items = []
    for slug, limit in SOURCES:
        source = by_slug(slug)
        if limit:
            source = dataclasses.replace(source, max_details=limit)
        got, counters = harvest(source, "Київ", VenueIndex([], "Київ"), now=now)
        print(f"{slug}: {len(got)} подій, помилка: {counters.get('error')}", flush=True)
        items += got
    art.settle(items, dictionary)
    rows = [{"source": i.source_slug, "title": i.title, "category": i.category, "venue": i.venue_name,
             "url": i.canonical_url, "starts": i.starts_at.isoformat(), "text": i.text,
             "artists": [dataclasses.asdict(a) for a in i.artists]} for i in items]
    _write(CORPUS, rows)
    return rows


# ---- 2. Вибірка

def pick_sample(rows: list[dict], seed: int = 42) -> list[dict]:
    rng = random.Random(seed)
    seen, pool = set(), []
    for r in sorted(rows, key=lambda r: (r["source"], r["url"])):
        k = art.key(r["title"])
        if k not in seen:                       # один сеанс на назву: серія не має важити більше
            seen.add(k)
            pool.append(r)
    rng.shuffle(pool)
    chosen: list[dict] = []
    taken: set[str] = set()

    def take(row, hard=False):
        taken.add(row["url"])
        chosen.append({**row, "hard": hard})

    for row in [r for r in pool if HARD.search(r["title"]) and r["category"] in QUOTA][:18]:
        take(row, hard=True)
    for category, quota in QUOTA.items():
        group = [r for r in pool if r["url"] not in taken
                 and (r["category"] == category if category != "other" else r["category"] not in QUOTA)]
        by_source = collections.defaultdict(list)
        for r in group:
            by_source[r["source"]].append(r)
        have = sum(1 for c in chosen if (c["category"] == category if category != "other"
                                         else c["category"] not in QUOTA))
        queues = [q for _, q in sorted(by_source.items())]
        while have < quota and any(queues):             # по колу між джерелами
            for q in queues:
                if q and have < quota:
                    take(q.pop())
                    have += 1
    _write(SAMPLE, chosen)
    return chosen


# ---- 3. Знімки сторінок

_OTHER_EVENTS = re.compile(r"(?im)^(схожі події|інші події|вам також|рекомендуємо|популярні події|більше подій)\b")
_DROP = re.compile(r"<(script|style|noscript|svg|header|nav|footer|form)\b.*?</\1>", re.S | re.I)


def page_text(page: str, title: str) -> str:
    """Видимий текст сторінки, від назви події. Меню й підвал відсікаємо тегами, решту обрізаємо.
    Повний опис із розмітки йде першим: на Karabas текст сторінки починається з меню сайту."""
    described = ""
    for e in events_from_html(page):
        described = clean_text(e.get("description") or "")
        if described:
            break
    text = _DROP.sub(" ", re.sub(r"(?is)<head\b.*?</head>", " ", page))
    text = htmllib.unescape(re.sub(r"<[^>]+>", "\n", text))
    lines = [re.sub(r"\s+", " ", ln).strip() for ln in text.splitlines()]
    text = "\n".join(ln for ln in lines if ln)
    at = text.find(title[:25])
    body = text[at:] if at >= 0 else text
    # Блоки інших подій розмітку б отруїли чужими іменами.
    cut = _OTHER_EVENTS.search(body, 40)
    body = (body[:cut.start()] if cut else body)[:TEXT_LIMIT]
    return (f"ОПИС (з розмітки): {described}\n---\n" if described else "") + body


def take_snapshots(sample: list[dict]) -> int:
    SNAPSHOTS.mkdir(parents=True, exist_ok=True)
    done = 0
    for n, row in enumerate(sample):
        out = SNAPSHOTS / f"{n:03d}.json"
        if out.exists():
            continue
        try:
            r = get(row["url"], delay=by_slug(row["source"]).crawl_delay)
        except Exception as exc:                        # noqa: BLE001
            print(f"{n}: {exc}", file=sys.stderr)
            continue
        if r.status != 200:
            print(f"{n}: HTTP {r.status} {row['url']}", file=sys.stderr)
            continue
        _write(out, {"n": n, "url": row["url"], "title": row["title"], "source": row["source"],
                     "venue": row["venue"], "text": page_text(r.body, row["title"])})
        done += 1
    return done


# ---- 4. Розмітка А

def _verify(artists: list, text: str) -> tuple[list[dict], list[dict]]:
    """Ім'я мусить стояти в цитаті, а цитата — в тексті сторінки (після нормалізації)."""
    flat = art.key(text)
    ok, bad = [], []
    for a in artists if isinstance(artists, list) else []:
        if not isinstance(a, dict):
            continue
        name, quote = clean_text(a.get("name") or ""), clean_text(a.get("evidence") or "")
        good = bool(name and quote and art.key(quote) in flat and art.has_name(name, quote))
        (ok if good else bad).append({"name": name, "role": a.get("role") or "headliner",
                                      "evidence": quote})
    return ok, bad


def _parse(raw: str):
    start, end = raw.find("{"), raw.rfind("}")
    try:
        return json.loads(raw[start:end + 1]).get("artists", [])
    except (ValueError, AttributeError):
        return None


def label_openai(workers: int = 4) -> dict:
    agent = Agent()
    if not agent.ready:
        raise SystemExit("потрібен OPENAI_API_KEY")
    labels = _read(LABELS_A) if LABELS_A.exists() else {}

    def one(path: pathlib.Path):
        snap = _read(path)
        prompt = (f"{RULES}\n\nПодія: «{snap['title']}»\nМайданчик: {snap['venue'] or '—'}\n"
                  f"ТЕКСТ СТОРІНКИ:\n{snap['text']}")
        for _ in range(2):
            try:
                parsed = _parse(agent.ask(prompt))
            except Exception as exc:                    # noqa: BLE001
                return snap["url"], {"error": f"{type(exc).__name__}: {str(exc)[:80]}"}
            if parsed is not None:
                ok, bad = _verify(parsed, snap["text"])
                return snap["url"], {"artists": ok, "rejected": bad}
        return snap["url"], {"error": "не JSON"}

    todo = [p for p in sorted(SNAPSHOTS.glob("*.json")) if _read(p)["url"] not in labels
            or "error" in labels[_read(p)["url"]]]
    with concurrent.futures.ThreadPoolExecutor(workers) as pool:
        for url, result in pool.map(one, todo):
            labels[url] = result
    _write(LABELS_A, labels)
    return labels


# ---- 5. Злиття голосів

def _names(artists) -> set[str]:
    return {art.key(a["name"] if isinstance(a, dict) else a) for a in artists}


def merge() -> dict:
    sample = {r["url"]: r for r in _read(SAMPLE)}
    a_labels = _read(LABELS_A)
    b_labels = _read(LABELS_B) if LABELS_B.exists() else {}
    gold, queue = [], []
    for url, row in sample.items():
        votes = {"openai": a_labels.get(url), "claude": b_labels.get(url)}
        sets = {}
        if votes["openai"] and "artists" in votes["openai"]:
            sets["openai"] = _names(votes["openai"]["artists"])
        if votes["claude"] is not None:
            sets["claude"] = _names(votes["claude"]["artists"] if isinstance(votes["claude"], dict)
                                    else votes["claude"])
        # Голос джерела: лише структура самого продавця (щабель 1), не результат правил назви.
        sets["source"] = _names(a for a in row["artists"] if a.get("how") == "source")
        agreed = None
        voters = list(sets)
        for i, v in enumerate(voters):
            for w in voters[i + 1:]:
                # Порожня відповідь джерела — «не знає», а не голос за «жодного».
                if sets[v] == sets[w] and (sets[v] or "source" not in (v, w)):
                    agreed = (v, w)
                    break
            if agreed:
                break
        canonical = {}
        for who in ("openai", "claude"):
            vote = votes.get(who)
            for a in (vote["artists"] if isinstance(vote, dict) else vote or []):
                canonical.setdefault(art.key(a["name"]), a)
        entry = {"url": url, "title": row["title"], "source": row["source"],
                 "category": row["category"], "hard": row.get("hard", False),
                 "votes": {k: sorted(v) for k, v in sets.items()}}
        if agreed:
            names = sorted(sets[agreed[0]])
            entry.update(artists=[{"name": canonical.get(k, {}).get("name", k), "role":
                                   canonical.get(k, {}).get("role", "headliner")} for k in names],
                         status=f"agreed:{'+'.join(agreed)}")
            gold.append(entry)
        else:
            entry["status"] = "disputed"
            queue.append(entry)
    gold, queue = _adjudicate(gold, queue, a_labels, b_labels)
    _write(GOLD, {"made": dt.date.today().isoformat(), "events": gold, "disputed": queue})
    return {"gold": len(gold), "disputed": len(queue)}


def _adjudicate(gold: list, queue: list, *labels) -> tuple[list, list]:
    """Третій голос для спірних і перевірка правила про акторів для погоджених. Файли суддів лежать
    у cache/: суддя бачить обох кандидатів і правила й вирішує по кожному імені."""
    roles: dict[tuple, str] = {}
    for L in labels:
        for url, v in L.items():
            for a in (v.get("artists") if isinstance(v, dict) else v) or []:
                roles.setdefault((url, art.key(a["name"])), a.get("role", "headliner"))
    disputes = CACHE / "gold_adjudication.json"
    casts = CACHE / "gold_cast_adjudication.json"
    if disputes.exists():
        verdicts, rest = _read(disputes), []
        for e in queue:
            v = verdicts.get(e["url"])
            if v is None:
                rest.append(e)
                continue
            people = [{"name": n, "role": roles.get((e["url"], art.key(n)), "headliner")} for n in v.get("keep", [])]
            people += [{"name": a["name"], "role": a.get("role", "headliner")} for a in v.get("added", [])]
            gold.append({**e, "artists": people, "status": "adjudicated", "why": v.get("why", "")})
        queue = rest
    if casts.exists():
        verdicts = _read(casts)
        for e in gold:
            v = verdicts.get(e["url"])
            if v is not None:
                e["artists"] = [a for a in e["artists"] if art.key(a["name"]) in {art.key(n) for n in v["keep"]}]
                e["status"] += "+cast-rule"
                e["why"] = v.get("why", "")
    return gold, queue


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("step", choices=["corpus", "sample", "snapshot", "label", "merge"])
    step = ap.parse_args(argv).step
    if step == "corpus":
        print(len(build_corpus()), "подій у корпусі")
    elif step == "sample":
        s = pick_sample(_read(CORPUS))
        print(len(s), "подій у вибірці", dict(collections.Counter(r["category"] for r in s)))
    elif step == "snapshot":
        print(take_snapshots(_read(SAMPLE)), "знімків")
    elif step == "label":
        labels = label_openai()
        print(len(labels), "розмічено, помилок:", sum("error" in v for v in labels.values()))
    else:
        print(merge())
    return 0


if __name__ == "__main__":
    sys.exit(main())
