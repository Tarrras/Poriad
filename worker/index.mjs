// Cloudflare Worker перед GitHub Pages: сторінка події `poriad.app/e/{id}` з прев'ю для Telegram і
// файли, за якими iOS і Android перевіряють, що посилання належать застосунку. Решту сайту не чіпає —
// маршрути в wrangler.toml перехоплюють лише ці адреси. Дані — публічний RPC `event_details`, той
// самий, що бачить гість у застосунку: приховані й приватні події він не віддає.

const APP_STORE_URL = "https://apps.apple.com/ua/app/id6813543772";
// Порожньо, доки застосунок не вийшов у Google Play: кнопку не показуємо.
const PLAY_URL = "";
const IOS_APP_ID = "QTYQMJ94D2.app.poriad.ios";
// Play Console → Test and release → App integrity → App signing: SHA-256 ключа підпису застосунку.
// Порожньо — Android не підтвердить App Links і відкриватиме посилання в браузері, на цій же сторінці.
const ANDROID_CERT_FINGERPRINTS = [];
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
  const when = formatWhen(e.starts_at, e.time_zone);
  // Імпорт часто вже пише місто в адресі: «Київ, …, м. Київ» читається як помилка.
  const place = e.address && e.city && e.address.includes(e.city) ? e.address : [e.city, e.address].filter(Boolean).join(", ");
  const imported = e.origin === "import";
  const cancelled = e.status === "cancelled";
  const past = new Date(e.ends_at || e.starts_at) < now;
  const image = httpsOrNull(e.image_url);
  const ticketUrl = imported ? httpsOrNull(e.canonical_url) : null;

  const facts = [
    price(e),
    !imported && e.capacity ? `Учасників: ${e.attendee_count} з ${e.capacity}` : !imported && e.attendee_count > 0 ? `Учасників: ${e.attendee_count}` : null,
    e.min_age ? `${e.min_age}+` : null,
    !imported && e.approval_required ? "Участь за підтвердженням організатора" : null,
  ].filter(Boolean);
  const notice = cancelled ? "Подію скасовано." : past ? "Ця подія вже минула." : null;

  return layout({
    title: e.title,
    description: [when, place].filter(Boolean).join(" · "),
    image: image || "https://poriad.app/img/og.png",
    url: link,
    // Поки в політиці не сказано, що події індексуються пошуковиками, сторінки — лише за посиланням.
    head: `<meta name="robots" content="noindex">
<meta name="apple-itunes-app" content="app-id=${APP_STORE_URL.match(/id(\d+)/)[1]}, app-argument=${link}">
${ticketUrl ? `<link rel="canonical" href="${esc(ticketUrl)}">` : ""}`,
    body: `
${notice ? `<p class="notice">${notice}</p>` : ""}
<article class="card event">
  ${image ? `<img class="cover" src="${esc(image)}" alt="">` : ""}
  <h1>${esc(e.title)}</h1>
  <p class="when">${esc(when)}</p>
  <p class="where"><a href="https://maps.google.com/?q=${Number(e.latitude)},${Number(e.longitude)}">${esc(place)}</a></p>
  ${facts.length ? `<p class="facts">${facts.map(esc).join(" · ")}</p>` : ""}
  ${!imported && e.organizer_name ? `<p class="note">Організовує ${esc(e.organizer_name)}</p>` : ""}
  ${e.description ? `<p class="description">${esc(e.description)}</p>` : ""}
  ${ticketUrl ? `<p><a href="${esc(ticketUrl)}" rel="nofollow">Квитки${e.source_name ? ` на ${esc(e.source_name)}` : ""}</a></p>` : ""}
</article>
${!cancelled && !past ? sheltersSection(shelters) : ""}
${storeButtons(e.id, imported ? "Зберегти подію, отримати нагадування й знайти, що ще відбувається поряд, можна в застосунку." : "Приєднатися, написати в чат учасників і отримати нагадування можна в застосунку.")}`,
  });
}

// Правила Мінкульту з 11.09.2026: про найближче укриття повідомляють заздалегідь, зокрема на сайті.
const SHELTER_KINDS = { metro: "Метро", underpass: "Підземний перехід", parking: "Підземний паркінг", basement: "Укриття" };

