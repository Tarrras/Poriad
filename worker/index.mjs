// Cloudflare Worker перед GitHub Pages: сторінка події `poriad.app/e/{id}` з прев'ю для Telegram і
// файли, за якими iOS і Android перевіряють, що посилання належать застосунку. Решту сайту не чіпає —
// маршрути в wrangler.toml перехоплюють лише ці адреси. Дані — публічний RPC `event_details`, той
// самий, що бачить гість у застосунку: приховані й приватні події він не віддає.

// Назви, дати й ціна — ті самі правила, що на сайті (site/js/poriad.js, порт TitleRules і формату застосунку).
// wrangler збирає цей імпорт у воркер; той самий файл сайт віддає браузеру.
import { displayTitle, overline, stubParts, price, httpsOrNull, esc, CATEGORIES, playUrl, discover, cardsByIds, fold, inWhen, dayLabel, timeOf, cityOf, plural, EVENTS } from "../site/js/poriad.js";
export { esc };

// Мітка ct: завантаження зі сторінок подій (event) і з запрошень (invite) окремо від сайту (site/js/poriad.js).
const appStoreUrl = (ct) => `https://apps.apple.com/app/apple-store/id6813543772?pt=129478154&ct=${ct}&mt=8`;
// Порожньо, коли в site/js/poriad.js вимкнено PLAY_LIVE: тоді кнопку Google Play не показуємо. Мітка utm — та сама.
const IOS_APP_ID = "QTYQMJ94D2.app.poriad.ios";
// Play Console → Test and release → App integrity → App signing: SHA-256 ключа підпису застосунку
// (збірки з Play) і ключа завантаження (локальні prodRelease). Без них Android відкриває посилання в браузері.
const ANDROID_CERT_FINGERPRINTS = [
  "E4:3A:7F:9B:CF:4B:A5:BE:77:92:7D:80:00:4A:A9:56:D1:00:B0:42:43:FD:DC:7B:B5:61:EA:C8:91:9E:C1:00",
  "34:B7:9F:9D:37:41:74:DC:66:54:E3:6C:3E:CE:AB:04:E2:ED:5C:60:8F:49:8B:0C:6D:C4:7C:2F:78:EA:06:03",
];
const CACHE_SECONDS = 300;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
// Токен «Покликати з собою» (docs/invites.md): 128 біт у base64url.
const INVITE = /^[A-Za-z0-9_-]{22}$/;
// Хеш єдиного вбудованого скрипта (кнопка «Поділитися» внизу eventPage: ділиться адресою без запрошення — хто ділиться
// зі сторінки, той не кличе); worker/test.mjs звіряє його з текстом. Не експорт: workerd приймає з модуля лише обробники.
const SHARE_SCRIPT_HASH = "sha256-jSzQzkOzijHE4QQonaYxQFjt59YF0NEivzZqmyVNC6g=";
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
    const afisha = url.pathname.startsWith("/afisha/");
    const match = url.pathname.match(/^\/e\/([^/]+)\/?$/);
    if (!match && !afisha) return fetch(request);
    if (request.method !== "GET" && request.method !== "HEAD") return new Response(null, { status: 405 });
    if (afisha) return cityRoute(url, ctx);

    // Запрошення: сторінка з ім'ям того, хто кличе, особиста — повз спільний кеш в обидва боки. Невідомий чи
    // протухлий токен дає звичайну сторінку з кешу.
    const by = url.searchParams.get("by");
    const inviter = by && INVITE.test(by) ? await inviterOf(by, match[1], env) : null;
    if (inviter) return eventResponse(match[1], env, { by, name: inviter });

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

