// Дані й формат для сайту «Поряд». Афіша — та сама, що бачить гість у застосунку: публічні RPC prod-проєкту
// (discover_events, event_cards_by_ids, event_safety) з publishable-ключем, як у worker/. Модуль без побічних
// дій при імпорті: правила назв, дат і згортання перевіряє `node tools/site_test.mjs`.

const SUPABASE_URL = "https://tzdogzdvctlumsqlqskr.supabase.co";
const SUPABASE_KEY = "sb_publishable_RoY0wFzTOcXlmOIYC0UE-w_fOt5rXPq";
export const APP_STORE_URL = "https://apps.apple.com/ua/app/id6813543772";
export const PLAY_URL = "https://play.google.com/store/apps/details?id=app.poriad.android";

/** `HomeLocation.covered` (core/domain Rules.kt): центр міста; вікно — ±0.15° широти й ±0.25° довготи, як перша мапа. */
export const CITIES = [
  { name: "Київ", lat: 50.4501, lng: 30.5234, in: "Києві", of: "Києва" },
  { name: "Львів", lat: 49.8397, lng: 24.0297, in: "Львові", of: "Львова" },
  { name: "Одеса", lat: 46.4825, lng: 30.7233, in: "Одесі", of: "Одеси" },
  { name: "Дніпро", lat: 48.4647, lng: 35.0462, in: "Дніпрі", of: "Дніпра" },
  { name: "Харків", lat: 49.9935, lng: 36.2304, in: "Харкові", of: "Харкова" },
];
export const cityOf = (name) => CITIES.find((c) => c.name === name) ?? CITIES[0];

/** Підписи категорій — як у застосунку. Порядок — що частіше трапляється в афіші. */
export const CATEGORIES = {
  music: "Музика", art: "Мистецтво", comedy: "Стендап", kids: "Дітям", social: "Зустрічі", games: "Ігри",
  sport: "Спорт", food: "Їжа", outdoors: "Природа", tours: "Екскурсії", conference: "Конференції",
};
/** Ті самі відтінки, що `--cat-*` у tokens.css: мапа малює на canvas і CSS-змінних не бачить. */
export const CATEGORY_COLORS = {
  music: "#6D4AC9", sport: "#0F7F73", art: "#C43B6B", food: "#C96A1E", games: "#2F63C4", outdoors: "#3E7D3A",
  social: "#B8562F", comedy: "#A07813", kids: "#1F8A8A", tours: "#5F7F1F", conference: "#933FA8",
};

