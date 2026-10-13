#!/usr/bin/env python3
"""Єдине джерело правди для іконок Poruch.

Іконки малюються тут на сітці 24 одиниці й генеруються в код обох платформ: Compose `ImageVector`
і SwiftUI `Shape`. Дві копії геометрії руками розходяться, а дуги легко намалювати криво.

    python3 tools/generate_icons.py

Стиль: тонка лінія 1.75 із круглими кінцями на сітці 24, вміст у межах 3..21. Заливка лише для
крапок і залитої закладки. Колір не запікається: усе чорне, платформа тонує сама.
"""

from __future__ import annotations

from pathlib import Path as FilePath

ROOT = FilePath(__file__).resolve().parent.parent

# Кубічна апроксимація чверті кола; чотири такі — коло, яке не відрізнити від справжнього.
K = 0.5522847498


def move(x, y):
    return ("M", (x, y))


def line(x, y):
    return ("L", (x, y))


def curve(x1, y1, x2, y2, x, y):
    return ("C", (x1, y1, x2, y2, x, y))


def close():
    return ("Z", ())


def circle(cx, cy, r):
    """Коло з чотирьох кубічних сегментів, зліва за годинниковою стрілкою."""
    o = r * K
    return [
        move(cx - r, cy),
        curve(cx - r, cy - o, cx - o, cy - r, cx, cy - r),
        curve(cx + o, cy - r, cx + r, cy - o, cx + r, cy),
        curve(cx + r, cy + o, cx + o, cy + r, cx, cy + r),
        curve(cx - o, cy + r, cx - r, cy + o, cx - r, cy),
        close(),
    ]


def polyline(*points):
    """Штрих через задані точки."""
    pairs = list(zip(points[0::2], points[1::2]))
    return [move(*pairs[0])] + [line(*p) for p in pairs[1:]]


def rounded_rect(x, y, w, h, r):
    """Скруглений прямокутник для товстих брусків і плит."""
    o = r * K
    return [
        move(x + r, y),
        line(x + w - r, y),
        curve(x + w - r + o, y, x + w, y + r - o, x + w, y + r),
        line(x + w, y + h - r),
        curve(x + w, y + h - r + o, x + w - r + o, y + h, x + w - r, y + h),
        line(x + r, y + h),
        curve(x + r - o, y + h, x, y + h - r + o, x, y + h - r),
        line(x, y + r),
        curve(x, y + r - o, x + r - o, y, x + r, y),
        close(),
    ]


def flat(groups):
    """Зливає кілька підшляхів в один шлях для однієї even-odd заливки."""
    return [command for group in groups for command in group]


# ---- Набір. Кожна іконка — (штрихи, заливки, even-odd заливки). У третьому живе суцільний
# стиль: один шлях, де внутрішні форми вирізають дірки в зовнішній.

ICONS: dict[str, tuple] = {}


def icon(name, stroke=None, fill=None, punch=None, doc=""):
    ICONS[name] = (stroke or [], fill or [], punch or [], doc)


# ---- Категорії: гліфи на плитках, пінах і плейсхолдерах подій без фото

icon(
    "music",
    stroke=[
        circle(8.5, 16.5, 3.0),
        [move(11.5, 16.5), line(11.5, 4.5)],
        [move(11.5, 4.5), curve(14.5, 5.0, 18.0, 6.5, 18.0, 10.5)],
    ],
    doc="Восьма нота: кільце головки, стебло і прапорець однією кривою.",
)

icon(
    "sport",
    stroke=[
        [move(6.5, 3.5), line(6.5, 20.5)],
        [move(6.5, 4.5), line(18.5, 8.2), line(6.5, 11.9), close()],
    ],
    doc="Вимпел на держаку. М'яч був би третім колом у наборі.",
)

icon(
    "art",
    stroke=[[move(4.0, 20.0), line(9.8, 14.2)]],
    fill=[
        [
            move(8.4, 15.6),
            curve(8.6, 10.6, 13.6, 5.0, 20.6, 3.4),
            curve(19.0, 10.4, 13.4, 15.4, 8.4, 15.6),
            close(),
        ]
    ],
    doc="Пензель: короткий держак і великий лист щетини. Голова займає пів гліфа, інакше на піні лишається сама риска.",
)

icon(
    "food",
    stroke=[
        [move(9.5, 8.5), curve(9.5, 7.0, 11.0, 6.5, 11.0, 4.5)],
        [move(14.0, 8.5), curve(14.0, 7.0, 15.5, 6.5, 15.5, 4.5)],
        [move(4.0, 11.5), line(20.0, 11.5)],
        [move(4.5, 11.5), curve(4.5, 16.5, 7.8, 20.0, 12.0, 20.0), curve(16.2, 20.0, 19.5, 16.5, 19.5, 11.5)],
    ],
    doc="Миска під двома завитками пари.",
)

icon(
    "games",
    stroke=[rounded_rect(4.5, 4.5, 15.0, 15.0, 3.6)],
    fill=[circle(8.6, 8.6, 1.35), circle(12.0, 12.0, 1.35), circle(15.4, 15.4, 1.35)],
    doc="Гральний кубик контуром із трьома очками по діагоналі.",
)

