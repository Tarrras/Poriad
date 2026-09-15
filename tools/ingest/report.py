"""Чи вистачає категорій під те, що приносить імпорт.

`normalize.classify` завжди повертає категорію (`social` за замовчуванням), тож прогалина
нізвідки не видна: так довго ховався стендап у `art`. Два способи побачити її заздалегідь:
1. Чим вирішено: тип schema.org, лексикон, агент чи fallback. Зростання fallback — словник відстав.
2. Наскільки грубий кошик: чужий тип або велика група слів усередині категорії — кандидат на власну.

Модуль не вирішує, лише показує числа: нова категорія коштує міграції й роботи дизайнера.
"""
from __future__ import annotations

import collections
import re

from .normalize import normalize_name

# Слова, що нічого не розрізняють: без списку «концерт» і «вистава» очолюють будь-який рейтинг.
_STOP = {
    # родові слова афіші
    "концерт", "вистава", "шоу", "квитки", "гурт", "тур", "презентація", "програма",
    "вечір", "нова", "нове", "новий", "нової", "великий", "велика", "святковий", "сольний",
    "україна", "українськ", "року", "рік", "театр",
    "the", "and", "for", "live", "show", "band", "part", "feat",
    # службові
    "все", "усі", "від", "для", "про", "під", "над", "або", "як", "що", "це", "їх",
    # назви категорій: усередині свого кошика вони тавтологія
    "музика", "музичн", "мистецтво", "спорт", "їжа", "ігри", "природа", "зустрічі", "стендап",
}

# Міста й місяці в усіх формах: часті, але описують «де й коли», а не тип події.
_STOP |= {
    "київ", "києві", "київський", "київська", "київського",
    "львів", "львові", "львівський", "львівська", "львівського",
    "харків", "харкові", "харківський", "харківська",
    "одеса", "одесі", "одеський", "одеська",
    "дніпро", "дніпрі", "дніпровський", "дніпровська",
}
_STOP |= {"січня", "лютого", "березня", "квітня", "травня", "червня", "липня", "серпня",
          "вересня", "жовтня", "листопада", "грудня"}

# Мінімум заголовків зі словом, щоб це був тип подій, а не шум однієї.
_MIN_TITLES = 6

# Скільки подій чужого типу в кошику варті власної категорії незалежно від частки.
_BIG_ENOUGH = 60


def _tokens(title: str) -> set[str]:
    words = normalize_name(title).split()
    return {w for w in words
            if len(w) >= 4 and w not in _STOP and not w.isdigit()}


def _clusters(titles: list[str], minimum: int = _MIN_TITLES) -> list[tuple[str, int, list[str]]]:
    """Слова, спільні для багатьох різних заголовків, з прикладами.

    Рахуємо заголовки, а не входження: серія з двадцяти однакових сеансів не має видавати себе
    за двадцять різних подій.
    """
    seen: dict[str, set[str]] = collections.defaultdict(set)
    for t in titles:
        for w in _tokens(t):
            seen[w].add(t)
    out = [(w, len(ts), sorted(ts)[:3]) for w, ts in seen.items() if len(ts) >= minimum]
    return sorted(out, key=lambda r: -r[1])


# Мінімум подій джерела, щоб говорити про розподіл типів.
_ENOUGH_TO_JUDGE = 20

# Частка головного типу, вище якої сигнал нічого не розрізняє. Не 100%: один виняток нічого не міняє.
_USELESS_SHARE = 95.0


def source_health(items, sources=None) -> list[dict]:
    """Чи несе тип schema.org від джерела хоч якусь інформацію.

    Лічильник, а не модель: «усі події concert.ua — MusicEvent» видно з розподілу. Джерела з
    `type_policy="weak"` не позначаються: для них щабель типу вже вимкнено.
    """
    by_source: dict = collections.defaultdict(collections.Counter)
    for i in items:
        if i.stage in ("published", "review"):
            by_source[i.source_slug][getattr(i, "source_type", "—") or "—"] += 1

    policies = {s.slug: getattr(s, "type_policy", "trust") for s in (sources or [])}
    out = []
    for slug, types in sorted(by_source.items()):
        total = sum(types.values())
        if total < _ENOUGH_TO_JUDGE:
            continue
        dominant, count = types.most_common(1)[0]
        share = 100 * count / total
        out.append({
            "source": slug, "events": total, "types": len(types),
            "dominant": dominant, "share": share,
            "policy": policies.get(slug, "trust"),
            "useless": share >= _USELESS_SHARE and policies.get(slug, "trust") != "weak",
        })
    return out


def print_source_health(rows: list[dict]) -> None:
    if not rows:
        return
    print("\n" + "═" * 62)
    print("ЧИ НЕСЕ ТИП SCHEMA.ORG ІНФОРМАЦІЮ")
    for r in sorted(rows, key=lambda r: -r["share"]):
        mark = "  ← тип нічого не розрізняє" if r["useless"] else ""
        weak = "  (тип вимкнено)" if r["policy"] == "weak" else ""
        print(f"  {r['source']:<16} подій {r['events']:>4} · різних типів {r['types']:>2}"
              f" · головний {r['dominant']} {r['share']:.0f}%{weak}{mark}")
    flagged = [r for r in rows if r["useless"]]
    if flagged:
        print("\n  Джерело ставить той самий тип майже всьому. Такий сигнал гірший за відсутній:")
        print("  він стоїть вище за словник і перебиває його правильну відповідь. Саме так усі")
        print("  191 подія concert.ua опинилась у «музиці». Лікується `type_policy=\"weak\"`")
        print("  у sources.py — тоді щабель типу для цього джерела просто не читається.")


