// Cloudflare Worker перед GitHub Pages: сторінка події `poriad.app/e/{id}` з прев'ю для Telegram і
// файли, за якими iOS і Android перевіряють, що посилання належать застосунку. Решту сайту не чіпає —
// маршрути в wrangler.toml перехоплюють лише ці адреси. Дані — публічний RPC `event_details`, той
// самий, що бачить гість у застосунку: приховані й приватні події він не віддає.

// Назви, дати й ціна — ті самі правила, що на сайті (site/js/poriad.js, порт TitleRules і формату застосунку).
// wrangler збирає цей імпорт у воркер; той самий файл сайт віддає браузеру.
import { displayTitle, overline, stubParts, price, httpsOrNull, esc, CATEGORIES, playUrl } from "../site/js/poriad.js";
export { esc };

// Мітка ct=event: завантаження зі сторінок подій окремо від сайту (site/js/poriad.js).
const APP_STORE_URL = "https://apps.apple.com/app/apple-store/id6813543772?pt=129478154&ct=event&mt=8";
// Порожньо, коли в site/js/poriad.js вимкнено PLAY_LIVE: тоді кнопку Google Play не показуємо. Мітка utm — event.
const PLAY_URL = playUrl("event");
const IOS_APP_ID = "QTYQMJ94D2.app.poriad.ios";
// Play Console → Test and release → App integrity → App signing: SHA-256 ключа підпису застосунку
// (збірки з Play) і ключа завантаження (локальні prodRelease). Без них Android відкриває посилання в браузері.
const ANDROID_CERT_FINGERPRINTS = [
  "E4:3A:7F:9B:CF:4B:A5:BE:77:92:7D:80:00:4A:A9:56:D1:00:B0:42:43:FD:DC:7B:B5:61:EA:C8:91:9E:C1:00",
  "34:B7:9F:9D:37:41:74:DC:66:54:E3:6C:3E:CE:AB:04:E2:ED:5C:60:8F:49:8B:0C:6D:C4:7C:2F:78:EA:06:03",
];
const CACHE_SECONDS = 300;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
// Хеш єдиного вбудованого скрипта (кнопка «Поділитися» внизу eventPage); worker/test.mjs звіряє його з текстом.
export const SHARE_SCRIPT_HASH = "sha256-+OMlclOt3WjumM9V/xC1Thxi7720WWamOx2Q9R1RPO0=";
// Обкладинки — з сайтів продавців, тож img-src https:; маячок Cloudflare Web Analytics Cloudflare вставляє в сторінку
// сам (скрипт зі static.cloudflareinsights.com, дані — на cloudflareinsights.com); решта — лише свій домен.
const SECURITY_HEADERS = {
  "strict-transport-security": "max-age=31536000",
  "x-content-type-options": "nosniff",
  "x-frame-options": "DENY",
  "referrer-policy": "strict-origin-when-cross-origin",
  "content-security-policy": `default-src 'self'; img-src 'self' https: data:; script-src '${SHARE_SCRIPT_HASH}' `
    + "https://static.cloudflareinsights.com; connect-src 'self' https://cloudflareinsights.com; style-src 'self'; "
    + "font-src 'self'; object-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
};

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (url.pathname === "/.well-known/apple-app-site-association") return json(appleAssociation());
    if (url.pathname === "/.well-known/assetlinks.json") return json(androidAssociation());
    const match = url.pathname.match(/^\/e\/([^/]+)\/?$/);
    if (!match) return fetch(request);
    if (request.method !== "GET" && request.method !== "HEAD") return new Response(null, { status: 405 });

    // Telegram, месенджери й люди відкривають одне посилання хвилями: кеш на краю, а не запит у базу щоразу.
    // Ключ у нижньому регістрі: UUID приймаємо без огляду на регістр, тож варіанти однієї адреси не оминають кеш.
    const cacheKey = new Request(url.origin + url.pathname.toLowerCase());
    const cached = await caches.default.match(cacheKey);
    if (cached) return cached;
    const response = await eventResponse(match[1], env);
    if (response.status === 200 || response.status === 404) ctx.waitUntil(caches.default.put(cacheKey, response.clone()));
    return response;
  },
};

