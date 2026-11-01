#!/usr/bin/env python3
"""Lottie публікації події (docs/organizers-1.5.md, 1.6): «публікується» в петлі й «опубліковано» раз.

Світ «Корінець»: горизонтальний квиток зі стубом за перфорацією, як `Ticket`; штамп — контур 1,5 з нахилом −4°
і текстом Sofia Sans Condensed 800, як `TicketStamp`. Кольори запечені, тож кожна анімація має світлий і темний
варіант, як у tools/generate_lottie.py: `<name>.json` удень і `<name>_dark.json` уночі в design/lottie/, звідки
клієнти беруть копії (design/lottie/LICENSES.md). Без виразів і картинок: сайт грає їх `lottie_light` під суворою CSP.
Корінець — окремий шар «Stub» кольору жанру (за замовчуванням музика): клієнт може перефарбувати його в жанр події.
Вибір власника 02.11 з прев'ю кандидатів: «публікується» — рядки друкуються, «опубліковано» — штамп.

    python3 -m pip install fonttools   # контури літер штампа
    python3 tools/generate_publish_lottie.py
"""

from __future__ import annotations

import json
from pathlib import Path

from fontTools.pens.basePen import BasePen
from fontTools.ttLib import TTFont

from generate_lottie import (EASE_IN, EASE_OUT, LINEAR, SMOOTH, anim, bezier, compose, fill, group, layer, path, rgba,
                             static, stroke, ticket_part, transform)

ROOT = Path(__file__).resolve().parent.parent
FPS = 30
W, H = 240, 160
# Токени з site/tokens.css (DesignSystem.swift / Tokens.kt); корінці жанрів однакові в обох темах.
THEMES = {
    "light": {"canvas": "#F2F2F4", "surface": "#FFFFFF", "hairline": "#E0E0E5", "ink": "#141417",
              "ink2": "#5E5E66", "ink3": "#6A6A73", "success": "#2E7D4F", "stub": "#6041B1", "edge": False},
    "dark": {"canvas": "#0F0F13", "surface": "#1C1B21", "hairline": "#2E2D35", "ink": "#F3F3F0",
             "ink2": "#A6A5AD", "ink3": "#96959E", "success": "#5DC389", "stub": "#6041B1", "edge": True},
}
WHITE = "#FFFFFF"

# Квиток 176×80: основа 120, корінець 56, радіус md 14, вирізи 7.
X0, TEAR, X1, Y0, Y1 = 32, 152, 208, 40, 120


def trim(end):
    return {"ty": "tm", "s": static(0), "e": end, "o": static(0), "m": 1}


def row(x0, x1, y, width, hex_, end=None, opacity=100):
    """Рядок друку — капсула; з `end` друкується обрізкою зліва направо."""
    items = [path([(x0, y), (x1, y)])] + ([trim(end)] if end else [])
    return group(*items, stroke(hex_, width) | {"o": static(opacity)})


def ticket_layers(t, rows, stub_rows):
    """Основа й корінець окремими шарами: корінець має ім'я «Stub» для перефарбування в жанр."""
    edge = [stroke(t["hairline"], 1)] if t["edge"] else []  # удень квиток відділяє тон, уночі — ще й волосина
    # Перфорація, як у Ticket.swift: крапки 2,5 кольору полотна на кроці 6, з відступом 11 від країв.
    holes = [group({"ty": "el", "d": 1, "p": static([TEAR, y]), "s": static([2.5, 2.5])}, fill(t["canvas"]))
             for y in range(Y0 + 11, Y1 - 10, 6)]
    body = layer("Body", [*rows, group(ticket_part(X0, TEAR, Y0, Y1, 14, 7, left=True), *edge, fill(t["surface"]))],
                 transform())
    stub = layer("Stub", [*holes, *stub_rows,
                          group(ticket_part(TEAR, X1, Y0, Y1, 14, 7, left=False), fill(t["stub"]))],
                 transform())
    return [stub, body]


def printed_rows(t, ends=(None, None, None)):
    return [row(46, 128, 60, 9, t["ink"], ends[0]), row(46, 106, 76, 6, t["ink2"], ends[1]),
            row(46, 86, 90, 6, t["ink3"], ends[2])]


def stub_rows(ends=(None, None)):
    mid = (TEAR + X1) / 2 + 1
    return [row(mid - 11, mid + 11, 72, 10, WHITE, ends[0]), row(mid - 7, mid + 7, 90, 6, WHITE, ends[1], 80)]


def blank_rows(t):
    """Незадруковане — смуги hairline, як у `BlankTicket`."""
    return [row(46, 128, 60, 9, t["hairline"]), row(46, 106, 76, 6, t["hairline"]), row(46, 86, 90, 6, t["hairline"])]


def finish(name, end, layers):
    return compose(name, W, end, layers) | {"fr": FPS, "h": H}


# ---------- «публікується»: рядки друкуються ----------

