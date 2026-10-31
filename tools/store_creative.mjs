// Креативні ассети з нічною мапою «Корінця»: Header і Search Results App Store (iOS 27), постер 16:9 і тло роликів 16:9.
//
//     node tools/store_creative.mjs [header|search|poster|map…]
//
// Безпечні зони — з шаблонів Apple (developer.apple.com/app-store/asset-best-practices, PSD «Art Safe Area»):
// Header 3840×1646 — 1646×661 по центру, Search Results 3840×2560 — 2168×1030 по центру. Усе важливе стоїть
// у них, решта полотна — те, що пристрій може обрізати. Світ «Корінець» (DESIGN.md): квитки на нічному полотні.
// Search Results — справжня мапа Києва стилем застосунку (порт у site/js/poriad.js, тайли OpenFreeMap), тож
// потрібна мережа. Рендер — Chrome через DevTools: віртуальний час headless не чекає тайлів мапи.
import { spawn } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { cityOf, discover, mapStyle } from "../site/js/poriad.js";

const ROOT = fileURLToPath(new URL("..", import.meta.url));
const OUT = join(ROOT, "store", "appstore");
const CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const font = (file) => pathToFileURL(join(ROOT, "site", "fonts", file)).href;
// Гліфи застосунку (tools/generate_icons.py), той самий спрайт, що на сайті.
const ICONS = readFileSync(join(ROOT, "site", "img", "icons.svg"), "utf8").replace("<svg ", '<svg style="display:none" ');

// Нічна шкала й корінці жанрів (`cat-*-stub`) з DESIGN.md.
const C = { canvas: "#0F0F13", surface: "#1C1B21", raised: "#26252C", hairline: "#2E2D35", paper: "#F3F3F0", ink2: "#A6A5AD", ink3: "#96959E" };
const STUB = { music: "#6041B1", food: "#B15D1A", social: "#A24C29", outdoors: "#376E33", games: "#2957AC", art: "#AC345E", comedy: "#8D6A11", sport: "#0D7065", kids: "#1B7979", tours: "#54701B", conference: "#813794" };
const CAT = { music: "#6D4AC9", art: "#C43B6B", comedy: "#A07813", games: "#2F63C4", social: "#B8562F", outdoors: "#3E7D3A", food: "#C96A1E", sport: "#0F7F73", kids: "#1F8A8A", tours: "#5F7F1F", conference: "#933FA8" };
// `categoryInk` уночі — відтінок із 45 % білого.
const inkOf = (hex) => "#" + [1, 3, 5].map((i) => Math.round(parseInt(hex.slice(i, i + 2), 16) * 0.55 + 255 * 0.45).toString(16).padStart(2, "0")).join("");

const FONTS = `
@font-face{font-family:Cond;font-weight:700;src:url(${font("sofia-sans-condensed-700.woff2")})}
@font-face{font-family:Cond;font-weight:800;src:url(${font("sofia-sans-condensed-800.woff2")})}
@font-face{font-family:XCond;font-weight:800;src:url(${font("sofia-sans-extra-condensed-800.woff2")})}
`;
const SF = `@font-face{font-family:Sys;src:url(${pathToFileURL("/System/Library/Fonts/SFNS.ttf").href})}`;
// У рекламі поза стором гротеск — Inter: ліцензія SF Pro дозволяє його лише в макетах інтерфейсу Apple-платформ.
const INTER = [400, 600].flatMap((wt) => [["cyrillic", "U+0400-045F,U+0490-0491,U+2116"], ["latin", "U+0000-00FF,U+2000-206F"]]
  .map(([set, range]) => `@font-face{font-family:Sys;font-weight:${wt};src:url(${font(`inter-${set}-${wt}-normal.woff2`)});unicode-range:${range}}`)).join("");
const BASE = `
*{margin:0;box-sizing:border-box}
body{background:${C.canvas};color:${C.paper};font-family:Sys,sans-serif;-webkit-font-smoothing:antialiased;overflow:hidden;position:relative}
.t{position:absolute}.shape{position:absolute;inset:0;overflow:visible}
.main{position:absolute;top:0;bottom:0;left:0;display:flex;flex-direction:column;justify-content:center}
.stub{position:absolute;top:0;bottom:0;right:0;display:flex;flex-direction:column;align-items:center;justify-content:center;color:#fff}
.genre{font:800 var(--genre)/1 Cond;letter-spacing:.06em;text-transform:uppercase}
.time{font:800 var(--time)/1 XCond;font-variant-numeric:tabular-nums}
.day{font:600 var(--day)/1 Sys;letter-spacing:.06em;text-transform:uppercase}
.ico{width:1em;height:1em;flex:none}
`;
const CSS = FONTS + SF + BASE;

/**
 * Горизонтальний квиток (`TicketShape`): радіус r, корінець stub завширшки праворуч, на лінії відриву два
 * півкруглі вирізи n і перфорація кольору полотна. u — масштаб у CSS px на pt застосунку.
 */
