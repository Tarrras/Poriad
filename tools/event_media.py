"""Медіа для In-App Events App Store (store/in-app-events.md): без тексту, логотипів і градієнтів.

Світ «Корінець»: два квитки на нічному полотні, від одного до другого — пунктирна нитка запрошення («Покликати»).
Важливе — у верхніх двох третинах: знизу App Store кладе назву й опис події. Рендерить headless Chrome:

    python3 tools/event_media.py
"""
import pathlib

from store_shots import ROOT, render

OUT = ROOT / "store" / "events"

# Квиток лежить горизонтально: друкована частина зліва, за вертикальною перфорацією корінець кольору жанру.
# Сірі смуги на квитку — «надрук» без жодної літери.
HTML = """<!doctype html><html><head><meta charset="utf-8"><style>
*{margin:0;box-sizing:border-box}
body{width:{w}px;height:{h}px;overflow:hidden;position:relative;background:#0F0F13}
.t{position:absolute;width:{tw}px;height:{th}px;border-radius:{r}px;overflow:hidden;background:var(--stub);
 box-shadow:0 {s1}px {s2}px rgba(0,0,0,.5)}
.m{position:absolute;left:0;top:0;bottom:0;width:72%;background:#1C1B21;box-shadow:0 0 0 2px #2E2D35 inset}
.p{position:absolute;left:calc(72% + {pg}px);top:{pt}px;bottom:{pt}px;width:{d}px;
 background:radial-gradient(circle at {dh}px {dh}px,#0F0F13 {dr}px,transparent {dr2}px) 0 0/{d}px {ds}px repeat-y}
.n{position:absolute;left:calc(72% - {nh}px + {pg}px + {dh}px);width:{nd}px;height:{nd}px;border-radius:50%;background:#0F0F13}
.b{position:absolute;left:{bl}px;height:{bh}px;border-radius:{bh}px;background:#2E2D35}
svg{position:absolute;left:0;top:0}
</style></head><body>
<svg width="{w}" height="{h}"><path d="{thread}" fill="none" stroke="#F3F3F0" stroke-opacity=".55"
 stroke-width="{sw}" stroke-linecap="round" stroke-dasharray="{dash}"/></svg>
{tickets}
</body></html>"""

TICKET = """<div class="t" style="--stub:{stub};left:{x}px;top:{y}px;transform:rotate({a}deg)">
<div class="m"></div><div class="p"></div>
<div class="n" style="top:-{nh}px"></div><div class="n" style="bottom:-{nh}px"></div>
<div class="b" style="top:{b1}px;width:{b1w}px"></div><div class="b" style="top:{b2}px;width:{b2w}px"></div>
<div class="b" style="top:{b3}px;width:{b3w}px"></div></div>"""

# (файл, полотно, розмір квитка, [(x, y, нахил, колір корінця)], нитка SVG між корінцем першого й другим квитком)
# Корінці: «Зустрічі» (#A24C29, як «Шукаю компанію» на слайдах) і «Музика» (#6041B1).
SCENES = [
    ("invite_card_1920x1080.png", (1920, 1080), (720, 320),
     [(170, 190, -7, "#A24C29"), (1040, 350, 6, "#6041B1")],
     "M 860 470 C 930 620, 1010 600, 1060 520"),
    ("invite_page_1080x1920.png", (1080, 1920), (820, 364),
     [(110, 330, -6, "#A24C29"), (150, 900, 5, "#6041B1")],
     "M 760 720 C 860 790, 820 860, 700 930"),
]


def fill(template, **values):
    """`str.format` без екранування фігурних дужок CSS."""
    for key, value in values.items():
        template = template.replace("{" + key + "}", str(value))
    return template


def scene_html(size, ticket, placed, thread):
    (w, h), (tw, th) = size, ticket
    u = th / 320  # усе міряємо від висоти квитка
    tickets = "".join(
        fill(
            TICKET, stub=stub, x=x, y=y, a=a, nh=round(26 * u), b1=round(70 * u), b1w=round(tw * .52),
            b2=round(140 * u), b2w=round(tw * .36), b3=round(230 * u), b3w=round(tw * .22),
        )
        for x, y, a, stub in placed
    )
    return fill(
        HTML, w=w, h=h, tw=tw, th=th, r=round(28 * u), s1=round(30 * u), s2=round(70 * u), pg=round(6 * u),
        pt=round(34 * u), d=round(10 * u), dh=round(5 * u), dr=round(4.4 * u), dr2=round(5 * u), ds=round(18 * u),
        nh=round(26 * u), nd=round(52 * u), bl=round(56 * u), bh=round(26 * u), sw=round(5 * u),
        dash=f"{round(2 * u)} {round(16 * u)}", thread=thread, tickets=tickets,
    )


def main():
    OUT.mkdir(exist_ok=True)
    for name, size, ticket, placed, thread in SCENES:
        render(scene_html(size, ticket, placed, thread), OUT / name, *size)


if __name__ == "__main__":
    main()
