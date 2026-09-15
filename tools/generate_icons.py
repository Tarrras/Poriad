#!/usr/bin/env python3
"""Єдине джерело правди для іконок Poruch.

Іконки малюються тут на сітці 24 одиниці й генеруються в код обох платформ: Compose `ImageVector`
і SwiftUI `Shape`. Дві копії геометрії руками розходяться, а дуги легко намалювати криво.

    python3 tools/generate_icons.py

Стиль: суцільні форми з вирізаним негативним простором (even-odd), а не тонкі контури; вміст у
межах 3..21. Де без лінії не обійтись, це товстий штрих 2.6 із круглими кінцями. Колір не
запікається: усе чорне, платформа тонує сама.
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
    fill=[
        circle(8.9, 16.9, 3.5),
        rounded_rect(11.5, 5.0, 2.0, 12.2, 1.0),
        [
            move(13.5, 5.0),
            curve(16.9, 6.0, 19.0, 8.0, 19.0, 10.9),
            curve(19.0, 11.8, 18.8, 12.6, 18.3, 13.3),
            curve(18.5, 10.4, 16.7, 8.6, 13.5, 7.7),
            close(),
        ],
    ],
    doc="Суцільна восьма нота. Прапорець — півмісяць, а не гачок, щоб тримати вагу головки.",
)

icon(
    "sport",
    fill=[
        rounded_rect(5.9, 3.2, 2.0, 17.6, 1.0),
        [move(7.9, 4.4), line(19.4, 8.1), line(7.9, 12.6), close()],
    ],
    doc="Суцільний вимпел. М'яч був би третім колом у наборі, а шви на ньому читаються як обличчя.",
)

icon(
    "art",
    punch=[
        flat([
            circle(12, 12, 8.4),
            circle(8.6, 9.0, 1.75),
            circle(13.7, 7.9, 1.75),
            circle(16.2, 12.5, 1.75),
            circle(10.6, 15.9, 2.5),
        ])
    ],
    doc="Палітра: суцільний диск із чотирма вирізами, найбільший — для пальця.",
)

icon(
    "food",
    stroke=[
        [move(9.5, 8.5), curve(9.5, 7.0, 10.9, 6.5, 10.9, 4.9)],
        [move(14.1, 8.5), curve(14.1, 7.0, 15.5, 6.5, 15.5, 4.9)],
    ],
    fill=[
        [
            move(4.2, 11.0),
            line(19.8, 11.0),
            curve(19.8, 15.8, 16.3, 19.7, 12.0, 19.7),
            curve(7.7, 19.7, 4.2, 15.8, 4.2, 11.0),
            close(),
        ]
    ],
    doc="Миска під двома завитками пари. Прибори на такому розмірі — дві нерозрізнені палички.",
)

icon(
    "games",
    punch=[
        flat([
            rounded_rect(4.4, 4.4, 15.2, 15.2, 4.4),
            circle(9.1, 9.1, 1.7),
            circle(12.0, 12.0, 1.7),
            circle(14.9, 14.9, 1.7),
        ])
    ],
    doc="Гральний кубик на діагоналі з вирізаними очками. Геймпад не переживає зменшення до піна.",
)

icon(
    "outdoors",
    fill=[
        [
            move(12.0, 3.4),
            line(16.6, 11.2),
            line(14.5, 11.2),
            line(19.0, 18.2),
            line(5.0, 18.2),
            line(9.5, 11.2),
            line(7.4, 11.2),
            close(),
        ],
        rounded_rect(11.0, 17.6, 2.0, 3.2, 1.0),
    ],
    doc="Ялина двома ярусами. Один трикутник з перекладиною читається як літера A.",
)

icon(
    "social",
    fill=[
        circle(16.6, 9.4, 2.6),
        [
            move(21.0, 19.8),
            curve(21.0, 15.9, 19.1, 13.7, 16.6, 13.7),
            curve(15.5, 13.7, 14.6, 14.1, 13.8, 14.7),
            line(13.8, 19.8),
            close(),
        ],
        circle(9.3, 8.5, 3.4),
        [
            move(2.6, 19.8),
            curve(2.6, 15.5, 5.4, 13.1, 9.3, 13.1),
            curve(13.2, 13.1, 16.0, 15.5, 16.0, 19.8),
            close(),
        ],
    ],
    doc="Дві фігури одна за одною: зустріч, а не профіль.",
)

icon(
    "comedy",
    stroke=[
        # Тримач — єдина лінія, без якої не обійтись: суцільним він поглинув би капсулу.
        [
            move(6.9, 10.3),
            curve(6.9, 13.1, 9.2, 15.4, 12.0, 15.4),
            curve(14.8, 15.4, 17.1, 13.1, 17.1, 10.3),
        ],
    ],
    fill=[
        rounded_rect(9.4, 2.8, 5.2, 10.4, 2.6),      # the capsule head
        rounded_rect(11.2, 15.0, 1.6, 3.6, 0.8),     # the stem
        rounded_rect(8.4, 18.0, 7.2, 2.0, 1.0),      # the base bar
    ],
    doc="Мікрофон: капсула, тримач, стійка. Маска читалась би як театр, з якого комедію якраз виділили.",
)

icon(
    "kids",
    stroke=[
        # Нитка має бути лінією: суцільна перетворила б кульку на вишню.
        [
            move(12.0, 15.6),
            curve(12.0, 17.4, 13.6, 18.2, 13.6, 20.0),
        ],
    ],
    fill=[
        circle(12.0, 9.2, 6.0),
        # Вузлик між кулькою і ниткою.
        [
            move(10.6, 14.6),
            line(13.4, 14.6),
            line(12.0, 16.4),
            close(),
        ],
    ],
    doc="Кулька на нитці. Читається як «для дітей» і на розмірі піна, де ведмедик стає плямою.",
)

icon(
    "tours",
    punch=[
        flat([
            # Зовнішня арка.
            [
                move(3.4, 20.9),
                line(3.4, 11.5),
                curve(3.4, 6.8, 7.3, 3.0, 12.0, 3.0),
                curve(16.7, 3.0, 20.6, 6.8, 20.6, 11.5),
                line(20.6, 20.9),
                close(),
            ],
            # Проріз брами.
            [
                move(8.0, 20.9),
                line(8.0, 11.8),
                curve(8.0, 9.2, 9.8, 7.3, 12.0, 7.3),
                curve(14.2, 7.3, 16.0, 9.2, 16.0, 11.8),
                line(16.0, 20.9),
                close(),
            ],
        ])
    ],
    doc="Брама зі склепінням. Вимпел гіда на піні не відрізнити від «спорту».",
)

icon(
    "conference",
    punch=[
        flat(
            [rounded_rect(3.3, 3.3, 17.4, 12.5, 2.3)]
            # Два рядки тексту різної довжини: рівні читаються як пауза, один довгий — як перекреслення.
            + [rounded_rect(6.5, 6.9, 10.9, 1.8, 0.9), rounded_rect(6.5, 10.5, 7.1, 1.8, 0.9)]
        )
    ],
    fill=[
        rounded_rect(11.1, 15.8, 1.8, 3.3, 0.9),
        rounded_rect(7.3, 18.9, 9.4, 1.7, 0.85),
    ],
    doc="Слайд на стійці. Від календаря відрізняється широкою дошкою, довгими рядками й ніжкою.",
)


# ---- Навігація

icon(
    "home",
    punch=[
        flat([
            [
                move(12.0, 3.0),
                line(21.4, 11.6),
                line(18.7, 11.6),
                line(18.7, 20.8),
                line(5.3, 20.8),
                line(5.3, 11.6),
                line(2.6, 11.6),
                close(),
            ],
            rounded_rect(10.1, 14.4, 3.8, 6.4, 1.5),
        ])
    ],
    doc="Будинок із вирізаними дверима: без них силует — просто п'ятикутник.",
)

icon(
    "map",
    fill=[
        [move(3.2, 6.4), line(8.3, 4.2), line(8.3, 17.6), line(3.2, 19.8), close()],
        [move(9.5, 4.4), line(14.5, 6.8), line(14.5, 20.2), line(9.5, 17.8), close()],
        [move(15.7, 6.8), line(20.8, 4.4), line(20.8, 17.8), line(15.7, 20.2), close()],
    ],
    doc="Три панелі зі справжніми проміжками: лінії згину всередині однієї форми зникають на розмірі таббара.",
)

icon(
    "calendar",
    punch=[
        flat(
            [rounded_rect(3.4, 5.2, 17.2, 15.6, 3.6)]
            # Два ряди днів у нижній половині; смуга над ними — шапка. Три крапки читались як обличчя.
            + [
                rounded_rect(x, y, 2.2, 2.2, 0.7)
                for y in (12.2, 15.9)
                for x in (6.3, 10.9, 15.5)
            ]
        )
    ],
    fill=[rounded_rect(7.2, 2.2, 2.1, 4.6, 1.05), rounded_rect(14.7, 2.2, 2.1, 4.6, 1.05)],
    doc="Сторінка з вирізаною сіткою місяця під шапкою і двома вушками зверху.",
)

icon(
    "person",
    fill=[
        circle(12, 8.2, 3.7),
        [
            move(4.4, 20.6),
            curve(4.4, 16.2, 7.8, 13.7, 12.0, 13.7),
            curve(16.2, 13.7, 19.6, 16.2, 19.6, 20.6),
            close(),
        ],
    ],
    doc="Голова й плечі двома масами, відкриті знизу, щоб стояти на базовій лінії.",
)

# ---- Дії

icon(
    "search",
    stroke=[polyline(15.3, 15.3, 19.9, 19.9)],
    punch=[flat([circle(10.4, 10.4, 7.0), circle(10.4, 10.4, 4.0)])],
    doc="Товсте кільце й ручка. Кільце вирізане, а не обведене, щоб важити як сусідні гліфи.",
)

icon(
    "filters",
    fill=[
        rounded_rect(3.4, 5.9, 17.2, 2.5, 1.25),
        rounded_rect(6.1, 10.75, 11.8, 2.5, 1.25),
        rounded_rect(8.9, 15.6, 6.2, 2.5, 1.25),
    ],
    doc="Три плити, що звужуються: лійка, без повзунків Material.",
)

icon(
    "bookmark",
    punch=[
        flat([
            [move(5.2, 3.2), line(18.8, 3.2), line(18.8, 21.0), line(12.0, 15.9), line(5.2, 21.0), close()],
            [move(7.9, 5.9), line(16.1, 5.9), line(16.1, 15.6), line(12.0, 12.5), line(7.9, 15.6), close()],
        ])
    ],
    doc="Закладка з вирізаною серединою: незбережений стан важкий, але не суцільний.",
)

icon(
    "bookmarkFilled",
    fill=[[move(5.2, 3.2), line(18.8, 3.2), line(18.8, 21.0), line(12.0, 15.9), line(5.2, 21.0), close()]],
    doc="Збережено: та сама закладка, залита.",
)

icon(
    "plus",
    fill=[rounded_rect(10.65, 4.6, 2.7, 14.8, 1.35), rounded_rect(4.6, 10.65, 14.8, 2.7, 1.35)],
    doc="",
)

icon(
    "pin",
    punch=[
        flat([
            [
                move(12.0, 21.0),
                curve(12.0, 21.0, 4.6, 13.6, 4.6, 9.4),
                curve(4.6, 5.4, 7.9, 2.6, 12.0, 2.6),
                curve(16.1, 2.6, 19.4, 5.4, 19.4, 9.4),
                curve(19.4, 13.6, 12.0, 21.0, 12.0, 21.0),
                close(),
            ],
            circle(12.0, 9.4, 3.0),
        ])
    ],
    doc="Знак застосунку: іконка лаунчера, пін мапи і цей гліф — одна форма.",
)

icon(
    "myLocation",
    fill=[
        circle(12, 12, 1.9),
        rounded_rect(11.0, 2.4, 2.0, 3.6, 1.0),
        rounded_rect(11.0, 18.0, 2.0, 3.6, 1.0),
        rounded_rect(2.4, 11.0, 3.6, 2.0, 1.0),
        rounded_rect(18.0, 11.0, 3.6, 2.0, 1.0),
    ],
    punch=[flat([circle(12, 12, 5.4), circle(12, 12, 3.4)])],
    doc="Кільце навколо крапки з чотирма рисками. Крапка каже «ви».",
)

icon(
    "recenter",
    fill=[
        circle(12, 12, 2.6),
        flat([
            [
                move(3.2, 9.6),
                line(3.2, 5.6),
                curve(3.2, 4.3, 4.3, 3.2, 5.6, 3.2),
                line(9.6, 3.2),
                line(9.6, 5.8),
                line(5.8, 5.8),
                line(5.8, 9.6),
                close(),
            ],
            [
                move(20.8, 9.6),
                line(20.8, 5.6),
                curve(20.8, 4.3, 19.7, 3.2, 18.4, 3.2),
                line(14.4, 3.2),
                line(14.4, 5.8),
                line(18.2, 5.8),
                line(18.2, 9.6),
                close(),
            ],
            [
                move(3.2, 14.4),
                line(3.2, 18.4),
                curve(3.2, 19.7, 4.3, 20.8, 5.6, 20.8),
                line(9.6, 20.8),
                line(9.6, 18.2),
                line(5.8, 18.2),
                line(5.8, 14.4),
                close(),
            ],
            [
                move(20.8, 14.4),
                line(20.8, 18.4),
                curve(20.8, 19.7, 19.7, 20.8, 18.4, 20.8),
                line(14.4, 20.8),
                line(14.4, 18.2),
                line(18.2, 18.2),
                line(18.2, 14.4),
                close(),
            ],
        ]),
    ],
    doc="Чотири дужки навколо крапки: повернути місто в кадр.",
)

icon(
    "sparkle",
    fill=[
        [
            move(12.0, 2.8),
            curve(12.9, 8.7, 15.3, 11.1, 21.2, 12.0),
            curve(15.3, 12.9, 12.9, 15.3, 12.0, 21.2),
            curve(11.1, 15.3, 8.7, 12.9, 2.8, 12.0),
            curve(8.7, 11.1, 11.1, 8.7, 12.0, 2.8),
            close(),
        ]
    ],
    doc="Чотирикутна зірка з увігнутими боками: запрошення, а не рейтинг.",
)

icon(
    "lock",
    stroke=[
        [
            move(8.3, 10.2),
            line(8.3, 7.8),
            curve(8.3, 5.7, 9.9, 4.1, 12.0, 4.1),
            curve(14.1, 4.1, 15.7, 5.7, 15.7, 7.8),
            line(15.7, 10.2),
        ]
    ],
    punch=[flat([rounded_rect(4.6, 10.1, 14.8, 10.6, 3.2), circle(12.0, 15.4, 1.7)])],
    doc="Замок із вирізаною шпариною під товстою дужкою.",
)

icon(
    "checkCircle",
    stroke=[polyline(8.2, 12.2, 10.9, 14.9, 15.9, 9.4)],
    punch=[flat([circle(12, 12, 8.6), circle(12, 12, 6.2)])],
    doc="",
)

icon(
    "alert",
    fill=[rounded_rect(10.7, 7.0, 2.6, 6.6, 1.3), circle(12, 16.4, 1.55)],
    punch=[flat([circle(12, 12, 8.6), circle(12, 12, 6.2)])],
    doc="",
)

icon(
    "clock",
    stroke=[polyline(12.0, 7.4, 12.0, 12.0, 15.4, 14.1)],
    punch=[flat([circle(12, 12, 8.6), circle(12, 12, 6.2)])],
    doc="",
)

icon(
    "queue",
    fill=[
        rounded_rect(6.4, 3.0, 11.2, 2.3, 1.15),
        rounded_rect(6.4, 18.7, 11.2, 2.3, 1.15),
        [
            move(8.2, 5.3),
            line(15.8, 5.3),
            line(12.7, 12.0),
            line(15.8, 18.7),
            line(8.2, 18.7),
            line(11.3, 12.0),
            close(),
        ],
    ],
    doc="Пісочний годинник для черги: час минає, а не помилка.",
)


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
        " * Власні гліфи застосунку: суцільні форми на сітці 24 з вирізами за even-odd.",
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
        "private const val STROKE = 2.6f",
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
        "/// Власні гліфи застосунку: суцільні форми на сітці 24 з вирізами за even-odd.",
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
        "    static let stroke: CGFloat = 2.6",
        "}",
        "",
    ]
    (ROOT / "iosApp/Poruch/DesignSystem/PoruchIcons.swift").write_text("\n".join(parts), encoding="utf-8")


if __name__ == "__main__":
    write_kotlin()
    write_swift()
    print(f"{len(ICONS)} icons → Kotlin + Swift")
