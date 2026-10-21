// Дані й формат для сайту «Поряд». Афіша — та сама, що бачить гість у застосунку: публічні RPC prod-проєкту
// (discover_events, event_cards_by_ids, event_safety) з publishable-ключем, як у worker/. Модуль без побічних
// дій при імпорті: правила назв, дат і згортання перевіряє `node tools/site_test.mjs`.

const SUPABASE_URL = "https://tzdogzdvctlumsqlqskr.supabase.co";
const SUPABASE_KEY = "sb_publishable_RoY0wFzTOcXlmOIYC0UE-w_fOt5rXPq";
// Мітки джерела: ct — кампанія App Store Connect (Analytics → Campaigns, pt — наш акаунт), utm — звіт Play Console.
// Сайт — ct=site, сторінки подій (worker/) — event, QR і /app — qr, банер Safari — banner.
export const APP_STORE_URL = "https://apps.apple.com/app/apple-store/id6813543772?pt=129478154&ct=site&mt=8";
// Google Play: публічний з 21.10.2026. false ховає значки Google Play, «iPhone і Android» і QR для Android
// (після зміни — підняти ?v=N і викласти сайт і worker).
const PLAY_LIVE = true;
export const playUrl = (campaign) => PLAY_LIVE ? `https://play.google.com/store/apps/details?id=app.poriad.android&referrer=utm_source%3Dporiad.app%26utm_campaign%3D${campaign}` : "";
export const PLAY_URL = playUrl("site");

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

/**
 * Друк корінця квитка, порт `stubParts` (iOS DesignSystem.swift): [година, день]. Те, що йде, — «ЗАРАЗ / ТРИВАЄ»
 * або «31.10 / ДО» для прокату; минуле — година й дата. `compact` — малий корінець рядка: дата числом.
 */
export function stubParts(card, now = new Date(), compact = false) {
  const tz = card.time_zone || "Europe/Kyiv";
  const start = new Date(card.starts_at);
  const end = card.ends_at ? new Date(card.ends_at) : null;
  const date = (d) => fmt(tz, { day: "2-digit", month: "2-digit" }).format(d);
  if ((end ?? new Date(+start + 3 * 36e5)) < now) return [timeOf(start, tz), date(start)];
  if (start <= now) return end && end - start > 864e5 ? [date(end), "ДО"] : ["ЗАРАЗ", "ТРИВАЄ"];
  return [timeOf(start, tz), compact ? date(start) : dayLabel(start, tz, now).toUpperCase()];
}

/**
 * Фільтр дат, як чипи головної (`HomeRules`): вихідні — з найближчої суботи (сьогодні, якщо вже) до понеділка.
 * «Сьогодні ввечері» — лише сайт: сьогодні з початком о 17:00 і пізніше в поясі події.
 */
export const WHEN = { today: "Сьогодні", evening: "Сьогодні ввечері", tomorrow: "Завтра", weekend: "Вихідні" };
export function inWhen(entry, when, now = new Date()) {
  if (!when) return true;
  const today = dayNumber(now, entry.tz);
  const start = new Date(entry.startsAt);
  const day = dayNumber(start, entry.tz) - today;
  if (when === "today") return day === 0;
  if (when === "evening") return day === 0 && Number(timeOf(start, entry.tz).slice(0, 2)) >= 17;
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

// ---- Календар. Як «Додати в календар» у застосунку: кінець невідомий — година від початку; на сайті ще й нагадування за годину.

export const eventUrl = (card) => `https://poriad.app/e/${card.id}`;
const calendarEnd = (card) => card.ends_at ? new Date(card.ends_at) : new Date(Date.parse(card.starts_at) + 36e5);
const calendarTime = (date) => date.toISOString().replace(/[-:]|\.\d{3}/g, "");
/** Місце, адреса й місто — без частин, які вже є в іншій (адреса джерела часто сама містить заклад і місто). */
function calendarPlace(card) {
  const parts = [card.place_name, card.address, card.city].filter(Boolean);
  const inside = (v, w) => w.toLowerCase().includes(v.toLowerCase());
  return parts.filter((v, i) => !parts.some((w, j) => j !== i && inside(v, w) && (w.length > v.length || j < i))).join(", ");
}

/** Файл .ics (RFC 5545): рядки через CRLF, текст екрановано, рядки довші за 75 байтів згорнуто. */
export function icsFile(card, now = new Date()) {
  const text = (value) => value.replace(/[\\;,]/g, (c) => `\\${c}`).replace(/\r?\n/g, "\\n");
  const title = text(displayTitle(card.title));
  return ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Poriad//poriad.app//UK", "METHOD:PUBLISH", "BEGIN:VEVENT",
    `UID:${card.id}@poriad.app`, `DTSTAMP:${calendarTime(now)}`, `DTSTART:${calendarTime(new Date(card.starts_at))}`, `DTEND:${calendarTime(calendarEnd(card))}`,
    `SUMMARY:${title}`, `LOCATION:${text(calendarPlace(card))}`, `URL:${eventUrl(card)}`, `DESCRIPTION:${eventUrl(card)}`,
    "BEGIN:VALARM", "ACTION:DISPLAY", `DESCRIPTION:${title}`, "TRIGGER:-PT1H", "END:VALARM", "END:VEVENT", "END:VCALENDAR",
  ].map(foldLine).join("\r\n") + "\r\n";
}
function foldLine(line) {
  let out = "", bytes = 0;
  for (const ch of line) {
    const n = utf8.encode(ch).length;
    if (bytes + n > 75) { out += "\r\n "; bytes = 1; }
    out += ch;
    bytes += n;
  }
  return out;
}