/** Ім'я того, хто кличе, або null: збій бази тут не помилка, а звичайна сторінка. */
async function inviterOf(token, id, env) {
  if (!UUID.test(id)) return null;
  try {
    const response = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/invite_inviter`, {
      method: "POST",
      headers: { apikey: env.SUPABASE_KEY, "content-type": "application/json" },
      body: JSON.stringify({ p_token: token, p_event_id: id }),
    });
    const name = response.ok ? (await response.json())?.[0]?.name : null;
    return typeof name === "string" && name.trim() ? name.trim() : null;
  } catch {
    return null;
  }
}

/** [invite] — `{ by, name }` запрошення, що вже пройшло перевірку: сторінка особиста й не кешується спільно. */
export async function eventResponse(id, env, invite = null) {
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
  if (UUID.test(live) && live.toLowerCase() !== id.toLowerCase()) {
    return Response.redirect(`https://poriad.app/e/${live}${invite ? `?by=${invite.by}` : ""}`, 301);
  }
  // Укриття — доповнення: збій чи стара база без event_safety лише ховають секцію.
  const shelters = safety?.ok ? ((await safety.json().catch(() => null))?.shelters ?? []) : [];
  return html(eventPage(rows[0], new Date(), shelters, invite), 200, Boolean(invite));
}

export function eventPage(e, now, shelters = [], invite = null) {
  const link = `https://poriad.app/e/${e.id}`;
  // Запрошення несе токен далі: у застосунок кнопкою й банером Safari, у стори — міткою invite.
  const by = invite ? `?by=${invite.by}` : "";
  const ct = invite ? "invite" : "event";
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
    // «Тарас кличе тебе: …» — і в прев'ю месенджера.
    title: invite ? `${invite.name} кличе тебе: ${title}` : title,
    description: [when, place].filter(Boolean).join(" · "),
    image: image || "https://poriad.app/img/og.png",
    url: link,
    // Поки в політиці не сказано, що події індексуються пошуковиками, сторінки — лише за посиланням.
    head: `<meta name="robots" content="noindex">
<meta name="apple-itunes-app" content="app-id=6813543772, affiliate-data=ct=${ct}&amp;pt=129478154, app-argument=${link}${by}">
${ticketUrl ? `<link rel="canonical" href="${esc(ticketUrl)}">` : ""}`,
    body: `<article class="sheet-box">
  <header class="cover-big cat-${category}"><div class="art cat-${category}">${icon(category, "glyph")}${image ? `<img src="${esc(image)}" alt="" referrerpolicy="no-referrer">` : ""}</div>
    ${invite ? `<p class="quiet"><b>${esc(invite.name)}</b> кличе тебе</p>` : ""}<p class="quiet"><span class="genre-word">${esc(CATEGORIES[category])}</span> · ${esc(imported ? `Афіша${sellers ? ` · ${sellers}` : ""}` : "Від людей")}${e.min_age ? ` · ${Number(e.min_age)}+` : ""}</p><h1>${esc(title)}</h1>
  </header>
  <div class="detail">
    ${notice ? `<p class="notice${calm ? " calm" : ""}">${notice}</p>` : ""}
    ${parent ? `<p class="note">Разом на: <a href="/e/${parent.id}">${esc(parent.title)}</a></p>` : ""}
    <div class="actions">
      <a href="${maps}" rel="noopener"><i>${icon("pin")}</i>Маршрут</a>
      <button type="button" data-share><i>${icon("share")}</i>Поділитися</button>
      <a href="poriad://event/${e.id}${by}"><i>${icon("bookmark")}</i>У «Поряд»</a>
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
      <div class="stores">${storeButtons(ct)}</div></div>
  </div>
  <div class="bar"><div class="ticket cat-${category}"><div class="face"><div class="top"><div class="meta">${spots ? "" : "<small>Ціна</small>"}<span>${esc(cost || spots || "Вхід уточнюйте")}</span></div>
    ${ticketUrl && live ? `<a class="btn primary" href="${esc(ticketUrl)}" rel="nofollow noopener">Квитки${e.source_name ? ` на ${esc(e.source_name)}` : ""}</a>`
      : `<a class="btn primary" href="/app?from=${ct}">${imported ? "Завантажити «Поряд»" : "Приєднатися в застосунку"}</a>`}</div></div>
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

// ---- Сторінки міст для пошуковиків: `/afisha/{місто}[/{розділ}]`. Веб-афіша малює події в браузері, і пошуковик
// її майже не бачить; тут той самий індекс віддається готовим HTML. Лише афіша квиткових сервісів: зустрічі людей
// лишаються доступними за посиланням, як і їхні сторінки (noindex у eventPage).

/** Місто в адресі → назва в базі й «де» для заголовків («у Львові», як у підказках пошуку). */
const CITY_PAGES = { kyiv: ["Київ", "в Києві"], lviv: ["Львів", "у Львові"], odesa: ["Одеса", "в Одесі"], dnipro: ["Дніпро", "в Дніпрі"], kharkiv: ["Харків", "в Харкові"] };
/** Розділ: чип, заголовок, що беремо й на скільки днів уперед. Категорії — ті, де в кожному місті є з чого вибрати. */
const FACETS = {
  "": { chip: "Уся афіша", h1: (at, of) => `Афіша ${of}`, title: (at, of) => `Афіша ${of} на тиждень: куди піти`, days: 7, lead: "на найближчий тиждень: концерти, театр, стендап, події для дітей" },
  sohodni: { chip: "Сьогодні", h1: (at) => `Куди піти ${at} сьогодні`, when: "today", days: 1, lead: "ще попереду сьогодні" },
  vykhidni: { chip: "Вихідні", h1: (at) => `Куди піти ${at} на вихідних`, when: "weekend", days: 8, lead: "на суботу й неділю" },
  kontserty: { chip: "Концерти", h1: (at) => `Концерти ${at}`, category: "music", days: 31, lead: "на найближчий місяць" },
  teatr: { chip: "Театр і виставки", h1: (at) => `Театр і виставки ${at}`, category: "art", days: 31, lead: "на найближчий місяць" },
  standup: { chip: "Стендап", h1: (at) => `Стендап ${at}`, category: "comedy", days: 31, lead: "на найближчий місяць" },
  dityam: { chip: "Дітям", h1: (at) => `Куди піти з дітьми ${at}`, category: "kids", days: 31, lead: "на найближчий місяць" },
};
const MAX_ROWS = 100; // стеля event_cards_by_ids: сторінка — два запити в базу
const MIN_INDEXED = 3; // менше — тонка сторінка: людям показуємо, пошуковику індексувати не пропонуємо

async function cityRoute(url, ctx) {
  const path = url.pathname.toLowerCase();
  if (path === "/afisha/") return Response.redirect("https://poriad.app/afisha.html", 301);
  if (path.endsWith("/")) return Response.redirect(`https://poriad.app${path.slice(0, -1)}`, 301);
  const [, slug, facet = ""] = path.match(/^\/afisha\/([a-z]+)(?:\/([a-z]+))?$/) ?? [];
  if (!Object.hasOwn(CITY_PAGES, slug ?? "") || !Object.hasOwn(FACETS, facet)) return html(notFoundPage("Такої сторінки афіші нема."), 404);
  const cacheKey = new Request(url.origin + path);
  const cached = await caches.default.match(cacheKey);
  if (cached) return cached;
  const response = await cityResponse(slug, facet);
  if (response.status === 200) ctx.waitUntil(caches.default.put(cacheKey, response.clone()));
  return response;
}