let clipSeq = 0;
function ticket({ x, y, w, h, u, stub, fill, main = "", stubHtml = "", pad = 16 }) {
  const r = 18 * u, n = 7 * u, s = w - stub, id = `k${clipSeq++}`;
  const d = `M${r} 0H${s - n}A${n} ${n} 0 0 0 ${s + n} 0H${w - r}A${r} ${r} 0 0 1 ${w} ${r}V${h - r}A${r} ${r} 0 0 1 ${w - r} ${h}`
    + `H${s + n}A${n} ${n} 0 0 0 ${s - n} ${h}H${r}A${r} ${r} 0 0 1 0 ${h - r}V${r}A${r} ${r} 0 0 1 ${r} 0Z`;
  return `<div class="t" style="left:${x}px;top:${y}px;width:${w}px;height:${h}px">
<svg class="shape" viewBox="0 0 ${w} ${h}" width="${w}" height="${h}"><clipPath id="${id}"><path d="${d}"/></clipPath>
<path d="${d}" fill="${C.surface}"/><rect x="${s}" y="0" width="${stub}" height="${h}" fill="${fill}" clip-path="url(#${id})"/>
<line x1="${s}" x2="${s}" y1="${n + 11 * u}" y2="${h - n - 11 * u}" stroke="${C.canvas}" stroke-width="${2.5 * u}" stroke-linecap="round" stroke-dasharray="0 ${6 * u}"/>
<path d="${d}" fill="none" stroke="${C.hairline}" stroke-width="${u}"/></svg>
<div class="main" style="width:${s}px;padding:0 ${pad * u}px">${main}</div>
<div class="stub" style="width:${stub}px;--genre:${13 * u}px;--time:${34 * u}px;--day:${11 * u}px">${stubHtml}</div></div>`;
}

// `StubTime`: жанр словом, година, день; у зустрічі від людей — ще гліф людей і місця.
const stubTime = (genre, time, day) => `<div class="genre">${genre}</div><div class="time" style="margin:.12em 0 .14em">${time}</div><div class="day">${day}</div>`;
const seats = (u, n) => `<div style="display:flex;align-items:center;gap:${4 * u}px;margin-top:${8 * u}px;font:800 ${20 * u}px/1 XCond;font-variant-numeric:tabular-nums">`
  + `<svg class="ico" style="width:${20 * u}px;height:${20 * u}px"><use href="#i-people"/></svg>${n}</div>`;
// Незадрукований рядок, як у `BlankTicket`.
const blank = (u, w) => `<div style="width:${w};height:${6 * u}px;border-radius:${3 * u}px;background:${C.hairline};margin-top:${8 * u}px"></div>`;

// Пачка квитків цеглою на W×H: менші квитки без назв, жанри — за часткою в афіші тижня (мистецтво, музика, стендап, дітям).
function ticketWall(W, H) {
  const wu = 1.5, wh = 112 * wu, mix = ["art", "music", "art", "comedy", "kids", "art", "music", "comedy"];
  const times = ["18:00", "19:00", "19:30", "20:00", "18:30", "21:00", "17:00"], widths = [380, 460, 340, 420, 500];
  const wall = [];
  for (let rIdx = 0, ry = -wh * 0.6; ry < H + wh; rIdx++, ry += wh + 16) {
    for (let i = 0, rx = -260 - (rIdx % 3) * 150; rx < W + 300; i++) {
      const j = rIdx * 7 + i, w = widths[j % widths.length], g = mix[(j * 5 + rIdx) % mix.length];
      wall.push(ticket({ x: rx, y: ry, w, h: wh, u: wu, stub: 84 * wu, fill: STUB[g], pad: 16,
        main: blank(wu, "70%") + blank(wu, "40%"), stubHtml: `<div class="time">${times[j % times.length]}</div>` }));
      rx += w + 16;
    }
  }
  return wall;
}

// ---- Header 3840×1646 (CSS 1920×823 при ×2). Безпечна зона: x 548.5–1371.5, y 246.5–577.
// У безпечній зоні — квиток зі слоганом: корінець стендапу на сьогодні з місцями «2/4» сам несе обидві половини,
// «є куди» (час) і «буде з ким» (місця), тож на iPhone, де лишається лише він, вистачає одного квитка. Обабіч —
// афіша й компанія на неї для ширших екранів, позаду — притемнена пачка вечірніх квитків замість голого полотна.
function headerHtml() {
  const u = 2.25, h = 310, y = (823 - h) / 2, stub = 84 * u, gap = 12 * u;
  const cw = 760, cx = (1920 - cw) / 2, sw = 500;
  const title = (t) => `<div style="font:700 ${24 * u}px/1.08 Cond;letter-spacing:-.004em">${t}</div>`;
  const place = (color, t) => `<div style="display:flex;align-items:center;gap:${8 * u}px;margin-top:${10 * u}px;font-size:${15 * u}px;color:${C.ink2}">`
    + `<span style="width:${8 * u}px;height:${8 * u}px;border-radius:50%;background:${color}"></span>${t}</div>`;
  // `HostLine`: буквений аватар 20 і «Збирає {імʼя}» caption.
  const host = `<div style="display:flex;align-items:center;gap:${6 * u}px;margin-top:${10 * u}px;font-size:${13 * u}px;color:${C.ink2};white-space:nowrap">`
    + `<span style="width:${20 * u}px;height:${20 * u}px;border-radius:50%;background:${C.hairline};color:${C.paper};display:grid;place-items:center;font-weight:600;font-size:${11 * u}px">О</span>Збирає Оля</div>`;
  const row = [
    ticket({ x: cx - sw - gap, y, w: sw, h, u, stub, fill: STUB.music, pad: 14, stubHtml: stubTime("Музика", "19:00", "Сьогодні"),
      main: title("Камерний<br>концерт") + place(inkOf(CAT.music), "Поділ") }),
    ticket({ x: cx, y, w: cw, h, u, stub, fill: STUB.comedy, pad: 20, stubHtml: stubTime("Стендап", "20:00", "Сьогодні") + seats(u, "2/4"),
      main: `<div data-fit style="font:800 ${56 * u}px/.94 Cond;letter-spacing:-.012em;white-space:nowrap">Є куди.<br>Буде з ким.</div>` }),
    // Компанія на той самий концерт («Разом на: …» у застосунку): збір за пів години до початку.
    ticket({ x: cx + cw + gap, y, w: sw, h, u, stub, fill: STUB.social, pad: 14, stubHtml: stubTime("Зустрічі", "18:30", "Сьогодні") + seats(u, "3/5"),
      main: title("Разом<br>на концерт") + host }),
  ];
  const wall = ticketWall(1920, 823);
  // Слоган — найбільший кегль, з яким «Буде з ким.» ще вміщається в рядок квитка.
  return `<!doctype html><html><head><meta charset="utf-8"><style>${CSS}body{width:1920px;height:823px}
.wall{position:absolute;inset:0;transform:rotate(-7deg) scale(1.12)}
.veil{position:absolute;inset:0;background:${C.canvas};opacity:.88}</style></head>
<body>${ICONS}<div class="wall">${wall.join("")}</div><div class="veil"></div>${row.join("")}<script>document.fonts.ready.then(() => {
  for (const el of document.querySelectorAll("[data-fit]"))
    for (let s = parseFloat(getComputedStyle(el).fontSize); el.scrollWidth > el.clientWidth; ) el.style.fontSize = (s -= 1) + "px";
  document.title = "ready";
})</script></body></html>`;
}