def publishing(t):
    """Петля 2,4 с. Кадр 0 — надрукований квиток; друк блідне до незадрукованих смуг і набирається знову:
    назва, рядок організатора, місце, потім час і день на корінці."""
    end = 72

    def printing(start, length):
        return anim((0, 100, LINEAR), (23, 100, LINEAR), (24, 0, LINEAR), (start, 0, SMOOTH),
                    (start + length, 100, LINEAR), (end, 100))

    fade = anim((0, 100), (12, 100, SMOOTH), (22, 0, LINEAR), (24, 0, LINEAR), (25, 100, LINEAR), (end, 100))
    ink = [printing(26, 16), printing(34, 12), printing(40, 10)]
    stub_ink = [printing(48, 8), printing(52, 6)]
    stub, body = ticket_layers(t, printed_rows(t, ink) + blank_rows(t), stub_rows(stub_ink))
    for lr in (stub, body):
        for g in lr["shapes"]:
            for it in g["it"]:
                if it["ty"] == "st" and it["c"]["k"][:3] != rgba(t["hairline"])[:3]:
                    it["o"] = fade  # друк блідне, незадруковані смуги лишаються
    return finish("Poriad publishing", end, [stub, body])


# ---------- «опубліковано»: штамп ----------

class LottiePen(BasePen):
    """Контури TrueType → команди M/L/C/Z для `bezier` у системі координат Lottie (y донизу)."""

    def __init__(self, glyph_set, scale, x, y):
        super().__init__(glyph_set)
        self.contours, self.scale, self.x, self.y = [], scale, x, y

    def pt(self, p):
        return (round(self.x + p[0] * self.scale, 2), round(self.y - p[1] * self.scale, 2))

    def _moveTo(self, p):
        self.contours.append([("M", self.pt(p))])

    def _lineTo(self, p):
        self.contours[-1].append(("L", self.pt(p)))

    def _curveToOne(self, a, b, c):
        self.contours[-1].append(("C", (*self.pt(a), *self.pt(b), *self.pt(c))))

    def _closePath(self):
        self.contours[-1].append(("Z", ()))


def stamp_text(text, size, tracking, baseline):
    """Текст штампа контурами Sofia Sans Condensed 800 (шрифт застосунку з українськими формами), по центру x=0."""
    font = TTFont(ROOT / "iosApp/Poruch/Fonts/SofiaSansCondensed-ExtraBold.ttf")
    cmap, glyphs, metrics = font.getBestCmap(), font.getGlyphSet(), font["hmtx"]
    scale = size / font["head"].unitsPerEm
    names = [cmap[ord(ch)] for ch in text]
    width = sum(metrics[n][0] * scale for n in names) + tracking * (len(names) - 1)
    pen, x = LottiePen(glyphs, scale, -width / 2, baseline), -width / 2
    for n in names:
        pen.x = x
        glyphs[n].draw(pen)
        x += metrics[n][0] * scale + tracking
    return [bezier(c) for c in pen.contours], width, font["OS/2"].sCapHeight * scale


def stamp_layer(t, text, at, start):
    """`TicketStamp`: контур 1,5 тоном, радіус 5, −4°, капс stamp 13/+0.8. Падає з ×2,4 і сідає пружиною."""
    shapes, width, cap = stamp_text(text, 13, 0.8, 0)
    box = {"ty": "rc", "d": 1, "p": static([0, -cap / 2]), "s": static([width + 14, cap + 10]), "r": static(5)}
    stamp = layer("Stamp", [group(*shapes, fill(t["success"]) | {"r": 2}), group(box, stroke(t["success"], 1.5))],
                  transform(p=at, r=static(-4),
                            s=anim((start, [240, 240], EASE_IN), (start + 9, [96, 96], EASE_OUT),
                                   (start + 16, [100, 100])),
                            o=anim((start, 0), (start + 5, 100))), ip=start)
    return stamp


def published(t):
    """Раз, 1,8 с: надрукований квиток — і на основу падає штамп «ОПУБЛІКОВАНО»; квиток ледь просідає від удару.
    Стоп-кадр для «зменшити рух» — останній кадр: штамп уже стоїть."""
    end, hit = 54, 15
    stub, body = ticket_layers(t, printed_rows(t)[:2], stub_rows())
    press = anim((0, [100, 100]), (hit, [100, 100], EASE_OUT), (hit + 3, [98.5, 98.5]), (hit + 12, [100, 100]))
    c = ((X0 + X1) / 2, (Y0 + Y1) / 2)
    for lr in (stub, body):
        lr["ks"] = transform(p=c, a=c, s=press)
    return finish("Poriad published", end, [stamp_layer(t, "ОПУБЛІКОВАНО", (92, 103), hit - 9), stub, body])


ANIMATIONS = {"publishing": publishing, "published": published}

if __name__ == "__main__":
    out = ROOT / "design/lottie"
    out.mkdir(parents=True, exist_ok=True)
    for name, build in ANIMATIONS.items():
        for theme_name, theme in THEMES.items():
            data = json.dumps(build(theme), separators=(",", ":"))
            target = out / f"{name}{'_dark' if theme_name == 'dark' else ''}.json"
            target.write_text(data)
            print(f"{target.name:20} {len(data):6} B")
