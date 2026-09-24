#!/usr/bin/env python3
"""Фірмові Lottie-анімації: сплеш, лоадер і порожній стан.

Усі три зібрані з двох знаків продукту: шпильки з іконки застосунку (чорнило або папір і помаранчева
крапка «ви тут») і пінів подій з мапи (біле коло з кільцем кольору категорії). Кольори запечені, тож
кожна анімація має світлий і темний варіант. Android бере їх із raw / raw-night під одним іменем,
iOS — з Data Set `<Name>Light` / `<Name>Dark`.

    python3 tools/generate_lottie.py
"""

from __future__ import annotations

import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FPS = 60
ORANGE = "#D9603A"
# Відтінки категорій з DesignSystem.swift / Tokens.kt; у темній темі — categoryInk (+45 % білого).
CATEGORIES = {"music": "#6D4AC9", "art": "#C43B6B", "sport": "#0F7F73", "food": "#C96A1E", "games": "#2F63C4"}
THEMES = {
    "light": {"pin": "#1D1D1F", "surface": "#FFFFFF", "disc": "#EBEBF0", "road": "#FFFFFF",
              "ring": "#C7C7CC", "shadow": 14},
    "dark": {"pin": "#F5F3EE", "surface": "#202027", "disc": "#141419", "road": "#24242C",
             "ring": "#3A3A42", "shadow": 0},
}

EASE_IN = ({"x": 0.55, "y": 0}, {"x": 0.9, "y": 0.6})  # падіння з прискоренням
EASE_OUT = ({"x": 0.2, "y": 0.8}, {"x": 0.3, "y": 1})
SMOOTH = ({"x": 0.4, "y": 0}, {"x": 0.2, "y": 1})
LINEAR = ({"x": 0, "y": 0}, {"x": 1, "y": 1})


# ---------- примітиви формату ----------

def rgba(hex_: str) -> list[float]:
    return [int(hex_[i:i + 2], 16) / 255 for i in (1, 3, 5)] + [1]


def blend(hex_: str, amount: float) -> str:
    return "#" + "".join(f"{round(int(hex_[i:i + 2], 16) * (1 - amount) + 255 * amount):02X}" for i in (1, 3, 5))


def static(v):
    return {"a": 0, "k": v}


def anim(*keys):
    """keys: (кадр, значення[, крива до наступного ключа])."""
    frames = []
    for n, key in enumerate(keys):
        k = {"t": key[0], "s": key[1] if isinstance(key[1], list) else [key[1]]}
        if n < len(keys) - 1:
            o, i = key[2] if len(key) > 2 else SMOOTH
            k |= {"o": o, "i": i}
        frames.append(k)
    return {"a": 1, "k": frames}


def transform(p=(0, 0), a=(0, 0), s=None, o=None, r=None):
    return {"o": o or static(100), "r": r or static(0), "p": static(list(p)) if isinstance(p, tuple) else p,
            "a": static(list(a)), "s": s or static([100, 100])}


def group(*items):
    return {"ty": "gr", "it": [*items, {"ty": "tr", **transform(), "sk": static(0), "sa": static(0)}]}


def fill(hex_, opacity=100):
    return {"ty": "fl", "c": static(rgba(hex_)), "o": static(opacity), "r": 1}


def stroke(hex_, width):
    return {"ty": "st", "c": static(rgba(hex_)), "o": static(100), "w": static(width), "lc": 2, "lj": 2, "ml": 4}


def ellipse(size, p=(0, 0)):
    return {"ty": "el", "d": 1, "p": static(list(p)), "s": size if isinstance(size, dict) else static(list(size))}


def path(points, closed=False):
    return {"ty": "sh", "ks": static({"c": closed, "v": [list(p) for p in points],
                                      "i": [[0, 0]] * len(points), "o": [[0, 0]] * len(points)})}


def compose(name, size, end, layers):
    for n, lr in enumerate(layers, 1):
        lr.setdefault("ind", 100 + n)  # явні індекси (шпилька й крапка) лишаються нижче 100
        lr.setdefault("op", end)
    return {"v": "5.7.4", "fr": FPS, "ip": 0, "op": end, "w": size, "h": size, "nm": name, "ddd": 0,
            "assets": [], "layers": layers}


def layer(name, shapes, ks, ip=0, **extra):
    return {"ddd": 0, "ty": 4, "nm": name, "sr": 1, "ks": ks, "ao": 0, "shapes": shapes, "ip": ip, "st": 0,
            "bm": 0, **extra}