function sheltersSection(shelters) {
  if (!Array.isArray(shelters) || shelters.length === 0) return "";
  const rows = shelters.map((s) => {
    const extras = [s.hours, s.accessible ? "Є пандус" : null].filter(Boolean).map(esc).join(" · ");
    return `<li><a href="https://maps.google.com/?q=${Number(s.latitude)},${Number(s.longitude)}">${esc(s.address)}</a>
      <span class="note">${esc(SHELTER_KINDS[s.kind] || "Укриття")} · ${Number(s.distance_m)} м${extras ? ` · ${extras}` : ""}</span></li>`;
  }).join("");
  return `<section class="card"><h2>Укриття поруч</h2><ul class="shelters">${rows}</ul>
<p class="note">За відкритими даними КМДА (CC BY).</p></section>`;
}

export function notFoundPage(message = "Подію не знайдено: її могли приховати або посилання неповне.") {
  return layout({
    title: "Поряд — події вашого міста",
    description: "Концерти, настолки, пробіжки й зустрічі поруч із вами на одній мапі.",
    image: "https://poriad.app/img/og.png",
    url: "https://poriad.app/",
    head: `<meta name="robots" content="noindex">`,
    body: `<p class="notice">${esc(message)}</p>${storeButtons(null, "Що відбувається поряд із вами сьогодні — у застосунку.")}`,
  });
}

function storeButtons(id, pitch) {
  return `<div class="card">
  <p>${esc(pitch)}</p>
  <div class="row">
    ${id ? `<a class="pill" href="poriad://event/${id}">Відкрити в «Поряд»</a>` : ""}
    <a class="pill ${id ? "ghost" : ""}" href="${APP_STORE_URL}">App Store</a>
    ${PLAY_URL ? `<a class="pill ghost" href="${PLAY_URL}">Google Play</a>` : ""}
  </div>
</div>`;
}

function layout({ title, description, image, url, head, body }) {
  return `<!doctype html>
<html lang="uk">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)} — Поряд</title>
<meta name="description" content="${esc(description)}">
<meta property="og:type" content="website">
<meta property="og:site_name" content="Поряд">
<meta property="og:title" content="${esc(title)}">
<meta property="og:description" content="${esc(description)}">
<meta property="og:image" content="${esc(image)}">
<meta property="og:url" content="${esc(url)}">
<meta name="twitter:card" content="summary_large_image">
${head}
<link rel="stylesheet" href="/style.css">
<link rel="icon" href="/icon.png">
<style>
.event h1 { margin: 12px 0 4px; }
.event .cover { width: 100%; max-height: 360px; object-fit: cover; border-radius: 14px; }
.event .when { font-weight: 600; margin: 0; }
.event .where { margin: 0 0 8px; color: var(--ink-2); }
.event .facts { font-size: 15px; color: var(--ink-2); }
.event .description { white-space: pre-line; overflow-wrap: anywhere; }
.shelters { list-style: none; padding: 0; margin: 0; }
.shelters li { display: flex; flex-direction: column; padding: 8px 0; border-bottom: 1px solid var(--hairline); }
.shelters li:last-child { border-bottom: 0; }
.card h2 { margin-top: 0; }
.notice { background: var(--accent-soft); color: var(--accent); padding: 12px 16px; border-radius: 14px; font-weight: 600; }
</style>
</head>
<body>
<header class="hero"><div class="wrap"><a class="brand" href="/"><img src="/icon.png" alt=""><b>Поряд</b></a></div></header>
<main><div class="wrap">${body}</div></main>
<footer><div class="wrap"><a href="/privacy.html">Конфіденційність</a><a href="/terms.html">Умови</a><a href="mailto:hello@poriad.app">hello@poriad.app</a></div></footer>
</body>
</html>`;
}

function formatWhen(startsAt, timeZone) {
  if (!startsAt) return "";
  const options = { weekday: "long", day: "numeric", month: "long", hour: "2-digit", minute: "2-digit" };
  try {
    return new Intl.DateTimeFormat("uk-UA", { ...options, timeZone: timeZone || "Europe/Kyiv" }).format(new Date(startsAt));
  } catch {
    // Невідома зона з бази — показуємо київський час, а не падаємо.
    return new Intl.DateTimeFormat("uk-UA", { ...options, timeZone: "Europe/Kyiv" }).format(new Date(startsAt));
  }
}

function price(e) {
  if (e.is_free) return "Безкоштовно";
  if (e.price_min > 0) return `від ${Math.round(e.price_min)} грн`;
  return null;
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

function httpsOrNull(value) {
  return typeof value === "string" && value.startsWith("https://") ? value : null;
}

export function esc(value) {
  return String(value ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
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
