// Cloudflare Worker перед GitHub Pages: сторінка події `poriad.app/e/{id}` з прев'ю для Telegram і
// файли, за якими iOS і Android перевіряють, що посилання належать застосунку. Решту сайту не чіпає —
// маршрути в wrangler.toml перехоплюють лише ці адреси. Дані — публічний RPC `event_details`, той
// самий, що бачить гість у застосунку: приховані й приватні події він не віддає.

// Назви, дати й ціна — ті самі правила, що на сайті (site/js/poriad.js, порт TitleRules і формату застосунку).
// wrangler збирає цей імпорт у воркер; той самий файл сайт віддає браузеру.
import { displayTitle, overline, price, httpsOrNull, esc, CATEGORIES } from "../site/js/poriad.js";
export { esc };

const APP_STORE_URL = "https://apps.apple.com/ua/app/id6813543772";
// Порожньо, доки застосунок не вийшов у Google Play: кнопку не показуємо.
const PLAY_URL = "";
const IOS_APP_ID = "QTYQMJ94D2.app.poriad.ios";
// Play Console → Test and release → App integrity → App signing: SHA-256 ключа підпису застосунку
// (збірки з Play) і ключа завантаження (локальні prodRelease). Без них Android відкриває посилання в браузері.
const ANDROID_CERT_FINGERPRINTS = [
  "E4:3A:7F:9B:CF:4B:A5:BE:77:92:7D:80:00:4A:A9:56:D1:00:B0:42:43:FD:DC:7B:B5:61:EA:C8:91:9E:C1:00",
  "34:B7:9F:9D:37:41:74:DC:66:54:E3:6C:3E:CE:AB:04:E2:ED:5C:60:8F:49:8B:0C:6D:C4:7C:2F:78:EA:06:03",
];
const CACHE_SECONDS = 300;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (url.pathname === "/.well-known/apple-app-site-association") return json(appleAssociation());
    if (url.pathname === "/.well-known/assetlinks.json") return json(androidAssociation());
    const match = url.pathname.match(/^\/e\/([^/]+)\/?$/);
    if (!match) return fetch(request);
    if (request.method !== "GET" && request.method !== "HEAD") return new Response(null, { status: 405 });

    // Telegram, месенджери й люди відкривають одне посилання хвилями: кеш на краю, а не запит у базу щоразу.
    const cacheKey = new Request(url.origin + url.pathname);
    const cached = await caches.default.match(cacheKey);
    if (cached) return cached;
    const response = await eventResponse(match[1], env);
    if (response.status === 200) ctx.waitUntil(caches.default.put(cacheKey, response.clone()));
    return response;
  },
};

