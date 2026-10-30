"""Збирає графіку для сторів із сирих екранів у store/screens/.

Світ «Корінець» (DESIGN.md): кожен слайд — квиток на нічному полотні. Угорі, на квитку, штамп і заголовок
Sofia Sans Condensed, підзаголовок системним гротеском платформи; за перфорацією — корінець кольору жанру показаної
події, з якого виростає телефон. На екрані — фокус, як у підказках першого знайомства: решту притемнено, а головний
компонент лишається на своєму місці й ледь піднятий. Рендерить headless Chrome. Перезняти екрани після зміни UI (див. store/listing.md),
оновити координати в SLIDES і запустити:

    python3 tools/store_shots.py
"""
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCREENS = ROOT / "store" / "screens"
FONTS = ROOT / "site" / "fonts"  # Sofia Sans з вшитою українською кирилицею — та сама, що на сайті й у застосунку
# Решта тексту — системний гротеск платформи, як у застосунку: SF Pro з macOS для App Store, Roboto з Android SDK для Play.
SYSTEM_FONT = {
    "ios": pathlib.Path("/System/Library/Fonts/SFNS.ttf"),
    "and": next(pathlib.Path.home().glob("Library/Android/sdk/platforms/*/data/fonts/Roboto-Regular.ttf"), None),
}
LIFT = 1.04  # наскільки піднятий компонент більший за себе на екрані
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# Сирі розміри екранів: iPhone 16 Pro і Android-емулятор з `wm size 1080x2400`.
RAW = {"ios": (1206, 2622), "and": (1080, 2400)}

# Перші три слайди видно в пошуку стору — на них головні гачки, і поки людей мало, це афіша, а не компанія. Жодних чужих постерів, облич, імен виконавців і
# логотипів (docs/legal-audit-afisha-2026-10-28.md, P0): знімати на dev, де обкладинки на час зйомки сховано. stub — колір корінця (`cat-*-stub`), як у застосунку:
# жанр події, яку показує слайд (рядок або {платформа: колір}, коли події різні); слайди про людей — «Зустрічі».
# ios/android: (x0, y0, x1, y1, радіус) у пікселях сирого екрана — точні межі компонента у фокусі (рамка картки з
# радіусом її кутів); без них — увесь екран. lift=False — лише притемнення довкола, без підйому: для ділянки без власних
# меж (градієнт обкладинки), де збільшена копія розійшлась би з фоном; така ділянка — смуга на всю ширину, бо рамка
# впритул до тексту на краю екрана виглядала б тісною.
SLIDES = [
    dict(
        key="map", stub="#8D6A11",  # стендап на картці
        # Слоган — у Header сторінки App Store (tools/store_creative.mjs), тут не повторюємо. Фокусу нема: мапа і є суть.
        stamp="Афіша на мапі", title="Афіша міста на&nbsp;одній мапі",
        sub="Концерти, вистави й зустрічі Києва, Львова, Одеси, Дніпра й Харкова",
    ),
    dict(
        key="deck", stub="#AC345E",  # вистави на картці
        stamp="Ваш тиждень", title="Куди піти — за хвилину",
        sub="Гортайте події під ваш смак: «Так» зберігає подію й нагадує напередодні",
        ios=(48, 730, 1158, 1634, 51), android=(42, 657, 1038, 1445, 48),
    ),
    # Квиток — згенерований PDF на два місця з власними QR, без марки продавця.
    dict(
        key="wallet", stub="#AC345E",  # «Три товариші», вистава
        stamp="Квитки", title="Квиток завжди під&nbsp;рукою",
        sub="Поділіться PDF-квитком із Telegram — покажемо код на весь екран і нагадаємо за годину",
        ios=(48, 559, 1158, 1669, 42), android=(42, 526, 1038, 1522, 34),
    ),
    # 1.4: компанію на dev шукають демо-профілі без фото (Соня, Денис, Іра). iOS знято з акаунтом — видно людей;
    # Android гостем — лише тизер.
    dict(
        key="company", stub="#A24C29",
        stamp="Компанія", title="Не хочете йти самі?",
        sub="Побачите, хто ще шукає компанію на подію й що у вас спільного",
        ios=(48, 1313, 1158, 2023, 48), android=(42, 1355, 1038, 1664, 34),
    ),
    dict(
        key="district", stub={"ios": "#8D6A11", "and": "#6041B1"},  # стендап / концерт на картці
        stamp="Район", title="Події біля дому",
        sub="Оберіть свій район — і мапа та список покажуть лише його",
    ),
    # Запрошення знято на dev: Марта (демо-профіль) кличе на «Дух Франції», рядок видно лише другу.
    dict(
        key="invite", stub="#6041B1",  # «Дух Франції», музика
        stamp="Покликати", title="Покличте друга",
        sub="Друг отримає посилання й побачить, що кличете саме ви",
        ios=(0, 940, 1206, 1374, 0), android=(0, 820, 1080, 1187, 0), lift=False,  # смуга до низу обкладинки
    ),
    dict(
        key="safety", stub="#AC345E",  # вистава в Театрі на Подолі
        stamp="Безпека", title="Укриття поруч&nbsp;— ще до виходу",
        sub="Найближчі укриття й час до комендантської біля кожної події. Укриття — поки що для Києва",
        ios=(48, 876, 1158, 1433, 48), android=(42, 1221, 1038, 1710, 34),
    ),
    dict(
        key="create", stub="#A24C29",
        stamp="Від людей", title="Зберіть своїх",
        sub="Настолки, пробіжка чи кіно: назва, точка на мапі й час — і квиток готовий",
        ios=(46, 454, 1160, 988, 44), android=(42, 252, 1038, 717, 34),
    ),
]