export async function eventResponse(id, env) {
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
  // Злиту подію (docs/event-offers.md, R2) база віддає під живим id: стара адреса переїжджає назавжди.
  const live = String(rows[0].id ?? "");
  if (UUID.test(live) && live.toLowerCase() !== id.toLowerCase()) return Response.redirect(`https://poriad.app/e/${live}`, 301);
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
  // Стан афіші з усіх продавців (docs/event-offers.md R4, R11). База без фази 4 його не віддає — тоді, як і
  // застосунок, читаємо import_status: знята — «не знайшли в продажу».
  const state = imported ? (STATES[e.state] ? e.state : e.import_status === "withdrawn" ? "unknown" : "scheduled") : null;
  const cancelled = e.status === "cancelled" || state === "cancelled";
  // Скасована, відкладена чи ніде не продається: сторінка не показує її живою з кнопкою «Квитки».
  const withdrawn = state === "postponed" || state === "unknown";
  const moved = state === "scheduled" && e.previous_starts_at ? longDate(e.previous_starts_at, e.time_zone) : null;
  const past = new Date(e.ends_at || e.starts_at) < now;
  const image = httpsOrNull(e.image_url);
  const ticketUrl = imported ? httpsOrNull(e.canonical_url) : null;
  const category = CATEGORIES[e.category] ? e.category : "social";
  const when = overline(e, now);
  const [stubTime, stubDay] = stubParts(e, now);
  const maps = `https://www.google.com/maps/dir/?api=1&destination=${Number(e.latitude)},${Number(e.longitude)}`;
  // Супутник «Йдемо разом»: посилання на афішу, на яку йдуть. UUID перевіряємо — рядок з бази йде в href.
  const parent = UUID.test(e.companion_of ?? "") ? { id: e.companion_of, title: displayTitle(e.companion_of_title || "подію") } : null;
  const cost = price(e);
  const spots = !imported && e.capacity ? `Учасників: ${e.attendee_count} з ${e.capacity}` : !imported && e.attendee_count > 0 ? `Учасників: ${e.attendee_count}` : null;
  const notice = past ? "Ця подія вже минула." : cancelled ? (imported ? STATES.cancelled : "Подію скасовано.")
    : withdrawn ? STATES[state] : moved ? `Перенесено: було ${moved}. Якщо нова дата не підходить, квиток повертають там, де купували.` : null;
  const live = !cancelled && !withdrawn && !past;
  // «Не знайшли» — без тривоги: ми не знаємо, що сталось. Перенесена жива — теж не червоним.
  const calm = !past && !cancelled && (state === "unknown" || Boolean(moved));
  // Продавці: основний першим. Без даних фази 4 — лише основний з полів події.
  const offers = (Array.isArray(e.offers) && e.offers.length ? e.offers
    : [{ source: e.source_name, url: e.canonical_url, price_min: e.price_min, is_free: e.is_free, live: !withdrawn && !cancelled }])
    .filter((o) => o && o.source && httpsOrNull(o.url));
  const liveOffers = offers.filter((o) => o.live !== false);
  // Підпис афіші — усі живі продавці через кому, як у застосунку (docs/event-offers.md, питання 5).
  const sellers = [...new Set(liveOffers.map((o) => o.source))].join(", ") || e.source_name;
  const facts = [
    ["Коли", overline(e, now, true), null],
    ["Де", place.split(", ")[0] || e.city, place],
    [spots ? "Учасники" : "Ціна", spots ? spots.replace("Учасників: ", "") : cost || "Уточнюйте", null],
    [imported ? "Джерело" : "Організовує", imported ? sellers || "Афіша" : e.organizer_name || "Організатор", null],
  ];

  return layout({
    title,
    description: [when, place].filter(Boolean).join(" · "),
    image: image || "https://poriad.app/img/og.png",
    url: link,
    // Поки в політиці не сказано, що події індексуються пошуковиками, сторінки — лише за посиланням.
    head: `<meta name="robots" content="noindex">
<meta name="apple-itunes-app" content="app-id=${APP_STORE_URL.match(/id(\d+)/)[1]}, affiliate-data=ct=event&amp;pt=129478154, app-argument=${link}">
${ticketUrl ? `<link rel="canonical" href="${esc(ticketUrl)}">` : ""}`,
    body: `<article class="sheet-box">
  <header class="cover-big cat-${category}"><div class="art cat-${category}">${icon(category, "glyph")}${image ? `<img src="${esc(image)}" alt="" referrerpolicy="no-referrer">` : ""}</div>
    <p class="quiet"><span class="genre-word">${esc(CATEGORIES[category])}</span> · ${esc(imported ? `Афіша${sellers ? ` · ${sellers}` : ""}` : "Від людей")}${e.min_age ? ` · ${Number(e.min_age)}+` : ""}</p><h1>${esc(title)}</h1>
  </header>
  <div class="detail">
    ${notice ? `<p class="notice${calm ? " calm" : ""}">${notice}</p>` : ""}
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
    ${imported && !past ? sellersSection(live ? liveOffers : offers, !live, e.checked_at, e.time_zone) : ""}
    ${e.description ? `<div class="block"><h2>Опис</h2><p class="description">${esc(e.description)}</p></div>` : ""}
    ${live ? sheltersSection(shelters) : ""}
    <div class="app-only"><b>${imported ? "Підете? Не забудьте" : "Приєднатися — в застосунку"}</b>
      <ul><li>${icon("bell")}Нагадування за годину до початку</li><li>${icon("people")}«Шукаю компанію» — знайдіть, з ким піти</li><li>${icon("map")}Що ще відбувається поряд — на мапі</li></ul>
      <div class="stores">${storeButtons()}</div></div>
  </div>
  <div class="bar"><div class="ticket cat-${category}"><div class="face"><div class="top"><div class="meta">${spots ? "" : "<small>Ціна</small>"}<span>${esc(cost || spots || "Вхід уточнюйте")}</span></div>
    ${ticketUrl && live ? `<a class="btn primary" href="${esc(ticketUrl)}" rel="nofollow noopener">Квитки${e.source_name ? ` на ${esc(e.source_name)}` : ""}</a>`
      : `<a class="btn primary" href="/app?from=event">${imported ? "Завантажити «Поряд»" : "Приєднатися в застосунку"}</a>`}</div></div>
    <div class="stub" role="img" aria-label="${esc(overline(e, now, true))}"><b class="t">${esc(stubTime)}</b><small>${esc(stubDay)}</small></div></div></div>
</article>`,
  });
}