export async function cityResponse(slug, key, now = new Date()) {
  const facet = FACETS[key];
  try {
    const { index } = await discover(CITY_PAGES[slug][0], { cards: 0, category: facet.category ?? null, to: new Date(+now + facet.days * 864e5).toISOString() });
    // Те, що ще попереду; сеанси прокату й той самий вечір у двох продавців — один рядок.
    const list = fold(index.filter((e) => e.origin === "import" && Date.parse(e.startsAt) >= +now && (!facet.when || inWhen(e, facet.when, now))));
    const cards = (await cardsByIds(spread(list, now).map((e) => e.id))).filter(isLive);
    return html(cityPage(slug, key, cards, list.length, now), 200);
  } catch {
    // Збій бази не кешуємо й не видаємо за порожню афішу.
    return html(notFoundPage("Не вдалося завантажити афішу. Спробуйте ще раз за хвилину."), 503);
  }
}

/** До сотні рядків порівну між днями, щоб «тиждень» не закінчувався на понеділку. */
function spread(list, now) {
  const days = groupBy(list, (e) => dayLabel(new Date(e.startsAt), e.tz, now));
  const each = Math.max(1, Math.floor(MAX_ROWS / Math.max(days.size, 1)));
  return [...days.values()].flatMap((day) => day.slice(0, each)).slice(0, MAX_ROWS);
}