# ---------- знаки ----------

# Шпилька з ic_launcher_foreground.xml у координатах відносно вістря: голова — коло r 21.5 з центром
# на 40 вище, боки сходяться у вістря. Висота 61.5.
K = 21.5 * 0.5523
BRAND_PIN = {"ty": "sh", "ks": static({"c": True,
                                       "v": [[0, 0], [-21.5, -40], [0, -61.5], [21.5, -40]],
                                       "i": [[0, 0], [0, 13], [-K, 0], [0, -K]],
                                       "o": [[0, 0], [0, -K], [K, 0], [0, 13]]})}


def brand_pin(theme, ind, position, scale, opacity=None):
    """Шпилька й крапка — два шари: крапка дочірня, тож їде й сплющується разом зі шпилькою."""
    pin = layer("Pin", [group(BRAND_PIN, fill(theme["pin"]))],
                transform(p=position, s=scale, o=opacity), ind=ind)
    dot = layer("Dot", [group(ellipse((17, 17), (0, -42.5)), fill(ORANGE))],
                transform(p=(0, -42.5), a=(0, -42.5)), ind=ind - 1, parent=ind)
    return dot, pin


def event_pin(theme, hue, at, pop, react):
    """Пін події з мапи: біле коло з кільцем категорії та хвостиком; росте з точки на землі."""
    s = anim((pop, [0, 0], EASE_OUT), (pop + 10, [148, 148]), (pop + 18, [130, 130], LINEAR),
             (react, [130, 130], SMOOTH), (react + 6, [152, 152]), (react + 16, [130, 130]))
    return layer(f"Event {hue}", [
        group(ellipse((6, 6), (0, -24)), fill(hue)),
        group(ellipse((30, 30), (0, -24)), stroke(hue, 3.5), fill(theme["surface"])),
        group(path([(-6, -11), (6, -11), (0, -2)], closed=True), fill(hue)),
    ], transform(p=at, s=s), ip=pop)


def ripple(size_from, size_to, start, length, width, opacity, at, hex_=ORANGE):
    return layer("Ripple", [group(ellipse(anim((start, size_from, EASE_OUT), (start + length, size_to))),
                                  stroke(hex_, width))],
                 transform(p=at, o=anim((start, opacity), (start + length, 0))), ip=start)


# ---------- сплеш: місто оживає ----------

def splash(theme):
    """Диск мапи, вулиці прокреслюються, спливають події, у центр падає шпилька — і від неї хвиля,
    на яку події відповідають. Назву й підпис застосунок малює під анімацією своїм шрифтом."""
    c, tip, land, scale = (200, 200), (200, 236), 60, 170
    roads = [([(60, 170), (335, 130)], 7), ([(120, 70), (150, 200), (130, 330)], 5),
             ([(250, 60), (270, 340)], 5), ([(70, 260), (320, 300)], 5)]
    # Обрізка стоїть між шляхом і обведенням: вона діє на те, що вище за неї.
    road_layers = [layer("Road", [group(path(pts), {"ty": "tm", "s": static(0), "o": static(0), "m": 1,
                                                     "e": anim((4 + n * 4, 0, SMOOTH), (34 + n * 4, 100))},
                                        stroke(theme["road"], w))],
                         transform()) for n, (pts, w) in enumerate(roads)]
    spots = [(110, 125), (298, 118), (95, 250), (300, 262), (205, 322)]
    hues = [h if theme is THEMES["light"] else blend(h, 0.45) for h in CATEGORIES.values()]
    # Хвиля біжить від вістря ~170 одиниць за 40 кадрів: кожна подія відповідає, коли її досягає.
    events = [event_pin(theme, hue, at, 18 + n * 5, land + 2 + round(math.dist(at, tip) / 170 * 30))
              for n, (at, hue) in enumerate(zip(spots, hues))]
    x, y = tip
    dot, pin = brand_pin(theme, 12, anim((40, [x, y - 70], EASE_IN), (land, [x, y])),
                         anim((40, [scale * 0.94, scale * 1.04], EASE_IN),
                              (land, [scale * 0.94, scale * 1.04], EASE_OUT),
                              (land + 6, [scale * 1.08, scale * 0.9]), (land + 18, [scale, scale])),
                         anim((40, 0), (46, 100)))
    dot["ks"]["s"] = anim((land + 6, [0, 0], EASE_OUT), (land + 18, [115, 115]), (land + 28, [100, 100]))
    dot["ip"] = land + 6
    shadow = layer("Shadow", [group(ellipse((70, 16)), fill("#000000", theme["shadow"]))],
                   transform(p=(x, y + 2), s=anim((40, [30, 30], EASE_IN), (land, [100, 100])),
                             o=anim((40, 0, EASE_IN), (land, 100))), ip=40)
    disc = layer("Map", [group(ellipse((320, 320)), fill(theme["disc"]))],
                 transform(p=c, s=anim((0, [82, 82], EASE_OUT), (24, [100, 100])), o=anim((0, 0), (16, 100))))
    return compose("Poriad splash", 400, 105, [
        dot, pin, *events, ripple([0, 0], [340, 340], land + 2, 40, 3, 70, tip), shadow, *road_layers, disc])


