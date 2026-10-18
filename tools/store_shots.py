"""Збирає графіку для сторів із сирих екранів у store/screens/.

Світ «Корінець» (DESIGN.md): кожен слайд — квиток на нічному полотні. Угорі, на квитку, штамп і заголовок
Sofia Sans Condensed; за перфорацією — корінець кольору жанру, з якого виростає телефон, а над ним «винесений»
шматок справжнього UI. Рендерить headless Chrome. Перезняти екрани після зміни UI (див. store/listing.md),
оновити координати в SLIDES і запустити:

    python3 tools/store_shots.py
"""
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCREENS = ROOT / "store" / "screens"
FONTS = ROOT / "site" / "fonts"  # Sofia Sans з вшитою українською кирилицею й Inter — ті самі, що на сайті
ZOOM = 1.12
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# Сирі розміри екранів: iPhone 16 Pro і Android-емулятор з `wm size 1080x2400`.
RAW = {"ios": (1206, 2622), "and": (1080, 2400)}

# Перші три слайди видно в пошуку стору — на них головні гачки. stub — колір корінця (`cat-*-stub`), підібраний так,
# щоб винесений шматок із власним корінцем не зливався з тлом. ios/android: (x0, y0, x1, y1, радіус, нахил) у пікселях
# сирого екрана — шматок UI, збільшений у ZOOM разів; якщо його місце нижче краю слайда, він піднімається у видиму частину.
SLIDES = [
    dict(
        key="map", stub="#6041B1",
        stamp="Афіша на мапі", title="Є куди.<br>Буде з ким.",
        sub="Концерти, вистави й зустрічі Києва, Львова, Одеси, Дніпра й Харкова — на одній мапі",
        ios=(46, 1906, 1042, 2244, 54, -2), android=(41, 1821, 952, 2115, 47, -2),
    ),
    dict(
        key="detail", stub="#AC345E",
        stamp="Шукаю компанію", title="Не хочете йти самі?",
        sub="На будь-яку подію з афіші можна зібрати невелику компанію. Кого взяти, вирішуєте ви",
        ios=(34, 2098, 1166, 2521, 66, 2), android=(31, 1945, 1046, 2315, 58, 2),
    ),
    dict(
        key="create", stub="#0D7065",
        stamp="Від людей", title="Зберіть своїх",
        sub="Настолки, пробіжка чи кіно: назва, точка на мапі й час — і квиток готовий",
        ios=(46, 454, 1158, 986, 42, -2), android=(41, 251, 1037, 716, 37, -2),
    ),
    dict(
        key="home", stub="#2957AC",
        stamp="У місті", title="Куди піти — за хвилину",
        sub="Сотні подій із квиткових сервісів: концерти, стендап, вистави й виставки",
        ios=(46, 483, 1002, 1566, 54, 1.5), android=(41, 240, 970, 1185, 47, 1.5),
    ),
    dict(
        key="safety", stub="#376E33",
        stamp="Безпека", title="Укриття поруч&nbsp;— ще до виходу",
        sub="Найближчі укриття й час до комендантської біля кожної події. Укриття — поки що для Києва",
        ios=(47, 1297, 1157, 2048, 42, -1.5), android=(41, 1174, 1037, 1833, 37, -1.5),
    ),
]

TARGETS = [
    # (тека, префікс, платформа, ширина, висота)
    ("appstore", "iphone69_", "ios", 1320, 2868),
    ("appstore", "iphone67_", "ios", 1290, 2796),
    ("appstore", "iphone65_", "ios", 1242, 2688),
    ("play", "phone_", "and", 1080, 1920),
]


def _inter(weight, subset, rng):
    src = (FONTS / f"inter-{subset}-{weight}-normal.woff2").as_uri()
    return f"@font-face{{font-family:Inter;font-weight:{weight};src:url({src});unicode-range:{rng}}}"


FONT_CSS = "".join(
    _inter(w, sub, rng) for w in (400, 500)
    for sub, rng in (("cyrillic", "U+0400-045F,U+0490-0491"), ("latin", "U+0000-00FF,U+2000-206F"))
) + f"""
@font-face{{font-family:Cond;font-weight:800;src:url({(FONTS / 'sofia-sans-condensed-800.woff2').as_uri()})}}
@font-face{{font-family:XCond;font-weight:800;src:url({(FONTS / 'sofia-sans-extra-condensed-800.woff2').as_uri()})}}
"""