export const googleCalendarUrl = (card) => `https://calendar.google.com/calendar/render?${new URLSearchParams({
  action: "TEMPLATE", text: displayTitle(card.title), dates: `${calendarTime(new Date(card.starts_at))}/${calendarTime(calendarEnd(card))}`,
  location: calendarPlace(card), details: eventUrl(card) })}`;

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

// ---- QR-код (ISO 18004): байтовий режим, рівень M, версії 1–6 (до 106 байтів; посиланню на подію вистачає 4-ї).
// Маску вибирає штраф, як у `npx qrcode`, тож poriad.app/app дає той самий знак, що друкувався раніше (site_test).

/** Рівень M: кодових слів даних і корекції на блок, блоків — для версій 1–6. */
const utf8 = new TextEncoder();
const QR_M = [[16, 10, 1], [28, 16, 1], [44, 26, 1], [32, 18, 2], [43, 24, 2], [27, 16, 4]];
const EXP = [], LOG = [];
for (let i = 0, x = 1; i < 255; i++) { EXP[i] = x; LOG[x] = i; x = (x << 1) ^ (x & 128 ? 0x11d : 0); }
const gmul = (a, b) => a && b ? EXP[(LOG[a] + LOG[b]) % 255] : 0;

function reedSolomon(data, n) {
  let gen = [1];
  for (let i = 0; i < n; i++) gen = [...gen, 0].map((c, j) => c ^ (j ? gmul(gen[j - 1], EXP[i]) : 0));
  const rem = new Array(n).fill(0);
  for (const b of data) {
    const f = b ^ rem.shift();
    rem.push(0);
    for (let i = 0; i < n; i++) rem[i] ^= gmul(gen[i + 1], f);
  }
  return rem;
}

const QR_MASKS = [(r, c) => (r + c) % 2, (r) => r % 2, (r, c) => c % 3, (r, c) => (r + c) % 3,
  (r, c) => (Math.floor(r / 2) + Math.floor(c / 3)) % 2, (r, c) => (r * c) % 2 + (r * c) % 3,
  (r, c) => ((r * c) % 2 + (r * c) % 3) % 2, (r, c) => ((r * c) % 3 + (r + c) % 2) % 2];