# ---------- лоадер: шпилька підстрибує ----------

def loader(theme):
    """Безшовний цикл 0.9 с: удар об землю на кадрі 0 і 54, кільце від кожного приземлення."""
    ground, top, end = 100, 78, 54
    squash, stretch, rest = [112, 86], [95, 106], [100, 100]
    dot, pin = brand_pin(
        theme, 5,
        anim((0, [60, ground], LINEAR), (4, [60, ground], EASE_OUT), (26, [60, top], EASE_IN), (48, [60, ground], LINEAR),
             (end, [60, ground])),
        anim((0, squash), (8, stretch), (26, rest, EASE_IN), (48, stretch, LINEAR), (end, squash)))
    shadow = layer("Shadow", [group(ellipse((34, 8)), fill("#000000", theme["shadow"] * 1.4))],
                   transform(p=(60, ground + 1), s=anim((0, [110, 110]), (26, [60, 60], EASE_IN), (48, [100, 100], LINEAR),
                                                       (end, [110, 110])),
                             o=anim((0, 100), (26, 45, EASE_IN), (end, 100))))
    return compose("Poriad loader", 120, end, [
        dot, pin, ripple([10, 3], [96, 28], 0, 40, 2.5, 60, (60, ground)), shadow])


# ---------- порожній стан: шукаємо поруч ----------

def empty(theme):
    """Тло під плиткою з гліфом (її малює застосунок): кола розходяться, крапка обходить довкола.
    Цикл 4 с, спокійний. Плитка 64 у центрі полотна 160."""
    c, end = (80, 80), 240

    def ring(phase):
        # Лінійно від краю плитки до краю полотна; з фазою коло «перескакує» назад, коли вже невидиме.
        at = lambda t: 64 + (156 - 64) * ((t + phase) % end) / end
        cut = end - phase
        keys = [(0, [at(0)] * 2, LINEAR), (cut - 1, [155.6] * 2, LINEAR), (cut, [64, 64], LINEAR), (end, [at(end - 1e-9)] * 2)] \
            if phase else [(0, [64, 64], LINEAR), (end, [156, 156])]
        fade = lambda t: max(0.0, 55 * (1 - ((t + phase) % end) / end))
        okeys = [(0, fade(0), LINEAR), (cut - 1, 0, LINEAR), (cut, 55, LINEAR), (end, fade(end - 1e-9))] \
            if phase else [(0, 55, LINEAR), (end, 0)]
        return layer("Ring", [group(ellipse(anim(*keys)), stroke(theme["ring"], 1.5))],
                     transform(p=c, o=anim(*okeys)))

    orbit = layer("Orbit", [group(ellipse((8, 8), (0, -52)), fill(ORANGE))],
                  transform(p=c, r=anim((0, 0, LINEAR), (end, 360))))
    return compose("Poriad empty", 160, end, [orbit, ring(0), ring(end // 2)])


ANIMATIONS = {"splash": splash, "loader": loader, "empty": empty}

if __name__ == "__main__":
    for name, build in ANIMATIONS.items():
        for theme_name, theme in THEMES.items():
            data = json.dumps(build(theme), separators=(",", ":"))
            night = "-night" if theme_name == "dark" else ""
            dataset = ROOT / f"iosApp/Poruch/Assets.xcassets/{name.title()}{theme_name.title()}.dataset"
            for target in (ROOT / f"androidApp/src/main/res/raw{night}/{name}.json", dataset / f"{name}_{theme_name}.json"):
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(data)
            (dataset / "Contents.json").write_text(json.dumps(
                {"data": [{"filename": f"{name}_{theme_name}.json", "idiom": "universal",
                           "universal-type-identifier": "public.json"}],
                 "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
            print(f"{name:7} {theme_name:5} {len(data):6} B")