async function rpc(name, body) {
  const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: { apikey: SUPABASE_KEY, "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!response.ok) throw new Error(`${name}: ${response.status}`);
  return response.json();
}

/**
 * Афіша міста: індекс усіх майбутніх подій (дати й категорії фільтруємо на місці — миттєво) і перші картки.
 * Текст шукає сервер: він бачить ще опис і адресу, яких в індексі нема.
 */
export async function discover(city, { text = null, cards = 24 } = {}) {
  const c = cityOf(city);
  const data = await rpc("discover_events", {
    p_south: c.lat - 0.15, p_west: c.lng - 0.25, p_north: c.lat + 0.15, p_east: c.lng + 0.25,
    p_text: text || null, p_cards: cards,
  });
  return { index: data.index.map(toEntry), cards: data.cards };
}

const toEntry = ([id, lat, lng, category, startsAt, tz, title, origin, source, capacity, count]) =>
  ({ id, lat, lng, category, startsAt, tz: tz || "Europe/Kyiv", title, origin, source, capacity, count });

/** Картки за id, до сотні за раз (стеля RPC). */
export async function cardsByIds(ids) {
  const out = [];
  for (let i = 0; i < ids.length; i += 100) out.push(...await rpc("event_cards_by_ids", { p_ids: ids.slice(i, i + 100) }));
  return out;
}

export const eventSafety = (id) => rpc("event_safety", { p_event_id: id });

// ---- Назва. Порт `TitleRules` (core/domain): капс — у «Кожне Слово З Великої», лапки — «ялинки», апостроф — ’.

const SHOUT_MIN_LETTERS = 5;
const SMALL_WORDS = new Set(["і", "й", "та", "а", "але", "або", "чи", "в", "у", "на", "з", "зі", "із", "до", "від", "по", "за", "про", "при", "під", "над", "без", "для", "між", "через"]);
const isLetter = (c) => /\p{L}/u.test(c);
const isLower = (c) => c !== c.toUpperCase() && c === c.toLowerCase();
const isLetterOrDigit = (c) => /[\p{L}\p{N}]/u.test(c);
const isWordChar = (c) => isLetterOrDigit(c) || c === "'" || c === "’" || c === "ʼ" || c === "-";

export function displayTitle(title) {
  return apostrophes(quotes(isShouting(title) ? capitalized(title) : title));
}

function isShouting(title) {
  let letters = 0;
  for (const c of title) if (isLetter(c)) { if (isLower(c)) return false; letters++; }
  return letters >= SHOUT_MIN_LETTERS;
}

function capitalized(title) {
  const chars = [...title];
  let out = "";
  for (let i = 0; i < chars.length;) {
    if (!isWordChar(chars[i])) { out += chars[i++]; continue; }
    let j = i;
    while (j < chars.length && isWordChar(chars[j])) j++;
    out += caseWord(chars.slice(i, j).join(""), isMidPhrase(chars, i));
    i = j;
  }
  return out;
}

function isMidPhrase(chars, at) {
  if (at === 0 || !/\s/.test(chars[at - 1])) return false;
  let k = at - 1;
  while (k >= 0 && /\s/.test(chars[k])) k--;
  return k >= 0 && (isLetterOrDigit(chars[k]) || chars[k] === "’" || chars[k] === "'");
}

function caseWord(word, midPhrase) {
  if (/\p{N}/u.test(word) || (word.length <= 3 && /^[A-Z-]+$/.test(word))) return word;
  const lower = word.toLowerCase();
  return midPhrase && SMALL_WORDS.has(lower) ? lower : lower.charAt(0).toUpperCase() + lower.slice(1);
}

function quotes(title) {
  if (!/["“”„]/.test(title)) return title;
  let out = "";
  [...title].forEach((c, i, chars) => {
    const before = i === 0 ? " " : chars[i - 1];
    if (c === "“" || c === "„") out += "«";
    else if (c === "”") out += "»";
    else if (c === '"') out += /\p{N}/u.test(before) ? c : /\s/.test(before) || "([—–-:«".includes(before) ? "«" : "»";
    else out += c;
  });
  return out;
}

function apostrophes(title) {
  const chars = [...title];
  return chars.map((c, i) => "'`´‘".includes(c) && i > 0 && i < chars.length - 1 && isLetter(chars[i - 1]) && isLetter(chars[i + 1]) ? "’" : c).join("");
}

// ---- Дати. Усе в поясі події (у містах афіші — Київ), а не браузера.

const formatters = new Map();
function fmt(tz, options) {
  const key = tz + JSON.stringify(options);
  if (!formatters.has(key)) {
    try { formatters.set(key, new Intl.DateTimeFormat(options.locale ?? "uk-UA", { ...options, timeZone: tz })); }
    catch { formatters.set(key, new Intl.DateTimeFormat(options.locale ?? "uk-UA", { ...options, timeZone: "Europe/Kyiv" })); }
  }
  return formatters.get(key);
}
/** Номер дня від 1970-01-01 у поясі `tz`: різниця двох — скільки календарних днів між ними. */
const dayNumber = (date, tz) => Date.parse(fmt(tz, { locale: "en-CA", year: "numeric", month: "2-digit", day: "2-digit" }).format(date)) / 864e5;
/** 0 — понеділок … 6 — неділя. 1970-01-01 був четвергом. */
const isoWeekday = (day) => (day + 3) % 7;
const WEEKDAY_ON = ["У понеділок", "У вівторок", "У середу", "У четвер", "У п’ятницю", "У суботу", "У неділю"];
const year = (date, tz) => fmt(tz, { year: "numeric" }).format(date);

export const timeOf = (date, tz) => fmt(tz, { hour: "2-digit", minute: "2-digit" }).format(date);

/** «Сьогодні», «Завтра», «У суботу», далі — «пт, 23 жовт.» (з роком, якщо не цього року). Як `dayLabel` в iOS. */
export function dayLabel(date, tz, now = new Date(), long = false) {
  const days = dayNumber(date, tz) - dayNumber(now, tz);
  if (days === 0) return "Сьогодні";
  if (days === 1) return "Завтра";
  if (days >= 2 && days <= 6) return WEEKDAY_ON[isoWeekday(dayNumber(date, tz))];
  const other = year(date, tz) !== year(now, tz) ? { year: "numeric" } : {};
  return fmt(tz, long ? { weekday: "long", day: "numeric", month: "long", ...other } : { weekday: "short", day: "numeric", month: "short", ...other }).format(date);
}

const plainDate = (date, tz, now) => fmt(tz, { day: "numeric", month: "long", ...(year(date, tz) !== year(now, tz) ? { year: "numeric" } : {}) }).format(date);

/** Надрядок картки: «Сьогодні · 18:30»; для того, що вже йде, — «Триває зараз» або «до 31 жовтня» (прокат). */
export function overline(card, now = new Date(), long = false) {
  const tz = card.time_zone || "Europe/Kyiv";
  const start = new Date(card.starts_at);
  const end = card.ends_at ? new Date(card.ends_at) : null;
  if (end && start <= now && now < end) return end - start > 864e5 ? `до ${plainDate(end, tz, now)}` : "Триває зараз";
  return `${dayLabel(start, tz, now, long)} · ${timeOf(start, tz)}`;
}

/** Фільтр дат, як чипи головної (`HomeRules`): вихідні — з найближчої суботи (сьогодні, якщо вже) до понеділка. */
export const WHEN = { today: "Сьогодні", tomorrow: "Завтра", weekend: "Вихідні" };
export function inWhen(entry, when, now = new Date()) {
  if (!when) return true;
  const today = dayNumber(now, entry.tz);
  const day = dayNumber(new Date(entry.startsAt), entry.tz) - today;
  if (when === "today") return day === 0;
  if (when === "tomorrow") return day === 1;
  const iso = isoWeekday(today);
  return day >= Math.max(5 - iso, 0) && day < 7 - iso;
}

// ---- Згортання. Сеанси прокату й той самий вечір від двох продавців — одна картка, як `EventSeries`/`DuplicateEvents`.

const normTitle = (title) => title.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, " ").trim();

/**
 * Згортає індекс (уже відсортований сервером за часом). Голова групи — найближчий сеанс, решта в `sessions`.
 * ponytail: точний збіг назви в тій самій точці або вкладена назва в той самий час; схожість, як у застосунку, — якщо дублі пролізуть.
 */
export function fold(entries) {
  const byTitle = new Map(), byTime = new Map(), out = [];
  for (const e of entries) {
    if (e.origin === "community") { out.push(e); continue; }
    const place = `${e.lat.toFixed(4)},${e.lng.toFixed(4)}`;
    const title = normTitle(e.title);
    const run = byTitle.get(`${place}|${title}`);
    if (run) { run.sessions.push(e); continue; }
    const twins = byTime.get(`${place}|${e.startsAt}`) ?? [];
    if (twins.some((t) => t.norm.includes(title) || title.includes(t.norm))) continue;
    const head = { ...e, sessions: [e] };
    byTitle.set(`${place}|${title}`, head);
    byTime.set(`${place}|${e.startsAt}`, [...twins, { norm: title }]);
    out.push(head);
  }
  return out;
}

/**
 * Порядок стрічки на сайті: те, що вже йде (виставка «до 31 жовтня»), — після найближчих 12 годин, а не першим.
 * Сервер ставить його на «зараз»; у застосунку зверху «Ваше», а на сайті перший екран — це вечір.
 */
export function soonFirst(list, now = Date.now()) {
  const key = (e) => { const t = Date.parse(e.startsAt); return t < now ? now + 12 * 36e5 : t; };
  return [...list].sort((a, b) => key(a) - key(b));
}

/** Скільки ще днів у прокаті, крім показаного. */
export function otherDays(sessions) {
  if (!sessions || sessions.length < 2) return 0;
  return new Set(sessions.map((s) => dayNumber(new Date(s.startsAt), s.tz))).size - 1;
}

export const price = (card) => card.is_free ? "Безкоштовно" : card.price_min > 0 ? `від ${Math.round(card.price_min)} ₴` : null;

/** «Афіша · Concert.ua» або «Від людей». */
export const sourceNote = (card) => card.origin === "import" ? `Афіша${card.source_name ? ` · ${card.source_name}` : ""}` : "Від людей";

export const httpsOrNull = (value) => typeof value === "string" && value.startsWith("https://") ? value : null;

export function esc(value) {
  return String(value ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
}

/** «1 340 подій»: число з вузьким пробілом і слово в потрібному відмінку. */
export function plural(n, [one, few, many]) {
  const mod10 = n % 10, mod100 = n % 100;
  const word = mod10 === 1 && mod100 !== 11 ? one : mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14) ? few : many;
  return `${n.toLocaleString("uk-UA")} ${word}`;
}
export const EVENTS = ["подія", "події", "подій"];

// ---- Стиль мапи. Порт `poruchMapStyle` (shared/MapStyle.kt), світлий: тло — папір екранів, дороги — поверхня карток.

export function mapStyle() {
  const c = { land: "#F5F5F7", landTint: "#EBEBF0", green: "#E3EBDD", water: "#CBD9DE", waterLine: "#B5C7CE", building: "#EBEBF0",
    buildingLine: "#E5E5EA", road: "#FFFFFF", casing: "#E5E5EA", rail: "#DCD7C9", boundary: "#6E6E78",
    label: "#1D1D1F", muted: "#6E6E73", faint: "#6E6E78", halo: "#F5F5F7", waterLabel: "#6E858F" };
  const zoom = (stops, base = 1) => ["interpolate", ["exponential", base], ["zoom"], ...stops.flat()];
  const NAME = ["coalesce", ["get", "name:uk"], ["get", "name"]];
  const POLY = ["match", ["geometry-type"], ["Polygon", "MultiPolygon"], true, false];
  const LINE = ["match", ["geometry-type"], ["LineString", "MultiLineString"], true, false];
  const cls = (...names) => ["match", ["get", "class"], names, true, false];
  const src = { source: "openmaptiles" };
  const round = { "line-cap": "round", "line-join": "round" };
  const major = cls("primary", "secondary", "tertiary", "trunk");
  const halo = (w) => ({ "text-halo-color": c.halo, "text-halo-width": w });
  return {
    version: 8,
    sources: { openmaptiles: { type: "vector", url: "https://tiles.openfreemap.org/planet" } },
    glyphs: "https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf",
    layers: [
      { id: "ground", type: "background", paint: { "background-color": c.land } },
      { id: "residential", type: "fill", ...src, "source-layer": "landuse", maxzoom: 16, filter: ["all", POLY, cls("residential", "suburb", "neighbourhood")], paint: { "fill-color": c.landTint, "fill-opacity": zoom([[8, 0.4], [13, 0.75]]) } },
      { id: "park", type: "fill", ...src, "source-layer": "park", filter: POLY, paint: { "fill-color": c.green } },
      { id: "woodland", type: "fill", ...src, "source-layer": "landcover", minzoom: 8, filter: ["all", POLY, cls("wood", "grass")], paint: { "fill-color": c.green, "fill-opacity": zoom([[8, 0], [11, 1]]) } },
      { id: "water", type: "fill", ...src, "source-layer": "water", filter: ["all", POLY, ["!=", ["get", "brunnel"], "tunnel"]], paint: { "fill-color": c.water } },
      { id: "waterway", type: "line", ...src, "source-layer": "waterway", minzoom: 8, filter: LINE, paint: { "line-color": c.waterLine, "line-width": zoom([[9, 0.6], [16, 3.5]]) } },
      { id: "building", type: "fill", ...src, "source-layer": "building", minzoom: 13, paint: { "fill-color": c.building, "fill-outline-color": c.buildingLine, "fill-opacity": zoom([[13, 0], [14.5, 1]]) } },
      { id: "road-minor", type: "line", ...src, "source-layer": "transportation", minzoom: 12, filter: ["all", LINE, cls("minor", "service", "track")], layout: round, paint: { "line-color": c.road, "line-opacity": zoom([[12, 0], [13.5, 1]]), "line-width": zoom([[13, 1.4], [20, 18]], 1.55) } },
      { id: "road-major-casing", type: "line", ...src, "source-layer": "transportation", minzoom: 11, filter: ["all", LINE, major], layout: round, paint: { "line-color": c.casing, "line-width": zoom([[11, 3], [20, 24]], 1.3) } },
      { id: "road-major", type: "line", ...src, "source-layer": "transportation", filter: ["all", LINE, major], layout: round, paint: { "line-color": c.road, "line-opacity": zoom([[8, 0.5], [11, 1]]), "line-width": zoom([[8, 0.8], [11, 2], [20, 20]], 1.3) } },
      { id: "road-motorway-casing", type: "line", ...src, "source-layer": "transportation", minzoom: 7, filter: ["all", LINE, ["==", ["get", "class"], "motorway"]], layout: round, paint: { "line-color": c.casing, "line-width": zoom([[7, 3], [20, 28]], 1.3) } },
      { id: "road-motorway", type: "line", ...src, "source-layer": "transportation", filter: ["all", LINE, ["==", ["get", "class"], "motorway"]], layout: round, paint: { "line-color": c.road, "line-width": zoom([[5, 0.8], [7, 1.8], [20, 24]], 1.3) } },
      { id: "rail", type: "line", ...src, "source-layer": "transportation", minzoom: 13, filter: ["all", LINE, ["==", ["get", "class"], "rail"]], paint: { "line-color": c.rail, "line-width": zoom([[13, 0.8], [18, 2]]), "line-dasharray": [3, 2] } },
      { id: "label-road", type: "symbol", ...src, "source-layer": "transportation_name", minzoom: 14, filter: cls("motorway", "trunk", "primary", "secondary", "tertiary"), layout: { "symbol-placement": "line", "text-field": NAME, "text-font": ["Noto Sans Regular"], "text-size": zoom([[14, 10], [18, 12]]), "text-letter-spacing": 0.02 }, paint: { "text-color": c.faint, ...halo(1.1) } },
      { id: "label-water", type: "symbol", ...src, "source-layer": "water_name", minzoom: 8, maxzoom: 12.5, layout: { "text-field": NAME, "text-font": ["Noto Sans Italic"], "text-max-width": 6, "text-letter-spacing": 0.1, "text-size": zoom([[8, 11], [12, 13]]) }, paint: { "text-color": c.waterLabel, ...halo(1.2) } },
      { id: "label-district", type: "symbol", ...src, "source-layer": "place", minzoom: 12.5, filter: ["all", cls("suburb", "quarter"), ["<=", ["get", "rank"], 25]], layout: { "text-field": NAME, "text-font": ["Noto Sans Bold"], "text-transform": "uppercase", "text-letter-spacing": 0.14, "text-max-width": 8, "text-size": zoom([[12.5, 9.5], [16, 11]]) }, paint: { "text-color": c.faint, ...halo(1.2) } },
      { id: "label-settlement", type: "symbol", ...src, "source-layer": "place", minzoom: 8, maxzoom: 14, filter: cls("town", "village", "hamlet"), layout: { "text-field": NAME, "text-font": ["Noto Sans Regular"], "text-max-width": 8, "text-size": zoom([[8, 11], [13, 13]]) }, paint: { "text-color": c.muted, ...halo(1.3) } },
      { id: "label-city", type: "symbol", ...src, "source-layer": "place", minzoom: 4, filter: cls("city", "state", "country"), layout: { "text-field": NAME, "text-font": ["Noto Sans Bold"], "text-max-width": 8, "text-size": zoom([[4, 12], [8, 15], [12, 17]]) }, paint: { "text-color": c.label, "text-opacity": zoom([[10.5, 1], [12, 0]]), ...halo(1.4) } },
    ],
  };
}