TARGETS = [
    # (тека, префікс, платформа, ширина, висота)
    ("appstore", "iphone69_", "ios", 1320, 2868),
    ("appstore", "iphone67_", "ios", 1290, 2796),
    ("appstore", "iphone65_", "ios", 1242, 2688),
    ("appstore", "iphone63_", "ios", 1206, 2622),  # обов'язковий слот ASC «Dynamic Island, medium display»
    ("play", "phone_", "and", 1080, 1920),
]


def system_font_css(plat):
    font = SYSTEM_FONT[plat]
    if not font or not font.exists():
        raise SystemExit(f"Нема системного шрифту для {plat}: {font} (SF Pro — macOS, Roboto — Android SDK platforms/*/data/fonts)")
    # SF змінний: opsz 17 — текстовий оптичний розмір, як у застосунку для підписів.
    opsz = ';font-variation-settings:"opsz" 17' if plat == "ios" else ""
    return f"@font-face{{font-family:Sys;src:url({font.as_uri()})}}p{{font-optical-sizing:none{opsz}}}"


FONT_CSS = f"""
@font-face{{font-family:Cond;font-weight:800;src:url({(FONTS / 'sofia-sans-condensed-800.woff2').as_uri()})}}
@font-face{{font-family:XCond;font-weight:800;src:url({(FONTS / 'sofia-sans-extra-condensed-800.woff2').as_uri()})}}
"""

# Нічна шкала з DESIGN.md: полотно, квиток, волосина, папір (головне чорнило вночі) і друге чорнило.
CSS = FONT_CSS + """
:root{--canvas:#0F0F13;--surface:#1C1B21;--hairline:#2E2D35;--paper:#F3F3F0;--ink2:#A6A5AD}
*{margin:0;box-sizing:border-box}
html{font-size:calc(var(--w)/100)}
body{width:var(--w);height:var(--h);overflow:hidden;position:relative;background:var(--canvas);
 font-family:Sys,sans-serif;-webkit-font-smoothing:antialiased;color:var(--paper)}
.ticket{position:absolute;left:4rem;right:4rem;top:4rem;bottom:-12rem;border-radius:5rem;overflow:hidden;
 background:radial-gradient(70rem 60rem at 50% calc(var(--perf) + 26rem),rgba(255,255,255,.16),transparent 70%),var(--stub)}
.main{position:absolute;left:0;right:0;top:0;height:calc(var(--perf) - 4rem);background:var(--surface);
 box-shadow:0 0 0 .15rem var(--hairline) inset}
/* Перфорація: крапки кольору полотна наскрізь і два півкруглі вирізи, як у TicketShape. */
.perf{position:absolute;left:9rem;right:9rem;top:calc(var(--perf) - .45rem);height:.9rem;
 background:radial-gradient(circle at .45rem .45rem,var(--canvas) .42rem,transparent .48rem) 0 0/1.7rem .9rem repeat-x}
.notch{position:absolute;top:calc(var(--perf) - 2.6rem);width:5.2rem;height:5.2rem;border-radius:50%;background:var(--canvas)}
.head{position:absolute;left:9.5rem;right:9.5rem;top:4rem;height:calc(var(--perf) - 4rem);display:flex;
 flex-direction:column;justify-content:center;align-items:flex-start}
.stamp{display:inline-block;font:800 var(--stampsize)/1 Cond,sans-serif;letter-spacing:.09em;text-transform:uppercase;
 color:var(--ink2);padding:.9rem 1.7rem .8rem;border:.32rem solid var(--ink2);border-radius:1rem;
 transform:rotate(-4deg);transform-origin:left center;margin-bottom:var(--gap1)}
h1{font:800 var(--h1)/.94 Cond,sans-serif;letter-spacing:-.012em;text-wrap:balance;max-width:81rem}
p{font-size:var(--sub);line-height:1.36;margin-top:var(--gap2);color:var(--ink2);text-wrap:pretty;max-width:76rem}
.phone{position:absolute;left:50%;top:var(--phonetop);width:var(--phonew);transform:translateX(-50%);
 border-radius:var(--rad);padding:var(--bezel);background:linear-gradient(160deg,#3a3a3e,#111113 40%,#1c1c1f);
 box-shadow:0 0 0 .22rem rgba(255,255,255,.14) inset,0 0 0 .3rem rgba(0,0,0,.35),0 8rem 16rem rgba(0,0,0,.45),
 0 2rem 4rem rgba(0,0,0,.25)}
.screen{position:relative;overflow:hidden;border-radius:calc(var(--rad) - var(--bezel))}
.screen img{display:block;width:100%}
.hole{position:absolute;left:50%;top:calc(var(--bezel) + 1.5rem);width:2.4rem;height:2.4rem;margin-left:-1.2rem;
 border-radius:50%;background:#050505}
/* Фокус, як у підказках першого знайомства (DESIGN.md): притемнення з вирізом під справжню ціль. */
.spot{position:absolute;box-shadow:0 0 0 400rem rgba(15,15,19,.62)}
.lift{position:absolute;background-repeat:no-repeat;
 box-shadow:0 0 0 .14rem rgba(243,243,240,.18),0 3rem 7rem rgba(0,0,0,.6),0 .8rem 2rem rgba(0,0,0,.35)}
"""


