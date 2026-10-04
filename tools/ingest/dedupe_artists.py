"""Дублі артистів: пошук агентом, застосування через `artists.json`.

    python3 -m tools.ingest.dedupe_artists --db dev              # перегляд: що зіллє агент і чому
    python3 -m tools.ingest.dedupe_artists --db dev --apply      # дописати аліаси в tools/ingest/artists.json
    python3 -m tools.ingest.dedupe_artists artists.json          # або з файлу

Вхід — база (`--db dev|prod`, лише SELECT, рядок зʼєднання як у tools/apply_sql.py), або JSON конвеєра
(`--json` у `python3 -m tools.ingest`), або список `[{"name", "kind", "events": [{"title", "venue", "city"}]}]`.
Аліаси діють з наступного прогону конвеєра, який і зводить дублі в базі.

Чому агент, а не правило. «Струнний квартет «Black Tie»», «Black Tie String Quartet» і «Black Tie Quintet»,
«Олена Тополь» і «Олена Тополя»: збіг за схожістю хибно злив би різних людей, а ручні аліаси не
ловлять невідомого. Тож три щаблі, у кожного своя роль:
1. Евристика дає **кандидатів** (спільне рідкісне слово, схожі слова, транслітерація). Агент нічого не шукає сам.
2. Агент бачить для кожного імені контекст (події, зали, міста) і довідку з Вікіпедії, і повертає групи з причиною.
   Імена в групі мусять бути з кластера: вигадати артиста чи канонічну форму він не може.
3. Код застосовує лише впевнене (≥ MIN_CONFIDENCE) і не суперечливе (різний вид: людина проти колективу);
   решта лишається в звіті. Результат — аліас у `artists.json` з причиною: видно в git, відкочується.
Хибне злиття гірше за дубль, тож агент «не знаю» вважає відповіддю.
"""
from __future__ import annotations

import argparse
import collections
import difflib
import json
import pathlib
import re
import sys
import time
import urllib.parse
import urllib.request

from .agent import Agent
from .artists import DICT_PATH, display, key
from .fetch import USER_AGENT

CACHE = pathlib.Path(__file__).resolve().parent / "cache" / "artists_dedupe.json"
MIN_CONFIDENCE = 0.9
MAX_CLUSTER = 8
MAX_DF = 6                    # слово в більшій кількості імен — не відрізняє артиста («black» у п'яти іменах ще так)
BATCH = 3                     # менші партії: серед шумних кластерів модель пропускала очевидні пари
PASSES = 2                    # модель недетермінована: два проходи, результати об'єднуються
# Слова, що не відрізняють артистів: склад колективу, статус, місто.
_GENERIC = frozenset("""оркестр orchestra квартет quartet квінтет quintet ансамбль ensemble театр theatre theater хор
 гурт band група капела симфонічний камерний академічний національний заслужений народний київський київські
 україни українська українського імені філармонії show шоу party club клуб project проєкт string струнний
 trio тріо джаз jazz the and big""".split())
_CYR = dict(zip("абвгґдеєжзиіїйклмнопрстуфхцчшщюя", ["a", "b", "v", "h", "g", "d", "e", "ye", "zh", "z", "y", "i", "yi", "y",
             "k", "l", "m", "n", "o", "p", "r", "s", "t", "u", "f", "kh", "ts", "ch", "sh", "shch", "yu", "ya"]))


def _translit(token: str) -> str:
    return "".join(_CYR.get(c, "" if c in "ьʼ'’" else c) for c in token)


def load_artists(path: pathlib.Path) -> list[dict]:
    """Список артистів із контекстом. Приймає й JSON конвеєра (події з полем `artists`)."""
    data = json.loads(path.read_text("utf-8"))
    if data and "events" in data[0]:
        return data
    by_name: dict[str, dict] = {}
    for e in data:
        for a in e.get("artists", []):
            name = a["name"] if isinstance(a, dict) else a
            row = by_name.setdefault(name, {"name": name, "kind": None, "events": []})
            row["events"].append({"title": e.get("title"), "venue": e.get("venue"), "city": e.get("city")})
    return list(by_name.values())


