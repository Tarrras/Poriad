"""Збирає графіку для сторів із сирих екранів у store/screens/.

Кожен слайд — HTML (фон у мові бренду, заголовок Source Serif 4, великий телефон, обрізаний краєм,
і «винесений» над ним шматок справжнього UI), який рендерить headless Chrome. Перезняти екрани після
зміни UI (див. store/listing.md), оновити координати crop у SLIDES і запустити:

    python3 tools/store_shots.py
"""
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCREENS = ROOT / "store" / "screens"
FONTS = ROOT / "site" / "fonts"  # ті самі Inter і Source Serif 4, що на сайті й у застосунку
ZOOM = 1.12
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# Сирі розміри екранів: iPhone 16 Pro і Pixel-емулятор.
RAW = {"ios": (1206, 2622), "and": (1280, 2856)}

# Перші три слайди видно в пошуку стору — на них головні гачки.
# tint: сяйво слайда (dark — темний слайд). float: (x0, y0, x1, y1, радіус, нахил) у пікселях сирого екрана —
# шматок UI, збільшений у ZOOM разів з тінню; якщо його місце нижче краю слайда, він піднімається у видиму частину.
SLIDES = [
    dict(
        key="map", dark=True, tint="#3B2F8F",
        eyebrow="Київ · Львів · Одеса · Дніпро · Харків", pin=True,
        title="Куди піти сьогодні ввечері?",
        sub="Концерти, вистави й зустрічі міста на одній мапі",
        ios=(87, 1914, 1080, 2242, 78, -2), android=(49, 2208, 1137, 2529, 63, -2),
    ),
    dict(
        key="detail", tint="#F1D9BC",
        eyebrow="Афіша", title="Увесь вечір на одному екрані",
        sub="Дати, ціна, маршрут і календар. Квиток — на сайті організатора",
        ios=(39, 2097, 1167, 2485, 84, 2), android=(37, 2320, 1243, 2757, 69, 2),
    ),
    dict(
        key="companions", tint="#F4D3DE",
        eyebrow="Шукаю компанію", title="Не хочете йти самі?",
        sub="Зберіть невелику компанію на концерт — ви вирішуєте, кого взяти",
        ios=(50, 755, 1156, 1001, 72, -2), android=(49, 1694, 1231, 1940, 51, -2),
    ),
    dict(
        key="safety", tint="#D3E6D5",
        eyebrow="Безпека", title="Укриття поруч&nbsp;— ще до виходу",
        sub="Найближчі укриття, метро й час до комендантської. Поки що для Києва",
        ios=(50, 910, 1156, 1657, 72, -1.5), android=(49, 1046, 1231, 1788, 51, -1.5),
    ),
    dict(
        key="home", tint="#E4E1F6",
        eyebrow="Афіша й люди", title="Не лише афіша, а й люди поруч",
        sub="Концерти з квиткових сервісів і настолки, пробіжки, кіно від сусідів",
        ios=(50, 524, 1156, 763, 72, -2), android=(49, 494, 1231, 697, 63, -2),
    ),
    dict(
        key="create", tint="#D6E2F6",
        eyebrow="Свої зустрічі", title="Зберіть своїх за три кроки",
        sub="Настолки, пробіжка чи кіно: опис, місце й час",
        ios=(427, 1940, 779, 2223, 60, -4), android=(451, 1863, 829, 2146, 46, -4),
    ),
]

TARGETS = [
    # (тека, префікс, платформа, ширина, висота)
    ("appstore", "iphone69_", "ios", 1320, 2868),
    ("appstore", "iphone67_", "ios", 1290, 2796),
    ("appstore", "iphone65_", "ios", 1242, 2688),
    ("play", "phone_", "and", 1080, 1920),
]

PIN = ('<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" '
       'stroke-linejoin="round"><path d="M12 21C12 21 4.8 13.6 4.8 9.4C4.8 5.4 8 2.8 12 2.8C16 2.8 19.2 5.4 19.2 '
       '9.4C19.2 13.6 12 21 12 21ZM9.2 9.4a2.8 2.8 0 1 0 5.6 0a2.8 2.8 0 1 0-5.6 0Z"/></svg>')