function groupBy(list, key) {
  const out = new Map();
  for (const x of list) { const k = key(x); if (!out.has(k)) out.set(k, []); out.get(k).push(x); }
  return out;
}

/** Скасоване, відкладене й зняте з продажу у списку «куди піти» не показуємо. */
const isLive = (card) => UUID.test(card.id ?? "") && card.status !== "cancelled" && card.import_status !== "withdrawn"
  && !["cancelled", "postponed", "unknown"].includes(card.state);

export function cityPage(slug, key, cards, total, now) {
  const facet = FACETS[key];
  const [name, at] = CITY_PAGES[slug];
  const city = cityOf(name);
  const h1 = facet.h1(at, city.of);
  const here = (s, k) => `/afisha/${s}${k ? `/${k}` : ""}`;
  const url = `https://poriad.app${here(slug, key)}`;
  const intro = `${plural(total, EVENTS)} ${facet.lead}`;
  const days = groupBy(cards, (c) => dayLabel(new Date(c.starts_at), c.time_zone || "Europe/Kyiv", now, true));
  const chips = Object.entries(FACETS).filter(([k]) => k !== key).map(([k, f]) =>
    `<a class="chip${f.category ? ` cat-${f.category}` : ""}" href="${here(slug, k)}">${f.category ? '<span class="dot"></span>' : ""}${f.chip}</a>`).join("");
  const others = Object.entries(CITY_PAGES).filter(([s]) => s !== slug).map(([s, [n]]) => `<a href="${here(s, key)}">${n}</a>`).join(" · ");
  const afishaHref = `/afisha.html${name === "Київ" ? "" : `?city=${encodeURIComponent(name)}`}`;
  const ld = { "@context": "https://schema.org", "@type": "ItemList", name: h1, numberOfItems: cards.length,
    itemListElement: cards.map((card, i) => ({ "@type": "ListItem", position: i + 1, item: eventLd(card) })) };

  return layout({
    title: facet.title?.(at, city.of) ?? h1,
    description: `${h1}: ${intro}. ${cards.slice(0, 3).map((c) => displayTitle(c.title)).join(", ")}`.slice(0, 200),
    image: "https://poriad.app/img/og.png",
    url,
    head: `<meta name="robots" content="${cards.length >= MIN_INDEXED ? "index, follow" : "noindex, follow"}">
<link rel="canonical" href="${url}">
<meta name="apple-itunes-app" content="app-id=6813543772, affiliate-data=ct=city&amp;pt=129478154">
<script type="application/ld+json">${JSON.stringify(ld).replace(/</g, "\\u003c")}</script>`,
    body: `<article class="sheet-box"><div class="detail">
  <div class="block"><p class="overline">${esc(name)} · афіша квиткових сервісів</p><h1>${esc(h1)}</h1>
    <p class="lead">${esc(intro)}. Час, місце й ціна; квитки продають на сайтах продавців. Афіша оновлюється щодня.</p></div>
  <nav class="chips" aria-label="Розділи афіші">${chips}</nav>
  ${cards.length ? [...days].map(([day, list]) => `<section class="block"><h2>${esc(day)}</h2><div class="rows">${list.map((c) => cityRow(c, now)).join("")}</div></section>`).join("")
    : `<div class="empty"><b>Тут поки тихо</b><span>На ці дні в афіші ${esc(city.of)} такого нема.</span><a class="btn secondary" href="${key ? here(slug, "") : afishaHref}">Уся афіша ${esc(city.of)}</a></div>`}
  ${cards.length && cards.length < total ? `<p class="fine">Тут ${cards.length} з ${total}. Решта — <a href="${afishaHref}">в афіші на сайті</a> і в застосунку.</p>` : ""}
  <div class="app-only"><b>Що поруч з вами, видно на мапі</b>
    <ul><li>${icon("map")}Уся афіша міста на мапі, фільтр «сьогодні»</li><li>${icon("bell")}Нагадування за годину до початку</li><li>${icon("people")}«Шукаю компанію», якщо нема з ким піти</li></ul>
    <div class="stores">${storeButtons("city")}</div></div>
  <p class="fine">Афіша інших міст: ${others}</p>
</div></article>`,
  });
}