// ---- Нічна мапа міста зі справжніми подіями тижня: Search Results, постер 16:9 і тло роликів 16:9.
// Кластери-квитки й піни стоять там, де події, кластеризовані як у застосунку. Ліворуч — фраза-гачок і квиток
// вибраної події, праворуч — центр міста з кластерами, щоб і в найвужчому кадрі було видно, що це мапа подій.
const U = 2;
// Кластер — квиток 46×28 з вирізами 4,5 з боків, заливка папером, край 2 кольором поверхні; від 2 до 60 подій росте до ×1,3.
function cluster(x, y, count) {
  const k = 1 + 0.3 * Math.min(1, Math.max(0, (count - 2) / 58));
  const w = 46 * U * k, h = 28 * U * k, r = 7 * U * k, n = 4.5 * U * k;
  const d = `M${r} 0H${w - r}A${r} ${r} 0 0 1 ${w} ${r}V${h / 2 - n}A${n} ${n} 0 0 0 ${w} ${h / 2 + n}V${h - r}A${r} ${r} 0 0 1 ${w - r} ${h}`
    + `H${r}A${r} ${r} 0 0 1 0 ${h - r}V${h / 2 + n}A${n} ${n} 0 0 0 0 ${h / 2 - n}V${r}A${r} ${r} 0 0 1 ${r} 0Z`;
  return `<div class="t" style="left:${x - w / 2}px;top:${y - h / 2}px;width:${w}px;height:${h}px;filter:drop-shadow(0 ${2 * U}px ${5 * U}px rgba(0,0,0,.25))">
<svg class="shape" viewBox="0 0 ${w} ${h}" width="${w}" height="${h}"><path d="${d}" fill="${C.paper}" stroke="${C.surface}" stroke-width="${2 * U}"/></svg>
<div style="position:absolute;inset:0;display:grid;place-items:center;font:700 ${(13 + 3 * (k - 1) / 0.3) * U}px/1 Sys;color:#141417">${count}</div></div>`;
}
// Пін категорії: коло поверхні з кільцем і гліфом кольору жанру; вибраний — залитий корінцевим відтінком, гліф білий.
function pin(x, y, cat, on = false) {
  const size = (on ? 52 : 44) * U, glyph = CAT[cat] ? cat : "pin", hue = CAT[cat] || C.ink3;
  return `<div class="t" style="left:${x - size / 2}px;top:${y - size / 2}px;width:${size}px;height:${size}px;border-radius:50%;display:grid;place-items:center;
background:${on ? STUB[cat] : C.surface};box-shadow:0 0 0 ${3 * U}px ${on ? C.paper : hue}${on ? `,0 ${8 * U / 3}px ${8 * U}px rgba(0,0,0,.45)` : ""};color:${on ? "#fff" : inkOf(hue)}">
<svg class="ico" style="width:${22 * U}px;height:${22 * U}px"><use href="#i-${glyph}"/></svg></div>`;
}

// Квиток вибраної події: друкована сторона з назвою й рядком під нею, корінець 84 з жанром, часом і днем, як панель дії на деталях.
const K = 2;
const pick = (x, y, below) => ticket({ x, y, w: 343 * K, h: 116 * K, u: K, stub: 84 * K, fill: STUB.music,
  main: `<div style="font:700 ${20 * K}px/1.15 Cond">Джазовий вечір</div>` + below, stubHtml: stubTime("Музика", "19:30", "Сьогодні") });
// Головна дія квитка — біла кнопка з гліфом, як на деталях застосунку.
const action = (glyph, text) => `<div style="display:flex;align-items:center;justify-content:center;gap:${8 * K}px;height:${48 * K}px;margin-top:${12 * K}px;border-radius:${14 * K}px;`
  + `background:${C.paper};color:#141417;font:600 ${16 * K}px/1 Sys"><svg class="ico" style="width:${18 * K}px;height:${18 * K}px"><use href="#i-${glyph}"/></svg>${text}</div>`;