def slide_html(s, plat, w, h):
    rw, rh = RAW[plat]
    tall = h / w > 2  # iPhone 19.5:9 проти Play 16:9
    perf = 77 if tall else 63  # однакова лінія відриву на всіх слайдах набору — у ряду стору вони читаються пачкою
    phone_w = 74 if tall else 64
    phone_top = perf + 7
    bezel = 1.25
    scale = (phone_w - 2 * bezel) / rw  # rem на сирий піксель
    vars_ = {
        "--w": f"{w}px", "--h": f"{h}px", "--stub": s["stub"] if isinstance(s["stub"], str) else s["stub"][plat], "--perf": f"{perf}rem",
        "--stampsize": "3.3rem" if tall else "3rem",
        "--h1": "13.4rem" if tall else "11.2rem",
        "--sub": "3.7rem" if tall else "3.3rem",
        "--gap1": "4.6rem" if tall else "3.4rem",
        "--gap2": "3.4rem" if tall else "2.6rem",
        "--phonetop": f"{phone_top}rem", "--phonew": f"{phone_w}rem",
        "--rad": "10rem" if plat == "ios" else "8rem", "--bezel": f"{bezel}rem",
    }
    img = (SCREENS / f"{plat}_{s['key']}.png").as_uri()
    focus = ""
    box = s.get("ios" if plat == "ios" else "android")
    if box:
        x0, y0, x1, y1, rad = box
        k = scale * (LIFT if s.get("lift", True) else 1)  # rem на сирий піксель у піднятому компоненті
        cx, cy = (x0 + x1) / 2 * scale, (y0 + y1) / 2 * scale  # центр компонента на екрані, rem
        spot = (f'left:{x0 * scale}rem;top:{y0 * scale}rem;width:{(x1 - x0) * scale}rem;'
                f'height:{(y1 - y0) * scale}rem;border-radius:{rad * scale}rem')
        if s.get("lift", True):
            fw, fh = (x1 - x0) * k, (y1 - y0) * k
            focus = (f'<div class="spot" style="{spot}"></div>'
                     f'<div class="lift" style="left:{cx - fw / 2}rem;top:{cy - fh / 2}rem;width:{fw}rem;height:{fh}rem;'
                     f'border-radius:{rad * k}rem;background-image:url({img});background-size:{rw * k}rem {rh * k}rem;'
                     f'background-position:{-x0 * k}rem {-y0 * k}rem"></div>')
        else:
            focus = f'<div class="spot" style="{spot}"></div>'
    style = ";".join(f"{name}:{value}" for name, value in vars_.items())
    hole = '<div class="hole"></div>' if plat == "and" else ""
    return f"""<!doctype html><html style="{style}"><head><meta charset="utf-8"><style>{system_font_css(plat)}{CSS}</style></head><body>
<div class="ticket"><div class="main"></div></div>
<div class="perf"></div><div class="notch" style="left:1.4rem"></div><div class="notch" style="right:1.4rem"></div>
<div class="head"><div class="stamp">{s['stamp']}</div><h1>{s['title']}</h1><p>{s['sub']}</p></div>
<div class="phone"><div class="screen"><img src="{img}">{focus}</div>{hole}</div>
</body></html>"""


# Банер Play — горизонтальний квиток: слоган на квитку, за вертикальною перфорацією корінець із двома телефонами.
FEATURE = """<!doctype html><html><head><meta charset="utf-8"><style>{sys}""" + FONT_CSS + """
*{margin:0;box-sizing:border-box}
body{width:1024px;height:500px;overflow:hidden;position:relative;background:#0F0F13;color:#F3F3F0;
 font-family:Sys,sans-serif;-webkit-font-smoothing:antialiased}
.ticket{position:absolute;inset:28px;border-radius:26px;overflow:hidden;background:#A24C29}
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
        FEATURE.replace("{sys}", system_font_css("and"))
        .replace("{icon}", (ROOT / "store" / "play" / "icon_512.png").as_uri())
        .replace("{a}", (SCREENS / "and_map.png").as_uri())
        .replace("{b}", (SCREENS / "and_deck.png").as_uri())
    )
    render(feature, ROOT / "store" / "play" / "feature_graphic_1024x500.png", 1024, 500)


if __name__ == "__main__":
    main()