icon(
    "outdoors",
    stroke=[
        [
            move(12.0, 3.5),
            line(7.5, 10.8),
            line(9.6, 10.8),
            line(5.0, 17.5),
            line(19.0, 17.5),
            line(14.4, 10.8),
            line(16.5, 10.8),
            close(),
        ],
        [move(12.0, 17.5), line(12.0, 20.5)],
    ],
    doc="Ялина двома ярусами і стовбур.",
)

icon(
    "social",
    stroke=[
        circle(9.0, 8.0, 3.3),
        [move(3.5, 20.0), curve(3.5, 15.6, 6.0, 13.3, 9.0, 13.3), curve(12.0, 13.3, 14.5, 15.6, 14.5, 20.0)],
        [move(15.0, 5.3), curve(17.0, 5.8, 18.3, 7.3, 18.3, 9.0), curve(18.3, 10.2, 17.8, 11.1, 17.0, 11.7)],
        [move(16.5, 13.6), curve(19.0, 14.2, 20.5, 16.5, 20.5, 20.0)],
    ],
    doc="Дві фігури одна за одною: друга лише контуром за плечем першої.",
)

icon(
    "comedy",
    stroke=[
        rounded_rect(9.5, 3.0, 5.0, 10.0, 2.5),
        [move(6.8, 10.0), curve(6.8, 13.2, 9.1, 15.5, 12.0, 15.5), curve(14.9, 15.5, 17.2, 13.2, 17.2, 10.0)],
        [move(12.0, 15.5), line(12.0, 19.5)],
        [move(8.8, 19.5), line(15.2, 19.5)],
    ],
    doc="Мікрофон: капсула, тримач, стійка.",
)

icon(
    "kids",
    stroke=[
        circle(12.0, 8.8, 5.3),
        [move(12.0, 14.1), line(11.0, 15.6), line(13.0, 15.6), close()],
        [move(12.0, 15.6), curve(12.0, 17.6, 13.8, 18.4, 13.8, 20.5)],
    ],
    doc="Кулька на нитці з вузликом.",
)

icon(
    "tours",
    stroke=[
        [
            move(4.0, 20.5),
            line(4.0, 11.5),
            curve(4.0, 7.1, 7.6, 3.5, 12.0, 3.5),
            curve(16.4, 3.5, 20.0, 7.1, 20.0, 11.5),
            line(20.0, 20.5),
        ],
        [
            move(8.7, 20.5),
            line(8.7, 12.5),
            curve(8.7, 10.7, 10.2, 9.2, 12.0, 9.2),
            curve(13.8, 9.2, 15.3, 10.7, 15.3, 12.5),
            line(15.3, 20.5),
        ],
        [move(3.0, 20.5), line(21.0, 20.5)],
    ],
    doc="Брама зі склепінням і прорізом.",
)

icon(
    "conference",
    stroke=[
        rounded_rect(3.5, 4.0, 17.0, 12.0, 2.4),
        [move(7.5, 8.3), line(16.5, 8.3)],
        [move(7.5, 11.7), line(13.0, 11.7)],
        [move(12.0, 16.0), line(12.0, 19.5)],
        [move(8.5, 19.5), line(15.5, 19.5)],
    ],
    doc="Слайд на стійці з двома рядками різної довжини.",
)


# ---- Навігація

icon(
    "home",
    stroke=[
        [move(3.5, 11.5), line(12.0, 4.0), line(20.5, 11.5)],
        [move(5.7, 9.6), line(5.7, 20.0), line(18.3, 20.0), line(18.3, 9.6)],
        [move(10.0, 20.0), line(10.0, 14.5), line(14.0, 14.5), line(14.0, 20.0)],
    ],
    doc="Дах, стіни й двері трьома лініями.",
)

icon(
    "map",
    stroke=[
        [
            move(3.5, 6.0),
            line(9.0, 4.0),
            line(15.0, 6.5),
            line(20.5, 4.5),
            line(20.5, 18.0),
            line(15.0, 20.0),
            line(9.0, 17.5),
            line(3.5, 19.5),
            close(),
        ],
        [move(9.0, 4.0), line(9.0, 17.5)],
        [move(15.0, 6.5), line(15.0, 20.0)],
    ],
    doc="Складена мапа з двома згинами.",
)

icon(
    "calendar",
    stroke=[
        rounded_rect(3.5, 5.0, 17.0, 15.5, 3.0),
        [move(3.5, 10.0), line(20.5, 10.0)],
        [move(8.0, 3.0), line(8.0, 7.0)],
        [move(16.0, 3.0), line(16.0, 7.0)],
    ],
    fill=[circle(12.0, 15.0, 1.35)],
    doc="Сторінка з шапкою, двома вушками і крапкою сьогоднішнього дня.",
)

icon(
    "person",
    stroke=[
        circle(12.0, 8.0, 3.8),
        [move(4.5, 20.5), curve(4.5, 16.0, 7.8, 13.8, 12.0, 13.8), curve(16.2, 13.8, 19.5, 16.0, 19.5, 20.5)],
    ],
    doc="Голова й плечі, відкриті знизу, щоб стояти на базовій лінії.",
)

# ---- Дії

icon(
    "search",
    stroke=[circle(10.5, 10.5, 6.5), [move(15.3, 15.3), line(20.5, 20.5)]],
    doc="",
)