FONT_CSS = f"""
@font-face{{font-family:Inter;font-weight:400;src:url({(FONTS / 'inter-cyrillic-400-normal.woff2').as_uri()});unicode-range:U+0400-045F,U+0490-0491}}
@font-face{{font-family:Inter;font-weight:500;src:url({(FONTS / 'inter-cyrillic-500-normal.woff2').as_uri()});unicode-range:U+0400-045F,U+0490-0491}}
@font-face{{font-family:Inter;font-weight:600;src:url({(FONTS / 'inter-cyrillic-600-normal.woff2').as_uri()});unicode-range:U+0400-045F,U+0490-0491}}
@font-face{{font-family:Inter;font-weight:400;src:url({(FONTS / 'inter-latin-400-normal.woff2').as_uri()});unicode-range:U+0000-00FF,U+2000-206F}}
@font-face{{font-family:Inter;font-weight:500;src:url({(FONTS / 'inter-latin-500-normal.woff2').as_uri()});unicode-range:U+0000-00FF,U+2000-206F}}
@font-face{{font-family:Inter;font-weight:600;src:url({(FONTS / 'inter-latin-600-normal.woff2').as_uri()});unicode-range:U+0000-00FF,U+2000-206F}}
@font-face{{font-family:Serif;font-weight:600;src:url({(FONTS / 'source-serif-4-600.woff2').as_uri()})}}
"""

CSS = FONT_CSS + """
*{margin:0;box-sizing:border-box}
html{font-size:calc(var(--w)/100)}
body{width:var(--w);height:var(--h);overflow:hidden;position:relative;color:var(--ink);
 font-family:Inter,-apple-system,sans-serif;-webkit-font-smoothing:antialiased;background:var(--bg)}
.glow{position:absolute;border-radius:50%;filter:blur(14rem)}
.head{position:absolute;left:6rem;right:6rem;top:var(--headtop);text-align:center;display:flex;flex-direction:column;align-items:center}
.eyebrow{display:inline-flex;align-items:center;gap:1rem;height:6.4rem;padding:0 3rem;border-radius:10rem;
 font-weight:500;font-size:2.9rem;letter-spacing:.01em;background:var(--chip);color:var(--chipink);
 box-shadow:0 0 0 .18rem var(--chipline) inset;margin-bottom:var(--gap1)}
.eyebrow svg{width:3rem;height:3rem}
h1{font-family:Serif,Georgia,serif;font-weight:600;font-size:var(--h1);line-height:1.04;letter-spacing:-.025em;
 text-wrap:balance;max-width:88rem}
p{font-size:var(--sub);line-height:1.38;margin-top:var(--gap2);color:var(--ink2);text-wrap:balance;max-width:82rem}
.phone{position:absolute;left:50%;top:var(--phonetop);width:var(--phonew);transform:translateX(-50%);
 border-radius:var(--rad);padding:var(--bezel);background:linear-gradient(160deg,#3a3a3e,#111113 40%,#1c1c1f);
 box-shadow:0 0 0 .22rem rgba(255,255,255,.14) inset,0 0 0 .3rem var(--rim),0 10rem 20rem var(--shadow),0 3rem 6rem rgba(0,0,0,.12)}
.phone img{display:block;width:100%;border-radius:calc(var(--rad) - var(--bezel))}
.hole{position:absolute;left:50%;top:calc(var(--bezel) + 1.5rem);width:2.4rem;height:2.4rem;margin-left:-1.2rem;
 border-radius:50%;background:#050505}
.float{position:absolute;background-repeat:no-repeat;
 box-shadow:0 0 0 .22rem rgba(255,255,255,.75),0 5rem 11rem rgba(18,16,40,.28),0 1.2rem 3rem rgba(0,0,0,.12)}
"""


