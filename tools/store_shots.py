"""Збирає графіку для сторів із сирих екранів у store/screens/.

Кожен слайд — HTML (фон, заголовок, телефон у рамці, «винесені» шматки
справжнього UI), який рендерить headless Chrome. Перезняти екрани після
зміни UI, оновити координати crop у SLIDES і запустити:

    python3 tools/store_shots.py
"""
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCREENS = ROOT / "store" / "screens"
ZOOM = 1.18
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# Сирі розміри екранів: iPhone 17 Pro і Pixel-емулятор.
RAW = {"ios": (1206, 2622), "and": (1280, 2856)}

# bg: (верх, низ, колір сяйва); dark — світлий текст.
# float: шматок UI (x0, y0, x1, y1, радіус кутів) у пікселях сирого екрана, який «піднімається»
# над своїм місцем: збільшений у ZOOM разів, з тінню і нахилом rot.
SLIDES = [
    dict(
        key="map", dark=True, bg=("#1d1a16", "#0e0d0b", "#D9603A"),
        eyebrow="Мапа міста", title="Що відбувається поруч",
        sub="Концерти, настолки, пробіжки й лекції на одній мапі",
        ios=[(50, 1911, 1042, 2244, 52, -3)],
        android=[(49, 409, 1227, 520, 55, -2)],
    ),
    dict(
        key="plans", bg=("#FBE7DE", "#F2C6B2", "#EE8B63"),
        eyebrow="Мої події", title="Ваш план на тиждень",
        sub="Куди йдете, що організовуєте й що зберегли на потім",
        ios=[(50, 1009, 1156, 1337, 52, -3)],
        android=[(49, 986, 1227, 1239, 50, -3)],
    ),
    dict(
        key="detail", bg=("#EFE8FB", "#CDBDF2", "#8B6BE0"),
        eyebrow="Афіша", title="Уся подія на одному екрані",
        sub="Час, місце, ціна квитка, маршрут і нагадування",
        ios=[(52, 1442, 1154, 1698, 60, 2)],
        android=[(41, 1247, 1239, 1513, 60, 2)],
    ),
    dict(
        key="community", bg=("#E4F2E6", "#B9DDBF", "#4E9A5B"),
        eyebrow="Спільнота", title="Зустрічі, які створюють люди",
        sub="Пікнік, пробіжка, настолки: приєднуйтесь одним дотиком",
        ios=[(50, 1738, 1156, 2294, 66, -3)],
        android=[(49, 1669, 1227, 2135, 57, -3)],
    ),
    dict(
        key="create", bg=("#E0F1EE", "#AFD9D1", "#2F9C8A"),
        eyebrow="Організуйте", title="Своя зустріч за три кроки",
        sub="Опис, точка на мапі, час і кількість місць",
        ios=[(427, 1485, 779, 1772, 52, -4)],
        android=[(454, 1464, 826, 1750, 41, -4)],
    ),
]

TARGETS = [
    # (тека, префікс, платформа, ширина, висота)
    ("appstore", "iphone69_", "ios", 1320, 2868),
    ("appstore", "iphone67_", "ios", 1290, 2796),
    ("appstore", "iphone65_", "ios", 1242, 2688),
    ("play", "phone_", "and", 1080, 1920),
]

CSS = """
*{margin:0;box-sizing:border-box}
html{font-size:calc(var(--w)/100)}
body{width:var(--w);height:var(--h);overflow:hidden;position:relative;
 font-family:-apple-system,"SF Pro Display",system-ui,sans-serif;color:var(--ink);
 background:linear-gradient(180deg,var(--top),var(--bottom))}
.glow{position:absolute;border-radius:50%;filter:blur(12rem);opacity:.55}
.head{position:absolute;left:7rem;right:7rem;top:var(--headtop);text-align:center}
.pill{display:inline-block;font-size:3rem;font-weight:600;letter-spacing:.02em;padding:1.2rem 3rem;
 border-radius:10rem;background:var(--pill);color:var(--pillink);margin-bottom:3.6rem}
h1{text-wrap:balance;font-size:var(--h1);line-height:1.02;font-weight:800;letter-spacing:-.035em}
p{text-wrap:balance;font-size:3.9rem;line-height:1.3;margin-top:3rem;opacity:.72;font-weight:500}
.stage{position:absolute;left:50%;top:var(--phonetop);width:var(--phonew);transform:translateX(-50%)}
.phone{position:relative;width:100%;border-radius:var(--rad);padding:var(--bezel);background:#0b0b0c;
 box-shadow:0 0 0 .35rem #3a3a3d inset,0 6rem 12rem rgba(0,0,0,.35),0 2rem 4rem rgba(0,0,0,.2)}
.phone img{display:block;width:100%;border-radius:calc(var(--rad) - var(--bezel))}
.hole{position:absolute;left:50%;top:calc(var(--bezel) + 1.6rem);width:2.6rem;height:2.6rem;margin-left:-1.3rem;
 border-radius:50%;background:#050505}
.float{position:absolute;background-repeat:no-repeat;
 box-shadow:0 4rem 9rem rgba(0,0,0,.28),0 1rem 2.5rem rgba(0,0,0,.14),0 0 0 .25rem rgba(255,255,255,.6)}
"""