icon(
    "filters",
    stroke=[
        [move(4.0, 7.0), line(20.0, 7.0)],
        [move(4.0, 12.0), line(20.0, 12.0)],
        [move(4.0, 17.0), line(20.0, 17.0)],
    ],
    fill=[circle(9.0, 7.0, 1.9), circle(15.0, 12.0, 1.9), circle(11.0, 17.0, 1.9)],
    doc="Три повзунки: налаштування, а не лійка.",
)

icon(
    "bookmark",
    stroke=[[move(6.0, 3.5), line(18.0, 3.5), line(18.0, 20.5), line(12.0, 15.8), line(6.0, 20.5), close()]],
    doc="",
)

icon(
    "bookmarkFilled",
    fill=[[move(6.0, 3.5), line(18.0, 3.5), line(18.0, 20.5), line(12.0, 15.8), line(6.0, 20.5), close()]],
    doc="Збережено: та сама закладка, залита.",
)

icon(
    "plus",
    stroke=[[move(12.0, 5.0), line(12.0, 19.0)], [move(5.0, 12.0), line(19.0, 12.0)]],
    doc="",
)

icon(
    "pin",
    stroke=[
        [
            move(12.0, 21.0),
            curve(12.0, 21.0, 4.8, 13.6, 4.8, 9.4),
            curve(4.8, 5.4, 8.0, 2.8, 12.0, 2.8),
            curve(16.0, 2.8, 19.2, 5.4, 19.2, 9.4),
            curve(19.2, 13.6, 12.0, 21.0, 12.0, 21.0),
            close(),
        ],
        circle(12.0, 9.4, 2.8),
    ],
    doc="Знак застосунку: крапля з кільцем, у гліфі — контуром.",
)

icon(
    "myLocation",
    stroke=[
        circle(12.0, 12.0, 5.5),
        [move(12.0, 2.5), line(12.0, 5.0)],
        [move(12.0, 19.0), line(12.0, 21.5)],
        [move(2.5, 12.0), line(5.0, 12.0)],
        [move(19.0, 12.0), line(21.5, 12.0)],
    ],
    fill=[circle(12.0, 12.0, 1.8)],
    doc="Кільце навколо крапки з чотирма рисками. Крапка каже «ви».",
)

icon(
    "recenter",
    stroke=[
        [move(3.5, 9.0), line(3.5, 5.8), curve(3.5, 4.5, 4.5, 3.5, 5.8, 3.5), line(9.0, 3.5)],
        [move(15.0, 3.5), line(18.2, 3.5), curve(19.5, 3.5, 20.5, 4.5, 20.5, 5.8), line(20.5, 9.0)],
        [move(20.5, 15.0), line(20.5, 18.2), curve(20.5, 19.5, 19.5, 20.5, 18.2, 20.5), line(15.0, 20.5)],
        [move(9.0, 20.5), line(5.8, 20.5), curve(4.5, 20.5, 3.5, 19.5, 3.5, 18.2), line(3.5, 15.0)],
    ],
    fill=[circle(12.0, 12.0, 2.2)],
    doc="Чотири дужки навколо крапки: повернути місто в кадр.",
)

icon(
    "sparkle",
    stroke=[
        [
            move(12.0, 3.0),
            curve(12.8, 8.6, 15.4, 11.2, 21.0, 12.0),
            curve(15.4, 12.8, 12.8, 15.4, 12.0, 21.0),
            curve(11.2, 15.4, 8.6, 12.8, 3.0, 12.0),
            curve(8.6, 11.2, 11.2, 8.6, 12.0, 3.0),
            close(),
        ]
    ],
    doc="Чотирикутна зірка з увігнутими боками, контуром.",
)

icon(
    "lock",
    stroke=[
        [move(8.0, 10.5), line(8.0, 8.0), curve(8.0, 5.8, 9.8, 4.0, 12.0, 4.0), curve(14.2, 4.0, 16.0, 5.8, 16.0, 8.0), line(16.0, 10.5)],
        rounded_rect(4.5, 10.5, 15.0, 10.0, 3.0),
    ],
    fill=[circle(12.0, 15.5, 1.5)],
    doc="Замок: дужка, корпус, крапка шпарини.",
)

icon(
    "checkCircle",
    stroke=[circle(12, 12, 8.5), polyline(8.2, 12.3, 10.9, 15.0, 15.9, 9.5)],
    doc="",
)

icon(
    "alert",
    stroke=[circle(12, 12, 8.5), [move(12.0, 7.5), line(12.0, 13.0)]],
    fill=[circle(12.0, 16.4, 1.25)],
    doc="",
)

icon(
    "clock",
    stroke=[circle(12, 12, 8.5), polyline(12.0, 7.5, 12.0, 12.0, 15.4, 14.1)],
    doc="",
)

icon(
    "queue",
    stroke=[
        [move(7.0, 3.5), line(17.0, 3.5)],
        [move(7.0, 20.5), line(17.0, 20.5)],
        [move(8.5, 3.5), line(8.5, 7.0), curve(8.5, 10.0, 12.0, 11.0, 12.0, 12.0), curve(12.0, 13.0, 8.5, 14.0, 8.5, 17.0), line(8.5, 20.5)],
        [move(15.5, 3.5), line(15.5, 7.0), curve(15.5, 10.0, 12.0, 11.0, 12.0, 12.0), curve(12.0, 13.0, 15.5, 14.0, 15.5, 17.0), line(15.5, 20.5)],
    ],
    doc="Пісочний годинник для черги: час минає, а не помилка.",
)