/**
 * Нічна мапа міста `city` зі справжніми подіями тижня (за бажання лише категорії `only`), центр міста — у точці `focus`.
 * З `phrase` у зоні `box` ліворуч стоять фраза й квиток `below` з вибраним справжнім музичним піном праворуч від нього;
 * `brand` — довільний блок поверх. Маркери обходять фразу, квиток, підпис, бренд і прямокутники `keep`.
 * `bare` — тло для ролику: видно лише мапу й підпис, а маркери й накладки лягають у window.__map, щоб ролик проявив їх сам.
 */
async function mapHtml({ w, h, city = "Київ", only = null, focus, box, phrase = "", below = "", brand = "", keep = [], bare = false, inter = false, above = false, zoom = 13 }) {
  // Події на найближчий тиждень — той самий запит, що робить веб-афіша. Числа кластерів — знімок дня рендеру.
  const { index } = await discover(city, { cards: 0 });
  const now = Date.now();
  const points = index.filter((e) => { const t = Date.parse(e.startsAt); return t > now - 3 * 36e5 && t < now + 7 * 864e5 && (!only || e.category === only); })
    .map((e) => [e.lng, e.lat, e.category]);
  const { lat, lng } = cityOf(city);
  const card = phrase ? `<div class="raised" id="card">${pick(box.l + 24, box.b - 46 - 116 * K, below)}</div>` : "";
  return `<!doctype html><html><head><meta charset="utf-8">
<link rel="stylesheet" href="https://unpkg.com/maplibre-gl@4.7.1/dist/maplibre-gl.css">
<script src="https://unpkg.com/maplibre-gl@4.7.1/dist/maplibre-gl.js"></script>
<style>${FONTS}${inter ? INTER : SF}</style><style id="look">${BASE}body{width:${w}px;height:${h}px}#map{position:absolute;inset:0}
.raised{filter:drop-shadow(0 ${8 * U / 3}px ${8 * U}px rgba(0,0,0,.5))}
.glow{text-shadow:0 0 ${24 * U}px ${C.canvas},0 0 ${10 * U}px ${C.canvas}}
.bare #marks,.bare #card,.bare #phrase,.bare #brand{visibility:hidden}</style></head>
<body class="${bare ? "bare" : ""}">${ICONS}<div id="map"></div><div id="marks"></div>${card}
${phrase ? `<h1 class="glow" id="phrase" style="position:absolute;left:${box.l + 24}px;top:${box.t + 14}px;font:800 ${48 * U}px/.94 Cond;letter-spacing:-.012em;white-space:nowrap">${phrase}</h1>` : ""}
<p id="credit" style="position:absolute;left:${box.l + 28}px;top:${box.b - 12 - 11 * U}px;font-size:${11 * U}px;color:${C.ink3}">OpenMapTiles · OpenStreetMap contributors</p>
${brand}
<script>
const C = ${JSON.stringify(C)}, STUB = ${JSON.stringify(STUB)}, CAT = ${JSON.stringify(CAT)}, U = ${U};
const inkOf = ${inkOf};
${cluster}
${pin}
const points = ${JSON.stringify(points)}, focus = ${JSON.stringify(focus)}, box = ${JSON.stringify(box)}, extra = ${JSON.stringify(keep)};
const map = new maplibregl.Map({ container: "map", style: ${JSON.stringify(mapStyle(true))}, center: [${lng}, ${lat}], zoom: ${zoom},
  attributionControl: false, interactive: false, fadeDuration: 0 });
map.on("error", (e) => document.title = "error " + e.error?.message);
map.on("load", () => {
  map.panBy([${w / 2} - focus[0], ${h / 2} - focus[1]], { duration: 0 });
  map.addSource("e", { type: "geojson", cluster: ${!only}, clusterRadius: 60 * U, clusterMaxZoom: 15, // одна категорія — піни з її гліфом, не кластери
    data: { type: "FeatureCollection", features: points.map(([lng, lat, cat]) => ({ type: "Feature", geometry: { type: "Point", coordinates: [lng, lat] }, properties: { cat } })) } });
  map.addLayer({ id: "e", type: "circle", source: "e", paint: { "circle-radius": 1, "circle-opacity": 0 } });
  map.once("idle", async () => {
    await document.fonts.ready;
    // Фраза, квиток, підпис, бренд і вибраний пін лишаються чистими: що під ними, не малюємо, як застосунок під каруселлю.
    const box_ = (el, m) => { const r = el.getBoundingClientRect(); return [r.left - m, r.top - m, r.right + m, r.bottom + m]; };
    const ticketEl = window.card?.firstElementChild;
    const keep = [...[["phrase", 30], ["credit", 16], ["brand", 30]].filter(([id]) => window[id]).map(([id, m]) => box_(window[id], m)),
      ...(ticketEl ? [box_(ticketEl, 30)] : []), ...extra];
    const seen = new Set(), placed = [];
    const found = map.queryRenderedFeatures({ layers: ["e"] }).filter((f) => {
      const key = f.properties.cluster_id ?? f.geometry.coordinates.join();
      return !seen.has(key) && seen.add(key);
    }).map((f) => ({ f, ...map.project(f.geometry.coordinates) }));
    // Вибраний — справжній музичний пін праворуч від свого квитка (не налазить на корінець), цілий у зоні box;
    // з above — ще й над квитком, як у застосунку над каруселлю (вузькі вертикальні формати).
    let sel = null;
    if (ticketEl) {
      const t = ticketEl.getBoundingClientRect();
      sel = found.filter(({ f, x, y }) => !f.properties.cluster && f.properties.cat === "music" && (x > t.right + 70 || ${above} && x > t.left + 60 && y < t.top - 70) && x < box.r - 64 && y > box.t + 64 && y < box.b - 64)
        .sort((a, b) => Math.hypot(a.x - t.right, a.y - t.top) - Math.hypot(b.x - t.right, b.y - t.top))[0];
      if (!sel) { // окремі музичні піни в кадрі — підказка, куди зсунути focus
        const free = found.filter(({ f }) => !f.properties.cluster && f.properties.cat === "music").map(({ x, y }) => [Math.round(x), Math.round(y)]);
        document.title = "error: поруч із квитком нема музичної події; квиток " + [t.left, t.top, t.right].map(Math.round) + ", музика " + JSON.stringify(free); return; }
    }
    // Більші кластери першими; менший, що налазить на вже поставлений, не малюємо.
    for (const m of found.sort((a, b) => (b.f.properties.point_count || 1) - (a.f.properties.point_count || 1))) {
      const { x, y } = m;
      if (m === sel || x < 0 || y < 0 || x > ${w} || y > ${h}) continue;
      if (keep.some(([a, b, c, d]) => x > a - 50 && x < c + 50 && y > b - 40 && y < d + 40)) continue;
      if ([...placed, ...(sel ? [sel] : [])].some((o) => Math.abs(o.x - x) < 120 && Math.abs(o.y - y) < 76)) continue;
      placed.push({ x, y, html: m.f.properties.cluster ? cluster(x, y, m.f.properties.point_count) : pin(x, y, m.f.properties.cat) });
    }
    const chosen = sel ? pin(sel.x, sel.y, "music", true) : "";
    marks.innerHTML = placed.map((m) => m.html).join("") + chosen;
    // Для ролику: маркери від центру міста назовні, накладки й вигляд без шрифтів (шрифти ролик під'єднує свої).
    const out = (id) => window[id]?.outerHTML || "";
    window.__map = { w: ${w}, h: ${h}, focus, css: look.textContent, icons: ${JSON.stringify(ICONS)},
      marks: placed.map((m) => ({ ...m, d: Math.hypot(m.x - focus[0], m.y - focus[1]) })).sort((a, b) => a.d - b.d).map((m) => m.html),
      pin: chosen, card: out("card"), phrase: out("phrase"), brand: out("brand") };
    document.title = "ready";
  });
});
</script></body></html>`;
}