def slide_html(s, plat, w, h):
    rw, rh = RAW[plat]
    tall = h / w > 2  # iPhone 19.5:9 проти Play 16:9
    page_h = h / w * 100  # висота слайда в rem
    phone_w = 82 if tall else 72
    phone_top = 63 if tall else 49
    bezel = 1.25
    scale = (phone_w - 2 * bezel) / rw  # rem на сирий піксель
    dark = s.get("dark", False)
    tint = s["tint"]
    vars_ = {
        "--w": f"{w}px", "--h": f"{h}px",
        "--bg": "#0B0B0F" if dark else "#F5F5F7",
        "--ink": "#F5F5F7" if dark else "#1D1D1F",
        "--ink2": "rgba(245,245,247,.68)" if dark else "#6E6E73",
        "--chip": "rgba(255,255,255,.08)" if dark else "rgba(255,255,255,.85)",
        "--chipink": "#F5F5F7" if dark else "#1D1D1F",
        "--chipline": "rgba(255,255,255,.14)" if dark else "rgba(29,29,31,.06)",
        "--rim": "#4a4a50" if dark else "#c9c9cf",
        "--shadow": "rgba(0,0,0,.55)" if dark else "rgba(30,26,60,.22)",
        "--headtop": "12rem" if tall else "7rem",
        "--h1": "9.4rem" if tall else "8rem",
        "--sub": "3.5rem" if tall else "3.2rem",
        "--gap1": "4rem" if tall else "3rem",
        "--gap2": "2.8rem" if tall else "2.2rem",
        "--phonetop": f"{phone_top}rem", "--phonew": f"{phone_w}rem",
        "--rad": "10.5rem" if plat == "ios" else "8rem", "--bezel": f"{bezel}rem",
    }
    img = (SCREENS / f"{plat}_{s['key']}.png").as_uri()
    x0, y0, x1, y1, rad, rot = s["ios" if plat == "ios" else "android"]
    k = scale * ZOOM  # rem на сирий піксель у винесеному шматку
    fw, fh = (x1 - x0) * k, (y1 - y0) * k
    left = (100 - phone_w) / 2 + bezel + (x0 + x1) / 2 * scale - fw / 2
    top = phone_top + bezel + (y0 + y1) / 2 * scale - fh / 2
    top = min(top, page_h - fh - 7)  # шматок, що опинився б під краєм, піднімається у видиму частину
    left = max(3, min(left, 97 - fw))
    float_ = (
        f'<div class="float" style="left:{left}rem;top:{top}rem;width:{fw}rem;height:{fh}rem;'
        f'border-radius:{rad * k}rem;transform:rotate({rot}deg);background-image:url({img});'
        f'background-size:{rw * k}rem {rh * k}rem;background-position:{-x0 * k}rem {-y0 * k}rem"></div>'
    )
    glows = (
        f'<div class="glow" style="background:{tint};width:150rem;height:110rem;left:-25rem;top:-45rem;opacity:{.9 if dark else 1}"></div>'
        f'<div class="glow" style="background:{"#E0582F" if dark else tint};width:90rem;height:90rem;right:-40rem;'
        f'top:{page_h * .55}rem;opacity:{.22 if dark else .7}"></div>'
    )
    style = ";".join(f"{k}:{v}" for k, v in vars_.items())
    hole = '<div class="hole"></div>' if plat == "and" else ""
    pin = PIN if s.get("pin") else ""
    return f"""<!doctype html><html style="{style}"><head><meta charset="utf-8"><style>{CSS}</style></head><body>
{glows}
<div class="head"><div class="eyebrow">{pin}{s['eyebrow']}</div><h1>{s['title']}</h1><p>{s['sub']}</p></div>
<div class="phone"><img src="{img}">{hole}</div>{float_}
</body></html>"""


FEATURE = """<!doctype html><html><head><meta charset="utf-8"><style>""" + FONT_CSS + """
*{margin:0;box-sizing:border-box}
body{width:1024px;height:500px;overflow:hidden;position:relative;background:#0B0B0F;color:#F5F5F7;
 font-family:Inter,sans-serif;-webkit-font-smoothing:antialiased}
.glow{position:absolute;border-radius:50%;filter:blur(110px)}
.brand{position:absolute;left:64px;top:84px;display:flex;align-items:center;gap:14px;font:600 30px/1 Serif,serif}
.brand img{width:52px;height:52px;border-radius:13px}
h1{position:absolute;left:64px;top:170px;width:430px;font:600 56px/1.04 Serif,serif;letter-spacing:-.025em}
p{position:absolute;left:64px;top:304px;width:380px;font-size:20px;line-height:1.4;color:rgba(245,245,247,.68)}
.ph{position:absolute;width:236px;padding:6px;border-radius:38px;background:linear-gradient(160deg,#3a3a3e,#111113 40%,#1c1c1f);
 box-shadow:0 0 0 1px #4a4a50,0 30px 70px rgba(0,0,0,.6)}
.ph img{display:block;width:100%;border-radius:32px}
</style></head><body>
<div class="glow" style="background:#3B2F8F;width:560px;height:460px;right:-40px;top:-120px;opacity:.95"></div>
<div class="glow" style="background:#E0582F;width:300px;height:300px;right:120px;bottom:-200px;opacity:.3"></div>
<div class="brand"><img src="{icon}">Поряд</div>
<h1>Куди піти сьогодні ввечері?</h1>
<p>Концерти, вистави й зустрічі міста на одній мапі</p>
<div class="ph" style="left:572px;top:66px;transform:rotate(-6deg)"><img src="{a}"></div>
<div class="ph" style="left:776px;top:36px;transform:rotate(5deg)"><img src="{b}"></div>
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
        .replace("{b}", (SCREENS / "and_detail.png").as_uri())
    )
    render(feature, ROOT / "store" / "play" / "feature_graphic_1024x500.png", 1024, 500)


if __name__ == "__main__":
    main()
