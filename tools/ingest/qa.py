"""Рецензент рішень, які ухвалили пороги й регекси. Нічого не змінює, лише позначає підозріле.

`agent.py` ухвалює рішення там, де драбина не дала відповіді; тут модель перевіряє рішення, які
алгоритм ухвалив упевнено. Детерміновані правила ламаються мовчки: регекс без меж слова робив
музикою «1939 року», поріг схожості зіставляв «Feels Garden» з «Garden» за 10 км.

Три межі:
1. Нічого не пишеться: ні в базу, ні в JSON, ні в кеш. Вихід — звіт для людини.
2. Позначати лише явно хибне, інакше звіт не читається.
3. Перевіряються щаблі, де вирішує поріг: збіг майданчика за входженням, категорія від словника,
   злиття дублікатів. Псевдоніми, тип і каталог мають свою перевірку.

    python3 -m tools.ingest.qa прогін.json
    python3 -m tools.ingest.qa прогін.json --sample 40 --only venue
"""
from __future__ import annotations

import argparse
import json
import pathlib
import random
import sys

from .agent import Agent

# Скільки рішень одного класу показувати моделі за раз: рецензія вибіркова, а не суцільна.
SAMPLE = 25

_SHARED = (
    "Ти рецензуєш рішення алгоритму імпорту афіші. Твоє завдання — знайти ЯВНО хибні.\n"
    "Не переписуй і не покращуй: лише познач те, що неправильне, і скажи чому.\n"
    "Сумнівне не позначай. Рецензія, у якій половина рядків — сумніви, нечитабельна, а отже\n"
    "марна. Якщо рішення правдоподібне, його в відповіді бути не повинно.\n"
)

_VENUE = _SHARED + (
    "\nНижче збіги назви майданчика з афіші з назвою в OpenStreetMap. Їх зробив поріг схожості,\n"
    "і саме тут колись «Feels Garden» зіставився з «Garden» за десять кілометрів.\n"
    "Познач ті, де це РІЗНІ заклади.\n"
    'Відповідай масивом JSON: [{"n": 1, "why": "різні заклади: пивна й кавʼярня"}]\n'
    "Порожній масив означає «усе гаразд» — це нормальна й очікувана відповідь.\n"
)

_CATEGORY = _SHARED + (
    "\nНижче категорії, які подіям присвоїв словник регексів. Саме так лекція «Пастка серпня\n"
    "1939 року» стала музикою: «рок» зловився всередині слова «року».\n"
    "Познач ті, де категорія явно не та.\n"
    'Відповідай масивом JSON: [{"n": 1, "why": "це лекція, а не музика", "краще": "art"}]\n'
    "Порожній масив означає «усе гаразд».\n"
)

_MERGE = _SHARED + (
    "\nНижче пари подій, які алгоритм визнав однією й показав однією карткою. Друга зникла з\n"
    "видачі. Познач ті, де це РІЗНІ події — наприклад різні програми, різні виконавці або\n"
    "сусідні зали одного закладу.\n"
    'Відповідай масивом JSON: [{"n": 1, "why": "різні програми того самого оркестру"}]\n'
    "Порожній масив означає «усе гаразд».\n"
)


def _flags(text: str) -> dict:
    start, end = text.find("["), text.rfind("]")
    if start < 0 or end <= start:
        return {}
    try:
        rows = json.loads(text[start:end + 1])
    except json.JSONDecodeError:
        return {}
    out = {}
    for row in rows if isinstance(rows, list) else []:
        if not isinstance(row, dict):
            continue
        try:
            out[int(row.get("n"))] = row
        except (TypeError, ValueError):
            continue
    return out


def _review(agent: Agent, rules: str, lines: list[str]) -> dict:
    if not lines:
        return {}
    return _flags(agent.ask(rules + "\n" + "\n".join(lines)))


def venue_matches(items, sample):
    """Щаблі, де майданчик визначив не людина й не точний збіг.

    `contains` — поріг схожості назв. `detail` — адреса зі сторінки події, яку розвʼязав Photon:
    джерело могло написати адресу неповно, а геокодер — влучити в сусідній будинок.
    """
    rows = [i for i in items
            if i.get("venue_match") in ("contains", "detail") and i.get("stage") == "published"]
    return _pick(rows, sample), rows


