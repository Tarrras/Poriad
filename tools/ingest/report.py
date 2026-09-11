"""Чи вистачає наявних категорій під те, що приносить імпорт.

Навіщо це окремий модуль. `normalize.classify` завжди повертає категорію — останній її рядок
віддає `social` за замовчуванням. Тому подія, для якої скриньки немає, виглядає рівно так само,
як подія, яку впевнено розпізнали: обидві мають категорію, обидві публікуються, обидві осідають
у базі. Прогалина не проявляється ніде, і побачити її можна лише випадково.

Саме так довго ховався стендап: 41 подія в Києві лежала в `art` поруч із ляльковим театром, і
жоден лічильник про це не сигналив. Тут два способи побачити таке заздалегідь:

1. **Чим саме вирішено.** Скільки подій розпізнано за типом schema.org, скільки лексиконом, а
   скільки просто впало у fallback. Зростання fallback — це прямий сигнал, що словник відстав від
   того, що приносять джерела.

2. **Наскільки грубий кошик.** Усередині кожної категорії шукаємо слова, які повторюються в
   багатьох різних заголовках. Велика зв'язна група всередині однієї категорії — це кандидат на
   власну категорію, точно як комедія всередині `art`.

Чого цей модуль НЕ робить: він не вирішує. Він показує числа й приклади, а рішення про восьму чи
дев'яту категорію коштує міграції та роботи дизайнера на двох платформах, тож приймає його людина.
"""
from __future__ import annotations

import collections
import re

from .normalize import normalize_name

# Слова, які нічого не розрізняють: вони є в половині афіші будь-якого міста. Без цього списку
# «концерт» і «вистава» очолюють будь-який рейтинг і ховають те, заради чого рейтинг будувався.
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

# Міста й місяці в усіх формах, які трапляються в заголовках. Без цього рейтинг очолюють
# «львові» та «вересня» — вони справді часті, але не описують ТИП події, а лише де й коли вона.
_STOP |= {
    "київ", "києві", "київський", "київська", "київського",
    "львів", "львові", "львівський", "львівська", "львівського",
    "харків", "харкові", "харківський", "харківська",
    "одеса", "одесі", "одеський", "одеська",
    "дніпро", "дніпрі", "дніпровський", "дніпровська",
}
_STOP |= {"січня", "лютого", "березня", "квітня", "травня", "червня", "липня", "серпня",
          "вересня", "жовтня", "листопада", "грудня"}

# Скільки різних заголовків має зачепити слово, щоб про нього взагалі говорити. Нижче цього це
# шум окремої події, а не тип подій.
_MIN_TITLES = 6

# Скільки подій одного чужого типу в кошику вже варті власної категорії незалежно від
# частки. Комедія при виділенні важила 104 події — ця межа нижча, щоб побачити раніше.
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


def category_gaps(items) -> dict:
    """Зведення: чим вирішено, що впало у fallback, і які групи визріли всередині категорій."""
    live = [i for i in items if i.stage in ("published", "review")]
    how = collections.Counter(i.category_how for i in live)
    by_category: dict[str, list[str]] = collections.defaultdict(list)
    for i in live:
        by_category[i.category].append(i.title)

    # Найсильніший сигнал — не слова в заголовках, а тип schema.org. Це зʼясувалось на перевірці:
    # згорнувши comedy назад в art, детектор за словами стендапу НЕ побачив — заголовки надто
    # різні («Батя 2», «Просмажка Раміни», «СТЕНДАП СУБОТА»). А тип ComedyEvent видно одразу.
    # Тому тип рахується окремо й головним.
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
    print(f"  розпізнано за типом schema.org : {how.get('type', 0):>5}"
          f"  ({100 * how.get('type', 0) / total:.0f}%)")
    print(f"  розпізнано лексиконом          : {how.get('lexicon', 0):>5}"
          f"  ({100 * how.get('lexicon', 0) / total:.0f}%)")
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

    # ── головний сигнал: кілька різних типів schema.org в одному кошику
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
            # Кандидат — це тип, який кошик НЕ визначає, але який у ньому помітний. Домінантний
            # тип тут ні до чого: MusicEvent і має бути 97% музики. А от коли поруч із ним живе
            # чужий рід подій на 15% і більше — це рівно та ситуація, у якій був стендап.
            # `Event` і `—` не рахуються: це відсутність типу, а не інший рід подій.
            # Поріг подвійний. Частка ловить малий кошик із чужим вкрапленням; абсолютна
            # кількість — великий кошик, де 90 подій це вже окрема категорія за обсягом, хоч
            # частка й лишається невеликою. Без другої умови ChildrensEvent усередині art
            # (91 подія, 14.9%) не проходив на сотих відсотка.
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