def category_gaps(items) -> dict:
    """Зведення: чим вирішено, що впало у fallback, і які групи визріли всередині категорій."""
    live = [i for i in items if i.stage in ("published", "review")]
    how = collections.Counter(i.category_how for i in live)
    by_category: dict[str, list[str]] = collections.defaultdict(list)
    for i in live:
        by_category[i.category].append(i.title)

    # Головний сигнал — тип schema.org, не слова: за словами стендап не знаходився, за типом видно одразу.
    by_type: dict[str, collections.Counter] = collections.defaultdict(collections.Counter)
    for i in live:
        by_type[i.category][getattr(i, "source_type", "—")] += 1

    fallback_titles = [i.title for i in live if i.category_how == "fallback"]
    return {
        "total": len(live),
        "how": dict(how),
        "sizes": {c: len(t) for c, t in sorted(by_category.items(), key=lambda kv: -len(kv[1]))},
        "types": {c: dict(t.most_common()) for c, t in by_type.items()},
        "fallback": _clusters(fallback_titles, minimum=3),
        "fallback_examples": sorted(set(fallback_titles))[:10],
        "inside": {c: _clusters(t) for c, t in by_category.items() if len(t) >= _MIN_TITLES * 2},
    }


def print_category_gaps(gaps: dict, known_categories: list[str]) -> None:
    print("\n" + "═" * 62)
    print("ЧИ ВИСТАЧАЄ КАТЕГОРІЙ")
    total = gaps["total"] or 1
    how = gaps["how"]
    cat = how.get("catalog", 0)
    if cat:
        print(f"  взято з каталогу джерела       : {cat:>5}  ({100 * cat / total:.0f}%)")
    print(f"  розпізнано за типом schema.org : {how.get('type', 0):>5}"
          f"  ({100 * how.get('type', 0) / total:.0f}%)")
    print(f"  розпізнано лексиконом          : {how.get('lexicon', 0):>5}"
          f"  ({100 * how.get('lexicon', 0) / total:.0f}%)")
    # Щабель агента друкуємо окремо: видно, яка частка бази тримається на судженні моделі.
    ag = how.get("agent", 0)
    if ag:
        print(f"  розібрав агент                 : {ag:>5}  ({100 * ag / total:.0f}%)")
    fb = how.get("fallback", 0)
    print(f"  впало у fallback → social      : {fb:>5}  ({100 * fb / total:.0f}%)")
    print(f"  розмір кошиків: {gaps['sizes']}")

    if gaps["fallback"]:
        print("\n  Не розпізнано нічим — це те, під що словника ще немає:")
        for word, n, examples in gaps["fallback"][:8]:
            print(f"    «{word}» у {n} різних заголовках   напр.: {examples[0][:44]}")
    elif fb:
        print(f"\n  У fallback {fb} подій, але спільних слів немає — це поодинокі випадки,")
        print("  а не пропущений тип подій. Категорія тут не потрібна.")

    # Головний сигнал: кілька різних типів schema.org в одному кошику.
    print("\n  Типи schema.org усередині кожної категорії:")
    print("  (кілька типів в одному кошику — це і є те, як стендап ховався в art)")
    candidates = []
    for category, types in sorted(gaps.get("types", {}).items(), key=lambda kv: -sum(kv[1].values())):
        size = sum(types.values())
        if size < _MIN_TITLES:
            continue
        parts = []
        dominant = max(types, key=types.get)
        for t, n in types.items():
            share = 100 * n / size
            parts.append(f"{t} {n} ({share:.0f}%)")
            # Кандидат — помітний чужий тип у кошику (не домінантний, не `Event`/`—`). Поріг
            # подвійний: частка ловить малий кошик, абсолютна кількість — великий.
            if (t not in (dominant, "—", "Event")
                    and (share >= 15 or n >= _BIG_ENOUGH)):
                candidates.append((category, t, n, share))
        print(f"    {category:<9} {', '.join(parts)}")
    if candidates:
        print("\n  ← КАНДИДАТИ на власну категорію (не головний тип кошика, але ≥15% його):")
        for category, t, n, share in sorted(candidates, key=lambda c: -c[3]):
            print(f"      {t}: {n} подій, {share:.0f}% кошика «{category}»")
    else:
        print("    жоден чужий тип не займає ≥15% кошика — розділяти нічого")

    print("\n  Групи всередині наявних категорій (кандидати на власну категорію):")
    shown = False
    for category, clusters in gaps["inside"].items():
        top = [c for c in clusters if c[1] >= _MIN_TITLES][:4]
        if not top:
            continue
        shown = True
        size = gaps["sizes"][category]
        print(f"    {category} ({size} подій):")
        for word, n, examples in top:
            share = 100 * n / size
            mark = "  ←" if share >= 15 else ""
            print(f"      «{word}»: {n} заголовків ({share:.0f}% кошика){mark}")
            print(f"          напр.: {examples[0][:52]}")
    if not shown:
        print("    немає — наявні категорії покривають те, що приносять джерела")
    print("\n  Наявні категорії:", ", ".join(known_categories))
    print("  Стрілка ← позначає групу, що займає ≥15% свого кошика: приблизно стільки важив")
    print("  стендап усередині art, коли його виділили в окрему категорію.")