def lexicon_categories(items, sample):
    rows = [i for i in items if i.get("category_how") == "lexicon" and i.get("stage") == "published"]
    return _pick(rows, sample), rows


def merges(items, sample):
    by_uid = {(i.get("source"), i.get("source_uid")): i for i in items}
    pairs = []
    for item in items:
        origin = item.get("duplicate_of")
        if not origin:
            continue
        winner = by_uid.get(tuple(origin))
        if winner is not None:
            pairs.append((item, winner))
    return _pick(pairs, sample), pairs


def _pick(rows, sample):
    if sample <= 0 or len(rows) <= sample:
        return list(rows)
    return random.sample(list(rows), sample)


def run(path: pathlib.Path, sample: int, only: str | None, provider: str) -> int:
    items = json.loads(path.read_text("utf-8"))
    agent = Agent(provider=provider)
    if not agent.ready:
        print(f"потрібен {agent.provider.env_key} у середовищі або в .env", file=sys.stderr)
        return 2
    print(f"Рецензія: {agent.provider.name} / {agent.model} · {path.name} · {len(items)} елементів")

    flagged = 0

    if only in (None, "venue"):
        picked, total = venue_matches(items, sample)
        lines = [f"{n}. афіша: «{i['venue']}» → «{i.get('venue_display') or i.get('address') or '—'}»"
                 f" [{i.get('venue_match')}] · подія: «{i['title'][:46]}» · {i['city']}"
                 for n, i in enumerate(picked, 1)]
        found = _review(agent, _VENUE, lines)
        flagged += _print("Майданчики: входження й адреса зі сторінки", picked, total, found,
                          lambda i: f"«{i['venue']}» · {i['title'][:44]}")

    if only in (None, "category"):
        picked, total = lexicon_categories(items, sample)
        lines = [f"{n}. «{i['title'][:60]}» · майданчик: {i['venue'][:28]} → категорія: {i['category']}"
                 for n, i in enumerate(picked, 1)]
        found = _review(agent, _CATEGORY, lines)
        flagged += _print("Категорії від словника", picked, total, found,
                          lambda i: f"{i['category']:<11} {i['title'][:46]}")

    if only in (None, "merge"):
        picked, total = merges(items, sample)
        lines = [f"{n}. «{a['title'][:44]}» ({a['source']})  ЗЛИТО З  «{b['title'][:44]}» ({b['source']})"
                 for n, (a, b) in enumerate(picked, 1)]
        found = _review(agent, _MERGE, lines)
        flagged += _print("Злиті дублікати", picked, total, found,
                          lambda p: f"«{p[0]['title'][:34]}» ↔ «{p[1]['title'][:34]}»")

    print(f"\nПозначено підозрілих: {flagged}. Нічого не змінено — це звіт.")
    if agent.errors:
        print(f"помилки: {agent.errors}")
    return 0


def _print(title, picked, total, found, render) -> int:
    print(f"\n── {title}: перевірено {len(picked)} із {len(total)}")
    if not found:
        print("   нічого підозрілого")
        return 0
    for number, row in sorted(found.items()):
        if not 1 <= number <= len(picked):
            continue
        print(f"   ⚠ {render(picked[number - 1])}")
        print(f"       {row.get('why', '')}"
              + (f"  → краще: {row['краще']}" if row.get("краще") else ""))
    return len(found)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="tools.ingest.qa",
                                 description="Рецензія алгоритмічних рішень. Нічого не змінює.")
    ap.add_argument("json", type=pathlib.Path, help="JSON прогону (--json у tools.ingest)")
    ap.add_argument("--sample", type=int, default=SAMPLE, help="скільки рішень класу перевіряти")
    ap.add_argument("--only", choices=["venue", "category", "merge"], help="лише один клас")
    ap.add_argument("--provider", default="openai")
    args = ap.parse_args(argv)
    return run(args.json, args.sample, args.only, args.provider)


if __name__ == "__main__":
    raise SystemExit(main())