# ---- Службові гліфи: стрілки, галочка, хрестик, дії. Той самий набір на обох платформах замість
# Material Icons і SF Symbols, щоб іконка не мінялась стилем між екранами й платформами.

icon("chevronRight", stroke=[polyline(9.5, 6.0, 15.5, 12.0, 9.5, 18.0)], doc="")
icon("chevronLeft", stroke=[polyline(14.5, 6.0, 8.5, 12.0, 14.5, 18.0)], doc="«Назад».")
icon("chevronDown", stroke=[polyline(6.0, 9.5, 12.0, 15.5, 18.0, 9.5)], doc="")
icon("chevronUp", stroke=[polyline(6.0, 14.5, 12.0, 8.5, 18.0, 14.5)], doc="")
icon("check", stroke=[polyline(5.0, 12.5, 9.8, 17.3, 19.0, 8.0)], doc="")
icon("close", stroke=[[move(6.0, 6.0), line(18.0, 18.0)], [move(18.0, 6.0), line(6.0, 18.0)]], doc="")
icon(
    "closeCircle",
    stroke=[circle(12, 12, 8.5), [move(8.8, 8.8), line(15.2, 15.2)], [move(15.2, 8.8), line(8.8, 15.2)]],
    doc="Очистити поле, скасувати.",
)
icon("minus", stroke=[[move(5.0, 12.0), line(19.0, 12.0)]], doc="")
icon("arrowRight", stroke=[[move(4.5, 12.0), line(19.5, 12.0)], polyline(13.5, 6.0, 19.5, 12.0, 13.5, 18.0)], doc="")
icon("arrowUp", stroke=[[move(12.0, 19.5), line(12.0, 4.5)], polyline(6.0, 10.5, 12.0, 4.5, 18.0, 10.5)], doc="Надіслати.")
icon(
    "share",
    stroke=[
        polyline(8.5, 9.5, 5.5, 9.5, 5.5, 20.0, 18.5, 20.0, 18.5, 9.5, 15.5, 9.5),
        [move(12.0, 14.5), line(12.0, 3.5)],
        polyline(8.5, 7.0, 12.0, 3.5, 15.5, 7.0),
    ],
    doc="Стрілка з коробки вгору: «поділитися» однаково на обох платформах.",
)
icon(
    "directions",
    stroke=[[move(5.0, 20.0), line(5.0, 13.0), curve(5.0, 11.9, 5.9, 11.0, 7.0, 11.0), line(18.5, 11.0)], polyline(14.0, 6.5, 18.5, 11.0, 14.0, 15.5)],
    doc="Маршрут: поворот угору й праворуч.",
)
icon(
    "chat",
    stroke=[rounded_rect(3.5, 4.5, 17.0, 12.5, 3.5), polyline(8.0, 17.0, 8.0, 20.5, 12.0, 17.0)],
    doc="Бульбашка з хвостиком.",
)
icon(
    "mail",
    stroke=[rounded_rect(3.5, 5.5, 17.0, 13.0, 2.5), polyline(4.5, 7.5, 12.0, 13.0, 19.5, 7.5)],
    doc="",
)
icon(
    "bell",
    stroke=[
        [
            move(6.0, 16.5), line(18.0, 16.5), line(16.8, 14.5), line(16.8, 10.5),
            curve(16.8, 7.6, 14.7, 5.3, 12.0, 5.3), curve(9.3, 5.3, 7.2, 7.6, 7.2, 10.5), line(7.2, 14.5), close(),
        ],
        [move(10.3, 19.2), curve(10.7, 20.2, 11.3, 20.5, 12.0, 20.5), curve(12.7, 20.5, 13.3, 20.2, 13.7, 19.2)],
    ],
    doc="",
)
icon(
    "bellActive",
    stroke=[
        [
            move(6.0, 16.5), line(18.0, 16.5), line(16.8, 14.5), line(16.8, 10.5),
            curve(16.8, 7.6, 14.7, 5.3, 12.0, 5.3), curve(9.3, 5.3, 7.2, 7.6, 7.2, 10.5), line(7.2, 14.5), close(),
        ],
        [move(10.3, 19.2), curve(10.7, 20.2, 11.3, 20.5, 12.0, 20.5), curve(12.7, 20.5, 13.3, 20.2, 13.7, 19.2)],
        [move(3.5, 9.5), curve(3.5, 7.3, 4.4, 5.6, 5.8, 4.3)],
        [move(20.5, 9.5), curve(20.5, 7.3, 19.6, 5.6, 18.2, 4.3)],
    ],
    doc="Той самий дзвінок з двома дугами: сповіщення увімкнено.",
)
icon(
    "edit",
    stroke=[[move(4.0, 20.0), line(4.4, 16.2), line(15.8, 4.8), line(19.2, 8.2), line(7.8, 19.6), close()], [move(13.4, 7.2), line(16.8, 10.6)]],
    doc="Олівець.",
)
icon("star", stroke=[polyline(12.0, 4.0, 14.17, 9.61, 20.18, 9.94, 15.52, 13.74, 17.05, 19.56, 12.0, 16.3, 6.95, 19.56, 8.48, 13.74, 3.82, 9.94, 9.83, 9.61) + [close()]], doc="Оцінка.")
icon(
    "shield",
    stroke=[[move(12.0, 3.5), line(19.5, 6.5), line(19.5, 12.0), curve(19.5, 16.5, 16.5, 19.5, 12.0, 21.0), curve(7.5, 19.5, 4.5, 16.5, 4.5, 12.0), line(4.5, 6.5), close()]],
    doc="Безпека.",
)
icon(
    "trash",
    stroke=[
        [move(4.0, 7.0), line(20.0, 7.0)],
        polyline(9.5, 7.0, 9.5, 4.5, 14.5, 4.5, 14.5, 7.0),
        polyline(6.0, 7.0, 6.8, 20.0, 17.2, 20.0, 18.0, 7.0),
        [move(10.0, 10.5), line(10.2, 16.5)],
        [move(14.0, 10.5), line(13.8, 16.5)],
    ],
    doc="",
)


