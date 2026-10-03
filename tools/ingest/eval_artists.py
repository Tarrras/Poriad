"""Мірка артистів: що конвеєр показує проти золотого набору (`gold_artists.json`).

    python3 -m tools.ingest.eval_artists              # метрики й усі промахи
    python3 -m tools.ingest.eval_artists --stage 1    # лише щабель 1 (структура й лайнап), без правил назви
    python3 -m tools.ingest.eval_artists --stage 4    # + модель (платні запити, відповіді кешуються)

Корпус із cache/artists_corpus.json проганяється через `settle` заново, тож правила можна
міняти без повторного обходу джерел. Головна метрика — precision: показане артистом має бути
правдою; recall другорядний (docs/artists-discovery-2026-10.md, розд. 5).
"""
from __future__ import annotations

import argparse
import collections
import json
import types

from . import artists as art
from .gold_artists import CORPUS, GOLD

_STAGE1 = ("source", "lineup", "dictionary")


def _items(rows: list[dict]) -> list:
    return [types.SimpleNamespace(
        title=r["title"], category=r["category"], venue_name=r["venue"], latitude=None, longitude=None,
        text=r.get("text", ""), description=r.get("text", ""),
        artists=[art.Artist(**a) for a in r["artists"] if a["how"] in _STAGE1], url=r["url"])
        for r in rows]


def evaluate(stage: int = 3) -> dict:
    gold = {e["url"]: e for e in json.loads(GOLD.read_text("utf-8"))["events"]}
    rows = json.loads(CORPUS.read_text("utf-8"))
    items = _items(rows)
    if stage >= 2:
        dictionary = art.Dictionary.load()
        art.settle(items, dictionary)
        if stage >= 4:
            # Лише події золота: за решту корпусу платити для мірки ні до чого.
            from .agent import Agent
            agent = Agent()
            if not agent.ready:
                raise SystemExit("щабель 4 потребує OPENAI_API_KEY")
            stats = art.llm_fill([i for i in items if i.url in gold], agent.ask, dictionary)
            print("щабель 4:", stats)
    else:
        art.settle([i for i in items], art.Dictionary({}))
        for i in items:
            i.artists = [a for a in i.artists if a.how in _STAGE1]
    pred = {i.url: i for i in items}

    total = collections.Counter()
    by: dict[str, collections.Counter] = collections.defaultdict(collections.Counter)
    misses = []
    for url, g in gold.items():
        if url not in pred:
            total["missing_in_corpus"] += 1
            continue
        want = {art.key(a["name"]): a["name"] for a in g["artists"]}
        got = {art.key(a.name): a for a in pred[url].artists}
        tp, fp, fn = set(want) & set(got), set(got) - set(want), set(want) - set(got)
        for bucket in (total, by[f"src:{g['source']}"], by[f"cat:{g['category']}"],
                       by["hard" if g["hard"] else "random"]):
            bucket["events"] += 1
            bucket["tp"] += len(tp); bucket["fp"] += len(fp); bucket["fn"] += len(fn)
            bucket["exact"] += not fp and not fn
            bucket["wrong_events"] += bool(fp)
        for k in got:
            how = got[k].how
            total[f"{how}:tp"] += k in want
            total[f"{how}:fp"] += k not in want
        if fp or fn:
            misses.append({"title": g["title"], "source": g["source"], "cat": g["category"],
                           "fp": [(got[k].name, got[k].how) for k in fp], "fn": [want[k] for k in fn]})
    return {"total": total, "by": by, "misses": misses, "gold": len(gold)}


def _line(name: str, c: collections.Counter) -> str:
    p = c["tp"] / (c["tp"] + c["fp"]) if c["tp"] + c["fp"] else float("nan")
    r = c["tp"] / (c["tp"] + c["fn"]) if c["tp"] + c["fn"] else float("nan")
    return (f"{name:18} events={c['events']:3}  precision={p:5.1%}  recall={r:5.1%}  "
            f"exact={c['exact']}/{c['events']}  events_with_wrong={c['wrong_events']}")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--stage", type=int, default=3)
    ap.add_argument("--quiet", action="store_true", help="без списку промахів")
    args = ap.parse_args(argv)
    r = evaluate(args.stage)
    print(f"золото: {r['gold']} подій, щабель ≤{args.stage}")
    print(_line("УСЬОГО", r["total"]))
    for name in sorted(r["by"]):
        print(_line(name, r["by"][name]))
    stages = sorted({k.split(":")[0] for k in r["total"] if k.endswith((":tp", ":fp"))})
    for how in stages:
        tp, fp = r["total"][f"{how}:tp"], r["total"][f"{how}:fp"]
        print(f"  за щаблем {how:10} показано {tp + fp:3}, правильних {tp:3}  precision={tp / (tp + fp):5.1%}")
    if not args.quiet:
        for m in r["misses"]:
            print(f"- [{m['source']}/{m['cat']}] {m['title'][:70]}\n    зайве: {m['fp']}  пропущено: {m['fn']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
