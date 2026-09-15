"""Мірка для підказки агента. Запускається вручну, в обхід не входить.

Набір випадків із живих обходів із відомими відповідями й причиною, чому кожен у наборі:
без нього не видно, що виправилось і що зламалось поруч. Вивід показує кожен промах разом із
підставою моделі, і правити треба саме те місце підказки.

    python3 -m tools.ingest.eval_agent            # прогнати поточну підказку
    python3 -m tools.ingest.eval_agent --show-all # разом із тим, що вгадано правильно
"""
from __future__ import annotations

import argparse
import collections
import sys

from .agent import Agent

# (назва, майданчик, місто, правильна категорія, чому цей випадок у наборі). Категорії
# вирішені людиною; спірні — з причиною, щоб сперечатись явно, а не підганяти під модель.
CASES: list[tuple[str, str, str, str, str]] = [
    # Промахи живого прогону 2026-09-12.
    ("Human Development Summit 2026", "UNIT.City", "Київ", "conference",
     "саміт названо прямо; модель віддала social"),
    ("Майстер-клас з казкотерапії для дітей 8+ з авторкою", "Медіатека", "Львів", "kids",
     "«для дітей 8+» у назві; модель віддала social"),
    ("Іздрик. Поетичний вечір", "Будинок Кіно. Червоний зал", "Київ", "art",
     "література — це art за переліком; модель віддала social"),
    ("Сергій Жадан. Презентація книжки «Гімни барокових вітрів»", "ХНАТОБ LOFT STAGE",
     "Харків", "art", "презентація книжки — теж література"),
    ("Воркшоп «AI та кібербезпека»", "вулиця Січових Стрільців", "Київ", "conference",
     "фахова подія; межа з social тут найтонша"),

    # Те, що модель узяла правильно: полірування не має це зламати.
    ("Вілла Айва", "вул. Піскова, 10", "Львів", "tours",
     "назва будівлі з адресою — головна знахідка агента"),
    ("Дім Людкевича: спадщина, що вистояла", "вул. С. Людкевича, 7", "Львів", "tours",
     "те саме, зі словом «спадщина»"),
    ("Вежа Латинської катедри", "пл. Катедральна, 7", "Львів", "tours", "памʼятка як обʼєкт огляду"),
    ("Побачення наосліп (23-35 років)", "KVIN LOUNGE", "Харків", "social",
     "справжній social; його легко втягнути в conference"),
    ("Відкритий Клуб «Бувальщина»", "MODI Art and Wine Gallery", "Київ", "social",
     "клуб за інтересами, не конференція"),

    # Межі, на яких помиляються і словник, і модель.
    ("4К-Відеопрогулянка Страсбургом", "MODI Art and Wine Gallery", "Київ", "art",
     "відеопоказ у галереї, а не прогулянка: словник дав outdoors"),
    ("Піша прогулянка Личаковом", "Личаківський цвинтар", "Львів", "tours",
     "прогулянка з гідом — екскурсія, не природа"),
    ("Похід у Карпати", "збір на вокзалі", "Львів", "outdoors",
     "другий бік тієї самої межі"),
    ("Закритий Мікрофон", "Бочка PUB", "Київ", "comedy",
     "скарга власника: джерело каже MusicEvent, у назві слова «стендап» немає"),
    ("Дюймовочка (ХТДЮ)", "Харківський театр для дітей та юнацтва", "Харків", "kids",
     "дитяче важливіше за театральне, коли зал дитячий"),
    ("Чемпіонат України з боксу Ю-23", "Палац спорту", "Київ", "sport", "прямий спорт"),
    ("Kyiv Food and Wine Festival", "ВДНГ", "Київ", "food", "прямі їжа й вино"),
    ("Стендап та коктейлі", "Komediant", "Київ", "comedy", "коктейлі не роблять це їжею"),
    ("Найкращі короткометражки Європи: Блок #1", "Львівський Палац Мистецтв", "Львів", "art",
     "кінопоказ фестивалю"),
    ("Зоопарк", "Київський зоопарк", "Київ", "none",
     "МОЄ очікування було хибним, і мірка це показала: модель відповіла «жодна» з підставою "
     "«лише назва зоопарку без формату події», і вона має рацію — постійний заклад подією не є. "
     "Виправлено очікування, а не підказку."),
]


class _Row:
    """Той самий інтерфейс, що й `pipeline.Item`, рівно в тих полях, які читає агент."""

    def __init__(self, title, venue, city, source="lviv_travel"):
        self.title, self.venue_name, self.city = title, venue, city
        self.source_slug = source
        self.description, self.category, self.category_how = "", "social", "fallback"


def run(show_all: bool = False, provider: str = "openai") -> int:
    agent = Agent(provider=provider)
    if not agent.ready:
        print(f"потрібен {agent.provider.env_key} у середовищі або в .env", file=sys.stderr)
        return 2
    rows = [_Row(t, v, c) for t, v, c, _, _ in CASES]
    agent.classify(rows)

    got = {title: (category, why) for title, category, why in agent.decisions}
    for title, why in agent.unknown:
        got[title] = ("none", why)

    hits = 0
    misses: list[tuple] = []
    by_expected = collections.Counter()
    for (title, venue, city, expected, reason), row in zip(CASES, rows):
        answer, why = got.get(title, (row.category, ""))
        if answer == expected:
            hits += 1
            if show_all:
                print(f"  ✓ {expected:<11} {title[:44]}")
        else:
            by_expected[expected] += 1
            misses.append((title, expected, answer, why, reason))

    print(f"\n{agent.provider.name} / {agent.model}: {hits} із {len(CASES)}"
          f"  ({100 * hits / len(CASES):.0f}%)")
    if misses:
        print("\nпромахи — і підстава, яку назвала модель:")
        for title, expected, answer, why, reason in misses:
            print(f"  ✗ {title[:52]}")
            print(f"      треба {expected}, дала {answer}")
            print(f"      її підстава: {why or '—'}")
            print(f"      чому в наборі: {reason}")
    if by_expected:
        print(f"\n  промахи за правильною категорією: {dict(by_expected.most_common())}")
    if agent.refused:
        print(f"  відхилено вигаданих категорій: {len(agent.refused)}")
    if agent.errors:
        print(f"  помилок мережі: {agent.errors}")
    return 0 if not misses else 1


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="tools.ingest.eval_agent",
                                 description="Мірка підказки агента на випадках із живих обходів")
    ap.add_argument("--show-all", action="store_true", help="показати і вгадані правильно")
    ap.add_argument("--provider", default="openai")
    args = ap.parse_args(argv)
    return run(args.show_all, args.provider)


if __name__ == "__main__":
    raise SystemExit(main())