/** Відкриває сторінку в headless Chrome і знімає її, коли сторінка ставить title "ready". */
async function shoot(pages) {
  const dir = mkdtempSync(join(tmpdir(), "creative-"));
  const chrome = spawn(CHROME, ["--headless", "--remote-debugging-port=0", "--use-angle=swiftshader", "--enable-unsafe-swiftshader",
    "--hide-scrollbars", "--allow-file-access-from-files", "--force-color-profile=srgb", `--user-data-dir=${join(dir, "profile")}`, "about:blank"]);
  try {
    const url = await new Promise((ok) => chrome.stderr.on("data", (d) => { const m = /ws:\/\/\S+/.exec(String(d)); if (m) ok(m[0]); }));
    const ws = new WebSocket(url);
    await new Promise((ok) => (ws.onopen = ok));
    let id = 0;
    const waiting = new Map();
    ws.onmessage = (e) => { const m = JSON.parse(e.data); waiting.get(m.id)?.(m); };
    const send = (method, params = {}, sessionId) => new Promise((ok) => { waiting.set(++id, ok); ws.send(JSON.stringify({ id, method, params, sessionId })); });
    for (const { html, out, w, h } of pages) {
      const file = join(dir, "page.html");
      writeFileSync(file, await html());
      const { result: { targetId } } = await send("Target.createTarget", { url: "about:blank" });
      const { result: { sessionId } } = await send("Target.attachToTarget", { targetId, flatten: true });
      await send("Emulation.setDeviceMetricsOverride", { width: w / 2, height: h / 2, deviceScaleFactor: 2, mobile: false }, sessionId);
      await send("Page.navigate", { url: pathToFileURL(file).href }, sessionId);
      let title = "";
      for (let t = 0; t < 240 && title !== "ready"; t++) {
        await new Promise((ok) => setTimeout(ok, 250));
        title = (await send("Runtime.evaluate", { expression: "document.title" }, sessionId)).result.result.value;
        if (title.startsWith("error")) throw new Error(`${out}: ${title}`);
      }
      if (title !== "ready") throw new Error(`${out}: сторінка не дочекалась готовності`);
      // Квитки мапи ставляться поверх уже намальованих тайлів; кадр на всяк випадок.
      await new Promise((ok) => setTimeout(ok, 500));
      const jpeg = out.endsWith(".jpg");
      const shot = await send("Page.captureScreenshot", jpeg ? { format: "jpeg", quality: 90 } : { format: "png" }, sessionId);
      writeFileSync(out, Buffer.from(shot.result.data, "base64"));
      // Тло ролику: поруч скрипт з маркерами й накладками (MAPS[назва]), щоб ролик проявив їх сам.
      if (jpeg) writeFileSync(out.replace(/\.jpg$/, ".js"), `(window.MAPS ||= {})[${JSON.stringify(basename(out, ".jpg"))}] = `
        + (await send("Runtime.evaluate", { expression: "JSON.stringify(window.__map)" }, sessionId)).result.result.value + ";\n");
      await send("Target.closeTarget", { targetId });
      console.log(out.replace(ROOT, ""));
    }
  } finally {
    const exited = new Promise((ok) => chrome.once("exit", ok));
    chrome.kill();
    await exited; // інакше Chrome ще пише в профіль, поки його видаляємо
    rmSync(dir, { recursive: true, force: true, maxRetries: 5 });
  }
}