def slide_html(s, plat, w, h):
    rw, rh = RAW[plat]
    tall = h / w > 2  # iPhone 19.5:9 проти Play 16:9
    phone_w = 78 if tall else 72  # rem
    bezel = 1.6
    screen_w = phone_w - 2 * bezel
    scale = screen_w / rw  # rem на сирий піксель
    top, bottom, glow = s["bg"]
    dark = s.get("dark", False)
    vars_ = {
        "--w": f"{w}px", "--h": f"{h}px", "--top": top, "--bottom": bottom,
        "--ink": "#F5F3EE" if dark else "#14130F",
        "--pill": "rgba(255,255,255,.12)" if dark else "rgba(20,19,15,.9)",
        "--pillink": "#F5F3EE",
        "--headtop": "13rem" if tall else "6rem",
        "--h1": "10rem" if tall else "8.6rem",
        "--phonetop": "76rem" if tall else "56rem",
        "--phonew": f"{phone_w}rem", "--rad": "11rem" if plat == "ios" else "8.5rem",
        "--bezel": f"{bezel}rem",
    }
    img = (SCREENS / f"{plat}_{s['key']}.png").as_uri()
    floats = []
    for x0, y0, x1, y1, rad, rot in s["ios" if plat == "ios" else "android"]:
        k = scale * ZOOM  # rem на сирий піксель у винесеному шматку
        fw, fh = (x1 - x0) * k, (y1 - y0) * k
        cx, cy = bezel + (x0 + x1) / 2 * scale, bezel + (y0 + y1) / 2 * scale
        floats.append(
            f'<div class="float" style="left:{cx - fw / 2}rem;top:{cy - fh / 2}rem;width:{fw}rem;height:{fh}rem;'
            f'border-radius:{rad * k}rem;transform:rotate({rot}deg);background-image:url({img});'
            f'background-size:{rw * k}rem {rh * k}rem;background-position:{-x0 * k}rem {-y0 * k}rem"></div>'
        )
    style = ";".join(f"{k}:{v}" for k, v in vars_.items())
    hole = '<div class="hole"></div>' if plat == "and" else ""
    return f"""<!doctype html><html style="{style}"><head><meta charset="utf-8"><style>{CSS}</style></head><body>
<div class="glow" style="background:{glow};width:90rem;height:90rem;left:-30rem;top:40rem"></div>
<div class="glow" style="background:{glow};width:70rem;height:70rem;right:-35rem;bottom:-10rem;opacity:.35"></div>
<div class="head"><div class="pill">{s['eyebrow']}</div><h1>{s['title']}</h1><p>{s['sub']}</p></div>
<div class="stage" style="height:{rh * scale + 2 * bezel}rem"><div class="phone"><img src="{img}">{hole}</div>{''.join(floats)}</div>
</body></html>"""


FEATURE = """<!doctype html><html><head><meta charset="utf-8"><style>
*{margin:0;box-sizing:border-box}
body{width:1024px;height:500px;overflow:hidden;position:relative;background:linear-gradient(120deg,#1d1a16,#0e0d0b);
 font-family:-apple-system,system-ui,sans-serif;color:#F5F3EE}
.glow{position:absolute;border-radius:50%;filter:blur(90px)}
.brand{position:absolute;left:64px;top:92px;display:flex;align-items:center;gap:16px;font-size:34px;font-weight:700}
.brand img{width:64px;height:64px;border-radius:15px}
h1{position:absolute;left:64px;top:190px;width:480px;font-size:54px;line-height:1.02;font-weight:800;letter-spacing:-.035em}
p{position:absolute;left:64px;top:326px;font-size:21px;opacity:.7;font-weight:500}
.ph{position:absolute;width:250px;padding:7px;border-radius:40px;background:#0b0b0c;
 box-shadow:0 0 0 2px #3a3a3d inset,0 30px 60px rgba(0,0,0,.5)}
.ph img{display:block;width:100%;border-radius:33px}
</style></head><body>
<div class="glow" style="background:#D9603A;width:420px;height:420px;right:40px;top:40px;opacity:.55"></div>
<div class="glow" style="background:#8B6BE0;width:300px;height:300px;right:-80px;bottom:-160px;opacity:.45"></div>
<div class="brand"><img src="{icon}">Поряд</div>
<h1>Події вашого міста на одній мапі</h1>
<p>Знаходьте, приєднуйтесь, створюйте власні</p>
<div class="ph" style="left:590px;top:70px;transform:rotate(-6deg)"><img src="{a}"></div>
<div class="ph" style="left:785px;top:40px;transform:rotate(5deg)"><img src="{b}"></div>
</body></html>"""


def render(html, out, w, h):
    with tempfile.NamedTemporaryFile("w", suffix=".html", delete=False, encoding="utf-8") as f:
        f.write(html)
    subprocess.run(
        [CHROME, "--headless", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
         "--allow-file-access-from-files", f"--window-size={w},{h}", f"--screenshot={out}", f.name],
        check=True, capture_output=True,
    )
    pathlib.Path(f.name).unlink()
    print(out.relative_to(ROOT))


def main():
    for folder, prefix, plat, w, h in TARGETS:
        for i, s in enumerate(SLIDES, 1):
            render(slide_html(s, plat, w, h), ROOT / "store" / folder / f"{prefix}{i:02d}.png", w, h)
    feature = (
        FEATURE.replace("{icon}", (ROOT / "store" / "play" / "icon_512.png").as_uri())
        .replace("{a}", (SCREENS / "and_map.png").as_uri())
        .replace("{b}", (SCREENS / "and_community.png").as_uri())
    )
    render(feature, ROOT / "store" / "play" / "feature_graphic_1024x500.png", 1024, 500)


if __name__ == "__main__":
    main()