# ---- Ще службові: поодинокі іконки екранів, щоб жодна платформна не лишилась.

icon("personAdd", stroke=[circle(9.0, 8.0, 3.3), [move(3.5, 20.0), curve(3.5, 15.6, 6.0, 13.3, 9.0, 13.3), curve(12.0, 13.3, 14.5, 15.6, 14.5, 20.0)], [move(18.5, 9.0), line(18.5, 15.0)], [move(15.5, 12.0), line(21.5, 12.0)]], doc="Людина з плюсом: запит на участь.")
icon(
    "calendarAlert",
    stroke=[rounded_rect(3.5, 5.0, 17.0, 15.5, 2.5), [move(3.5, 9.5), line(20.5, 9.5)], [move(8.0, 3.0), line(8.0, 6.5)], [move(16.0, 3.0), line(16.0, 6.5)], [move(12.0, 12.0), line(12.0, 15.5)]],
    fill=[circle(12.0, 18.0, 1.1)],
    doc="Календар зі знаком оклику: подій нема або скасовано.",
)
icon(
    "ticket",
    stroke=[[move(3.5, 9.0), line(3.5, 6.5), line(20.5, 6.5), line(20.5, 9.0), curve(18.8, 9.0, 17.5, 10.3, 17.5, 12.0), curve(17.5, 13.7, 18.8, 15.0, 20.5, 15.0), line(20.5, 17.5), line(3.5, 17.5), line(3.5, 15.0), curve(5.2, 15.0, 6.5, 13.7, 6.5, 12.0), curve(6.5, 10.3, 5.2, 9.0, 3.5, 9.0), close()], [move(12.0, 6.5), line(12.0, 17.5)]],
    doc="Квиток з вирізами й перфорацією.",
)
icon("signOut", stroke=[polyline(13.0, 4.0, 5.0, 4.0, 5.0, 20.0, 13.0, 20.0), [move(9.5, 12.0), line(20.0, 12.0)], polyline(16.5, 8.5, 20.0, 12.0, 16.5, 15.5)], doc="Вихід: стрілка з рамки.")
icon("enter", stroke=[[move(3.5, 12.0), line(14.0, 12.0)], polyline(10.5, 8.5, 14.0, 12.0, 10.5, 15.5), [move(18.5, 5.0), line(18.5, 19.0)]], doc="Стрілка до лінії: перейти на джерело.")
icon(
    "link",
    stroke=[
        [move(10.0, 14.0), line(14.0, 10.0)],
        [move(8.5, 11.0), line(6.0, 13.5), curve(4.0, 15.5, 4.0, 18.0, 6.0, 19.5), curve(7.5, 21.0, 10.0, 21.0, 12.0, 19.0), line(13.5, 17.5)],
        [move(15.5, 13.0), line(18.0, 10.5), curve(20.0, 8.5, 20.0, 6.0, 18.0, 4.5), curve(16.5, 3.0, 14.0, 3.0, 12.0, 5.0), line(10.5, 6.5)],
    ],
    doc="Дві ланки.",
)
icon(
    "hand",
    stroke=[[move(6.5, 12.5), line(6.5, 6.5), curve(6.5, 5.7, 7.2, 5.0, 8.0, 5.0), curve(8.8, 5.0, 9.5, 5.7, 9.5, 6.5), line(9.5, 4.5), curve(9.5, 3.7, 10.2, 3.0, 11.0, 3.0), curve(11.8, 3.0, 12.5, 3.7, 12.5, 4.5), line(12.5, 5.5), curve(12.5, 4.7, 13.2, 4.0, 14.0, 4.0), curve(14.8, 4.0, 15.5, 4.7, 15.5, 5.5), line(15.5, 8.0), curve(15.5, 7.2, 16.2, 6.5, 17.0, 6.5), curve(17.8, 6.5, 18.5, 7.2, 18.5, 8.0), line(18.5, 14.0), curve(18.5, 18.0, 15.5, 21.0, 11.5, 21.0), curve(8.5, 21.0, 6.5, 19.5, 5.0, 16.5), line(3.8, 13.8), curve(3.4, 13.0, 3.8, 12.2, 4.6, 12.0), curve(5.4, 11.8, 6.1, 12.1, 6.5, 12.5), close()]],
    doc="Піднята долоня: модерація, скарга.",
)
icon("globe", stroke=[circle(12, 12, 8.5), [move(3.5, 12.0), line(20.5, 12.0)], [move(12.0, 3.5), curve(8.5, 7.0, 8.5, 17.0, 12.0, 20.5)], [move(12.0, 3.5), curve(15.5, 7.0, 15.5, 17.0, 12.0, 20.5)]], doc="Куля з меридіанами: усюди.")
icon("doc", stroke=[[move(6.0, 3.5), line(14.0, 3.5), line(19.0, 8.5), line(19.0, 20.5), line(6.0, 20.5), close()], polyline(14.0, 3.5, 14.0, 8.5, 19.0, 8.5), [move(9.0, 12.5), line(16.0, 12.5)], [move(9.0, 16.0), line(16.0, 16.0)]], doc="Аркуш із загнутим кутом: документ.")
icon("refresh", stroke=[[move(19.5, 12.0), curve(19.5, 7.9, 16.1, 4.5, 12.0, 4.5), curve(9.3, 4.5, 6.9, 5.9, 5.6, 8.0)], [move(4.5, 12.0), curve(4.5, 16.1, 7.9, 19.5, 12.0, 19.5), curve(14.7, 19.5, 17.1, 18.1, 18.4, 16.0)], polyline(5.0, 3.5, 5.6, 8.0, 10.0, 7.5), polyline(19.0, 20.5, 18.4, 16.0, 14.0, 16.5)], doc="Дві дуги зі стрілками.")
icon("wifiOff", stroke=[[move(3.0, 9.0), curve(5.0, 7.2, 7.5, 6.0, 10.3, 5.6)], [move(14.5, 5.8), curve(17.0, 6.3, 19.2, 7.4, 21.0, 9.0)], [move(6.0, 12.5), curve(7.3, 11.4, 8.9, 10.6, 10.7, 10.3)], [move(15.0, 10.8), curve(16.1, 11.2, 17.1, 11.8, 18.0, 12.5)], [move(9.0, 16.0), curve(9.8, 15.3, 10.9, 14.9, 12.0, 14.9), curve(13.1, 14.9, 14.2, 15.3, 15.0, 16.0)], [move(4.0, 4.0), line(20.0, 20.0)]], fill=[circle(12.0, 19.2, 1.3)], doc="Хвилі, перекреслені: звʼязку нема.")
icon("eye", stroke=[[move(2.5, 12.0), curve(5.0, 7.5, 8.3, 5.5, 12.0, 5.5), curve(15.7, 5.5, 19.0, 7.5, 21.5, 12.0), curve(19.0, 16.5, 15.7, 18.5, 12.0, 18.5), curve(8.3, 18.5, 5.0, 16.5, 2.5, 12.0), close()], circle(12.0, 12.0, 3.2)], doc="Показати пароль.")
icon("eyeOff", stroke=[[move(2.5, 12.0), curve(5.0, 7.5, 8.3, 5.5, 12.0, 5.5), curve(15.7, 5.5, 19.0, 7.5, 21.5, 12.0), curve(19.0, 16.5, 15.7, 18.5, 12.0, 18.5), curve(8.3, 18.5, 5.0, 16.5, 2.5, 12.0), close()], circle(12.0, 12.0, 3.2), [move(4.0, 20.0), line(20.0, 4.0)]], doc="Сховати пароль.")
icon("subway", stroke=[rounded_rect(5.0, 3.5, 14.0, 14.0, 3.0), [move(5.0, 11.0), line(19.0, 11.0)], [move(8.5, 17.5), line(6.5, 20.5)], [move(15.5, 17.5), line(17.5, 20.5)]], fill=[circle(8.5, 14.0, 1.2), circle(15.5, 14.0, 1.2)], doc="Вагон метро: укриття в підземці.")
icon("camera", stroke=[[move(3.5, 8.5), line(8.0, 8.5), line(9.5, 5.5), line(14.5, 5.5), line(16.0, 8.5), line(20.5, 8.5), line(20.5, 19.0), line(3.5, 19.0), close()], circle(12.0, 13.5, 3.2)], doc="Фотоапарат: обкладинка події.")
icon("moon", stroke=[[move(13.5, 3.5), curve(9.0, 4.5, 6.0, 8.5, 6.0, 12.5), curve(6.0, 17.2, 9.8, 21.0, 14.5, 21.0), curve(17.0, 21.0, 19.2, 19.9, 20.8, 18.2), curve(15.0, 18.0, 11.0, 13.0, 13.5, 3.5), close()]], fill=[circle(18.5, 6.5, 1.0), circle(20.5, 10.5, 0.8)], doc="Місяць із зірками: комендантська година.")
icon("flag", stroke=[[move(5.5, 21.0), line(5.5, 3.5)], [move(5.5, 4.5), line(18.5, 4.5), line(15.0, 9.0), line(18.5, 13.5), line(5.5, 13.5)]], doc="Прапорець: поскаржитись.")
icon("copy", stroke=[rounded_rect(8.5, 8.5, 12.0, 12.0, 2.0), [move(5.5, 15.5), curve(4.4, 15.5, 3.5, 14.6, 3.5, 13.5), line(3.5, 5.5), curve(3.5, 4.4, 4.4, 3.5, 5.5, 3.5), line(13.5, 3.5), curve(14.6, 3.5, 15.5, 4.4, 15.5, 5.5)]], doc="Два аркуші: скопіювати.")
icon("cloudOff", stroke=[[move(7.0, 18.5), curve(4.5, 18.5, 3.0, 16.8, 3.0, 14.7), curve(3.0, 12.6, 4.6, 11.0, 6.7, 10.8), curve(7.3, 7.9, 9.8, 6.0, 12.5, 6.0), curve(15.0, 6.0, 17.2, 7.5, 18.1, 9.8), curve(19.9, 10.3, 21.0, 11.9, 21.0, 13.8), curve(21.0, 16.4, 18.9, 18.5, 16.3, 18.5), line(7.0, 18.5)], [move(4.0, 4.0), line(20.0, 20.0)]], doc="Хмара, перекреслена: сервер не відповів.")
icon("block", stroke=[circle(12, 12, 8.5), [move(6.0, 6.0), line(18.0, 18.0)]], doc="Коло з рискою: заблокувати.")
icon("compass", stroke=[circle(12, 12, 8.5), [move(15.5, 8.5), line(13.5, 13.5), line(8.5, 15.5), line(10.5, 10.5), close()]], doc="Компас: знайти на мапі.")
icon("starFilled", fill=[polyline(12.0, 4.0, 14.17, 9.61, 20.18, 9.94, 15.52, 13.74, 17.05, 19.56, 12.0, 16.3, 6.95, 19.56, 8.48, 13.74, 3.82, 9.94, 9.83, 9.61) + [close()]], doc="Оцінка, поставлена.")