# Нічна шкала з DESIGN.md: полотно, квиток, волосина, папір (головне чорнило вночі) і друге чорнило.
CSS = FONT_CSS + """
:root{--canvas:#0F0F13;--surface:#1C1B21;--hairline:#2E2D35;--paper:#F3F3F0;--ink2:#A6A5AD}
*{margin:0;box-sizing:border-box}
html{font-size:calc(var(--w)/100)}
body{width:var(--w);height:var(--h);overflow:hidden;position:relative;background:var(--canvas);
 font-family:Inter,sans-serif;-webkit-font-smoothing:antialiased;color:var(--paper)}
.ticket{position:absolute;left:4rem;right:4rem;top:4rem;bottom:-12rem;border-radius:5rem;overflow:hidden;
 background:var(--stub)}
.main{position:absolute;left:0;right:0;top:0;height:calc(var(--perf) - 4rem);background:var(--surface);
 box-shadow:0 0 0 .15rem var(--hairline) inset}
/* Перфорація: крапки кольору полотна наскрізь і два півкруглі вирізи, як у TicketShape. */
.perf{position:absolute;left:9rem;right:9rem;top:calc(var(--perf) - .45rem);height:.9rem;
 background:radial-gradient(circle at .45rem .45rem,var(--canvas) .42rem,transparent .48rem) 0 0/1.7rem .9rem repeat-x}
.notch{position:absolute;top:calc(var(--perf) - 2.6rem);width:5.2rem;height:5.2rem;border-radius:50%;background:var(--canvas)}
.head{position:absolute;left:10rem;right:10rem;top:4rem;height:calc(var(--perf) - 4rem);display:flex;
 flex-direction:column;justify-content:center;align-items:flex-start}
.stamp{display:inline-block;font:800 var(--stampsize)/1 Cond,sans-serif;letter-spacing:.09em;text-transform:uppercase;
 color:var(--paper);padding:.9rem 1.7rem .8rem;border:.32rem solid var(--paper);border-radius:1rem;
 transform:rotate(-4deg);transform-origin:left center;opacity:.92;margin-bottom:var(--gap1)}
h1{font:800 var(--h1)/.94 Cond,sans-serif;letter-spacing:-.012em;text-wrap:balance;max-width:80rem}
p{font-size:var(--sub);line-height:1.36;margin-top:var(--gap2);color:var(--ink2);text-wrap:pretty;max-width:76rem}
.phone{position:absolute;left:50%;top:var(--phonetop);width:var(--phonew);transform:translateX(-50%);
 border-radius:var(--rad);padding:var(--bezel);background:linear-gradient(160deg,#3a3a3e,#111113 40%,#1c1c1f);
 box-shadow:0 0 0 .22rem rgba(255,255,255,.14) inset,0 0 0 .3rem rgba(0,0,0,.35),0 8rem 16rem rgba(0,0,0,.45),
 0 2rem 4rem rgba(0,0,0,.25)}
.phone img{display:block;width:100%;border-radius:calc(var(--rad) - var(--bezel))}
.hole{position:absolute;left:50%;top:calc(var(--bezel) + 1.5rem);width:2.4rem;height:2.4rem;margin-left:-1.2rem;
 border-radius:50%;background:#050505}
.slot{position:absolute;background:var(--canvas);box-shadow:0 0 0 .15rem var(--hairline) inset}
.float{position:absolute;background-repeat:no-repeat;
 box-shadow:0 0 0 .2rem rgba(255,255,255,.22),0 4rem 9rem rgba(0,0,0,.55),0 1rem 2.5rem rgba(0,0,0,.3)}
"""


def slide_html(s, plat, w, h):
    rw, rh = RAW[plat]
    tall = h / w > 2  # iPhone 19.5:9 проти Play 16:9
    page_h = h / w * 100  # висота слайда в rem
    perf = 77 if tall else 63  # однакова лінія відриву на всіх слайдах набору — у ряду стору вони читаються пачкою
    phone_w = 74 if tall else 64
    phone_top = perf + 7
    bezel = 1.25
    scale = (phone_w - 2 * bezel) / rw  # rem на сирий піксель
    vars_ = {
        "--w": f"{w}px", "--h": f"{h}px", "--stub": s["stub"], "--perf": f"{perf}rem",
        "--stampsize": "3.3rem" if tall else "3rem",
        "--h1": "12.6rem" if tall else "10.4rem",
        "--sub": "3.7rem" if tall else "3.3rem",
        "--gap1": "4.6rem" if tall else "3.4rem",
        "--gap2": "3.4rem" if tall else "2.6rem",
        "--phonetop": f"{phone_top}rem", "--phonew": f"{phone_w}rem",
        "--rad": "10rem" if plat == "ios" else "8rem", "--bezel": f"{bezel}rem",
    }
    img = (SCREENS / f"{plat}_{s['key']}.png").as_uri()
    x0, y0, x1, y1, rad, rot = s["ios" if plat == "ios" else "android"]
    k = scale * ZOOM  # rem на сирий піксель у винесеному шматку
    fw, fh = (x1 - x0) * k, (y1 - y0) * k
    left = (100 - phone_w) / 2 + bezel + (x0 + x1) / 2 * scale - fw / 2
    top = phone_top + bezel + (y0 + y1) / 2 * scale - fh / 2
    lifted = min(top, page_h - fh - 6)  # шматок, що опинився б під краєм, піднімається у видиму частину
    left = max(3, min(left, 97 - fw))
    # Піднятий шматок лишає на екрані порожнє місце, а не другу копію себе.
    slot = "" if lifted > top - 1 else (
        f'<div class="slot" style="left:{(100 - phone_w) / 2 + bezel + x0 * scale}rem;'
        f'top:{phone_top + bezel + y0 * scale}rem;width:{(x1 - x0) * scale}rem;height:{(y1 - y0) * scale}rem;'
        f'border-radius:{rad * scale}rem"></div>'
    )
    top = lifted
    float_ = slot + (
        f'<div class="float" style="left:{left}rem;top:{top}rem;width:{fw}rem;height:{fh}rem;'
        f'border-radius:{rad * k}rem;transform:rotate({rot}deg);background-image:url({img});'
        f'background-size:{rw * k}rem {rh * k}rem;background-position:{-x0 * k}rem {-y0 * k}rem"></div>'
    )
    style = ";".join(f"{name}:{value}" for name, value in vars_.items())
    hole = '<div class="hole"></div>' if plat == "and" else ""
    return f"""<!doctype html><html style="{style}"><head><meta charset="utf-8"><style>{CSS}</style></head><body>
<div class="ticket"><div class="main"></div></div>
<div class="perf"></div><div class="notch" style="left:1.4rem"></div><div class="notch" style="right:1.4rem"></div>
<div class="head"><div class="stamp">{s['stamp']}</div><h1>{s['title']}</h1><p>{s['sub']}</p></div>
<div class="phone"><img src="{img}">{hole}</div>{float_}
</body></html>"""