// ---- Постер-візитівка 16:9 3840×2160 (CSS 1920×1080 при ×2) — мовою Search Results, з постом якого вона зайшла
// найкраще (рішення 27.10). Поки компаній мало, дія квитка — «Додати в календар», а не «Шукаю компанію»; знизу — знак і де взяти.
const asset = (name) => pathToFileURL(join(ROOT, "marketing", "hyperframes", "_material", "library", name)).href;
// Бейджів сторів тут нема: яскравістю вони перебивають іконку «Поряд» (рішення 27.10), тож і рядка про ТМ не треба.
const brand = (text) => `<div id="brand" style="position:absolute;left:200px;top:880px;display:flex;align-items:center;gap:20px">
<img src="${asset("icon.png")}" style="width:64px;height:64px;border-radius:14px"><b style="font:800 56px/1 Cond;letter-spacing:-1px">Поряд</b>
<span style="width:2px;height:48px;background:${C.hairline};margin:0 16px"></span>${text}</div>`;
const poster = { w: 1920, h: 1080, focus: [1320, 500], box: { l: 176, t: 280, r: 1500, b: 800 }, phrase: "Куди піти<br>сьогодні?", below: action("calendar", "Додати в календар"), inter: true,
  brand: brand(`<span style="font:400 24px/1.3 Sys;color:${C.ink2}">Безкоштовно для iPhone і Android<br>poriad.app</span>`) };
// A/B (27.10): B відповідає на питання словами біля назви — без тексту поста видно, що мапа і є застосунок.
const posterB = { ...poster,
  brand: brand(`<span><b style="display:block;font:600 28px/1.2 Sys">Події твого міста на одній мапі</b><span style="display:block;margin-top:6px;font:400 20px/1.3 Sys;color:${C.ink2}">Безкоштовно для iPhone і Android · poriad.app</span></span>`) };
// Тло роликів 16:9 (marketing/hyperframes): мапа міста без накладок, ліва середина вільна під текст ролику.
const MAPS = join(ROOT, "marketing", "hyperframes", "_material", "maps");
const plate = (city, only) => ({ w: 1920, h: 1080, city, only, focus: [1150, 540], box: { l: 172, t: 0, r: 1920, b: 1010 }, keep: [[170, 360, 940, 700]], bare: true, inter: true });
// Реклама Instagram і Threads: та сама мапа, своя для кожного міста; 4:5 — стрічки й Threads, 9:16 — Stories і Reels.
// Знак угорі, бо низ 9:16 закривають підпис і кнопка Reels (Meta радить без тексту в нижніх 35 %).
const adBrand = (top) => `<div id="brand" style="position:absolute;left:80px;top:${top}px;display:flex;align-items:center;gap:18px">
<img src="${asset("icon.png")}" style="width:56px;height:56px;border-radius:12px"><b style="font:800 48px/1 Cond;letter-spacing:-1px">Поряд</b>
<span style="width:2px;height:40px;background:${C.hairline};margin:0 10px"></span><span style="font:600 26px/1.2 Sys">Події твого міста на одній мапі</span></div>`;
const meta = (city, zoom, [dx, dy], h, top) => ({ w: 1080, h, city, zoom, focus: [760 + dx, top + 640 + dy], box: { l: 56, t: top + 86, r: 1040, b: top + 1226 },
  phrase: "Куди піти<br>сьогодні?", below: action("calendar", "Додати в календар"), inter: true, above: true, brand: adBrand(top) });
const META = join(ROOT, "marketing", "meta-ads");

// ---- Друга хвиля реклами Instagram і Threads (31.10): три ідеї без мапи, у кожній — назва міста з таргетингу.
// Числа — лише ті, що тримаються в кожному місті весь місяць: «сотні щомісяця» (prod 31.10: Одеса 220 за 30 днів,
// «щотижня» тримає лише Київ). Події — жанрами без назв (юр. аудит 28.10). У 9:16 текст — між 250 і 1250:
// угорі профіль, нижні 35 % закривають підпис і кнопка.
const CITY = { "Київ": ["у Києві", "Києва", "Поділ"], "Львів": ["у Львові", "Львова", "Середмістя"], "Одеса": ["в Одесі", "Одеси", "Центр"] };
const adPage = (w, h, css, body) => `<!doctype html><html><head><meta charset="utf-8"><style>${FONTS}${INTER}${BASE}body{width:${w}px;height:${h}px}
.frame{position:absolute;left:80px;right:80px;display:flex;flex-direction:column;justify-content:space-between}
.frame>*{flex:none}.nine{justify-content:flex-start;gap:44px}.nine .foot{order:-1}
h1{font:800 104px/.92 Cond;letter-spacing:-.012em}
.foot{display:flex;align-items:center;gap:18px}.foot img{width:64px;height:64px;border-radius:14px}
.foot b{font:800 52px/1 Cond;letter-spacing:-1px}.foot span{font:400 24px/1.3 Sys;color:${C.ink2}}${css}</style></head>
<body>${ICONS}${body}<script>Promise.all([document.fonts.ready, ...[...document.images].map((i) => i.decode())]).then(() => document.title = "ready")</script></body></html>`;
const foot = (city) => `<div class="foot"><img src="${asset("icon.png")}"><b>Поряд</b>
<span style="margin-left:14px">Усі події ${CITY[city][1]} на одній мапі.<br>Безкоштовно для iPhone і Android.</span></div>`;
// У 9:16 знак — угорі, решта йде за ним: головне вміщається до 1250, низ стрічки чи чату лягає під підпис Reels.
const frame = (h) => (h === 1350 ? { top: 80, height: 1190, nine: false } : { top: 250, height: 1000, nine: true });