function cityRow(card, now) {
  const category = CATEGORIES[card.category] ? card.category : "social";
  const [stubTime, stubDay] = stubParts(card, now, true);
  const meta = [timeOf(new Date(card.starts_at), card.time_zone || "Europe/Kyiv"), CATEGORIES[category], card.place_name || card.address, price(card)].filter(Boolean).join(" · ");
  return `<a class="row" href="/e/${card.id}"><div class="ticket v stub-tile cat-${category}" aria-hidden="true"><div class="face"><b class="t">${esc(stubTime)}</b></div><div class="stub"><small>${esc(stubDay)}</small></div></div>
    <div class="txt"><small>${esc(meta)}</small><b>${esc(displayTitle(card.title))}</b></div></a>`;
}

/** schema.org/Event для рядка списку: квиток — у продавця, ціна — лише коли відома. */
function eventLd(card) {
  const ticket = httpsOrNull(card.canonical_url);
  const cost = card.is_free ? 0 : card.price_min > 0 ? Number(card.price_min) : null;
  return {
    "@type": "Event", name: displayTitle(card.title), url: `https://poriad.app/e/${card.id}`,
    startDate: card.starts_at, ...(card.ends_at ? { endDate: card.ends_at } : {}),
    eventStatus: "https://schema.org/EventScheduled", eventAttendanceMode: "https://schema.org/OfflineEventAttendanceMode",
    location: { "@type": "Place", name: card.place_name || card.address || card.city,
      address: { "@type": "PostalAddress", ...(card.address ? { streetAddress: card.address } : {}), addressLocality: card.city, addressCountry: "UA" } },
    ...(httpsOrNull(card.image_url) ? { image: card.image_url } : {}),
    ...(ticket && cost !== null ? { offers: { "@type": "Offer", url: ticket, price: cost, priceCurrency: "UAH" } } : {}),
  };
}

function storeButtons(ct = "event") {
  const play = playUrl(ct);
  return `<a class="store" href="${appStoreUrl(ct)}">${icon("apple")}<span><small>Завантажити в</small>App Store</span></a>
    ${play ? `<a class="store play" href="${play}">${icon("play")}<span><small>Завантажити з</small>Google Play</span></a>` : ""}`;
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
<link rel="stylesheet" href="/tokens.css?v=10">
<link rel="stylesheet" href="/web.css?v=10">
<link rel="icon" href="/icon.png">
</head>
<body class="event-page">
<header class="nav scrolled"><div class="wrap"><a class="brand" href="/"><img src="/icon.png" alt="">Поряд</a>
  <nav class="links" aria-label="Розділи"><a href="/afisha.html">Афіша</a><a class="btn primary small" href="/app?from=event">Завантажити</a></nav></div></header>
<main class="event-shell">${body}</main>
<footer class="site"><div class="wrap"><span>Питання й скарги: <a href="mailto:hello@poriad.app">hello@poriad.app</a></span>
  <nav aria-label="Афіша міст">${Object.entries(CITY_PAGES).map(([s, [n]]) => `<a href="/afisha/${s}">${n}</a>`).join("")}</nav>
  <nav aria-label="Документи"><a href="/afisha.html">Афіша</a><a href="/privacy.html">Конфіденційність</a><a href="/terms.html">Умови</a></nav></div></footer>
<script>
document.querySelector("[data-share]")?.addEventListener("click", async () => {
  const url = location.origin + location.pathname;
  const data = { title: document.querySelector("h1")?.textContent || document.title, url };
  if (navigator.share) { try { await navigator.share(data); } catch {} return; }
  try { await navigator.clipboard.writeText(url); alert("Посилання скопійовано"); } catch { prompt("Посилання на подію", url); }
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


function html(body, status, personal = false) {
  // 404 — на хвилину: випадкові /e/<uuid> інакше щоразу ходили б у базу. 503 не кешуємо: збій бази мине.
  // Сторінка запрошення — лише браузеру того, хто відкрив: проміжні кеші її не тримають.
  const cache = personal ? `private, max-age=${CACHE_SECONDS}` : status === 200 ? `public, max-age=${CACHE_SECONDS}`
    : status === 404 ? "public, max-age=60" : "no-store";
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