# Банер Play — горизонтальний квиток: слоган на квитку, за вертикальною перфорацією корінець із двома телефонами.
FEATURE = """<!doctype html><html><head><meta charset="utf-8"><style>""" + FONT_CSS + """
*{margin:0;box-sizing:border-box}
body{width:1024px;height:500px;overflow:hidden;position:relative;background:#0F0F13;color:#F3F3F0;
 font-family:Inter,sans-serif;-webkit-font-smoothing:antialiased}
.ticket{position:absolute;inset:28px;border-radius:26px;overflow:hidden;background:#6041B1}
.main{position:absolute;left:0;top:0;bottom:0;width:560px;background:#1C1B21;box-shadow:0 0 0 1.5px #2E2D35 inset}
.perf{position:absolute;left:583px;top:62px;bottom:62px;width:9px;
 background:radial-gradient(circle at 4.5px 4.5px,#0F0F13 4px,transparent 4.6px) 0 0/9px 16px repeat-y}
.notch{position:absolute;left:561px;width:52px;height:52px;border-radius:50%;background:#0F0F13}
.brand{position:absolute;left:84px;top:78px;display:flex;align-items:center;gap:14px;font:800 30px/1 Cond,sans-serif}
.brand img{width:48px;height:48px;border-radius:12px}
h1{position:absolute;left:84px;top:156px;font:800 92px/.92 Cond,sans-serif;letter-spacing:-.01em}
p{position:absolute;left:86px;top:356px;width:440px;font-size:19px;line-height:1.4;color:#A6A5AD;text-wrap:balance}
.ph{position:absolute;width:190px;padding:6px;border-radius:36px;background:linear-gradient(160deg,#3a3a3e,#111113 40%,#1c1c1f);
 box-shadow:0 0 0 1px rgba(0,0,0,.35),0 30px 60px rgba(0,0,0,.45)}
.ph img{display:block;width:100%;border-radius:30px}
</style></head><body>
<div class="ticket"><div class="main"></div>
<div class="ph" style="left:600px;top:62px;transform:rotate(-6deg)"><img src="{a}"></div>
<div class="ph" style="left:766px;top:34px;transform:rotate(5deg)"><img src="{b}"></div></div>
<div class="perf"></div><div class="notch" style="top:2px"></div><div class="notch" style="bottom:2px"></div>
<div class="brand"><img src="{icon}">Поряд</div>
<h1>Є куди.<br>Буде з ким.</h1>
<p>Афіша міста на одній мапі&nbsp;— і компанія, з якою піти</p>
</body></html>"""


def render(html, out, w, h):
    with tempfile.NamedTemporaryFile("w", suffix=".html", delete=False, encoding="utf-8") as f:
        f.write(html)
    subprocess.run(
        [CHROME, "--headless", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
         "--allow-file-access-from-files", "--virtual-time-budget=3000", f"--window-size={w},{h}",
         f"--screenshot={out}", f.name],
        check=True, capture_output=True,
    )
    pathlib.Path(f.name).unlink()
    print(out.relative_to(ROOT))


def main():
    for folder, prefix, plat, w, h in TARGETS:
        for old in (ROOT / "store" / folder).glob(f"{prefix}*.png"):
            old.unlink()  # слайдів могло стати менше
        for i, s in enumerate(SLIDES, 1):
            render(slide_html(s, plat, w, h), ROOT / "store" / folder / f"{prefix}{i:02d}.png", w, h)
    feature = (
        FEATURE.replace("{icon}", (ROOT / "store" / "play" / "icon_512.png").as_uri())
        .replace("{a}", (SCREENS / "and_map.png").as_uri())
        .replace("{b}", (SCREENS / "and_home.png").as_uri())
    )
    render(feature, ROOT / "store" / "play" / "feature_graphic_1024x500.png", 1024, 500)


if __name__ == "__main__":
    main()