// «Чек»: на скаргу «нема куди піти» місто відповідає касовою стрічкою з афішею вечора; підсумок — перша половина слогана.
function receiptHtml({ w, h, city }) {
  const f = frame(h), z = 16, step = 26, n = Math.ceil(640 / step);
  const edge = (bottom) => Array.from({ length: n + 1 }, (_, i) => `${i * step}px ${bottom ? `calc(100% - ${i % 2 ? 0 : z}px)` : `${i % 2 ? 0 : z}px`}`);
  const clip = `polygon(${[...edge(false), ...edge(true).reverse()].join(",")})`;
  const row = (dot, label, value) => `<div class="row">${dot ? `<i style="background:${dot}"></i>` : ""}<span>${label}</span><b></b><span>${value}</span></div>`;
  return adPage(w, h, `
.receipt{width:640px;margin:0 auto;padding:${z + 40}px 44px ${z + 34}px;background:${C.paper};color:#141417;clip-path:${clip};transform:rotate(-2.5deg);zoom:${f.nine ? 0.92 : 1};
  font:600 30px/1 Sys;text-transform:uppercase;letter-spacing:.02em;filter:drop-shadow(0 20px 40px rgba(0,0,0,.5))}
.row{display:flex;align-items:baseline;gap:14px;margin:22px 0}.row b{flex:1;border-bottom:4px dotted rgba(20,20,23,.35)}
.row i{width:18px;height:18px;border-radius:50%;align-self:center;flex:none}
.cut{border-top:3px dashed rgba(20,20,23,.4);margin:28px 0}
.bars{height:76px;margin-top:30px;background:repeating-linear-gradient(90deg,#141417 0 4px,#0000 4px 9px,#141417 9px 15px,#0000 15px 18px,#141417 18px 20px,#0000 20px 27px)}`,
  `<div class="frame${f.nine ? " nine" : ""}" style="top:${f.top}px;height:${f.height}px">
<h1>Нема куди<br>піти ${CITY[city][0]}?</h1>
<div class="receipt">
  <div style="text-align:center;font:800 64px/1 Cond;letter-spacing:.01em">ПОРЯД</div>
  <div style="text-align:center;margin-top:12px;font-size:22px;letter-spacing:.16em">Афіша · ${city} · вечір</div>
  <div class="cut"></div>
  ${row(STUB.music, "Концерт", "19:30")}${row(STUB.art, "Вистава", "19:00")}${row(STUB.comedy, "Стендап", "20:00")}${row(STUB.kids, "Дітям", "сб 12:00")}
  <div class="cut"></div>
  ${row("", "Подій за місяць", "сотні")}${row("", "Застосунок", "0 ₴")}
  <div class="cut" style="border-top-style:double;border-top-width:8px"></div>
  <div style="display:flex;justify-content:space-between;align-items:baseline;font:800 64px/1 Cond"><span>РАЗОМ</span><span>Є КУДИ</span></div>
  <div class="bars"></div>
  <div style="text-align:center;margin-top:14px;font:600 22px/1 Sys;letter-spacing:.2em;text-transform:none">poriad.app</div>
</div>
${foot(city)}</div>`);
}

// «Розрив»: три квитки, про які ти чув, на тлі стіни з сотень, про які ні.
function gapHtml({ w, h, city }) {
  const f = frame(h), u = 1.9, th = 116 * u, tw = 343 * u;
  const known = [["music", "Концерт", "19:00", "пт", -5, -60], ["comedy", "Стендап", "20:00", "сб", 3, 60], ["art", "Вистава", "18:00", "нд", 2, -100]]
    .map(([g, genre, time, day, rot, dx], i) => `<div style="position:absolute;left:${(920 - tw) / 2 + dx}px;top:${i * 150}px;transform:rotate(${rot}deg);filter:drop-shadow(0 16px 30px rgba(0,0,0,.6))">`
      + ticket({ x: 0, y: 0, w: tw, h: th, u, stub: 84 * u, fill: STUB[g], main: blank(u, "72%") + blank(u, "44%"), stubHtml: stubTime(genre, time, day) }) + "</div>");
  return adPage(w, h, `.wall{position:absolute;inset:-200px;transform:rotate(-7deg)}.veil{position:absolute;inset:0;background:${C.canvas};opacity:.82}
.stack{position:relative;height:${th + 2 * 150}px;zoom:${f.nine ? 0.72 : 1}}
h2{font:800 76px/.98 Cond;letter-spacing:-.01em}h2 em{font-style:normal;color:${C.ink2}}`,
  `<div class="wall">${ticketWall(w + 400, h + 400).join("")}</div><div class="veil"></div>
<div class="frame${f.nine ? " nine" : ""}" style="top:${f.top}px;height:${f.height}px">
<h1>Ти знаєш<br>про 3 події<br>${CITY[city][0]}.</h1>
<div class="stack">${known.join("")}</div>
<h2>Їх сотні щомісяця.<br><em>Усі — на одній мапі.</em></h2>
${foot(city)}</div>`);
}

