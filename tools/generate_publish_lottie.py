#!/usr/bin/env python3
"""Lottie публікації події (docs/organizers-1.5.md, 1.6): «публікується» в петлі й «опубліковано» раз.

Світ «Корінець»: горизонтальний квиток зі стубом за перфорацією, як `Ticket`; штамп — контур 1,5 з нахилом −4°
і текстом Sofia Sans Condensed 800, як `TicketStamp`. Кольори запечені, тож кожна анімація має світлий і темний
варіант, як у tools/generate_lottie.py. Без виразів і картинок: сайт грає їх `lottie_light` під суворою CSP.
Корінець — окремий шар «Stub» кольору жанру (за замовчуванням музика): клієнт може перефарбувати його в жанр події.

    python3 -m pip install fonttools   # контури літер штампа
    python3 tools/generate_publish_lottie.py [тека]
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from fontTools.pens.basePen import BasePen
from fontTools.ttLib import TTFont

from generate_lottie import (EASE_IN, EASE_OUT, LINEAR, SMOOTH, anim, bezier, compose, fill, glyph, group, layer,
                             path, rgba, static, stroke, ticket_part, transform)

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
SPRING = ({"x": 0.3, "y": 0}, {"x": 0.2, "y": 1.35})  # штамп сідає з легким перельотом, як «ЗБЕРЕЖЕНО» у стосі

# Квиток 176×80: основа 120, корінець 56, радіус md 14, вирізи 7.
X0, TEAR, X1, Y0, Y1 = 32, 152, 208, 40, 120


def trim(end):
    return {"ty": "tm", "s": static(0), "e": end, "o": static(0), "m": 1}


def row(x0, x1, y, width, hex_, end=None, opacity=100):
    """Рядок друку — капсула; з `end` друкується обрізкою зліва направо."""
    items = [path([(x0, y), (x1, y)])] + ([trim(end)] if end else [])
    return group(*items, stroke(hex_, width) | {"o": static(opacity)})


def ticket_layers(t, rows, stub_rows, dx=0):
    """Основа й корінець окремими шарами: корінець має ім'я «Stub» для перефарбування в жанр."""
    edge = [stroke(t["hairline"], 1)] if t["edge"] else []  # удень квиток відділяє тон, уночі — ще й волосина
    # Перфорація, як у Ticket.swift: крапки 2,5 кольору полотна на кроці 6, з відступом 11 від країв.
    holes = [group({"ty": "el", "d": 1, "p": static([TEAR + dx, y]), "s": static([2.5, 2.5])}, fill(t["canvas"]))
             for y in range(Y0 + 11, Y1 - 10, 6)]
    body = layer("Body", [*rows, group(ticket_part(X0 + dx, TEAR + dx, Y0, Y1, 14, 7, left=True), *edge, fill(t["surface"]))],
                 transform())
    stub = layer("Stub", [*holes, *stub_rows,
                          group(ticket_part(TEAR + dx, X1 + dx, Y0, Y1, 14, 7, left=False), fill(t["stub"]))],
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


def rigid(lr, p=None, s=None, o=None, a=(0, 0)):
    lr["ks"] = transform(p=p or (0, 0), a=a, s=s, o=o)
    return lr


# ---------- «публікується»: квиток виходить із прорізу ----------

SLOT_X = 26


def slot(t, o=None):
    return layer("Slot", [group(path([(SLOT_X, 30), (SLOT_X, 130)]), stroke(t["ink"], 6))],
                 transform(o=o))


def matte():
    """Альфа-матовий шар: видно лише те, що вже вийшло праворуч від прорізу."""
    return layer("Matte", [group({"ty": "rc", "d": 1, "p": static([(SLOT_X + 3 + W) / 2, H / 2]),
                                  "s": static([W - SLOT_X - 3, H]), "r": static(0)}, fill(WHITE))],
                 transform(), td=1)


def feed(start, steps, distance, step=9, pause=3):
    """Подача кроками, як друкарка квитків: рух, пауза, рух."""
    keys, x = [], -distance
    for n in range(steps):
        f = start + n * (step + pause)
        keys += [(f, [x, 0], SMOOTH), (f + step, [x + distance / steps, 0], LINEAR)]
        x += distance / steps
    return keys


def publishing_slot(t):
    """Петля 2,8 с. Кадр 0 — квиток повністю вийшов (стоп-кадр для «зменшити рух»): його забирають праворуч,
    і з прорізу чотирма кроками виходить наступний."""
    end, out = 84, X1 - SLOT_X + 4
    p = anim((0, [0, 0]), (6, [0, 0], EASE_IN), (18, [24, 0], LINEAR), (19, [24, 0], LINEAR),
             (20, [-out, 0], LINEAR), *feed(24, 4, out), (72, [0, 0], LINEAR), (end, [0, 0]))
    o = anim((0, 100), (6, 100, EASE_IN), (16, 0, LINEAR), (20, 0, LINEAR), (21, 100, LINEAR), (end, 100))
    stub, body = ticket_layers(t, printed_rows(t), stub_rows())
    # Батько несе рух і прозорість; обидві частини квитка під одним матом — через прекомпозицію.
    ticket = {"id": "ticket", "layers": [stub, body]}
    for n, lr in enumerate(ticket["layers"], 1):
        lr |= {"ind": n, "op": end}
    comp = {"ddd": 0, "ty": 0, "nm": "Ticket", "refId": "ticket", "sr": 1, "ks": transform(p=p, o=o), "ao": 0,
            "w": W, "h": H, "ip": 0, "st": 0, "bm": 0, "tt": 1}
    data = finish("Poriad publishing — slot", end, [slot(t), matte(), comp])
    data["assets"] = [ticket]
    return data


# ---------- «публікується»: рядки друкуються на місці ----------

def publishing_rows(t):
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
    return finish("Poriad publishing — rows", end, [stub, body])


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


def published_stamp(t):
    """Раз, 1,8 с: надрукований квиток — і на основу падає штамп «ОПУБЛІКОВАНО»; квиток ледь просідає від удару."""
    end, hit = 54, 15
    stub, body = ticket_layers(t, printed_rows(t)[:2], stub_rows())
    press = anim((0, [100, 100]), (hit, [100, 100], EASE_OUT), (hit + 3, [98.5, 98.5]), (hit + 12, [100, 100]))
    for lr in (stub, body):
        rigid(lr, p=((X0 + X1) / 2, (Y0 + Y1) / 2), a=((X0 + X1) / 2, (Y0 + Y1) / 2), s=press)
    return finish("Poriad published — stamp", end, [stamp_layer(t, "ОПУБЛІКОВАНО", (92, 103), hit - 9), stub, body])


# ---------- «опубліковано»: квиток готовий ----------

def published_ready(t):
    """Раз, 1,6 с: продовження петлі з прорізу — останній крок подачі, проріз зникає, квиток трохи
    піднімається, і на корінці малюється біла галочка."""
    end, out = 48, X1 - SLOT_X + 4
    lift = anim((10, [100, 100], SMOOTH), (20, [103, 103], SMOOTH), (34, [100, 100]))
    c = ((X0 + X1) / 2, (Y0 + Y1) / 2)
    stub, body = ticket_layers(t, printed_rows(t), [])
    for lr in (stub, body):
        rigid(lr, p=c, a=c, s=lift)
    mid = (TEAR + X1) / 2 + 1
    check = glyph("check", WHITE, at=(mid, (Y0 + Y1) / 2), scale=130)
    for g in check["it"][:-1]:
        g["it"].insert(-2, trim(anim((20, 0, EASE_OUT), (32, 100))))  # обрізка — перед обведенням
    tick = layer("Check", [check], transform(p=c, a=c, s=lift), ip=20)
    ticket = {"id": "ticket", "layers": [tick, stub, body]}
    for n, lr in enumerate(ticket["layers"], 1):
        lr |= {"ind": n, "op": end}
    comp = {"ddd": 0, "ty": 0, "nm": "Ticket", "refId": "ticket", "sr": 1, "ao": 0, "w": W, "h": H, "ip": 0,
            "st": 0, "bm": 0, "tt": 1, "ks": transform(p=anim((0, [-out / 4, 0], SMOOTH), (9, [0, 0])))}
    data = finish("Poriad published — ready", end, [
        slot(t, o=anim((8, 100, SMOOTH), (18, 0))), matte(), comp])
    data["assets"] = [ticket]
    return data


ANIMATIONS = {"publishing-slot": publishing_slot, "publishing-rows": publishing_rows,
              "published-stamp": published_stamp, "published-ready": published_ready}

if __name__ == "__main__":
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "design/lottie"
    out.mkdir(parents=True, exist_ok=True)
    for name, build in ANIMATIONS.items():
        for theme_name, theme in THEMES.items():
            data = json.dumps(build(theme), separators=(",", ":"), ensure_ascii=False)
            target = out / f"{name}{'-dark' if theme_name == 'dark' else ''}.json"
            target.write_text(data)
            print(f"{target.name:28} {len(data):6} B")