// Що сторінка каже про стан афіші — ті самі слова, що в застосунку (strings.xml, state_*_hint).
const STATES = {
  scheduled: null,
  cancelled: "Подію скасовано: продавець позначив її скасованою. Квиток повертають там, де купували.",
  postponed: "Подію відкладено, нової дати ще нема. Квиток повертають там, де купували, або тримають до нової дати.",
  unknown: "Не знайшли в продажу: жоден продавець більше не продає квитки на цю дату. Можливо, подію скасували чи перенесли — перевірте у продавця.",
};

/** «чт, 22 жовтня о 19:30» у поясі події. */
function longDate(iso, tz) {
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return null;
  const options = { weekday: "short", day: "numeric", month: "long", hour: "2-digit", minute: "2-digit" };
  try { return new Intl.DateTimeFormat("uk-UA", { ...options, timeZone: tz || "Europe/Kyiv" }).format(date); }
  catch { return new Intl.DateTimeFormat("uk-UA", { ...options, timeZone: "Europe/Kyiv" }).format(date); }
}

/**
 * Квитки афіші (R10–R11): рядок на кожного продавця з ціною й посиланням — атрибуція кожного (§8). Не в силі —
 * «Якщо купили квиток» з усіма, де могли купити, без цін. «Перевірено» — датою: сторінку кешують, «сьогодні» застаріло б.
 */
function sellersSection(offers, refund, checkedAt, tz) {
  if (offers.length === 0) return "";
  const rows = offers.map((o) => {
    const cost = refund ? null : price(o);
    return `<a class="row" href="${esc(httpsOrNull(o.url))}" rel="nofollow noopener"><i>${icon("ticket")}</i><div class="txt"><b>${esc(o.source)}</b>${cost ? `<small>${esc(cost)}</small>` : ""}</div></a>`;
  }).join("");
  const checked = checkedAt ? longDate(checkedAt, tz) : null;
  return `<div class="block"><h2>${refund ? "Якщо купили квиток" : "Квитки"}</h2><div class="rows">${rows}</div>${checked ? `<p class="fine">Перевірено ${esc(checked)}.</p>` : ""}</div>`;
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
<html lang="uk">
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
<meta name="theme-color" content="#F2F2F4" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#0F0F13" media="(prefers-color-scheme: dark)">
${head}
<link rel="preload" href="/fonts/sofia-sans-condensed-800.woff2" as="font" type="font/woff2" crossorigin>
<link rel="stylesheet" href="/tokens.css?v=9">
<link rel="stylesheet" href="/web.css?v=9">
<link rel="icon" href="/icon.png">
</head>
<body class="event-page">
<header class="nav scrolled"><div class="wrap"><a class="brand" href="/"><img src="/icon.png" alt="">Поряд</a>
  <nav class="links" aria-label="Розділи"><a href="/afisha.html">Афіша</a><a class="btn primary small" href="/app?from=event">Завантажити</a></nav></div></header>
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
  // 404 — на хвилину: випадкові /e/<uuid> інакше щоразу ходили б у базу. 503 не кешуємо: збій бази мине.
  const cache = status === 200 ? `public, max-age=${CACHE_SECONDS}` : status === 404 ? "public, max-age=60" : "no-store";
  return new Response(body, {
    status,
    headers: { "content-type": "text/html; charset=utf-8", "cache-control": cache, ...SECURITY_HEADERS },
  });
}

function json(body) {
  return new Response(JSON.stringify(body), {
    headers: { "content-type": "application/json", "cache-control": "public, max-age=3600", ...SECURITY_HEADERS },
  });
}