// «Чат»: друзі в груповому чаті не знають, куди піти, — у відповідь посилання на подію з «Поряд».
function chatHtml({ w, h, city }) {
  const f = frame(h), u = 1.6;
  const them = (who, hue, text) => `<div class="msg"><span class="ava">${who[0]}</span><div class="bub"><small style="color:${inkOf(hue)}">${who}</small>${text}</div></div>`;
  const card = ticket({ x: 0, y: 0, w: 343 * u, h: 116 * u, u, stub: 84 * u, fill: STUB.comedy, stubHtml: stubTime("Стендап", "20:00", "сб"),
    main: `<div style="font:700 ${20 * u}px/1.15 Cond">Стендап-вечір</div><div style="margin-top:${8 * u}px;font-size:${14 * u}px;color:${C.ink2}">${city} · ${CITY[city][2]}</div>` });
  return adPage(w, h, `
.chat{display:flex;flex-direction:column;gap:22px;zoom:${f.nine ? 1 : 1.15}}
.top{display:flex;align-items:center;gap:20px;padding-bottom:26px;border-bottom:2px solid ${C.hairline};font:600 34px/1.2 Sys}
.top small{display:block;font:400 24px/1.3 Sys;color:${C.ink3}}
.msg{display:flex;align-items:flex-end;gap:16px}.mine{justify-content:flex-end}
.ava{width:64px;height:64px;border-radius:50%;background:${C.raised};display:grid;place-items:center;font:600 28px/1 Sys;flex:none}
.bub{max-width:700px;padding:20px 28px;border-radius:36px 36px 36px 10px;background:${C.surface};font:400 38px/1.25 Sys}
.bub small{display:block;margin-bottom:6px;font:600 24px/1 Sys}
.mine .bub{border-radius:36px 36px 10px 36px;background:${C.paper};color:#141417}
.link{position:relative;width:${343 * u}px;height:${116 * u}px}`,
  `<div class="frame${f.nine ? " nine" : ""}" style="top:${f.top}px;height:${f.height}px">
<div class="chat">
  <div class="top"><span class="ava" style="width:80px;height:80px;font-size:40px">🎟</span><div>Субота<small>Оля, Макс і ти</small></div></div>
  ${them("Оля", CAT.art, "Що робимо в суботу?")}
  ${them("Макс", CAT.games, `${CITY[city][0][0].toUpperCase()}${CITY[city][0].slice(1)} нема куди піти 🙃`)}
  <div class="msg mine"><div class="link">${card}</div></div>
  <div class="msg mine"><div class="bub">Є куди. Глянь у «Поряд»</div></div>
  ${them("Оля", CAT.art, "О, го 🔥")}
</div>
${foot(city)}</div>`);
}
const AD2 = join(META, "v2");

const PAGES = [
  { name: "header", html: headerHtml, out: join(OUT, "header_3840x1646.png"), w: 3840, h: 1646 },
  { name: "search", html: () => mapHtml({ w: 1920, h: 1280, focus: [1120, 560], box: { l: 418, t: 382, r: 1502, b: 898 }, phrase: "Куди піти<br>сьогодні?", below: action("people", "Шукаю компанію") }),
    out: join(OUT, "search_3840x2560.png"), w: 3840, h: 2560 },
  { name: "poster", html: () => mapHtml(poster), out: join(ROOT, "marketing", "poster", "poriad-16x9.png"), w: 3840, h: 2160 },
  { name: "poster-b", html: () => mapHtml(posterB), out: join(ROOT, "marketing", "poster", "poriad-16x9-b.png"), w: 3840, h: 2160 },
  { name: "map-poster", html: () => mapHtml({ ...poster, bare: true }), out: join(MAPS, "poster.jpg"), w: 3840, h: 2160 },
  ...[["kyiv", "Київ"], ["kyiv-comedy", "Київ", "comedy"], ["lviv", "Львів"], ["odesa", "Одеса"], ["kharkiv", "Харків"], ["dnipro", "Дніпро"]]
    .map(([name, city, only]) => ({ name: `map-${name}`, html: () => mapHtml(plate(city, only)), out: join(MAPS, `${name}.jpg`), w: 3840, h: 2160 })),
  // Масштаб і зсув центру — щоб біля квитка був окремий музичний пін: у Львові на 13 музика ховається в кластери,
// а в Одесі майданчики на 1.5–2.5 км східніше точки міста.
  ...[["kyiv", "Київ", 13, [0, 0]], ["lviv", "Львів", 14, [0, 0]], ["odesa", "Одеса", 13, [-280, -200]]].flatMap(([name, city, zoom, shift]) => [
    { name: `meta-${name}-4x5`, html: () => mapHtml(meta(city, zoom, shift, 1350, 64)), out: join(META, `${name}-4x5.png`), w: 2160, h: 2700 },
    { name: `meta-${name}-9x16`, html: () => mapHtml(meta(city, zoom, shift, 1920, 270)), out: join(META, `${name}-9x16.png`), w: 2160, h: 3840 }]),
  ...[["receipt", receiptHtml], ["gap", gapHtml], ["chat", chatHtml]].flatMap(([idea, html]) =>
    [["kyiv", "Київ"], ["lviv", "Львів"], ["odesa", "Одеса"]].flatMap(([name, city]) => [[1350, "4x5"], [1920, "9x16"]].map(([h, ratio]) =>
      ({ name: `ad2-${idea}-${name}-${ratio}`, html: () => html({ w: 1080, h, city }), out: join(AD2, `${idea}-${name}-${ratio}.png`), w: 2160, h: h * 2 })))),
];
// node tools/store_creative.mjs [назва…] — лише сторінки з цими назвами (за початком: «map» — усе тло), без аргументів — усі.
const want = process.argv.slice(2);
await shoot(PAGES.filter((p) => !want.length || want.some((n) => p.name.startsWith(n))));