icon("arrowLeft", stroke=[[move(19.5, 12.0), line(4.5, 12.0)], polyline(10.5, 6.0, 4.5, 12.0, 10.5, 18.0)], doc="«Назад» у шапці.")
icon("signIn", stroke=[polyline(11.0, 4.0, 19.0, 4.0, 19.0, 20.0, 11.0, 20.0), [move(3.5, 12.0), line(14.0, 12.0)], polyline(10.5, 8.5, 14.0, 12.0, 10.5, 15.5)], doc="Вхід: стрілка в рамку.")


# ---- Генератори коду


def n(value):
    """Прибирає шум float після обчислення кола."""
    return f"{round(value, 3):g}"


def kotlin_commands(subpaths, indent):
    out = []
    pad = " " * indent
    for sub in subpaths:
        for op, args in sub:
            if op == "M":
                out.append(f"{pad}moveTo({n(args[0])}f, {n(args[1])}f)")
            elif op == "L":
                out.append(f"{pad}lineTo({n(args[0])}f, {n(args[1])}f)")
            elif op == "C":
                nums = ", ".join(f"{n(a)}f" for a in args)
                out.append(f"{pad}curveTo({nums})")
            else:
                out.append(f"{pad}close()")
    return "\n".join(out)


def write_kotlin():
    parts = [
        "package app.poruch.android.ui",
        "",
        "import androidx.compose.ui.graphics.Color",
        "import androidx.compose.ui.graphics.PathFillType",
        "import androidx.compose.ui.graphics.SolidColor",
        "import androidx.compose.ui.graphics.StrokeCap",
        "import androidx.compose.ui.graphics.StrokeJoin",
        "import androidx.compose.ui.graphics.vector.ImageVector",
        "import androidx.compose.ui.graphics.vector.path",
        "import androidx.compose.ui.unit.dp",
        "",
        "/**",
        " * Власні гліфи застосунку: тонка лінія на сітці 24, заливка лише для крапок.",
        " *",
        " * ЗГЕНЕРОВАНО tools/generate_icons.py: геометрію правити там, інакше Swift-двійник у",
        " * DesignSystem/PoruchIcons.swift розійдеться з цим файлом.",
        " *",
        " * Усе чорне: `Icon(tint = …)` перефарбовує весь вектор.",
        " */",
        "object PoruchIcons {",
    ]
    for name, (stroke, fill, punch, doc) in ICONS.items():
        if doc:
            parts.append(f"    /** {doc} */")
        parts.append(f"    val {name}: ImageVector by lazy {{")
        parts.append(f'        builder("{name}")')
        if punch:
            parts.append("            .punch {")
            parts.append(kotlin_commands(punch, 16))
            parts.append("            }")
        if fill:
            parts.append("            .fill {")
            parts.append(kotlin_commands(fill, 16))
            parts.append("            }")
        if stroke:
            parts.append("            .stroke {")
            parts.append(kotlin_commands(stroke, 16))
            parts.append("            }")
        parts.append("            .build()")
        parts.append("    }")
        parts.append("")
    parts += [
        "    private fun builder(name: String) =",
        '        ImageVector.Builder("Poruch.$name", SIZE.dp, SIZE.dp, SIZE, SIZE)',
        "",
        "    private inline fun ImageVector.Builder.stroke(block: androidx.compose.ui.graphics.vector.PathBuilder.() -> Unit) =",
        "        path(",
        "            stroke = SolidColor(Color.Black), strokeLineWidth = STROKE,",
        "            strokeLineCap = StrokeCap.Round, strokeLineJoin = StrokeJoin.Round,",
        "            pathBuilder = block",
        "        )",
        "",
        "    private inline fun ImageVector.Builder.fill(block: androidx.compose.ui.graphics.vector.PathBuilder.() -> Unit) =",
        "        path(fill = SolidColor(Color.Black), pathBuilder = block)",
        "",
        "    /** Один шлях, де внутрішні підшляхи вирізають дірки в зовнішньому. */",
        "    private inline fun ImageVector.Builder.punch(block: androidx.compose.ui.graphics.vector.PathBuilder.() -> Unit) =",
        "        path(fill = SolidColor(Color.Black), pathFillType = PathFillType.EvenOdd, pathBuilder = block)",
        "}",
        "",
        "private const val SIZE = 24f",
        "private const val STROKE = 1.75f",
        "",
    ]
    (ROOT / "androidApp/src/main/java/app/poruch/android/ui/PoruchIcons.kt").write_text(
        "\n".join(parts), encoding="utf-8"
    )