def load_from_db(env: str) -> list[dict]:
    """Артисти з базою контексту: до п'яти найближчих подій кожного. Лише читання."""
    from .. import apply_sql
    name = apply_sql.ENVS[env][1]
    url = apply_sql._env_values().get(name)
    if not url:
        raise SystemExit(f"немає {name} у середовищі чи .env")
    conn = apply_sql.connect(url, "60s")
    try:
        rows = conn.execute(
            "select a.name, a.kind, (select coalesce(jsonb_agg(x), '[]'::jsonb) from ("
            " select e.title, pl.name as venue, e.city from public.event_artists ea"
            " join public.events e on e.id = ea.event_id left join public.places pl on pl.id = e.place_id"
            " where ea.artist_id = a.id order by e.starts_at limit 5) x) from public.artists a").fetchall()
    finally:
        conn.close()
    return [{"name": n, "kind": k, "events": ev} for n, k, ev in rows]


# ---- 1. Кандидати

def candidates(artists: list[dict]) -> list[list[int]]:
    """Кластери імен, які МОЖУТЬ бути одним артистом. Повнота важливіша за точність: рішення за агентом."""
    toks = [[t for t in key(a["name"]).split() if len(t) >= 4 and t not in _GENERIC] for a in artists]
    df = collections.Counter(t for ts in toks for t in set(ts))
    parent = list(range(len(artists)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    def union(i, j):
        parent[find(i)] = find(j)

    owners: dict[str, list[int]] = collections.defaultdict(list)
    for i, ts in enumerate(toks):
        for t in set(ts):
            owners[t].append(i)
    words = [key(a["name"]).split() for a in artists]

    def first_name(t: str) -> bool:
        """Слово, що стоїть першим у всіх багатослівних імен, — ім'я людини («Олена …»), не прізвище."""
        return all(len(words[i]) > 1 and words[i][0] == t for i in owners[t])

    for t, idx in owners.items():                         # спільне рідкісне слово (прізвище, власна назва)
        if first_name(t):
            continue
        if 1 < len(idx) <= MAX_DF:
            for j in idx[1:]:
                union(idx[0], j)
    buckets: dict[str, list[str]] = collections.defaultdict(list)
    for t in df:
        buckets[_translit(t)[:3]].append(t)
    for group in buckets.values():                        # схожі слова: Тополь/Тополя, транслітерація
        for a in range(len(group)):
            for b in range(a + 1, len(group)):
                x, y = group[a], group[b]
                if x != y and df[x] <= MAX_DF and df[y] <= MAX_DF and len(x) >= 5 and len(y) >= 5 \
                        and not (first_name(x) and first_name(y)) \
                        and difflib.SequenceMatcher(None, _translit(x), _translit(y)).ratio() >= 0.8:
                    union(owners[x][0], owners[y][0])
    clusters: dict[int, list[int]] = collections.defaultdict(list)
    for i in range(len(artists)):
        clusters[find(i)].append(i)
    return [c[:MAX_CLUSTER] for c in clusters.values() if len(c) > 1]


# ---- 2. Агент

PROMPT = """Ти зводиш дублі в словнику артистів афіші. Нижче кластери імен, які МОЖУТЬ бути одним артистом
(схожі слова). Для кожного кластера визнач, які імена — ОДИН і той самий реальний артист (людина, гурт, трупа).

Зливай, коли це одне й те саме: інше написання, переклад чи транслітерація («Black Tie String Quartet» і
«Струнний квартет «Black Tie»»), відмінок («Олексія Мовчана»), порядок слів, скорочення, дужки.
НЕ зливай: різних людей зі спільним прізвищем чи іменем; колектив і його учасника чи керівника; різні склади
однієї агенції («BIGSHOW Band» і «BIGSHOW Brass Quintet»); артиста і його шоу. Не впевнений: не зливай.

Підстави в порядку вагомості: basis = "context" (контекст подій: ті самі зали, дати, назви), "wikipedia" (довідка
нижче прямо каже, що це одне й те саме), "spelling" (імена відрізняються лише написанням, а контекст не суперечить),
"knowledge" (твоє знання без довідки). Причина — одне речення з конкретним фактом.

Відповідай ЛИШЕ JSON:
{"clusters":[{"n":1,"groups":[{"canonical":"ім'я з кластера","members":["ім'я","ім'я"],"confidence":0.0-1.0,
"basis":"context|wikipedia|spelling|knowledge","reason":"..."}]}]}
canonical і members — ТОЧНІ імена з кластера. Групи лише з двох і більше імен; незлиті імена не вказуй.
Кожна група має canonical із members; кращий для показу — повніша й загальновживана форма."""


def _wiki(name: str) -> str:
    """Два найкращі збіги з української й англійської Вікіпедії. Не краулер: API Wikimedia з описовим
    User-Agent, по одному запиту (https://www.mediawiki.org/wiki/API:Etiquette). Збій — порожня довідка."""
    out = []
    for lang in ("uk", "en"):
        url = (f"https://{lang}.wikipedia.org/w/api.php?action=query&list=search&format=json&srlimit=2&srprop=snippet"
               f"&srsearch={urllib.parse.quote(name)}")
        time.sleep(0.4)                                      # по одному запиту й з паузою
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": USER_AGENT}), timeout=15) as r:
                for hit in json.loads(r.read())["query"]["search"]:
                    snippet = re.sub(r"<[^>]+>", "", hit["snippet"])
                    out.append(f"{lang}: {hit['title']} — {snippet}")
        except Exception:                                    # noqa: BLE001 — довідка не обов'язкова
            continue
    return "; ".join(out)[:600]


def _describe(n: int, cluster: list[dict], wiki: bool) -> str:
    lines = [f"Кластер {n}:"]
    for a in cluster:
        ev = a.get("events", [])
        titles = "; ".join(dict.fromkeys(e["title"] for e in ev if e.get("title")))[:140]
        venues = ", ".join(sorted({e["venue"] for e in ev if e.get("venue")}))[:90]
        cities = ", ".join(sorted({e["city"] for e in ev if e.get("city")}))
        lines.append(f"  - «{a['name']}» · вид: {a.get('kind') or '?'} · подій {len(ev)} · міста: {cities or '?'}"
                     f" · зали: {venues or '?'} · події: {titles or '?'}")
        if wiki:
            hint = _wiki(a["name"])
            if hint:
                lines.append(f"      довідка: {hint}")
    return "\n".join(lines)


def judge(clusters: list[list[dict]], ask, wiki: bool = True) -> list[dict]:
    """Групи злиття від агента, перевірені: імена з кластера, кожне в одній групі, canonical серед членів."""
    verdicts = []
    for start in range(0, len(clusters), BATCH):
        chunk = clusters[start:start + BATCH]
        prompt = PROMPT + "\n\n" + "\n\n".join(_describe(n, c, wiki) for n, c in enumerate(chunk, 1))
        rows = None
        for _ in range(2):                                   # один повтор: збій партії не має мовчки губити кластери
            try:
                raw = ask(prompt)
                rows = json.loads(raw[raw.find("{"):raw.rfind("}") + 1]).get("clusters", [])
                break
            except Exception as exc:                         # noqa: BLE001
                print(f"  ⚠ партія {start // BATCH + 1}: {type(exc).__name__}: {str(exc)[:80]}", file=sys.stderr)
        if rows is None:
            continue
        for row in rows if isinstance(rows, list) else []:
            try:
                cluster = chunk[int(row["n"]) - 1]
            except (KeyError, ValueError, IndexError, TypeError):
                continue
            by_name = {a["name"]: a for a in cluster}
            used: set[str] = set()
            for g in row.get("groups") or []:
                members = [m for m in g.get("members", []) if m in by_name and m not in used]
                if len(members) < 2 or g.get("canonical") not in members or not str(g.get("reason") or "").strip():
                    continue
                used.update(members)
                kinds = {by_name[m].get("kind") for m in members} - {None}
                verdicts.append({"canonical": g["canonical"], "members": members,
                                 "confidence": float(g.get("confidence") or 0), "basis": g.get("basis"),
                                 "reason": str(g["reason"]).strip()[:240],
                                 "kind": next(iter(kinds)) if len(kinds) == 1 else None,
                                 "kind_conflict": len(kinds) > 1})
    return verdicts


def judge_passes(clusters: list[list[dict]], ask, wiki: bool = True, passes: int = PASSES) -> list[dict]:
    """Кілька проходів: однакову групу беремо з найвищою впевненістю. Хибне злиття від цього не з'являється
    (кожен прохід проходить ті самі перевірки), а пропущене очевидне — ловиться другим проходом."""
    best: dict[frozenset, dict] = {}
    for _ in range(passes):
        for v in judge(clusters, ask, wiki):
            k = frozenset(v["members"])
            if k not in best or v["confidence"] > best[k]["confidence"]:
                best[k] = v
    return list(best.values())


# ---- 3. Застосування

_JOINER = re.compile(r"\s(?:та|і|&)\s")


def accepted(v: dict) -> bool:
    """Впевнене й без суперечності. Знання без довідки й контексту автоматично не застосовуємо. Ім'я зі
    сполучником («Вєсти Гунченко і Сергія Степаниська») — двоє людей разом: зливати його з одним
    артистом можна лише коли сполучник є в усіх іменах групи («Бампер і Сус» = «Петро Бампер і Сус»)."""
    joined = {bool(_JOINER.search(m)) for m in v["members"]}
    return (v["confidence"] >= MIN_CONFIDENCE and not v["kind_conflict"] and v["basis"] != "knowledge"
            and len(joined) == 1)


def apply(verdicts: list[dict], path: pathlib.Path = DICT_PATH) -> int:
    """Дописує аліаси в artists.json. Канонічним лишається наявний ручний запис, якщо він серед членів."""
    entries = json.loads(path.read_text("utf-8"))
    added = 0
    for v in verdicts:
        if not accepted(v):
            continue
        canonical = next((m for m in v["members"] if m in entries), display(v["canonical"]))
        entry = entries.get(canonical, {"kind": v["kind"]})
        have = {key(a) for a in [canonical, *entry.get("aliases", [])]}
        fresh = [m for m in v["members"] if key(m) not in have]
        if not fresh:
            continue                                         # вже зведені: порожнього запису не створюємо
        entries[canonical] = entry
        entry["aliases"] = [*entry.get("aliases", []), *fresh]
        entry["merged_by"] = f"агент: {v['basis']}, {v['confidence']:.2f}: {v['reason']}"
        added += len(fresh)
    path.write_text(json.dumps(entries, ensure_ascii=False, indent=2) + "\n", "utf-8")
    return added


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input", type=pathlib.Path, nargs="?")
    ap.add_argument("--db", choices=("dev", "prod"), help="читати артистів із бази")
    ap.add_argument("--apply", action="store_true", help="дописати аліаси в artists.json")
    ap.add_argument("--no-wikipedia", action="store_true")
    args = ap.parse_args(argv)
    agent = Agent()
    if not agent.ready:
        print(f"потрібен {agent.provider.env_key}", file=sys.stderr)
        return 1
    if not args.input and not args.db:
        ap.error("потрібен файл або --db")
    artists = load_from_db(args.db) if args.db else load_artists(args.input)
    clusters = [[artists[i] for i in c] for c in candidates(artists)]
    print(f"артистів {len(artists)}, кластерів-кандидатів {len(clusters)}")
    verdicts = judge_passes(clusters, agent.ask, wiki=not args.no_wikipedia)
    CACHE.parent.mkdir(exist_ok=True)
    CACHE.write_text(json.dumps(verdicts, ensure_ascii=False, indent=1), "utf-8")
    for v in sorted(verdicts, key=lambda v: -v["confidence"]):
        mark = "✓" if accepted(v) else "·"
        print(f"{mark} {v['confidence']:.2f} {v['basis']:9} {' = '.join(v['members'])}\n      {v['reason']}"
              + ("  [суперечність виду]" if v["kind_conflict"] else ""))
    if args.apply:
        print(f"\nДописано аліасів: {apply(verdicts)} (· не застосовано: вердикти нижче порога, на знанні або з суперечністю виду)")
    else:
        print("\nПерегляд. --apply допише ✓ в artists.json.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