async function eventResponse(id, env) {
  if (!UUID.test(id)) return html(notFoundPage(), 404);
  const rpc = (name) => fetch(`${env.SUPABASE_URL}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: { apikey: env.SUPABASE_KEY, "content-type": "application/json" },
    body: JSON.stringify({ p_event_id: id }),
  });
  const [upstream, safety] = await Promise.all([rpc("event_details"), rpc("event_safety").catch(() => null)]);
  // Помилку бази не кешуємо й не видаємо за «подію не знайдено».
  if (!upstream.ok) return html(notFoundPage("Не вдалося завантажити подію. Спробуйте ще раз за хвилину."), 503);
  const rows = await upstream.json();
  if (!Array.isArray(rows) || rows.length === 0) return html(notFoundPage(), 404);
  // Укриття — доповнення: збій чи стара база без event_safety лише ховають секцію.
  const shelters = safety?.ok ? ((await safety.json().catch(() => null))?.shelters ?? []) : [];
  return html(eventPage(rows[0], new Date(), shelters), 200);
}

export function eventPage(e, now, shelters = []) {
  const link = `https://poriad.app/e/${e.id}`;
  const title = displayTitle(e.title);
  const tz = e.time_zone || "Europe/Kyiv";
  // Імпорт часто вже пише місто в адресі: «Київ, …, м. Київ» читається як помилка.
  const place = e.address && e.city && e.address.includes(e.city) ? e.address : [e.city, e.address].filter(Boolean).join(", ");
  const imported = e.origin === "import";
  const cancelled = e.status === "cancelled";
  const past = new Date(e.ends_at || e.starts_at) < now;
  const image = httpsOrNull(e.image_url);
  const ticketUrl = imported ? httpsOrNull(e.canonical_url) : null;
  const category = CATEGORIES[e.category] ? e.category : "social";
  const when = overline(e, now);
  const maps = `https://www.google.com/maps/dir/?api=1&destination=${Number(e.latitude)},${Number(e.longitude)}`;
  // Супутник «Йдемо разом»: посилання на афішу, на яку йдуть. UUID перевіряємо — рядок з бази йде в href.
  const parent = UUID.test(e.companion_of ?? "") ? { id: e.companion_of, title: displayTitle(e.companion_of_title || "подію") } : null;
  const cost = price(e);
  const spots = !imported && e.capacity ? `Учасників: ${e.attendee_count} з ${e.capacity}` : !imported && e.attendee_count > 0 ? `Учасників: ${e.attendee_count}` : null;
  const notice = cancelled ? "Подію скасовано." : past ? "Ця подія вже минула." : null;
  const facts = [
    ["Коли", overline(e, now, true), null],
    ["Де", place.split(", ")[0] || e.city, place],
    [spots ? "Учасники" : "Ціна", spots ? spots.replace("Учасників: ", "") : cost || "Уточнюйте", null],
    [imported ? "Джерело" : "Організовує", imported ? e.source_name || "Афіша" : e.organizer_name || "Організатор", null],
  ];
  const extras = [e.min_age ? `${e.min_age}+` : null, !imported && e.approval_required ? "Участь за підтвердженням організатора" : null].filter(Boolean);

  return layout({
    title,
    description: [when, place].filter(Boolean).join(" · "),
    image: image || "https://poriad.app/img/og.png",
    url: link,
    // Поки в політиці не сказано, що події індексуються пошуковиками, сторінки — лише за посиланням.
    head: `<meta name="robots" content="noindex">
<meta name="apple-itunes-app" content="app-id=${APP_STORE_URL.match(/id(\d+)/)[1]}, app-argument=${link}">
${ticketUrl ? `<link rel="canonical" href="${esc(ticketUrl)}">` : ""}`,
    body: `<article class="sheet-box">
  <header class="cover-big cat-${category}"><div class="art cat-${category}">${icon(category, "glyph")}${image ? `<img src="${esc(image)}" alt="" referrerpolicy="no-referrer">` : ""}</div>
    <div class="badges"><span class="badge">${esc(CATEGORIES[category])}</span><span class="badge">${esc(imported ? `Афіша${e.source_name ? ` · ${e.source_name}` : ""}` : "Від людей")}</span>${extras.length && e.min_age ? `<span class="badge">${Number(e.min_age)}+</span>` : ""}</div>
    <div class="when">${esc(when)}</div><h1>${esc(title)}</h1>
  </header>
  <div class="detail">
    ${notice ? `<p class="notice">${notice}</p>` : ""}
    ${parent ? `<p class="note">Разом на: <a href="/e/${parent.id}">${esc(parent.title)}</a></p>` : ""}
    <div class="actions">
      <a href="${maps}" rel="noopener"><i>${icon("pin")}</i>Маршрут</a>
      <button type="button" data-share><i>${icon("share")}</i>Поділитися</button>
      <a href="poriad://event/${e.id}"><i>${icon("bookmark")}</i>У застосунку</a>
      <a href="/afisha.html${e.city && e.city !== "Київ" ? `?city=${encodeURIComponent(e.city)}` : ""}"><i>${icon("map")}</i>Афіша</a>
    </div>
    <div class="facts">${facts.map(([label, value, sub]) => `<div><span class="overline">${label}</span><b>${esc(value)}</b>${sub && sub !== value ? `<small>${esc(sub)}</small>` : ""}</div>`).join("")}</div>
    ${!imported && e.approval_required ? `<p class="fine">Участь за підтвердженням організатора.</p>` : ""}
    ${!imported && e.organizer_name ? `<p class="note">Організовує ${esc(e.organizer_name)}</p>` : ""}
    ${e.description ? `<div class="block"><h2>Опис</h2><p class="description">${esc(e.description)}</p></div>` : ""}
    ${!cancelled && !past ? sheltersSection(shelters) : ""}
    <div class="app-only"><b>${imported ? "Підете? Не забудьте" : "Приєднатися — в застосунку"}</b>
      <ul><li>${icon("bell")}Нагадування за годину до початку</li><li>${icon("people")}«Шукаю компанію» — знайдіть, з ким піти</li><li>${icon("map")}Що ще відбувається поряд — на мапі</li></ul>
      <div class="stores">${storeButtons()}</div></div>
  </div>
  <div class="bar"><div class="top"><div class="meta"><small>${esc(when)}</small><span>${esc(cost || spots || "Вхід уточнюйте")}</span></div>
    ${ticketUrl && !cancelled && !past ? `<a class="btn primary" href="${esc(ticketUrl)}" rel="nofollow noopener">Квитки${e.source_name ? ` на ${esc(e.source_name)}` : ""}</a>`
      : `<a class="btn primary" href="/app">${imported ? "Завантажити «Поряд»" : "Приєднатися в застосунку"}</a>`}</div></div>
</article>`,
  });
}

// Правила Мінкульту з 11.09.2026: про найближче укриття повідомляють заздалегідь, зокрема на сайті.
const SHELTER_KINDS = { metro: "Метро", underpass: "Підземний перехід", parking: "Підземний паркінг", basement: "Укриття" };

function sheltersSection(shelters) {
  if (!Array.isArray(shelters) || shelters.length === 0) return "";
  const rows = shelters.map((s) => {
    const extras = [s.hours, s.accessible ? "Є пандус" : null].filter(Boolean).map(esc).join(" · ");
    return `<a class="row" href="https://www.google.com/maps/dir/?api=1&destination=${Number(s.latitude)},${Number(s.longitude)}&travelmode=walking" rel="noopener">
      <i>${icon("shield")}</i><div class="txt"><small>${esc(SHELTER_KINDS[s.kind] || "Укриття")} · ${Number(s.distance_m)} м${extras ? ` · ${extras}` : ""}</small><b>${esc(s.address)}</b></div></a>`;
  }).join("");
  return `<div class="block"><h2>Укриття поруч</h2><div class="rows">${rows}</div><p class="fine">За відкритими даними КМДА (CC BY).</p></div>`;
}

export function notFoundPage(message = "Подію не знайдено: її могли приховати або посилання неповне.") {
  return layout({
    title: "Поряд — події вашого міста",
    description: "Концерти, настолки, пробіжки й зустрічі поруч із вами на одній мапі.",
    image: "https://poriad.app/img/og.png",
    url: "https://poriad.app/",
    head: `<meta name="robots" content="noindex">`,
    body: `<article class="sheet-box"><div class="detail lost"><p class="notice">${esc(message)}</p>
  <div class="app-only"><b>Що відбувається поряд сьогодні</b><ul><li>${icon("map")}Афіша п’яти міст на мапі</li><li>${icon("bell")}Нагадування й компанія — у застосунку</li></ul>
    <a class="btn" href="/afisha.html">Відкрити афішу</a><div class="stores">${storeButtons()}</div></div></div></article>`,
  });
}

function storeButtons() {
  return `<a class="store" href="${APP_STORE_URL}">${icon("apple")}<span><small>Завантажити в</small>App Store</span></a>
    ${PLAY_URL ? `<a class="store play" href="${PLAY_URL}">${icon("play")}<span><small>Завантажити з</small>Google Play</span></a>` : ""}`;
}

const icon = (name, cls = "ico") => `<svg class="${cls}" aria-hidden="true"><use href="/img/icons.svg#i-${name}"/></svg>`;

function layout({ title, description, image, url, head, body }) {
  return `<!doctype html>
<html lang="uk" data-theme="light">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>${esc(title)} — Поряд</title>
<meta name="description" content="${esc(description)}">
<meta property="og:type" content="website">
<meta property="og:site_name" content="Поряд">
<meta property="og:title" content="${esc(title)}">
<meta property="og:description" content="${esc(description)}">
<meta property="og:image" content="${esc(image)}">
<meta property="og:url" content="${esc(url)}">
<meta name="twitter:card" content="summary_large_image">
<meta name="theme-color" content="#F5F5F7">
${head}
<link rel="preload" href="/fonts/source-serif-4-600.woff2" as="font" type="font/woff2" crossorigin>
<link rel="stylesheet" href="/tokens.css">
<link rel="stylesheet" href="/web.css">
<link rel="icon" href="/icon.png">
</head>
<body class="event-page">
<header class="nav scrolled"><div class="wrap"><a class="brand" href="/"><img src="/icon.png" alt="">Поряд</a>
  <nav class="links" aria-label="Розділи"><a href="/afisha.html">Афіша</a><a class="btn primary small" href="/app">Завантажити</a></nav></div></header>
<main class="event-shell">${body}</main>
<footer class="site"><div class="wrap"><span>Питання й скарги: <a href="mailto:hello@poriad.app">hello@poriad.app</a></span>
  <nav aria-label="Документи"><a href="/afisha.html">Афіша</a><a href="/privacy.html">Конфіденційність</a><a href="/terms.html">Умови</a></nav></div></footer>
<script>
document.querySelector("[data-share]")?.addEventListener("click", async () => {
  const data = { title: document.title, url: location.href };
  if (navigator.share) { try { await navigator.share(data); } catch {} return; }
  try { await navigator.clipboard.writeText(location.href); alert("Посилання скопійовано"); } catch { prompt("Посилання на подію", location.href); }
});
</script>
</body>
</html>`;
}

function appleAssociation() {
  return { applinks: { details: [{ appIDs: [IOS_APP_ID], components: [{ "/": "/e/*" }] }] } };
}

function androidAssociation() {
  return [{
    relation: ["delegate_permission/common.handle_all_urls"],
    target: { namespace: "android_app", package_name: "app.poriad.android", sha256_cert_fingerprints: ANDROID_CERT_FINGERPRINTS },
  }];
}


function html(body, status) {
  return new Response(body, {
    status,
    headers: { "content-type": "text/html; charset=utf-8", "cache-control": status === 200 ? `public, max-age=${CACHE_SECONDS}` : "no-store" },
  });
}

function json(body) {
  return new Response(JSON.stringify(body), { headers: { "content-type": "application/json", "cache-control": "public, max-age=3600" } });
}