def swift_commands(subpaths, indent):
    out = []
    pad = " " * indent
    for sub in subpaths:
        for op, args in sub:
            if op == "M":
                out.append(f"{pad}path.move(to: point({n(args[0])}, {n(args[1])}, s))")
            elif op == "L":
                out.append(f"{pad}path.addLine(to: point({n(args[0])}, {n(args[1])}, s))")
            elif op == "C":
                out.append(
                    f"{pad}path.addCurve(to: point({n(args[4])}, {n(args[5])}, s), "
                    f"control1: point({n(args[0])}, {n(args[1])}, s), control2: point({n(args[2])}, {n(args[3])}, s))"
                )
            else:
                out.append(f"{pad}path.closeSubpath()")
    return "\n".join(out)


def write_swift():
    parts = [
        "import SwiftUI",
        "",
        "/// Власні гліфи застосунку: тонка лінія на сітці 24, заливка лише для крапок.",
        "///",
        "/// ЗГЕНЕРОВАНО tools/generate_icons.py: геометрію правити там, інакше Kotlin-двійник у",
        "/// ui/PoruchIcons.kt розійдеться з цим файлом.",
        "///",
        "/// Гліф без кольору: `PoruchIcon` малює поточним foreground, тож `.foregroundStyle(…)` працює як для SF Symbol.",
        "struct PoruchGlyph {",
        "    let stroke: ((inout Path, CGFloat) -> Void)?",
        "    let fill: ((inout Path, CGFloat) -> Void)?",
        "    /// Один шлях, де внутрішні підшляхи вирізають дірки в зовнішньому.",
        "    let punch: ((inout Path, CGFloat) -> Void)?",
        "",
        "    init(",
        "        stroke: ((inout Path, CGFloat) -> Void)? = nil,",
        "        fill: ((inout Path, CGFloat) -> Void)? = nil,",
        "        punch: ((inout Path, CGFloat) -> Void)? = nil",
        "    ) {",
        "        self.stroke = stroke",
        "        self.fill = fill",
        "        self.punch = punch",
        "    }",
        "}",
        "",
        "enum PoruchIcons {",
    ]
    for name, (stroke, fill, punch, doc) in ICONS.items():
        if doc:
            parts.append(f"    /// {doc}")
        parts.append(f"    static let {name} = PoruchGlyph(")
        pieces = []
        if stroke:
            pieces.append("        stroke: { path, s in\n" + swift_commands(stroke, 12) + "\n        }")
        if fill:
            pieces.append("        fill: { path, s in\n" + swift_commands(fill, 12) + "\n        }")
        if punch:
            pieces.append("        punch: { path, s in\n" + swift_commands(punch, 12) + "\n        }")
        parts.append(",\n".join(pieces))
        parts.append("    )")
        parts.append("")
    parts += [
        "}",
        "",
        "private func point(_ x: CGFloat, _ y: CGFloat, _ s: CGFloat) -> CGPoint {",
        "    CGPoint(x: x * s, y: y * s)",
        "}",
        "",
        "/// Малює `PoruchGlyph` заданого розміру, масштабуючи сітку 24 разом зі штрихом.",
        "struct PoruchIcon: View {",
        "    let glyph: PoruchGlyph",
        "    var size: CGFloat = 20",
        "",
        "    var body: some View {",
        "        ZStack {",
        "            if glyph.punch != nil {",
        "                GlyphShape(draw: glyph.punch).fill(style: FillStyle(eoFill: true))",
        "            }",
        "            if glyph.fill != nil {",
        "                GlyphShape(draw: glyph.fill).fill()",
        "            }",
        "            if glyph.stroke != nil {",
        "                GlyphShape(draw: glyph.stroke).stroke(style: StrokeStyle(",
        "                    lineWidth: PoruchIconMetrics.stroke * scale,",
        "                    lineCap: .round, lineJoin: .round",
        "                ))",
        "            }",
        "        }",
        "        .frame(width: size, height: size)",
        "    }",
        "",
        "    private var scale: CGFloat { size / PoruchIconMetrics.grid }",
        "}",
        "",
        "private struct GlyphShape: Shape {",
        "    let draw: ((inout Path, CGFloat) -> Void)?",
        "",
        "    func path(in rect: CGRect) -> Path {",
        "        var path = Path()",
        "        guard let draw else { return path }",
        "        draw(&path, min(rect.width, rect.height) / PoruchIconMetrics.grid)",
        "        return path",
        "    }",
        "}",
        "",
        "enum PoruchIconMetrics {",
        "    static let grid: CGFloat = 24",
        "    static let stroke: CGFloat = 1.75",
        "}",
        "",
    ]
    (ROOT / "iosApp/Poruch/DesignSystem/PoruchIcons.swift").write_text("\n".join(parts), encoding="utf-8")


if __name__ == "__main__":
    write_kotlin()
    write_swift()
    print(f"{len(ICONS)} icons → Kotlin + Swift")