/** `{ size, path }` для `<path stroke>` — по смузі на ряд темних модулів; null, якщо текст задовгий. */
export function qrPath(text) {
  const bytes = [...utf8.encode(text)];
  const v = QR_M.findIndex(([d, , blocks]) => d * blocks - 2 >= bytes.length) + 1;
  if (!v) return null;
  const [d, ec, blocks] = QR_M[v - 1], size = 17 + 4 * v;

  const bits = [];
  const put = (value, n) => { for (let i = n - 1; i >= 0; i--) bits.push((value >>> i) & 1); };
  put(4, 4); put(bytes.length, 8); bytes.forEach((b) => put(b, 8));
  put(0, Math.min(4, d * blocks * 8 - bits.length));
  while (bits.length % 8) bits.push(0);
  const data = [];
  for (let i = 0; i < bits.length; i += 8) data.push(parseInt(bits.slice(i, i + 8).join(""), 2));
  for (let pad = 0xEC; data.length < d * blocks; pad ^= 0xEC ^ 0x11) data.push(pad);
  const chunks = Array.from({ length: blocks }, (_, i) => data.slice(i * d, (i + 1) * d));
  const ecc = chunks.map((chunk) => reedSolomon(chunk, ec));
  const words = [];
  for (let i = 0; i < d; i++) chunks.forEach((chunk) => words.push(chunk[i]));
  for (let i = 0; i < ec; i++) ecc.forEach((chunk) => words.push(chunk[i]));

  const m = Array.from({ length: size }, () => new Array(size).fill(0));
  const fixed = Array.from({ length: size }, () => new Array(size).fill(false));
  const set = (r, c, on) => { m[r][c] = on ? 1 : 0; fixed[r][c] = true; };
  for (const [r0, c0] of [[0, 0], [size - 7, 0], [0, size - 7]]) {
    for (let r = -1; r <= 7; r++) for (let c = -1; c <= 7; c++) {
      if (r0 + r < 0 || r0 + r >= size || c0 + c < 0 || c0 + c >= size) continue;
      const ring = Math.max(Math.abs(r - 3), Math.abs(c - 3));
      set(r0 + r, c0 + c, ring !== 2 && ring < 4);
    }
  }
  for (let i = 8; i < size - 8; i++) { set(i, 6, i % 2 === 0); set(6, i, i % 2 === 0); }
  if (v > 1) for (let r = -2; r <= 2; r++) for (let c = -2; c <= 2; c++) set(size - 7 + r, size - 7 + c, Math.max(Math.abs(r), Math.abs(c)) !== 1);
  const format = (mask) => {
    let rem = mask << 10;
    for (let i = 14; i >= 10; i--) if ((rem >> i) & 1) rem ^= 0x537 << (i - 10);
    const info = ((mask << 10) | rem) ^ 0x5412;
    for (let i = 0; i < 15; i++) {
      const on = (info >> i) & 1;
      set(i < 6 ? i : i < 8 ? i + 1 : size - 15 + i, 8, on);
      set(8, i < 8 ? size - i - 1 : i === 8 ? 7 : 14 - i, on);
    }
    set(size - 8, 8, 1);
  };
  format(0);
  let bit = 0;
  for (let col = size - 1, up = true; col > 0; col -= 2, up = !up) {
    if (col === 6) col--;
    for (let k = 0; k < size; k++) {
      const row = up ? size - 1 - k : k;
      for (const c of [col, col - 1]) {
        if (fixed[row][c]) continue;
        m[row][c] = bit < words.length * 8 ? (words[bit >> 3] >> (7 - (bit & 7))) & 1 : 0;
        bit++;
      }
    }
  }

  const apply = (p) => { for (let r = 0; r < size; r++) for (let c = 0; c < size; c++) if (!fixed[r][c] && !QR_MASKS[p](r, c)) m[r][c] ^= 1; };
  const penalty = () => {
    let score = 0, dark = 0;
    for (let a = 0; a < size; a++) {
      let runR = 0, runC = 0, lastR = -1, lastC = -1, seqR = 0, seqC = 0;
      for (let b = 0; b < size; b++) {
        const x = m[a][b], y = m[b][a];
        dark += x;
        if (x === lastR) runR++; else { if (runR >= 5) score += runR - 2; lastR = x; runR = 1; }
        if (y === lastC) runC++; else { if (runC >= 5) score += runC - 2; lastC = y; runC = 1; }
        seqR = ((seqR << 1) & 0x7FF) | x; seqC = ((seqC << 1) & 0x7FF) | y;
        if (b >= 10) score += 40 * ((seqR === 0x5D0 || seqR === 0x05D) + (seqC === 0x5D0 || seqC === 0x05D));
        if (a < size - 1 && b < size - 1) { const s = x + m[a][b + 1] + m[a + 1][b] + m[a + 1][b + 1]; if (s === 0 || s === 4) score += 3; }
      }
      if (runR >= 5) score += runR - 2;
      if (runC >= 5) score += runC - 2;
    }
    return score + 10 * Math.abs(Math.ceil(dark * 100 / (size * size) / 5) - 10);
  };
  let best = 0, lowest = Infinity;
  for (let p = 0; p < 8; p++) {
    format(p); apply(p);
    const score = penalty();
    apply(p);
    if (score < lowest) { lowest = score; best = p; }
  }
  format(best); apply(best);

  let path = "";
  m.forEach((row, r) => {
    for (let c = 0, x = -1; c < size;) {
      if (!row[c]) { c++; continue; }
      let e = c;
      while (e < size && row[e]) e++;
      path += x < 0 ? `M${c} ${r + 0.5}h${e - c}` : `m${c - x} 0h${e - c}`;
      x = c = e;
    }
  });
  return { size, path };
}

// ---- Стиль мапи. Порт `poruchMapStyle` (shared/MapStyle.kt) з токенами «Корінця»: удень тло — полотно, дороги — поверхня
// квитків; уночі — графітове полотно й тихі дороги, як у застосунку.

export function mapStyle(dark = false) {
  const c = dark
    ? { land: "#0F0F13", landTint: "#16161B", green: "#18211A", water: "#131C21", waterLine: "#1D272C", building: "#16161B",
      buildingLine: "#2E2D35", road: "#2A2930", minor: "#1C1B21", casing: "#16161B", rail: "#2E2D35", boundary: "#96959E",
      label: "#F3F3F0", muted: "#A6A5AD", faint: "#96959E", halo: "#0F0F13", waterLabel: "#6E8794" }
    : { land: "#F2F2F4", landTint: "#E8E8EC", green: "#E3EBDD", water: "#CBD9DE", waterLine: "#B5C7CE", building: "#E8E8EC",
      buildingLine: "#E0E0E5", road: "#FFFFFF", minor: "#FFFFFF", casing: "#E0E0E5", rail: "#DCD7C9", boundary: "#6A6A73",
      label: "#141417", muted: "#5E5E66", faint: "#6A6A73", halo: "#F2F2F4", waterLabel: "#6E858F" };
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
      { id: "road-minor", type: "line", ...src, "source-layer": "transportation", minzoom: 12, filter: ["all", LINE, cls("minor", "service", "track")], layout: round, paint: { "line-color": c.minor, "line-opacity": zoom([[12, 0], [13.5, 1]]), "line-width": zoom([[13, 1.4], [20, 18]], 1.55) } },
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
