// Кабінет організатора poriad.app/kabinet (docs/organizers-1.5.md, 1.2, 1.4, 1.5): створити й вести спільнотну подію з
// комп'ютера. Маршрути в #: «#/» — мої події, «#/new», «#/e/{id}» — дії й учасники, «#/e/{id}/edit», «#/account» — акаунт
// організатора. Вхід (Google або пошта з паролем, docs/web-auth.md) — auth.js, дані —
// ті самі функції бази, що в застосунку; сторінка перевіряє лише очевидне, решту каже сервер. Чисті правила вгорі (дати,
// тривалість, медіа, текст для Threads) перевіряє `node tools/kabinet_test.mjs`; DOM — нижче, лише в браузері.
import { SUPABASE, CATEGORIES, CITIES, cityOf, displayTitle, esc, overline, mapStyle, threadsPost, threadsIntent, httpsOrNull, priceText, plural, EVENTS, POST_MONTHS, payWay } from "./poriad.js?v=18";
import { threadFeed, openProof, forgetProofs, fit, jpeg, jpegFile, PHOTO, payStage } from "./chat.js?v=18";
import { session, verifyCode, google, completeRedirect, rpc, upload, signOut, inAppBrowser, browserLinks, signInWithPassword, signUp, resendSignup,
  requestRecovery, updatePassword, reauthenticate, verifyPassword, currentUser, updateMetadata, signInMethods, isEmail, MIN_PASSWORD, MAX_PASSWORD } from "./auth.js?v=18";

// ---- Дати. Усі п'ять міст в одному поясі; подія з іншим поясом (з застосунку) редагується у своєму.
export const TZ = "Europe/Kyiv";
const HOUR = 36e5;

const formats = new Map();
function parts(ms, tz) {
  if (!formats.has(tz)) formats.set(tz, new Intl.DateTimeFormat("en-CA", { timeZone: tz, hourCycle: "h23", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit" }));
  return Object.fromEntries(formats.get(tz).formatToParts(ms).map((p) => [p.type, p.value]));
}
/** Місцевий годинник мінус UTC у мить `ms`. */
function offset(ms, tz) {
  const p = parts(ms, tz);
  return Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second) - Math.floor(ms / 1000) * 1000;
}
/** Місцеві дата й година (`YYYY-MM-DD`, `HH:MM`) → ISO UTC. Двічі: зсув поясу в цю мить може відрізнятися (літній час). */
export function instant(date, time, tz = TZ) {
  const wall = Date.parse(`${date}T${time}:00Z`);
  if (!date || !time || Number.isNaN(wall)) return null;
  return new Date(wall - offset(wall - offset(wall, tz), tz)).toISOString();
}
/** ISO → місцеві `{date, time}`. */
export function local(iso, tz = TZ) {
  const p = parts(Date.parse(iso), tz);
  return { date: `${p.year}-${p.month}-${p.day}`, time: `${p.hour}:${p.minute}` };
}
const addDays = (date, days) => { const [y, m, d] = date.split("-").map(Number); return new Date(Date.UTC(y, m - 1, d + days)).toISOString().slice(0, 10); };

/**
 * «Повторити» (1.5): на тиждень пізніше, і ще на тиждень, поки початок не в майбутньому. Тиждень — місцевим календарем,
 * як `EventRepeat` у застосунку, тож перехід на зимовий час не зсуває годину.
 */
export function repeatTimes(startsAt, endsAt, tz = TZ, now = Date.now()) {
  let start = local(startsAt, tz), end = local(endsAt, tz);
  do {
    start = { ...start, date: addDays(start.date, 7) };
    end = { ...end, date: addDays(end.date, 7) };
  } while (Date.parse(instant(start.date, start.time, tz)) <= now);
  return { start, end };
}

/** Тривалість чипами, як у застосунку (`commonDurations`); решта — полем кінця. */
export const DURATIONS = [1, 2, 3];
/** Кінець через `minutes` від початку — місцеві дата й година, з переходом через північ. */
export function endAfter(date, time, minutes, tz = TZ) {
  const start = instant(date, time, tz);
  return start ? local(new Date(Date.parse(start) + minutes * 6e4).toISOString(), tz) : null;
}
/** «2 год», «1 год 30 хв», «45 хв» — як `durationLabel` у застосунку. */
export function durationLabel(minutes) {
  const hours = Math.floor(minutes / 60), rest = minutes % 60;
  return hours === 0 ? `${rest} хв` : rest === 0 ? `${hours} год` : `${hours} год ${rest} хв`;
}

// ---- Фото й відео (1.2): фото стискає браузер, відео — лише готовий mp4.
export const MEDIA = { max: 5, side: PHOTO.side, photoBytes: PHOTO.bytes, videoBytes: 50 * 1024 * 1024, videoSeconds: 30 };
/** Що не так із файлом ще до відкриття: null — можна. `count` — скільки вже вибрано. */
export function mediaProblem({ type = "", size = 0 }, count) {
  if (count >= MEDIA.max) return "Уже 5 файлів — більше не можна";
  if (type.startsWith("image/")) return null;
  if (!type.startsWith("video/")) return "Лише фото чи відео mp4";
  if (type !== "video/mp4") return "Відео — лише mp4";
  if (size > MEDIA.videoBytes) return "Відео до 30 секунд і 50 МБ.";
  return null;
}
/** Тривалість з `<video>`; невідома (NaN, Infinity) — теж задовга. Півсекунди запасу на округлення контейнера. */
export const videoTooLong = (seconds) => !(seconds <= MEDIA.videoSeconds + 0.5);
export { fit }; // chat.js: спільне з розмовою (скріншот оплати)

// ---- Ціна (1.7): лише ціна, гроші — з організатором напряму. Порожньо — безкоштовно.
export const PRICE_TEXT = "Ціна — від 1 до 100 000 ₴";
export function priceProblem(price) {
  const text = String(price ?? "").trim();
  if (!text) return null;
  const value = Number(text);
  return Number.isInteger(value) && value >= 1 && value <= 100000 ? null : PRICE_TEXT;
}
/** `p_price`: завжди явно — 0 прибирає ціну (null сервер читає як старий клієнт і ціну лишає). */
export const priceParam = (price) => String(price ?? "").trim() ? Math.round(Number(price)) : 0;

// ---- «Пост для Threads» (1.5) — у poriad.js: той самий текст ділить і сторінка події (1.6).
export { threadsPost, threadsIntent, ABOUT_MAX } from "./poriad.js?v=18";

// ---- Анімації публікації (1.6, design/lottie/LICENSES.md): корінець запечений кольором музики — фарбуємо в жанр.
const MUSIC_STUB = [0x60, 0x41, 0xb1].map((v) => v / 255);
/** Копія даних Lottie, де заливки й обведення кольору музики в шарі «Stub» — кольором `hex` (#rrggbb). */
export function recolorStub(data, hex) {
  if (!/^#[0-9a-f]{6}$/i.test(hex ?? "")) return data;
  const target = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255);
  const out = structuredClone(data);
  const walk = (node) => {
    if (Array.isArray(node)) return node.forEach(walk);
    if (!node || typeof node !== "object") return;
    if ((node.ty === "fl" || node.ty === "st") && node.c?.a === 0 && MUSIC_STUB.every((v, i) => Math.abs(node.c.k[i] - v) < 0.01)) {
      node.c.k = [...target, node.c.k[3] ?? 1];
    }
    Object.values(node).forEach(walk);
  };
  out.layers.filter((layer) => layer.nm === "Stub").forEach(walk);
  return out;
}

/**
 * Вставлений анонс без того, чого людина не бачить: керівних і форматних символів, ігнорованих (DI: нульова ширина,
 * теги U+E0000, селектори варіанта, порожні літери), приватних, непарних сурогатів і порожнього Брайля — крім переносу,
 * табуляції, ZWJ і FE0F. Те саме, що `clean` у supabase/functions/parse-announcement/announce.ts: функція чистить і
 * сама, а тут — щоб і запасний опис був чистий.
 */
export function cleanText(text) {
  return text.replace(/\r\n?/g, "\n").replace(/[\p{Cc}\p{Cf}\p{DI}\p{Co}\p{Cs}\u2800]/gu, (c) => ("\n\t\u200D\uFE0F".includes(c) ? c : ""));
}

/** Анонс не розібрали: перший непорожній рядок без емодзі й хештегів — назва (до 120). */
export function firstLine(text) {
  const line = text.split("\n").map((l) => l.replace(/\p{Extended_Pictographic}|️|‍|#[\p{L}\p{N}_]+/gu, "").replace(/\s+/g, " ").trim()).find(Boolean) ?? "";
  return line.slice(0, 120).trim();
}

/**
 * Що робить «Опублікувати». Нову подію створює create_event. Файли вантажимо, коли список медіа змінився (нові,
 * скопійовані, прибрані чи переставлені), і тоді p_media — новий список, навіть порожній; інакше p_media null, і сервер
 * медіа не чіпає. update_event — при редагуванні, коли є що вантажити, і на повторі після збою (`existed`: create_event
 * повертає вже створену подію, не оновлюючи полів, тож правки між спробами інакше загубились би).
 */
export function publishPlan({ editing = false, existed = false, items, original = "" }) {
  const upload = items.some((m) => m.blob || m.copied) || items.map((m) => m.url).join(" ") !== original;
  return { create: !editing, upload, update: editing || existed || upload };
}

const DRAFT = "poriad.kabinet.draft";
const FILES = "poriad.kabinet";
export function writeDraft(draft) { try { draft ? localStorage.setItem(DRAFT, JSON.stringify(draft)) : localStorage.removeItem(DRAFT); } catch { /* приватне вікно */ } }
/** Вихід з акаунта: на спільному комп'ютері наступний не має побачити чужої чернетки (з чатом після «Повторити») і файлів. */
export function forgetDraft() {
  writeDraft(null);
  try { indexedDB.deleteDatabase(FILES); } catch { /* приватне вікно */ }
}

/** Нумерований список для організатора («Скопіювати список»). */
export const rosterText = (people) => people.map((p, i) => `${i + 1}. ${p.display_name || "Учасник"}`).join("\n");

// ---- Помилки сервера тими самими текстами, що в застосунку (ApiErrors.kt + strings.xml).
const SESSION = "Увійдіть у свій профіль";
const LINK_EXPIRED = "Посилання застаріло або вже використане. Надішліть новий лист";
const ERRORS = {
  AUTH_REQUIRED: SESSION, session_expired: SESSION,
  ACCOUNT_RESTRICTED: "Обліковий запис обмежено. Напишіть у підтримку",
  TOO_MANY_EVENTS: "Забагато подій за добу. Спробуйте завтра",
  OBJECTIONABLE_CONTENT: "Текст містить слова, які ми не публікуємо. Перепишіть, будь ласка.",
  INVALID_IMAGE_URL: "Не вдалося завантажити зображення",
  INVALID_TITLE: "Назва — щонайменше 3 символи",
  INVALID_DESCRIPTION: "Опис — щонайменше 10 символів",
  INVALID_AGE_LIMIT: "Вік — від 18; «до» не менше за «від» і не більше 120",
  INVALID_CONTACT_URL: "Посилання на чат — лише https://, без пробілів",
  INVALID_PRICE: PRICE_TEXT,
  START_MUST_BE_FUTURE: "Початок — дата й час у майбутньому",
  CAPACITY_BELOW_ATTENDANCE: "Не можна зменшити кількість місць нижче за тих, хто вже йде",
  EVENT_CANCELLED: "Подію скасовано",
  EVENT_NOT_FOUND: "Подія недоступна",
  NOT_ORGANIZER: "Ця дія доступна лише організатору",
  EVENT_FULL: "Вільних місць уже немає",
  TOO_MANY_MOVES: "Забагато спроб. Спробуйте трохи пізніше",
  otp_expired: "Код не підійшов або застарів. Надішліть новий",
  over_email_send_rate_limit: "Забагато листів за годину. Спробуйте трохи пізніше",
  over_request_rate_limit: "Забагато спроб. Спробуйте трохи пізніше",
  email_address_invalid: "Вкажіть коректний email",
  validation_failed: "Вкажіть коректний email",
  // Пошта з паролем (Supabase Auth, `error_code`).
  invalid_credentials: "Неправильна пошта або пароль. Пароля ще нема? Натисніть «Забули пароль?»",
  user_already_exists: "Акаунт з цією поштою вже є. Увійдіть з паролем чи через Google",
  signup_disabled: "Реєстрація зараз недоступна. Напишіть нам: hello@poriad.app",
  user_banned: "Обліковий запис обмежено. Напишіть у підтримку",
  same_password: "Новий пароль збігається з поточним",
  current_password_mismatch: "Поточний пароль не підходить",
  current_password_required: "Введіть поточний пароль",
  reauthentication_not_valid: "Код не підійшов або застарів. Надішліть новий",
  pkce_missing: "Вхід почався в іншій вкладці чи браузері. Відкрийте посилання там, де його просили, або почніть ще раз тут",
  flow_state_expired: LINK_EXPIRED,
  flow_state_not_found: LINK_EXPIRED,
  // Оплата онлайн і розмови (docs/organizer-events.md).
  PAYMENT_DETAILS: "Реквізити (картка, IBAN, банка) не пишуть у назві, описі, адресі чи посиланні на чат. Для оплати онлайн їх надсилають у розмові з тими, хто записався",
  TOO_MANY_MESSAGES: "Забагато повідомлень. Зачекайте хвилину",
  CHAT_CLOSED: "Розмову закрито: подія давно минула",
  INVALID_MESSAGE: "Повідомлення — до 2000 символів",
  NOT_MEMBER: "Написати можна лише тим, хто записався, подав заявку чи вже писав вам",
  // Сторінку відкрили, поки оплату онлайн ще не вимкнули (20261125160000_pay_online_switch).
  PAY_ONLINE_OFF: "Оплату онлайн тимчасово вимкнено. Оновіть сторінку — подія буде з оплатою на місці",
};
/** Реквізити в розмові події «на місці»: інший текст, ніж для опису. */
export const TALK_PAYMENT_DETAILS = "Реквізити в розмові — лише для подій з оплатою онлайн. Увімкніть її в редагуванні: «Як платять» → «Онлайн».";
/** Те саме, коли оплату онлайн вимкнено вимикачем: увімкнути її в редагуванні зараз не можна. */
export const TALK_PAY_OFF = "Оплату онлайн тимчасово вимкнено: реквізити в розмові не надсилаються, учасники платять на місці.";
export function errorText(error) {
  if (error?.code === "weak_password") return weakPasswordText(error.reasons);
  if (ERRORS[error?.code]) return ERRORS[error.code];
  const status = error?.status;
  if (!status) return "Немає звʼязку. Перевірте інтернет і спробуйте ще раз";
  if (status === 401) return SESSION;
  if (status === 403) return ERRORS.NOT_ORGANIZER;
  if (status === 429) return ERRORS.TOO_MANY_MOVES;
  return status < 500 ? "Не вдалося виконати дію. Перевірте дані та час події" : "Сервіс тимчасово недоступний. Спробуйте ще раз";
}

/** Слабкий пароль словами (`weak_password` з `reasons`): витік — окремо, бо довжина там може бути й достатня. */
export function weakPasswordText(reasons) {
  if (reasons?.includes("pwned")) return "Цей пароль є серед зламаних у відомих витоках. Оберіть інший";
  if (reasons?.includes("characters")) return "Пароль надто простий: додайте великі й малі літери, цифри чи символи";
  return `Пароль — щонайменше ${MIN_PASSWORD} символів`;
}
/** Відмова з повернення від Google чи з листа: протухле посилання каже `otp_expired` так само, як хибний код. */
export function redirectErrorText(error) {
  return ["otp_expired", "flow_state_expired", "flow_state_not_found"].includes(error?.code) ? LINK_EXPIRED : errorText(error);
}

// ---- Пароль і акаунт: правила без DOM.

/** Імʼя акаунта (як `handle_new_user` і застосунок): 2–60 символів. Текст помилки або "". */
export const nameProblem = (name) => (name.length < 2 || name.length > 60 ? "Вкажіть імʼя від 2 до 60 символів" : "");
/** Посилання на чат: лише https://, без пробілів (`INVALID_CONTACT_URL`). */
export const contactOk = (url) => Boolean(httpsOrNull(url)) && !/\s/.test(url);

/** Новий пароль і повтор → текст помилки або "" (межі — як `AccountRules` у застосунку). */
export function passwordProblem(password, repeat = password) {
  if (!password || password.length < MIN_PASSWORD) return `Пароль — щонайменше ${MIN_PASSWORD} символів`;
  if (password.length > MAX_PASSWORD) return `Пароль — до ${MAX_PASSWORD} символів`;
  if (password !== repeat) return "Паролі не збігаються";
  return "";
}
/**
 * Як змінювати пароль у цій сесії (`amr`): `recovery` — відкрили посилання з листа, поточний не потрібен; `change` —
 * увійшли паролем, поточний обовʼязковий (його й перевіряємо, як застосунок); `set` — Google чи код з пошти: пароля може
 * й не бути, тож поточний — лише якщо він є.
 */
export const passwordMode = (methods) => (methods.includes("recovery") ? "recovery" : methods.includes("password") ? "change" : "set");

/** Способи входу акаунта словами — з `identities` і `app_metadata.providers` Auth. */
export function providersText(user) {
  const names = { email: "пошта", google: "Google", apple: "Apple" };
  const found = new Set([...(user?.identities ?? []).map((i) => i?.provider), ...(user?.app_metadata?.providers ?? [])].filter(Boolean));
  const order = Object.keys(names);
  return [...found].sort((a, b) => (order.indexOf(a) + 1 || 99) - (order.indexOf(b) + 1 || 99)).map((p) => names[p] ?? p).join(" · ") || "—";
}

/**
 * Налаштування нових подій організатора: `user_metadata.kabinet` акаунта (Auth), тож вони ті самі на будь-якому
 * компʼютері. Чужі чи биті значення (метадані пише сам клієнт) відкидаємо.
 */
export function editorDefaults(meta) {
  const d = meta?.kabinet;
  if (!d || typeof d !== "object") return {};
  const out = {};
  if (CITIES.some((c) => c.name === d.city)) out.city = d.city;
  if (typeof d.contact === "string" && d.contact.length <= 500 && contactOk(d.contact)) out.contact = d.contact;
  if (typeof d.approval === "boolean") out.approval = d.approval;
  return out;
}

/**
 * Слова про учасників за способом оплати — однаково в таблиці й у розмові: з оплатою онлайн заявка — «Чекає оплати», а
 * схвалити — «Оплату отримано».
 */
export const payWords = (online) => (online
  ? { waiting: "Чекає оплати", approve: "Оплату отримано", approved: "Оплачено", done: "Оплату підтверджено" }
  : { waiting: "Заявка", approve: "Схвалити", approved: "У списку", done: "Схвалено" });

/** Питання перед «Відхилити» — однаково з таблиці й з розмови: людина отримає сповіщення, а гроші повертає організатор. */
export const declineQuestion = (name, online) => `Відхилити заявку? ${name || DEFAULT_NAME} отримає сповіщення, що заявку відхилено.`
  + (online ? " Якщо оплата вже прийшла, поверніть гроші: «Поряд» цього не робить." : "");

/**
 * Хто в розмові з організатором (кабінет): стан людини на цій події з ростера й заявок; без запису — лише питає. `stage` —
 * де заявка з оплатою онлайн за розмовою (chat.js, payStage): надіслала скріншот — «Скріншот надіслано».
 */
export function talkStatus(user, { roster = [], requests = [], payOnline = false, stage = "details" } = {}) {
  const words = payWords(payOnline);
  const approved = roster.find((p) => p.user_id === user), request = requests.find((p) => p.user_id === user);
  if (approved) return { stamp: words.approved, tone: "success", at: approved.joined_at, via: approved.via, pending: false };
  if (request) return { stamp: payOnline && stage === "proof" ? "Скріншот надіслано" : words.waiting, tone: "accent", at: request.joined_at, via: request.via, pending: true };
  return { stamp: "Питає", tone: "", at: null, via: null, pending: false };
}
/** Рядки картки учасника в розмові: профіль (`profile_card`) і стан запису. Пошти не показуємо — її нема й у картці. */
export function talkFacts(card, status, tz = TZ) {
  const attended = Number(card?.attended) || 0, organized = Number(card?.organized) || 0;
  const profile = [sinceText(card?.member_since, tz), attended ? `відвідано подій: ${attended}` : "", organized ? `організовано: ${organized}` : ""]
    .filter(Boolean).join(" · ");
  const when = status.at ? new Intl.DateTimeFormat("uk-UA", { timeZone: tz, day: "numeric", month: "long", hour: "2-digit", minute: "2-digit" }).format(new Date(status.at)) : "";
  const joined = status.at ? `${status.pending ? "Заявка" : "Записались"} ${when} · ${status.via === "web" ? "з вебу" : "із застосунку"}`
    : "Ще не записались на подію";
  return { profile, joined };
}

/** «з нами з жовтня 2026», як шапка профілю в застосунку. */
export function sinceText(iso, tz = TZ) {
  const ms = Date.parse(iso ?? "");
  if (Number.isNaN(ms)) return "";
  const { year, month } = parts(ms, tz);
  return `з нами з ${POST_MONTHS[Number(month) - 1]} ${year}`;
}

// ================= Сторінка =================

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const DEFAULT_NAME = "Учасник"; // так `handle_new_user` називає акаунт без імені: людина ще не назвалась
const $ = (selector, root = document) => root.querySelector(selector);
const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
let ui; // site/js/ui.js: квитки, значки й тост. Динамічно — тест імпортує цей файл без DOM.

let me = null; // рядок Auth: id, email, identities, user_metadata
let ready = null; // id, для якого імʼя й вік уже є
let card = null; // свій profile_card: імʼя, фото, «про вас», з якого часу, скільки подій
const busy = new Set();

/** Помилка, яку показуємо як є (перевірка поля), а не словами `errorText`. */
class Problem extends Error {}
/**
 * Дія форми чи кнопки: одна за раз (кнопка вимкнена, поки триває), помилка й підказка — у своїх рядках. `fn` кидає
 * помилку чи `Problem` і може повернути текст підказки.
 */
async function act(button, { error, note = null }, fn) {
  if (button.disabled) return;
  error.textContent = "";
  if (note) note.textContent = "";
  button.disabled = true;
  try {
    const text = await fn();
    if (note && text) note.textContent = text;
  } catch (e) {
    error.textContent = e instanceof Problem ? e.message : errorText(e);
  } finally {
    button.disabled = false;
  }
}

async function signedIn() {
  me = (await session().catch(() => null))?.user ?? null;
  if (!me) card = null;
  paintNav();
  if (me && card?.user_id !== me.id) loadCard().catch(() => {});
  return Boolean(me);
}

let cardLoad = null; // { id, promise } — profile_card у дорозі: вхід і сторінка акаунта питають його разом
/** Свій profile_card; `force` — перечитати (після входу з іншого акаунта чи на сторінці акаунта). */
function loadCard(force = false) {
  if (!force && card?.user_id === me.id) return Promise.resolve(card);
  const id = me.id;
  if (cardLoad?.id !== id) {
    const promise = rpc("profile_card", { p_user_id: id }).then((rows) => {
      if (me?.id !== id) return card; // поки чекали, людина вийшла чи ввійшла іншим акаунтом
      card = rows?.[0] ?? null;
      paintNav();
      return card;
    }).finally(() => { if (cardLoad?.promise === promise) cardLoad = null; });
    cardLoad = { id, promise };
  }
  return cardLoad.promise;
}
/** Імʼя з картки; «Учасник» — ще не назвався. */
const nameOf = (c) => (c?.display_name && c.display_name !== DEFAULT_NAME ? c.display_name : "");
const cardName = () => nameOf(card);
/** Аватар: фото або перша літера, як `Avatar` у застосунку. */
const avatarHtml = (name, url) => (url ? `<img src="${esc(url)}" alt="">` : esc([...(name || "?").trim()][0]?.toUpperCase() ?? "?"));
/** «Акаунт» у шапці — лише з входом, з фото чи літерою. */
function paintNav() {
  $("[data-account-link]").hidden = !me;
  if (me) $("[data-nav-avatar]").innerHTML = avatarHtml(cardName() || me.email, card?.user_id === me.id ? card.avatar_url : null);
}

/**
 * Запит до Supabase з токеном, коли його не дає auth.js: профіль, копія й видалення файлів, анонс. Тип — лише з тілом:
 * Storage відкидає DELETE з `application/json` без тіла.
 */
async function authed(path, init = {}) {
  const current = await session().catch(() => null);
  const response = await fetch(`${SUPABASE.url}${path}`, { ...init, headers: {
    apikey: SUPABASE.key, ...(init.body ? { "content-type": "application/json" } : {}), ...(current ? { authorization: `Bearer ${current.access_token}` } : {}),
  } });
  if (!response.ok) {
    const body = await response.json().catch(() => ({}));
    throw Object.assign(new Error(body.message || body.error || `HTTP ${response.status}`), { status: response.status, code: body.message || body.error || null });
  }
  return response;
}

// ---- Вхід організатора: Google (крім вбудованих браузерів) або пошта з паролем, як у застосунку. «Створити акаунт» —
// код з листа «Confirm signup» (чи посилання з нього), «Забули пароль?» — посилання з листа, по якому кабінет просить
// новий пароль. Вперше — імʼя. 18+ — рядком згоди, `confirm_adult` мовчки. Гості й учасники на /e/{id} входять Google
// або кодом з пошти (join.js) — та сама сесія.

const RESEND_AFTER = 60_000;
const returnTo = () => `${location.origin}/kabinet`;
const auth = { dialog: null, done: null, email: "", intent: null, flow: null, sentAt: 0 };

function step(name, note = "") {
  for (const el of $$("[data-step]", auth.dialog)) el.hidden = el.dataset.step !== name;
  for (const el of $$("[data-email]", auth.dialog)) el.textContent = auth.email;
  $("[data-auth-error]", auth.dialog).textContent = "";
  $("[data-auth-note]", auth.dialog).textContent = note;
  for (const button of $$("[data-resend]", auth.dialog)) cooldown(button);
  const inputs = $$(`[data-step="${name}"] input:not([type=hidden]):not([hidden])`, auth.dialog);
  (inputs.find((el) => !el.value) ?? inputs[0])?.focus();
}
/** «Надіслати ще раз» — не частіше, ніж раз на хвилину: ліміт листів Supabase на годину спільний для всіх. */
function cooldown(button) {
  const wait = auth.sentAt + RESEND_AFTER - Date.now();
  button.disabled = wait > 0;
  clearTimeout(button.timer);
  if (wait > 0) button.timer = setTimeout(() => { button.disabled = false; }, wait);
}

/**
 * Вікно входу; true — людина ввійшла й має імʼя. `at` — з якого кроку (`profile` — одразу імʼя, `password` — після
 * листа відновлення).
 */
function signIn({ lead = null, intent = null, at = "start" } = {}) {
  auth.intent = intent;
  $("[data-auth-lead]", auth.dialog).textContent = lead ?? "Тією самою поштою чи Google, що й у застосунку, — і ви побачите свої події.";
  step(at);
  if (!auth.dialog.open) auth.dialog.showModal();
  return new Promise((resolve) => { auth.done = resolve; });
}
function finishAuth(ok) {
  const done = auth.done;
  auth.done = null;
  if (auth.dialog.open) auth.dialog.close();
  done?.(ok);
}
/** Куди повернути людину з Google чи з листа: маршрут і «опублікувати», з якими вона пішла. */
const comeback = () => ({ hash: location.hash, ...auth.intent });

/** Чи має акаунт імʼя (вік перевіряє створення події: `AGE_REQUIRED`). */
async function profileReady() {
  if (ready === me.id) return true;
  await loadCard(true);
  $("[name=name]", auth.dialog).value = cardName();
  if (cardName()) ready = me.id;
  return ready === me.id;
}
/** Після будь-якого входу: імʼя вже є — готово, ні — крок імені. */
async function entered() {
  await signedIn();
  if (await profileReady()) finishAuth(true); else step("profile");
}

/** Вхід перед дією: true — можна. */
async function account(options = {}) {
  if (await signedIn() && await profileReady()) return true;
  return signIn({ ...options, at: me ? "profile" : "start" });
}

/** Один перемикач «Показати» на всі поля пароля кроку чи форми: пароль і повтор видно разом. */
function setupReveal(root) {
  root.addEventListener("click", (event) => {
    const button = event.target.closest("[data-reveal]");
    if (!button) return;
    const scope = button.closest("[data-step]") ?? button.closest("form");
    const show = button.getAttribute("aria-pressed") !== "true";
    for (const input of $$(".kab-secret input", scope)) input.type = show ? "text" : "password";
    for (const other of $$("[data-reveal]", scope)) {
      other.setAttribute("aria-pressed", String(show));
      other.textContent = show ? "Сховати" : "Показати";
    }
  });
}
/** Стерти й сховати паролі: після входу, збереження чи закриття вікна вони не лишаються на сторінці. */
function clearSecrets(root) {
  for (const input of $$(".kab-secret input", root)) Object.assign(input, { type: "password", value: "" });
  for (const button of $$("[data-reveal]", root)) { button.setAttribute("aria-pressed", "false"); button.textContent = "Показати"; }
}

function setupAuth() {
  auth.dialog = $("[data-auth]");
  const form = $("[data-auth-form]");
  const error = (e) => { $("[data-auth-error]").textContent = typeof e === "string" ? e : errorText(e); };
  const note = (text) => { $("[data-auth-note]").textContent = text; };
  // Вбудований браузер Threads чи Instagram: Google туди вхід не пускає — кличемо в Safari чи Chrome. Пароль працює.
  if (inAppBrowser()) {
    const links = browserLinks();
    $("[data-google]").hidden = true;
    $("[data-in-app]").hidden = false;
    $("[data-browser]").href = /Android/i.test(navigator.userAgent) ? links.android : links.ios;
  }
  setupReveal(form);
  $("[data-auth-close]").addEventListener("click", () => finishAuth(false));
  auth.dialog.addEventListener("cancel", () => finishAuth(false));
  auth.dialog.addEventListener("close", () => clearSecrets(form));
  $("[data-google]").addEventListener("click", () => google(returnTo(), comeback()));
  form.addEventListener("click", (event) => {
    const link = event.target.closest("[data-goto]");
    if (!link) return;
    const to = link.dataset.goto;
    // Пошту, яку вже ввели, несемо в наступний крок: друкувати двічі не треба.
    const email = (current() === "signup" ? form.signupEmail : current() === "forgot" ? form.forgotEmail : form.email).value.trim() || auth.email;
    form.email.value = form.email.value || email;
    if (to === "signup") form.signupEmail.value = form.signupEmail.value || email;
    if (to === "forgot") form.forgotEmail.value = email;
    step(to);
  });
  $$("[data-resend]", form).forEach((button) => button.addEventListener("click", async () => {
    button.disabled = true;
    try {
      if (auth.flow === "recovery") await requestRecovery(auth.email, returnTo(), comeback());
      else await resendSignup(auth.email, returnTo(), comeback());
      auth.sentAt = Date.now();
      note("Надіслали ще раз.");
    } catch (e) {
      error(e);
    }
    cooldown(button);
  }));
  const current = () => $$("[data-step]", form).find((el) => !el.hidden).dataset.step;
  /** Лист підтвердження чи відновлення пішов: крок з поштою й таймером «Надіслати ще раз». */
  const sent = (flow, email, at, text = "") => {
    auth.flow = flow;
    auth.email = email;
    auth.sentAt = Date.now();
    form.code.value = "";
    step(at, text);
  };

  const email = (input) => {
    const value = input.value.trim();
    if (!isEmail(value)) throw new Problem("Вкажіть коректний email");
    return value;
  };
  const named = (input) => {
    const name = input.value.trim(), problem = nameProblem(name);
    if (problem) throw new Problem(problem);
    return name;
  };
  /** Що робить «Далі» на кожному кроці вікна. */
  const steps = {
    async start() {
      const address = email(form.email);
      if (!form.password.value) throw new Problem("Введіть пароль");
      try {
        await signInWithPassword(address, form.password.value);
      } catch (e) {
        if (e.code !== "email_not_confirmed") throw e;
        // Зареєструвались, а пошту не підтвердили: шлемо код ще раз і просимо його тут же.
        await resendSignup(address, returnTo(), comeback());
        return sent("signup", address, "confirm", "Пошту ще не підтверджено — надіслали код ще раз.");
      }
      auth.email = address;
      await entered();
    },
    async signup() {
      const name = named(form.signupName), address = email(form.signupEmail), password = form.signupPassword.value;
      const weak = passwordProblem(password);
      if (weak) throw new Problem(weak);
      const result = await signUp(address, password, name, returnTo(), comeback());
      if (result.exists) {
        form.email.value = address;
        form.password.value = "";
        step("start");
        throw new Problem("Акаунт з цією поштою вже є. Увійдіть з паролем чи через Google, або натисніть «Забули пароль?».");
      }
      if (result.session) await entered(); else sent("signup", address, "confirm");
    },
    async confirm() {
      const code = form.code.value.replace(/\s/g, "");
      if (!code) throw new Problem("Введіть код з листа");
      await verifyCode(auth.email, code);
      await entered();
    },
    async forgot() {
      const address = email(form.forgotEmail);
      await requestRecovery(address, returnTo(), comeback());
      sent("recovery", address, "sent");
    },
    async password() {
      const problem = passwordProblem(form.newPassword.value, form.repeatPassword.value);
      if (problem) throw new Problem(problem);
      await updatePassword(form.newPassword.value);
      ui.toast("Пароль збережено");
      await entered();
    },
    async profile() {
      const name = named(form.name);
      await authed(`/rest/v1/profiles?id=eq.${me.id}`, { method: "PATCH", body: JSON.stringify({ display_name: name }) });
      await rpc("confirm_adult");
      ready = me.id;
      if (card) card = { ...card, display_name: name };
      paintNav();
      finishAuth(true);
    },
  };
  form.addEventListener("submit", (event) => {
    event.preventDefault();
    const at = current(), button = $(`[data-step="${at}"] [type=submit]`, form);
    if (button && steps[at]) act(button, { error: $("[data-auth-error]") }, steps[at]);
  });
}

/** Вихід: на спільному компʼютері наступний не має побачити чужої чернетки, файлів і акаунта. */
async function leave({ everywhere = false } = {}) {
  forgetDraft();
  forgetProofs();
  talkFeed?.clear();
  media = [];
  await signOut({ everywhere });
  me = null;
  ready = null;
  card = null;
  if (location.hash === "#/" || !location.hash) route(); else location.hash = "#/";
}

// ---- Маршрути

function view(name) {
  for (const el of $$("[data-view]")) el.hidden = el.dataset.view !== name;
  const link = $("[data-account-link]");
  if (name === "account") link.setAttribute("aria-current", "page"); else link.removeAttribute("aria-current");
  scrollTo(0, 0);
}

async function route() {
  const [, page, id, sub] = location.hash.split("/");
  try {
    if (page === "new") return await showEditor(null);
    if (page === "account") return await showAccount();
    if (page === "e" && UUID.test(id ?? "")) return await (sub === "edit" ? showEditor(id) : sub === "done" ? showDone(id) : showEvent(id));
    return await showList();
  } catch (e) {
    console.warn("kabinet", e);
    ui.toast(errorText(e));
  }
}

/** Подія організатора або null (чужа, прихована, мережа). */
async function ownEvent(id) {
  const [event] = await rpc("event_details", { p_event_id: id }) ?? [];
  return event && event.organizer_id === me?.id && event.origin === "community" ? event : null;
}

// ---- Акаунт організатора: профіль, який бачать учасники, налаштування нових подій, пароль і вхід.

let photo = { blob: null, url: null, removed: false, preview: null }; // нове фото чекає «Зберегти профіль», як у застосунку
let passwordAt = "set"; // passwordMode цієї сесії; після першого пароля — change

async function showAccount() {
  view("account");
  const settings = $("[data-settings]"), note = $("[data-account-note]");
  settings.hidden = true;
  if (!(await signedIn()) && !(await signIn({ lead: "Увійдіть, щоб відкрити налаштування акаунта." }))) return void (location.hash = "#/");
  note.textContent = "Завантажуємо…";
  const [user, current] = await Promise.all([currentUser().catch(() => me), session(), loadCard(true)]);
  me = user ?? me;
  note.textContent = "";
  settings.hidden = false;
  paintAccount();
  passwordView(passwordMode(signInMethods(current)), signInMethods(current));
}

function paintAccount() {
  const name = cardName();
  $("[data-me-avatar]").innerHTML = avatarHtml(name || me.email, card?.avatar_url);
  const organized = Number(card?.organized) || 0;
  $("[data-me-line]").textContent = [name, me.email, sinceText(card?.member_since), organized ? plural(organized, EVENTS) : ""]
    .filter(Boolean).join(" · ");
  const f = $("[data-profile-form]");
  f.name.value = name;
  f.bio.value = card?.bio ?? "";
  bioCount();
  setPhoto({ blob: null, url: null, removed: false, preview: null });
  for (const el of $$("[data-profile-error], [data-profile-note], [data-defaults-error], [data-defaults-note]")) el.textContent = "";

  const d = editorDefaults(me.user_metadata), df = $("[data-defaults-form]");
  df.city.value = d.city ?? (CITIES.some((c) => c.name === ui.savedCity.get()) ? ui.savedCity.get() : CITIES[0].name);
  df.contact.value = d.contact ?? "";
  df.approval.checked = Boolean(d.approval);

  $("[data-me-email]").textContent = me.email ?? "—";
  $("[data-me-methods]").textContent = providersText(me);
}

function bioCount() {
  const length = $("[data-profile-form]").bio.value.trim().length;
  $("[data-bio-count]").textContent = length ? `${length} з 300` : "До 300 символів. Учасники бачать це у вашій картці.";
}
function setPhoto(next) {
  if (photo.preview && photo.preview !== next.preview) URL.revokeObjectURL(photo.preview);
  photo = next;
  const shown = photo.preview ?? (photo.removed ? null : card?.avatar_url ?? null);
  $("[data-photo-preview]").innerHTML = avatarHtml($("[data-profile-form]").name.value || cardName() || me?.email, shown);
  $("[data-photo-remove]").hidden = !shown;
  $("[data-photo-pick]").textContent = shown ? "Змінити фото" : "Завантажити фото";
}
/** Фото профілю: JPEG без метаданих, довша сторона до 512 — як аватар у застосунку. */
const avatarJpeg = (file) => jpegFile(file, { side: 512, bytes: Infinity, qualities: [0.86] });

/** Форма пароля під спосіб входу цієї сесії. `methods` — `amr`: чим саме ввійшли, щоб сказати це словами. */
function passwordView(mode, methods = [], text = "") {
  passwordAt = mode;
  const f = $("[data-password-form]");
  f.username.value = me?.email ?? "";
  $("[data-password-title]").textContent = mode === "change" ? "Змінити пароль" : mode === "recovery" ? "Новий пароль" : "Пароль";
  const via = methods.includes("oauth") ? "через Google" : "кодом з пошти";
  $("[data-password-lead]").textContent = text || (mode === "recovery" ? "Ви відкрили посилання з листа — задайте новий пароль, поточний не потрібен."
    : mode === "set" ? `Ви ввійшли ${via}. Задайте пароль, щоб входити й поштою з паролем — у кабінет і в застосунок. Пароль уже є — введіть і поточний.`
    : "");
  $("[data-current-field]").hidden = mode === "recovery";
  $("[data-current-label]").textContent = mode === "set" ? "Поточний пароль, якщо він уже є" : "Поточний пароль";
  $("[data-password-forgot]").hidden = mode === "recovery";
  $("[data-password-submit]").textContent = mode === "change" ? "Змінити пароль" : "Зберегти пароль";
}

function setupAccount() {
  const profileForm = $("[data-profile-form]"), passwordForm = $("[data-password-form]"), defaultsForm = $("[data-defaults-form]");
  setupReveal(passwordForm);
  $("[data-defaults-city]").innerHTML = CITIES.map((c) => `<option>${esc(c.name)}</option>`).join("");

  // ---- Профіль
  profileForm.bio.addEventListener("input", bioCount);
  profileForm.name.addEventListener("input", () => { if (!photo.preview && !(card?.avatar_url && !photo.removed)) setPhoto(photo); });
  $("[data-photo-pick]").addEventListener("click", () => $("[data-photo-file]").click());
  $("[data-photo-file]").addEventListener("change", async (event) => {
    const file = event.target.files?.[0];
    event.target.value = "";
    const error = $("[data-profile-error]"), note = $("[data-profile-note]");
    error.textContent = note.textContent = "";
    if (!file) return;
    if (!file.type.startsWith("image/")) return void (error.textContent = "Оберіть фото");
    try {
      const blob = await avatarJpeg(file);
      setPhoto({ blob, url: null, removed: false, preview: URL.createObjectURL(blob) });
      note.textContent = "Фото збережеться разом із профілем";
    } catch (e) {
      error.textContent = e.message || "Не вдалося додати це фото";
    }
  });
  $("[data-photo-remove]").addEventListener("click", () => setPhoto({ blob: null, url: null, removed: true, preview: null }));
  const profileOut = { error: $("[data-profile-error]"), note: $("[data-profile-note]") };
  profileForm.addEventListener("submit", (event) => {
    event.preventDefault();
    act($("[type=submit]", profileForm), profileOut, async () => {
      const name = profileForm.name.value.trim(), bio = profileForm.bio.value.trim();
      const problem = nameProblem(name) || (bio.length > 300 ? "Про вас — до 300 символів" : "");
      if (problem) throw new Problem(problem);
      const before = card?.avatar_url ?? null;
      let avatar = photo.removed ? null : before;
      // Уже вивантажене фото повтор (після відмови стоп-словника, скажімо) не вантажить удруге.
      if (photo.blob) avatar = photo.url ??= await upload("event-images", `${me.id}/avatar/${crypto.randomUUID()}.jpg`, photo.blob);
      await authed(`/rest/v1/profiles?id=eq.${me.id}`, { method: "PATCH", body: JSON.stringify({ display_name: name, bio: bio || null, avatar_url: avatar }) });
      // Старе фото — геть зі сховища, як у застосунку; збій не важить: профіль уже збережено.
      if (before && before !== avatar && before.includes(`/event-images/${me.id}/avatar/`)) removeFiles([{ url: before }], []);
      card = { ...(card ?? { user_id: me.id }), display_name: name, bio: bio || null, avatar_url: avatar };
      ready = me.id;
      paintAccount();
      paintNav();
      return "Профіль збережено";
    });
  });

  // ---- Нові події
  const defaultsOut = { error: $("[data-defaults-error]"), note: $("[data-defaults-note]") };
  defaultsForm.addEventListener("submit", (event) => {
    event.preventDefault();
    act($("[type=submit]", defaultsForm), defaultsOut, async () => {
      const contact = defaultsForm.contact.value.trim();
      if (contact && !contactOk(contact)) throw new Problem(ERRORS.INVALID_CONTACT_URL);
      me = await updateMetadata({ kabinet: { city: defaultsForm.city.value, contact: contact || null, approval: defaultsForm.approval.checked } });
      return "Збережено. Так заповнимо наступну нову подію.";
    });
  });

  // ---- Пароль
  const passwordOut = { error: $("[data-password-error]"), note: $("[data-password-note]") };
  passwordForm.addEventListener("submit", (event) => {
    event.preventDefault();
    const f = passwordForm, button = $("[data-password-submit]");
    act(button, passwordOut, async () => {
      const problem = passwordProblem(f.password.value, f.repeat.value);
      if (problem) throw new Problem(problem);
      const current = passwordAt === "recovery" ? "" : f.current.value;
      if (passwordAt === "change" && !current) throw new Problem(ERRORS.current_password_required);
      // Поточний пароль перевіряємо самі, як застосунок, і шлемо серверу: з «Require current password» він звірить ще раз.
      if (current) {
        await verifyPassword(me.email, current).catch((e) => { throw e.code === "invalid_credentials" ? Object.assign(e, { code: "current_password_mismatch" }) : e; });
      }
      try {
        await updatePassword(f.password.value, { current: current || null, nonce: f.nonce.value.replace(/\s/g, "") || null });
      } catch (e) {
        if (e.code === "reauthentication_needed") {
          // «Secure password change»: вхід старший за добу — сервер просить код з листа.
          await reauthenticate();
          $("[data-nonce-field]").hidden = false;
          f.nonce.value = "";
          f.nonce.focus();
          return `Для безпеки надіслали код на ${me.email}. Введіть його й натисніть «${button.textContent}» ще раз.`;
        }
        if (e.code === "current_password_required" && passwordAt !== "change") {
          passwordView("change", [], "У акаунта вже є пароль. Введіть поточний — або «Забули поточний пароль?», і надішлемо посилання.");
          f.current.focus();
          return;
        }
        throw e;
      }
      clearSecrets(f);
      f.nonce.value = "";
      $("[data-nonce-field]").hidden = true;
      passwordView("change");
      return "Пароль збережено. На інших пристроях і в застосунку треба буде увійти знову.";
    });
  });
  // «Забули поточний пароль?» — лист не частіше, ніж раз на хвилину, як «Надіслати ще раз».
  $("[data-password-forgot]").addEventListener("click", async (event) => {
    const button = event.currentTarget;
    await act(button, passwordOut, async () => {
      await requestRecovery(me.email, returnTo(), { hash: "#/account" });
      return `Надіслали посилання на ${me.email}. Відкрийте його в цьому браузері протягом кількох хвилин — і задасте новий пароль.`;
    });
    button.disabled = true;
    setTimeout(() => { button.disabled = false; }, RESEND_AFTER);
  });

  // ---- Вхід
  $("[data-signout]").addEventListener("click", () => leave());
  $("[data-signout-all]").addEventListener("click", () => {
    if (confirm("Вийти з акаунта на всіх пристроях? У застосунку теж доведеться увійти знову.")) leave({ everywhere: true });
  });
}

// ---- Мої події

const ended = (e) => Date.parse(e.ends_at ?? e.starts_at) < Date.now();

async function showList() {
  view("list");
  const note = $("[data-list-note]");
  const guest = !(await signedIn());
  $("[data-guest]").hidden = !guest;
  $("[data-upcoming]").innerHTML = $("[data-past]").innerHTML = "";
  $("[data-past-title]").hidden = true;
  note.textContent = "";
  if (guest) return;
  note.textContent = "Завантажуємо…";
  const [events, requests] = await Promise.all([rpc("my_events"), rpc("my_join_requests", { p_limit: 200 }).catch(() => [])]);
  const waiting = new Map();
  for (const r of requests ?? []) waiting.set(r.event_id, (waiting.get(r.event_id) ?? 0) + 1);
  const mine = (events ?? []).filter((e) => e.organizer_id === me.id && e.origin === "community");
  const upcoming = mine.filter((e) => !ended(e));
  const past = mine.filter(ended).reverse();
  note.textContent = mine.length ? "" : "Тут будуть ваші події. Створіть першу — з готового анонсу це хвилина.";
  $("[data-upcoming]").innerHTML = upcoming.map((e) => row(e, waiting.get(e.id))).join("");
  $("[data-past]").innerHTML = past.map((e) => row(e, 0)).join("");
  $("[data-past-title]").hidden = !past.length;
}

function row(e, waiting) {
  const stats = [
    e.status === "cancelled" ? `<span class="stamp danger">Скасовано</span>` : "",
    `<span>Записалось ${e.attendee_count ?? 0}${e.capacity ? ` з ${e.capacity}` : ""}</span>`,
    waiting ? `<span class="kab-waiting">Чекають підтвердження: ${waiting}</span>` : "",
  ].join("");
  // Пачка корінців (DESIGN.md, My events): квиток із часом на корінці жанру; минула пробита, скасована — сірий корінець.
  // Місця — словами в рядку під назвою, тож на корінці їх не дублюємо.
  const kind = e.status === "cancelled" ? " void" : ended(e) ? " past" : "";
  return `<a class="kab-event ticket cat-${esc(e.category)}${kind}" href="#/e/${esc(e.id)}">
  <div class="face"><h3>${esc(displayTitle(e.title))}</h3><p>${esc(overline(e, new Date(), true))} · ${esc(e.address || e.city || "")}</p><p class="kab-stats">${stats}</p></div>
  ${ui.stubPrint({ ...e, capacity: null })}</a>`;
}

// ---- Подія: дії й учасники

let published = null; // { id, failed } — щойно опублікована: показуємо «Подію опубліковано»

async function showEvent(id) {
  view("event");
  for (const el of $$("[data-view=event] [data-event-title], [data-view=event] [data-event-when], [data-view=event] [data-event-place]")) el.textContent = "";
  $("[data-people]").innerHTML = "";
  if (!(await signedIn()) && !(await signIn({ lead: "Увійдіть тією поштою чи Google, з якими створювали подію." }))) return void (location.hash = "#/");
  const note = $("[data-event-note]");
  note.textContent = "Завантажуємо…";
  const event = await ownEvent(id);
  note.textContent = event ? "" : "Подію не знайдено: її могли приховати, або вона не ваша.";
  $("[data-view=event] .kab-tools").hidden = !event;
  $("[data-view=event] .kab-people").hidden = !event;
  const fresh = published?.id === id ? published : null;
  published = null;
  $("[data-published]").hidden = !fresh;
  if (fresh) $("[data-published-note]").textContent = fresh.failed
    ? `Не вдалося додати ${fresh.failed} ${fresh.failed === 1 ? "файл" : fresh.failed < 5 ? "файли" : "файлів"}. Спробуйте ще раз у редагуванні.` : fresh.edited ? "" : "Поділіться посиланням — і люди зможуть записатися просто з вебу.";
  if (fresh?.edited) $("[data-published] b").textContent = "Зміни збережено";
  else $("[data-published] b").textContent = "Подію опубліковано";
  if (!event) return;

  $("[data-event-title]").textContent = displayTitle(event.title);
  $("[data-event-when]").textContent = overline(event, new Date(), true);
  $("[data-event-place]").textContent = [[event.address, event.city].filter(Boolean).join(", "),
    Number(event.price_min) > 0 ? `${priceText(event.price_min)}, ${payWay(event)}` : ""].filter(Boolean).join(" · ");
  $("[data-open]").href = `/e/${event.id}`;
  $("[data-edit]").href = `#/e/${event.id}/edit`;
  const live = event.status === "published" && Date.parse(event.starts_at) > Date.now();
  $("[data-edit]").hidden = !live;
  $("[data-cancel]").hidden = !live;
  $("[data-threads]").hidden = event.status !== "published" || ended(event);
  current = event;
  // Розмови — окремо: таблиця учасників не чекає на них і не падає разом з ними.
  loadTalks(event).catch(() => { $("[data-talks]").hidden = true; });
  await loadPeople(event);
}

let current = null; // подія на екрані «Подія»
let roster = [];
let requests = []; // заявки події на екрані: стан людини в розмові

async function loadPeople(event) {
  const [approved, requested, talks] = await Promise.all([
    rpc("event_attendees", { p_event_id: event.id, p_limit: 100 }),
    event.approval_required ? rpc("event_requests", { p_event_id: event.id, p_limit: 100 }) : [],
    // Оплата онлайн: хто вже надіслав скріншот — видно в таблиці, без відкривання кожної розмови.
    event.pay_online ? rpc("event_questions", { p_event_id: event.id }).catch(() => []) : [],
  ]);
  const proofs = new Set((talks ?? []).filter((t) => t.has_proof).map((t) => t.thread_user_id));
  roster = approved ?? [];
  requests = requested ?? [];
  const when = (iso) => new Intl.DateTimeFormat("uk-UA", { timeZone: event.time_zone || TZ, day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" }).format(new Date(iso));
  const from = (via) => via === "web" ? "Веб" : "Застосунок";
  // «Написати» — кожному в таблиці: організатор пише першим тим, хто записався (оплата онлайн — реквізити).
  const write = (p) => `<button class="btn small" type="button" data-write="${esc(p.user_id)}" data-name="${esc(p.display_name || DEFAULT_NAME)}">Написати</button>`;
  const line = (p, state, actions = "") => `<tr><th scope="row">${esc(p.display_name || DEFAULT_NAME)}</th><td>${state}</td><td>${esc(when(p.joined_at))}</td><td>${from(p.via)}</td><td class="kab-act">${actions}${write(p)}</td></tr>`;
  const words = payWords(event.pay_online);
  $("[data-people]").innerHTML = requests.map((p) => line(p, `<span class="stamp accent">${proofs.has(p.user_id) ? "Скріншот надіслано" : words.waiting}</span>`,
    `<button class="btn small primary" type="button" data-approve="${esc(p.user_id)}">${words.approve}</button><button class="btn small" type="button" data-decline="${esc(p.user_id)}">Відхилити</button>`)).join("")
    + roster.map((p) => line(p, `<span class="stamp success">${words.approved}</span>`)).join("");
  $("[data-people-title]").textContent = `Учасники · ${roster.length}${event.capacity ? ` з ${event.capacity}` : ""}${requests.length ? ` · заявок ${requests.length}` : ""}`;
  $("[data-people-empty]").hidden = Boolean(roster.length || requests.length);
  $(".kab-table-wrap").hidden = !$("[data-people-empty]").hidden;
  $("[data-copy]").hidden = !roster.length;
}

// ---- Розмови з учасниками: «Поряд» — міст. Список — event_questions, розмова — event_messages з p_thread = людина.

async function loadTalks(event) {
  const box = $("[data-talks]");
  box.hidden = false;
  const talks = (await rpc("event_questions", { p_event_id: event.id })) ?? [];
  if (current?.id !== event.id) return;
  $("[data-talk-list]").innerHTML = talks.map((t) => `<li><button class="kab-talk-row" type="button" data-write="${esc(t.thread_user_id)}" data-name="${esc(t.asker_name || DEFAULT_NAME)}">
    <b>${esc(t.asker_name || DEFAULT_NAME)}${t.has_proof && event.pay_online ? ` <small class="stamp accent">Скріншот надіслано</small>` : ""}</b><span>${t.last_mine ? "Ви: " : ""}${esc(String(t.last_body || "").replace(/\s+/g, " ").slice(0, 120))}</span>${t.unread ? `<i class="kab-unread">${Number(t.unread)}</i>` : ""}</button></li>`).join("");
  $("[data-talks-empty]").hidden = talks.length > 0;
}

/** Рішення про заявку — з таблиці учасників і з розмови. */
async function decide(user, approve) {
  await rpc(approve ? "approve_member" : "decline_member", { p_event_id: current.id, p_user_id: user });
  ui.toast(approve ? payWords(current.pay_online).done : "Відхилено");
  await loadPeople(current);
}

const talk = { user: null, name: "", card: null, stage: "details", from: "[data-talk-list]", saved: null }; // з ким розмова на екрані
let talkFeed = null; // стрічка розмови (chat.js), setupTalk

async function openTalk(user, name) {
  const dialog = $("[data-talk]");
  Object.assign(talk, { user, name: name || DEFAULT_NAME, card: null, stage: "details", saved: null });
  paintAgain();
  // Реквізити, які вже надсилали в цій події, — вставити одним дотиком, а не набирати для кожного.
  if (current?.pay_online) rpc("my_payment_details", { p_event_id: current.id }).then((text) => { if (talk.user === user) { talk.saved = text || null; paintAgain(); } }).catch(() => {});
  $("[data-talk-note]").textContent = Number(current?.price_min) > 0
    ? current.pay_online
      ? `Оплата онлайн, ${priceText(current.price_min)}: надішліть тут реквізити. Прийде скріншот — звірте з банком і натисніть «Оплату отримано».`
      : "Оплата на цю подію — на місці, без передоплати: реквізити тут не надсилаються."
    : "Людина бачить лише вас; пошти й телефону ви одне одного не бачите.";
  $("[data-talk-error]").textContent = "";
  paintTalkPerson();
  if (!dialog.open) dialog.showModal();
  // Профіль — паралельно з розмовою: організатор має розуміти, з ким говорить (фото, «з нами з», відвідані події).
  rpc("profile_card", { p_user_id: user }).then((rows) => { if (talk.user === user) { talk.card = rows?.[0] ?? null; paintTalkPerson(); } }).catch(() => {});
  await talkFeed.show({ event: current.id, thread: user, me: me.id, organizer: me.id });
  $("[data-talk-form]").body.focus();
}

/** Картка учасника над розмовою: хто це, стан на події, коли й звідки записався; для заявки — «Оплату отримано» / «Відхилити». */
function paintTalkPerson() {
  const status = talkStatus(talk.user, { roster, requests, payOnline: Boolean(current?.pay_online), stage: talk.stage });
  const name = nameOf(talk.card) || talk.name;
  const { profile, joined } = talkFacts(talk.card, status, current?.time_zone || TZ);
  $("[data-talk-title]").textContent = name;
  $("[data-talk-person]").innerHTML = `<span class="kab-avatar big" aria-hidden="true">${avatarHtml(name, talk.card?.avatar_url)}</span>
    <div><p class="kab-person-line"><span class="stamp ${status.tone}">${esc(status.stamp)}</span>${profile ? `<small>${esc(profile)}</small>` : ""}</p>
    ${talk.card?.bio ? `<p class="kab-person-bio">${esc(talk.card.bio)}</p>` : ""}<small>${esc(joined)}</small></div>`;
  $("[data-talk-actions]").hidden = !status.pending;
  $("[data-talk-approve]").textContent = payWords(current?.pay_online).approve;
  // Скільки мало прийти — поруч із рішенням, щоб звірити зі скріншотом і банком.
  $("[data-talk-expected]").textContent = current?.pay_online && Number(current.price_min) > 0 ? `Очікувано: ${priceText(current.price_min)}` : "";
}

/** «Вставити ті самі реквізити»: є що вставити, цій людині ще не надсилали, а поле порожнє. */
function paintAgain() {
  const form = $("[data-talk-form]");
  $("[data-talk-again]").hidden = !(talk.saved && talk.stage === "details" && !form.body.value.trim());
}

function setupTalk() {
  const dialog = $("[data-talk]"), form = $("[data-talk-form]");
  const open = (event) => {
    const button = event.target.closest("[data-write]");
    if (!button) return;
    // Список і таблицю після розмови перемальовуємо: фокус повертаємо на ту саму кнопку в новій розмітці.
    talk.from = button.closest("[data-people]") ? "[data-people]" : "[data-talk-list]";
    openTalk(button.dataset.write, button.dataset.name).catch((e) => ui.toast(errorText(e)));
  };
  $("[data-people]").addEventListener("click", open);
  $("[data-talk-list]").addEventListener("click", open);
  $("[data-talk-close]").addEventListener("click", () => dialog.close());
  talkFeed = threadFeed($("[data-talk-thread]"), {
    empty: `<p class="kab-hint" data-empty>Напишіть першим — людина отримає сповіщення в застосунку чи лист.</p>`,
    alive: () => dialog.open,
    live: $("[data-talk-live]"),
    changed: (rows) => {
      const stage = payStage(rows, talk.user);
      if (stage !== talk.stage) { talk.stage = stage; paintTalkPerson(); paintAgain(); }
    },
  });
  const out = { error: $("[data-talk-error]") };
  // Рішення прямо з розмови: побачив скріншот — підтвердив оплату.
  const decision = (approve) => (event) => {
    if (!approve && !confirm(declineQuestion(talk.name, current?.pay_online))) return;
    act(event.currentTarget, out, async () => {
      await decide(talk.user, approve);
      paintTalkPerson();
    });
  };
  $("[data-talk-approve]").addEventListener("click", decision(true));
  $("[data-talk-decline]").addEventListener("click", decision(false));
  $("[data-talk-thread]").addEventListener("click", (event) => { if (openProof(event)) event.preventDefault(); });
  $("[data-talk-again]").addEventListener("click", () => {
    form.body.value = talk.saved;
    paintAgain();
    form.body.focus();
  });
  form.body.addEventListener("input", paintAgain);
  dialog.addEventListener("close", () => {
    talkFeed.stop();
    const { user, from } = talk;
    talk.user = null;
    const back = () => $(`${from} [data-write="${CSS.escape(user ?? "")}"]`)?.focus();
    back();
    if (current) loadTalks(current).then(back, () => {});
  });
  form.addEventListener("submit", (event) => {
    event.preventDefault();
    const body = form.body.value.trim();
    if (!body) return;
    act($("[type=submit]", form), out, async () => {
      await rpc("send_message", { p_event_id: current.id, p_body: body, p_thread: talk.user })
        .catch((e) => { throw e.code === "PAYMENT_DETAILS" ? new Problem(payOnlineOn ? TALK_PAYMENT_DETAILS : TALK_PAY_OFF) : e; });
      form.body.value = "";
      await talkFeed.load();
    });
  });
}

async function copyText(text) {
  try { await navigator.clipboard.writeText(text); return true; } catch { return false; }
}

/** «Поширити анонс» (організатор на своїй події, 1.6): пост для Threads. Вкладка — першою й без await: Safari блокує
 * window.open після очікування. Текст і так уже в інтенті, копія в буфері — на випадок, якщо інтент його загубить. */
async function shareAnnouncement(event) {
  const text = threadsPost(event);
  window.open(threadsIntent(text), "_blank", "noopener");
  if (await copyText(text)) ui.toast("Текст скопійовано");
}

function setupEvent() {
  $("[data-people]").addEventListener("click", async (event) => {
    const button = event.target.closest("[data-approve], [data-decline]");
    if (!button || button.disabled) return;
    const name = button.closest("tr")?.querySelector("th")?.textContent;
    if ("decline" in button.dataset && !confirm(declineQuestion(name, current.pay_online))) return;
    button.disabled = true;
    try {
      await decide(button.dataset.approve ?? button.dataset.decline, "approve" in button.dataset);
    } catch (e) {
      button.disabled = false;
      ui.toast(errorText(e));
    }
  });
  $("[data-copy]").addEventListener("click", async () => {
    const text = rosterText(roster);
    if (await copyText(text)) ui.toast("Список скопійовано"); else prompt("Список учасників", text);
  });
  $("[data-threads]").addEventListener("click", () => shareAnnouncement(current));
  $("[data-done-share]").addEventListener("click", () => shareAnnouncement(current));
  $("[data-done-copy]").addEventListener("click", async () => {
    const url = `https://poriad.app/e/${current.id}`;
    if (await copyText(url)) ui.toast("Посилання скопійовано"); else prompt("Посилання на подію", url);
  });
  $("[data-repeat]").addEventListener("click", async (event) => {
    event.preventDefault();
    if (!current) return;
    const old = readDraft();
    const unsaved = Boolean(old?.title?.trim() || old?.description?.trim() || (await mediaStore())?.length);
    if (unsaved && !confirm("Є незбережена чернетка нової події. Замінити її копією цієї події?")) return;
    startDraft(repeatDraft(current), repeatMedia(current));
    location.hash = "#/new";
  });
  $("[data-cancel]").addEventListener("click", async () => {
    if (!confirm("Скасувати подію? Учасники отримають сповіщення, а повернути подію не вийде.")) return;
    try {
      await rpc("cancel_event", { p_event_id: current.id });
      ui.toast("Подію скасовано");
      await showEvent(current.id);
    } catch (e) {
      ui.toast(errorText(e));
    }
  });
}

// ---- Анімації «Корінця» (1.6): lottie_light — SVG без виразів, тож суворій CSP не потрібен unsafe-eval. Тема — як у
// tokens.css: data-theme на <html>, інакше системна; «Зменшити рух» — стоп-кадр.

const isDark = () => {
  const theme = document.documentElement.dataset.theme;
  return theme === "dark" || (theme !== "light" && matchMedia("(prefers-color-scheme: dark)").matches);
};
let lottieLoading;
const loadLottie = () => lottieLoading ??= new Promise((resolve, reject) => {
  const js = Object.assign(document.createElement("script"), { src: "vendor/lottie-web@5.13.0/lottie_light.min.js" });
  js.addEventListener("load", () => resolve(window.lottie));
  js.addEventListener("error", () => { lottieLoading = null; reject(new Error("lottie")); });
  document.head.append(js);
});
const playing = new Map(); // контейнер → анімація: нова в тому самому місці прибирає стару
// Контейнер → останній виклик animate(). Плеєр і JSON вантажаться довше, ніж публікація без файлів: stop() чи новий
// виклик за цей час скасовує запізнілий, інакше петля стартувала б у вже закритій накладці.
const wanted = new Map();
const stop = (container) => { wanted.delete(container); playing.get(container)?.destroy(); playing.delete(container); };

/** `publishing` — петлею, стоп-кадр 0; `published` — раз, стоп-кадр — останній (штамп уже стоїть). Збій — без анімації. */
async function animate(container, name, category) {
  stop(container);
  const call = {};
  wanted.set(container, call);
  const still = matchMedia("(prefers-reduced-motion: reduce)").matches;
  try {
    const [lottie, data] = await Promise.all([loadLottie(), fetch(`vendor/lottie/${name}${isDark() ? "_dark" : ""}.json?v=18`).then((r) => r.json())]);
    if (wanted.get(container) !== call) return;
    const stub = getComputedStyle(document.documentElement).getPropertyValue(`--cat-${category}-stub`).trim();
    const loop = name === "publishing";
    const animation = lottie.loadAnimation({ container, renderer: "svg", loop, autoplay: !still, animationData: recolorStub(data, stub) });
    if (still) animation.addEventListener("DOMLoaded", () => animation.goToAndStop(loop ? 0 : animation.totalFrames - 1, true));
    playing.set(container, animation);
  } catch (e) {
    console.warn("lottie", e.message);
  }
}

// ---- «Подію створено» (1.6): лише одразу після публікації; перезавантаження веде на сторінку події.

async function showDone(id) {
  const fresh = published?.id === id && !published.edited ? published : null;
  published = null;
  if (!fresh || !(await signedIn())) {
    history.replaceState(history.state, "", `#/e/${id}`);
    return showEvent(id);
  }
  view("done");
  const event = await ownEvent(id);
  if (!event) return void (location.hash = `#/e/${id}`);
  current = event;
  $("[data-done-ticket]").innerHTML = doneTicket(event);
  $("[data-done-note]").textContent = fresh.failed
    ? `Не вдалося додати ${fresh.failed} ${fresh.failed === 1 ? "файл" : fresh.failed < 5 ? "файли" : "файлів"}. Спробуйте ще раз у редагуванні.` : "";
  $("[data-done-ics]").href = `/e/${event.id}.ics`;
  $("[data-done-ready]").href = `#/e/${event.id}`;
  animate($("[data-done-anim]"), "published", event.category);
}

/**
 * Квиток щойно створеної події — такий, яким його побачать люди (design-wow-1.5): обкладинка, назва, місце й корінець
 * жанру з часом. Друкується під штампом С1 (web.css, print-out); тап — сторінка події в новій вкладці.
 */
function doneTicket(e) {
  const cover = httpsOrNull(e.image_url);
  return `<a class="ticket v kab-ticket cat-${esc(e.category)}" href="/e/${esc(e.id)}" target="_blank" rel="noopener">
    ${cover ? `<img src="${esc(cover)}" alt="">` : ""}<span class="face"><b>${esc(displayTitle(e.title))}</b><small>${esc([e.address, e.city].filter(Boolean).join(", "))}</small></span>
    ${ui.stubPrint(e, { row: true })}</a>`;
}

// ---- Редактор: одна сторінка, чернетка в localStorage, файли — в IndexedDB (localStorage не тримає Blob, а вхід
// через Google перезавантажує сторінку).

let editing = null; // подія, яку редагуємо; null — нова
// Оплата онлайн за вимикачем на сервері (`pay_online_enabled`, 20261125160000): вимкнено — «Як платять» не показуємо.
let payOnlineOn = true;
let media = []; // [{ key, kind, url?, poster?, blob?, posterBlob?, copied? }]
let place = { lat: null, lon: null, placed: false };
let minutes = 120; // тривалість, яку тримають чипи й зсув початку
let original = ""; // адреси медіа події до правки: незмінний список шлемо як p_media null
let repeatFiles = null; // медіа «Повторити» — одразу в редактор, не чекаючи IndexedDB
let map, marker, mapLoading;

const form = () => $("[data-form]");
const FIELDS = ["title", "description", "address", "startDate", "startTime", "endDate", "endTime", "capacity", "minAge", "maxAge", "contact", "price"];
/** Порожня нова подія — з налаштувань «Нові події» в акаунті, якщо вони є. */
const blank = () => {
  const d = editorDefaults(me?.user_metadata);
  return { title: "", description: "", category: null, city: d.city ?? (ui?.savedCity.get() || CITIES[0].name), address: "", lat: null, lon: null, placed: false,
    startDate: "", startTime: "", endDate: "", endTime: "", capacity: 10, minAge: 18, maxAge: "", approval: d.approval ?? false, contact: d.contact ?? "", price: "",
    payOnline: false, id: null };
};

function readDraft() { try { return JSON.parse(localStorage.getItem(DRAFT)); } catch { return null; } }

function mediaStore(value) {
  return new Promise((resolve) => {
    let db;
    try { db = indexedDB.open(FILES, 1); } catch { return resolve(null); }
    db.addEventListener("upgradeneeded", () => db.result.createObjectStore("draft"));
    db.addEventListener("error", () => resolve(null));
    db.addEventListener("success", () => {
      const tx = db.result.transaction("draft", value === undefined ? "readonly" : "readwrite");
      const request = value === undefined ? tx.objectStore("draft").get("media") : tx.objectStore("draft").put(value, "media");
      tx.addEventListener("complete", () => { db.result.close(); resolve(request.result ?? null); });
      tx.addEventListener("error", () => resolve(null));
    });
  });
}
const saveMedia = () => { if (!editing) mediaStore(media.map(({ preview, ...item }) => item)); };

/** Повтор: усі поля, дата +7 днів поки не в майбутньому; нова подія — новий id. */
export function repeatDraft(e) {
  const d = eventDraft(e);
  const { start, end } = repeatTimes(instant(d.startDate, d.startTime, d.tz), instant(d.endDate, d.endTime, d.tz), d.tz);
  return { ...d, startDate: start.date, startTime: start.time, endDate: end.date, endTime: end.time };
}
/** Медіа повтору копіюються в теку нової події з публікацією; подія до 1.5 — її обкладинка. */
function repeatMedia(e) {
  const list = e.media?.length ? e.media : e.image_url ? [{ kind: "photo", url: e.image_url }] : [];
  return list.slice(0, MEDIA.max).map((m) => ({ key: crypto.randomUUID(), kind: m.kind, url: m.url, poster: m.poster ?? null, copied: true }));
}
function startDraft(draft, files) {
  writeDraft(draft);
  repeatFiles = files;
  mediaStore(files);
}

async function showEditor(id) {
  view("editor");
  $("[data-form-error]").textContent = $("[data-progress]").textContent = $("[data-announce-note]").textContent = $("[data-media-note]").textContent = "";
  editing = null;
  if (id) {
    if (!(await signedIn()) && !(await signIn({ lead: "Увійдіть тією поштою чи Google, з якими створювали подію." }))) return void (location.hash = "#/");
    editing = await ownEvent(id);
    if (!editing) { location.hash = `#/e/${id}`; return; }
    fill(eventDraft(editing));
    media = (editing.media?.length ? editing.media : editing.image_url ? [{ kind: "photo", url: editing.image_url }] : [])
      .map((m) => ({ key: m.url, kind: m.kind, url: m.url, poster: m.poster ?? null }));
    original = media.map((m) => m.url).join(" ");
  } else {
    fill(readDraft() ?? blank());
    original = "";
    media = repeatFiles ?? (await mediaStore()) ?? [];
    repeatFiles = null;
  }
  $("[data-editor-title]").textContent = editing ? "Редагувати подію" : "Нова подія";
  $("[data-submit]").textContent = editing ? "Зберегти зміни" : "Опублікувати";
  $("[data-announce-box]").hidden = Boolean(editing);
  $("[data-view=editor] .kab-back").href = editing ? `#/e/${editing.id}` : "#/";
  renderMedia();
  preview();
  await showMap();
  if (pendingPublish) { pendingPublish = false; publish(); }
}

/** Подія → чернетка редактора й «Повторити». Тест: ціна проходить її без втрат (інакше правка надіслала б 0). */
export function eventDraft(e) {
  const tz = e.time_zone || TZ;
  const start = local(e.starts_at, tz);
  const end = local(e.ends_at ?? new Date(Date.parse(e.starts_at) + 2 * HOUR).toISOString(), tz);
  return { ...blank(), title: e.title, description: e.description ?? "", category: e.category, city: e.city, address: e.address ?? "",
    lat: e.latitude, lon: e.longitude, placed: true, startDate: start.date, startTime: start.time, endDate: end.date, endTime: end.time,
    capacity: e.capacity ?? 10, minAge: e.min_age ?? 18, maxAge: e.max_age ?? "", approval: Boolean(e.approval_required), contact: e.contact_url ?? "", tz,
    payOnline: Boolean(e.pay_online),
    price: Number(e.price_min) > 0 ? String(Math.round(Number(e.price_min))) : "" };
}

/** Чернетка → форма. */
function fill(d) {
  const f = form();
  for (const name of FIELDS) f[name].value = d[name] ?? "";
  f.city.value = CITIES.some((c) => c.name === d.city) ? d.city : CITIES[0].name;
  f.approval.checked = Boolean(d.approval);
  for (const radio of $$("[name=pay]", f)) radio.checked = radio.value === (d.payOnline ? "online" : "onsite");
  payView();
  f.dataset.id = d.id ?? "";
  f.dataset.tz = d.tz ?? TZ;
  setCategory(d.category);
  place = { lat: d.lat, lon: d.lon, placed: Boolean(d.placed && d.lat != null) };
  const start = instant(d.startDate, d.startTime, f.dataset.tz), end = instant(d.endDate, d.endTime, f.dataset.tz);
  minutes = start && end && end > start ? Math.round((Date.parse(end) - Date.parse(start)) / 6e4) : 120;
  durations();
  if (map) placeMarker(false);
}

/** Форма → чернетка. */
function draft() {
  const f = form();
  const d = { id: f.dataset.id || null, tz: f.dataset.tz || TZ, category: f.dataset.category || null, approval: f.approval.checked, city: f.city.value, ...place,
    payOnline: f.pay.value === "online" };
  for (const name of FIELDS) d[name] = f[name].value;
  return d;
}

let saveTimer;
function changed() {
  clearTimeout(saveTimer);
  saveTimer = setTimeout(() => { if (!editing) writeDraft(draft()); preview(); }, 300);
}

/**
 * Як платять (docs/organizer-events.md): лише з ціною. Онлайн — завжди за підтвердженням: схвалення заявки і є
 * «Оплату отримано», тож галочку тримаємо й не даємо зняти.
 */
export const payPlan = (price, payOnline) => {
  const paid = priceParam(price) > 0;
  const online = paid && Boolean(payOnline);
  return {
    paid, online,
    hint: !paid ? "" : online
      ? "Реквізити надсилаєте в розмові тим, хто записався, а коли гроші прийдуть — натискаєте «Оплату отримано». «Поряд» не приймає оплату й не відповідає за неї й за повернення."
      : "Учасники платять вам на місці, без передоплати — так і написано на сторінці події.",
  };
};
function payView() {
  const f = form(), plan = payPlan(f.price.value, payOnlineOn && f.pay.value === "online");
  $("[data-pay-box]").hidden = !plan.paid || !payOnlineOn;
  const hint = $("[data-price-hint]");
  hint.textContent = plan.hint;
  hint.hidden = !plan.paid;
  if (plan.online) f.approval.checked = true;
  f.approval.disabled = plan.online;
  $("[data-approval-note]").textContent = plan.online
    ? "З оплатою онлайн — завжди: людина подає заявку, а ви підтверджуєте оплату"
    : "Ви вирішуєте, кого взяти: людина надсилає заявку, а не записується одразу";
}

function setCategory(key) {
  form().dataset.category = key ?? "";
  for (const chip of $$("[data-genres] [data-cat]")) chip.setAttribute("aria-pressed", String(chip.dataset.cat === key));
}

function durations() {
  const f = form();
  for (const chip of $$("[data-durations] [data-hours]")) chip.setAttribute("aria-pressed", String(+chip.dataset.hours * 60 === minutes));
  $("[data-duration-label]").textContent = DURATIONS.some((h) => h * 60 === minutes) || !f.endTime.value ? "" : durationLabel(minutes);
}

/** Початок змінився — кінець їде слідом, тривалість та сама. */
function moveEnd() {
  const f = form();
  const end = endAfter(f.startDate.value, f.startTime.value, minutes, f.dataset.tz);
  if (end) { f.endDate.value = end.date; f.endTime.value = end.time; }
  durations();
}

/** Квиток-чернетка справа, як `DraftTicket` у застосунку. */
function preview() {
  const d = draft();
  const startsAt = instant(d.startDate, d.startTime, d.tz) ?? new Date(Date.now() + 24 * HOUR).toISOString();
  // Обкладинка — лише те, що вже у сховищі: ui.poster приймає https, а не blob: щойно вибраного файлу.
  const first = media[0];
  const cover = first && !first.blob ? (first.kind === "photo" ? first.url : first.poster) : null;
  const card = { id: "draft", title: d.title.trim() || "Назва події", category: d.category || "social", starts_at: startsAt, ends_at: instant(d.endDate, d.endTime, d.tz),
    time_zone: d.tz, address: d.address.trim() || d.city, city: d.city, origin: "community", capacity: +d.capacity || null, attendee_count: 0, image_url: cover,
    price_min: priceProblem(d.price) ? null : priceParam(d.price) || null };
  $("[data-preview]").innerHTML = ui.poster(card);
}

// ---- Фото й відео

function renderMedia() {
  const list = $("[data-media]");
  for (const item of media) if (!item.preview && (item.blob || item.posterBlob)) item.preview = URL.createObjectURL(item.kind === "video" ? item.posterBlob : item.blob);
  list.innerHTML = media.map((item, i) => {
    const src = item.preview ?? (item.kind === "video" ? item.poster : item.url);
    return `<li class="kab-tile${item.kind === "video" ? " video" : ""}">${src ? `<img src="${esc(src)}" alt="">` : ""}
      ${item.kind === "video" ? `<span class="kab-play" aria-hidden="true">▶</span>` : ""}
      ${i === 0 ? `<span class="stamp photo">Обкладинка</span>` : `<button class="kab-chip-btn" type="button" data-first="${i}">Першим</button>`}
      <button class="kab-x" type="button" data-remove="${i}" aria-label="Прибрати">${ui.icon("close")}</button></li>`;
  }).join("") + (media.length < MEDIA.max ? `<li><button class="kab-add" type="button" data-add>${ui.icon("plus")}<span>Додати фото чи відео</span><small>або перетягніть сюди</small></button></li>` : "");
}

const once = (el, name) => new Promise((resolve, reject) => {
  el.addEventListener(name, resolve, { once: true });
  el.addEventListener("error", () => reject(new Error("Не вдалося додати цей файл")), { once: true });
});
/** Фото: JPEG без метаданих, довша сторона до 2048, до 5 МБ (chat.js, jpegFile). */
const photoItem = async (file) => ({ key: crypto.randomUUID(), kind: "photo", blob: await jpegFile(file) });

/** Відео: лише mp4 до 50 МБ і 30 с (перевіряє `<video>`), обкладинка — перший кадр. */
async function videoItem(file) {
  const src = URL.createObjectURL(file);
  try {
    const video = Object.assign(document.createElement("video"), { muted: true, playsInline: true, preload: "auto" });
    const loaded = once(video, "loadeddata");
    video.src = src;
    await loaded;
    if (videoTooLong(video.duration)) throw new Error("Відео до 30 секунд і 50 МБ.");
    const seeked = once(video, "seeked");
    video.currentTime = Math.min(0.05, video.duration / 2);
    await seeked;
    return { key: crypto.randomUUID(), kind: "video", blob: file, posterBlob: await jpeg(video, fit(video.videoWidth, video.videoHeight), 0.82) };
  } finally {
    URL.revokeObjectURL(src);
  }
}

async function addFiles(files) {
  const note = $("[data-media-note]");
  note.textContent = "";
  for (const file of files) {
    const problem = mediaProblem(file, media.length);
    if (problem) { note.textContent = problem; continue; }
    note.textContent = "Готуємо файл…";
    try {
      media.push(file.type.startsWith("image/") ? await photoItem(file) : await videoItem(file));
      note.textContent = "";
    } catch (e) {
      note.textContent = e.message || "Не вдалося додати цей файл";
    }
    renderMedia();
  }
  saveMedia();
  preview();
}

function setupMedia() {
  const list = $("[data-media]"), input = $("[data-file]");
  input.addEventListener("change", () => { addFiles([...input.files]); input.value = ""; });
  list.addEventListener("click", (event) => {
    const target = event.target.closest("[data-add], [data-remove], [data-first]");
    if (!target) return;
    if ("add" in target.dataset) return input.click();
    const i = +(target.dataset.remove ?? target.dataset.first);
    const [item] = media.splice(i, 1);
    if ("first" in target.dataset) media.unshift(item);
    else if (item.preview) URL.revokeObjectURL(item.preview);
    renderMedia();
    saveMedia();
    preview();
  });
  list.addEventListener("dragover", (event) => { event.preventDefault(); list.classList.add("drop"); });
  list.addEventListener("dragleave", () => list.classList.remove("drop"));
  list.addEventListener("drop", (event) => { event.preventDefault(); list.classList.remove("drop"); addFiles([...event.dataTransfer.files]); });
}

// ---- Місце: підказки адрес (/api/geocode) і мапа MapLibre з site/vendor. Крапку ставить організатор — кліком,
// перетягуванням чи вибором підказки; без неї «Опублікувати» не пускає (`placed`, як у застосунку).

let suggestTimer, suggestions = [], active = -1, lastQuery = "";

async function suggest(query) {
  const list = $("[data-places]"), input = form().address;
  const text = query.trim();
  if (text.length < 3 || text === lastQuery) { if (text.length < 3) closePlaces(); return; }
  lastQuery = text;
  try {
    const response = await fetch(`/api/geocode?${new URLSearchParams({ q: text, city: form().city.value })}`);
    suggestions = response.ok ? await response.json() : [];
  } catch { suggestions = []; }
  if (input.value.trim() !== text) return; // поки йшла відповідь, людина друкувала далі
  active = -1;
  list.innerHTML = suggestions.map((p, i) => `<li role="option" id="kab-place-${i}" data-place="${i}"><b>${esc(p.label)}</b><small>${esc(p.detail)}</small></li>`).join("");
  list.hidden = !suggestions.length;
  input.setAttribute("aria-expanded", String(!list.hidden));
}
function closePlaces() {
  $("[data-places]").hidden = true;
  form().address.setAttribute("aria-expanded", "false");
  form().address.removeAttribute("aria-activedescendant");
}
function pick(i) {
  const p = suggestions[i];
  if (!p) return;
  form().address.value = p.label;
  lastQuery = p.label;
  setPlace(p.lat, p.lon);
  closePlaces();
  map?.flyTo({ center: [p.lon, p.lat], zoom: 16 });
  changed();
}

function setPlace(lat, lon) {
  place = { lat, lon, placed: true };
  placeMarker(false);
  $("[data-map-hint]").textContent = "Точку поставлено. Її можна перетягнути.";
  changed();
}

function placeMarker(fly = true) {
  if (!map) return;
  if (!place.placed) { marker?.remove(); marker = null; return; }
  if (!marker) {
    marker = new maplibregl.Marker({ color: getComputedStyle(document.documentElement).getPropertyValue("--ink").trim() || "#141417", draggable: true });
    marker.on("dragend", () => { const { lat, lng } = marker.getLngLat(); setPlace(lat, lng); });
  }
  marker.setLngLat([place.lon, place.lat]).addTo(map);
  if (fly) map.flyTo({ center: [place.lon, place.lat], zoom: 16 });
}

function loadMapLibre() {
  return mapLoading ??= new Promise((resolve, reject) => {
    const css = Object.assign(document.createElement("link"), { rel: "stylesheet", href: "vendor/maplibre-gl@4.7.1/maplibre-gl.css" });
    const js = Object.assign(document.createElement("script"), { src: "vendor/maplibre-gl@4.7.1/maplibre-gl.js" });
    js.addEventListener("load", resolve);
    js.addEventListener("error", () => { mapLoading = null; reject(new Error("maplibre")); });
    document.head.append(css, js);
  });
}

async function showMap() {
  try { await loadMapLibre(); } catch { $("[data-map-hint]").textContent = "Мапа не завантажилась. Оновіть сторінку."; return; }
  const city = cityOf(form().city.value);
  const center = place.placed ? [place.lon, place.lat] : [city.lng, city.lat];
  $("[data-map-hint]").textContent = place.placed ? "Точку поставлено. Її можна перетягнути." : "Клікніть на мапі, щоб поставити точку зустрічі, або оберіть адресу з підказок.";
  if (map) { map.resize(); map.jumpTo({ center, zoom: place.placed ? 16 : 11.3 }); placeMarker(false); return; }
  const dark = isDark();
  // Мапа посеред форми: колесо гортає сторінку, мапу — з Ctrl/⌘, як вбудована мапа на сайтах.
  map = new maplibregl.Map({ container: $("[data-map]"), style: mapStyle(dark), center, zoom: place.placed ? 16 : 11.3, attributionControl: { compact: true }, dragRotate: false,
    cooperativeGestures: true, locale: {
      "CooperativeGesturesHandler.WindowsHelpText": "Щоб змінити масштаб, тримайте Ctrl і гортайте",
      "CooperativeGesturesHandler.MacHelpText": "Щоб змінити масштаб, тримайте ⌘ і гортайте",
      "CooperativeGesturesHandler.MobileHelpText": "Пересувайте мапу двома пальцями",
    } });
  map.addControl(new maplibregl.NavigationControl({ showCompass: false }), "top-right");
  map.on("click", (event) => setPlace(event.lngLat.lat, event.lngLat.lng));
  map.on("error", (event) => console.warn("map", event.error?.message));
  placeMarker(false);
}

function setupPlace() {
  const f = form(), list = $("[data-places]");
  f.city.innerHTML = CITIES.map((c) => `<option>${esc(c.name)}</option>`).join("");
  f.city.addEventListener("change", () => {
    lastQuery = "";
    if (!place.placed && map) { const c = cityOf(f.city.value); map.flyTo({ center: [c.lng, c.lat], zoom: 11.3 }); }
    if (f.address.value.trim()) suggest(f.address.value);
  });
  f.address.addEventListener("input", () => { clearTimeout(suggestTimer); suggestTimer = setTimeout(() => suggest(f.address.value), 300); });
  f.address.addEventListener("keydown", (event) => {
    if (list.hidden) return;
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault();
      active = (active + (event.key === "ArrowDown" ? 1 : -1) + suggestions.length) % suggestions.length;
      $$("[data-place]", list).forEach((li, i) => li.setAttribute("aria-selected", String(i === active)));
      f.address.setAttribute("aria-activedescendant", `kab-place-${active}`);
    } else if (event.key === "Enter" && active >= 0) {
      event.preventDefault();
      pick(active);
    } else if (event.key === "Escape") closePlaces();
  });
  f.address.addEventListener("blur", () => setTimeout(closePlaces, 150));
  // mousedown, а не click: інакше blur поля сховає список раніше за вибір.
  list.addEventListener("mousedown", (event) => { const li = event.target.closest("[data-place]"); if (li) { event.preventDefault(); pick(+li.dataset.place); } });
}

// ---- «Є готовий анонс?» (1.4): поля з тексту; адреса — у підказки, крапку ставить організатор.

const PARTS = { title: "назву", description: "опис", category: "жанр", starts_at: "дату", place: "місце", capacity: "кількість місць", min_age: "вік", contact_url: "чат" };

async function fillFromAnnouncement() {
  const f = form(), note = $("[data-announce-note]"), button = $("[data-fill]");
  const text = cleanText($("[data-announce]").value).trim();
  if (!text || button.disabled) return;
  button.disabled = true;
  note.textContent = "Заповнюємо…";
  let fields = null, limited = false;
  try {
    const response = await authed("/functions/v1/parse-announcement", { method: "POST", body: JSON.stringify({ text, city: f.city.value, today: local(new Date().toISOString()).date, tz: TZ }) });
    fields = await response.json();
  } catch (e) {
    limited = e.status === 429;
  } finally {
    button.disabled = false;
  }
  if (!fields || fields.error || typeof fields.title !== "string") {
    // Як у застосунку: перший рядок — назва, весь текст — опис, далі людина дописує сама.
    f.title.value = firstLine(text);
    f.description.value = text.slice(0, 5000);
    note.textContent = limited ? "Забагато анонсів за годину. Текст уже в описі — допишіть назву." : "Не вдалося розібрати анонс. Текст уже в описі — допишіть назву.";
    return changed();
  }
  const filled = [];
  if (fields.title) { f.title.value = fields.title; filled.push("title"); }
  if (fields.description) { f.description.value = fields.description; filled.push("description"); }
  if (fields.category && CATEGORIES[fields.category]) { setCategory(fields.category); filled.push("category"); }
  if (fields.starts_at) {
    [f.startDate.value, f.startTime.value] = fields.starts_at.split("T");
    if (fields.ends_at) {
      [f.endDate.value, f.endTime.value] = fields.ends_at.split("T");
      const start = instant(f.startDate.value, f.startTime.value), end = instant(f.endDate.value, f.endTime.value);
      if (start && end && end > start) minutes = Math.round((Date.parse(end) - Date.parse(start)) / 6e4);
      durations();
    } else moveEnd();
    filled.push("starts_at");
  }
  if (Number.isInteger(fields.capacity) && fields.capacity > 0) { f.capacity.value = fields.capacity; filled.push("capacity"); }
  if (Number.isInteger(fields.min_age) && fields.min_age >= 18) { f.minAge.value = fields.min_age; filled.push("min_age"); }
  if (fields.contact_url) { f.contact.value = fields.contact_url; filled.push("contact_url"); }
  if (fields.place) {
    f.address.value = fields.place;
    filled.push("place");
    suggest(fields.place);
    f.address.focus();
  }
  note.textContent = filled.length ? `Заповнили з анонсу: ${filled.map((k) => PARTS[k]).join(", ")}. Перевірте поля нижче${fields.place ? " й поставте точку на мапі" : ""}.` : "У тексті не знайшли полів — заповніть їх нижче.";
  changed();
}

// ---- Публікація: create_event (p_via 'web') → файли в Storage → update_event з p_media одним запитом.

let pendingPublish = false; // повернулись від Google з наміром опублікувати

/** Очевидне: порожні поля, точка, кінець раніше за початок. Решту перевірить сервер. */
function problems(d) {
  const out = [];
  if (d.title.trim().length < 3) out.push("Назва — щонайменше 3 символи");
  if (d.description.trim().length < 10) out.push("Опис — щонайменше 10 символів");
  if (!d.category) out.push("Оберіть категорію");
  if (!d.address.trim()) out.push("Вкажіть місто й адресу");
  if (!d.placed) out.push("Поставте точку зустрічі на мапі");
  const start = instant(d.startDate, d.startTime, d.tz), end = instant(d.endDate, d.endTime, d.tz);
  if (!start) out.push("Початок — дата й час у майбутньому");
  else if (!end || end <= start) out.push("Кінець — пізніше за початок");
  if (!(+d.capacity >= 1)) out.push("Кількість місць — від 1 до 10000");
  const price = priceProblem(d.price);
  if (price) out.push(price);
  return out;
}

function params(d, id) {
  const online = payPlan(d.price, payOnlineOn && d.payOnline).online; // онлайн — завжди за підтвердженням
  return {
    p_id: id, p_title: d.title.trim(), p_description: d.description.trim(), p_category: d.category, p_city: d.city, p_address: d.address.trim(),
    p_latitude: d.lat, p_longitude: d.lon, p_starts_at: instant(d.startDate, d.startTime, d.tz), p_ends_at: instant(d.endDate, d.endTime, d.tz),
    p_time_zone: d.tz, p_capacity: Math.round(+d.capacity), p_image_url: editing?.image_url ?? null, p_min_age: Math.round(+d.minAge || 18),
    p_max_age: d.maxAge === "" ? null : Math.round(+d.maxAge), p_approval_required: d.approval || online,
    // Вимкнено — спосіб оплати не чіпаємо (null): увімкнуть знову — подія, що була онлайн, знову онлайн.
    p_contact_url: d.contact.trim() || null, p_price: priceParam(d.price), p_pay_online: payOnlineOn ? online : null,
  };
}

const PUBLIC = "/storage/v1/object/public/";
const publicUrl = (bucket, key) => `${SUPABASE.url}${PUBLIC}${bucket}/${key}`;
const storageKey = (url) => { const [bucket, ...rest] = url.slice(url.indexOf(PUBLIC) + PUBLIC.length).split("/"); return [bucket, rest.join("/")]; };

/** Копія файлу іншої події в теку цієї (Storage copy): видалення старої події не ламає нову. */
async function copyFile(url, folder) {
  const [bucket, source] = storageKey(url);
  const key = `${folder}/${crypto.randomUUID()}.${source.split(".").pop()}`;
  await authed("/storage/v1/object/copy", { method: "POST", body: JSON.stringify({ bucketId: bucket, sourceKey: source, destinationKey: key }) });
  return publicUrl(bucket, key);
}

/** Усі файли — у теку події; невдалі пропускаємо, подія публікується без них. */
async function uploadMedia(id) {
  const folder = `${me.id}/${id}`, progress = $("[data-progress]");
  let failed = 0;
  const out = [];
  for (const [i, item] of media.entries()) {
    progress.textContent = `Завантажуємо ${i + 1} з ${media.length}`;
    try {
      if (item.copied) {
        item.url = await copyFile(item.url, folder);
        if (item.poster) item.poster = await copyFile(item.poster, folder);
      } else if (item.blob) {
        const name = crypto.randomUUID();
        if (item.kind === "photo") item.url = await upload("event-images", `${folder}/${name}.jpg`, item.blob);
        else {
          item.poster = await upload("event-images", `${folder}/${name}.jpg`, item.posterBlob);
          item.url = await upload("event-videos", `${folder}/${name}.mp4`, item.blob);
        }
      }
      // Вантажене — вже в теці: повтор публікації не вантажить його вдруге.
      Object.assign(item, { copied: false, blob: null, posterBlob: null });
      out.push(item.kind === "video" ? { kind: "video", url: item.url, poster: item.poster } : { kind: "photo", url: item.url });
    } catch (e) {
      console.warn("upload", e.status, e.code);
      failed++;
    }
  }
  return { list: out, failed };
}

async function publish() {
  const d = draft(), error = $("[data-form-error]"), progress = $("[data-progress]"), button = $("[data-submit]");
  if (busy.has("publish")) return;
  const wrong = problems(d);
  error.textContent = wrong.join(". ");
  if (wrong.length) return;
  if (!editing) writeDraft(d); // вхід через Google перезавантажить сторінку
  if (!(await account({ lead: "Подія майже готова. Увійдіть, щоб опублікувати її: тією самою поштою чи Google, що й у застосунку.", intent: { publish: true } }))) return;
  busy.add("publish");
  button.disabled = true;
  // Поки вантажаться файли — квиток друкується (П2), лічильник файлів під ним; закрити накладку посеред запису не можна.
  const overlay = $("[data-publishing]");
  $("[data-publishing-title]").textContent = editing ? "Зберігаємо зміни" : "Публікуємо подію";
  progress.textContent = "";
  overlay.showModal();
  animate($("[data-publishing-anim]"), "publishing", d.category);
  try {
    // id — у чернетці: повтор після збою не створить другу подію (create_event повертає наявну).
    const existed = Boolean(form().dataset.id);
    const id = editing?.id ?? (form().dataset.id ||= crypto.randomUUID());
    if (!editing) writeDraft(draft());
    const args = params(d, id);
    const plan = publishPlan({ editing: Boolean(editing), existed, items: media, original });
    if (plan.create) await rpc("create_event", { ...args, p_media: null, p_via: "web" });
    const { list, failed } = plan.upload ? await uploadMedia(id) : { list: null, failed: 0 };
    progress.textContent = "Зберігаємо…";
    if (plan.update) await rpc("update_event", { ...args, p_media: list });
    if (editing && list) removeFiles(editing.media ?? [], list);
    if (!editing) { writeDraft(null); media = []; mediaStore([]); }
    published = { id, failed, edited: Boolean(editing) };
    location.hash = editing ? `#/e/${id}` : `#/e/${id}/done`;
  } catch (e) {
    overlay.close();
    if (e.code === "AGE_REQUIRED" && await signIn({ at: "profile" })) { busy.delete("publish"); button.disabled = false; return publish(); }
    if (e.code === "session_expired") { me = null; ready = null; }
    error.textContent = errorText(e);
    saveMedia(); // вже вивантажене — з адресою: повтор його не вантажить
  } finally {
    if (overlay.open) overlay.close();
    stop($("[data-publishing-anim]"));
    busy.delete("publish");
    button.disabled = false;
  }
}

/** Прибрані з події файли — і зі сховища, як у застосунку. Збій не важить: подія вже збережена. */
function removeFiles(before, after) {
  const kept = new Set(after.flatMap((m) => [m.url, m.poster]));
  for (const url of before.flatMap((m) => [m.url, m.poster]).filter((u) => u && !kept.has(u))) {
    const [bucket, key] = storageKey(url);
    authed(`/storage/v1/object/${bucket}/${key}`, { method: "DELETE" }).catch(() => {});
  }
}

function setupEditor() {
  const f = form();
  $("[data-genres]").innerHTML = Object.entries(CATEGORIES).map(([key, label]) =>
    `<button class="chip cat-${key}" type="button" data-cat="${key}" aria-pressed="false"><span class="dot"></span>${esc(label)}</button>`).join("");
  $("[data-durations]").insertAdjacentHTML("afterbegin", DURATIONS.map((h) => `<button class="chip" type="button" data-hours="${h}" aria-pressed="false">${h} год</button>`).join(""));
  $("[data-genres]").addEventListener("click", (event) => { const chip = event.target.closest("[data-cat]"); if (chip) { setCategory(chip.dataset.cat); changed(); } });
  $("[data-durations]").addEventListener("click", (event) => { const chip = event.target.closest("[data-hours]"); if (chip) { minutes = +chip.dataset.hours * 60; moveEnd(); changed(); } });
  f.startDate.min = local(new Date().toISOString()).date;
  for (const name of ["startDate", "startTime"]) f[name].addEventListener("change", moveEnd);
  for (const name of ["endDate", "endTime"]) f[name].addEventListener("change", () => {
    const start = instant(f.startDate.value, f.startTime.value, f.dataset.tz), end = instant(f.endDate.value, f.endTime.value, f.dataset.tz);
    if (start && end && end > start) minutes = Math.round((Date.parse(end) - Date.parse(start)) / 6e4);
    durations();
  });
  f.addEventListener("input", changed);
  f.price.addEventListener("input", payView);
  for (const radio of $$("[name=pay]", f)) radio.addEventListener("change", payView);
  f.addEventListener("change", changed);
  f.addEventListener("submit", (event) => { event.preventDefault(); publish(); });
  $("[data-publishing]").addEventListener("cancel", (event) => event.preventDefault());
  $("[data-fill]").addEventListener("click", fillFromAnnouncement);
  setupMedia();
  setupPlace();
}

async function start() {
  ui = await import("./ui.js?v=18");
  window.poriadReady = true;
  setupAuth();
  setupAccount();
  setupEvent();
  setupTalk();
  setupEditor();
  rpc("pay_online_enabled").then((on) => { payOnlineOn = on !== false; payView(); }).catch(() => {});
  $("[data-signin]").addEventListener("click", () => signIn().then((ok) => ok && route()));
  // Повернення від Google чи з листа: намір несе маршрут і «опублікувати», з якими людина пішла; лист відновлення —
  // ще й крок нового пароля, поки решта сторінки чекає.
  let recovering = false;
  try {
    const intent = await completeRedirect();
    if (intent?.hash) history.replaceState(history.state, "", `${location.pathname}${location.search}${intent.hash}`);
    pendingPublish = Boolean(intent?.publish);
    recovering = intent?.flow === "recovery";
    if (intent?.flow === "signup") setTimeout(() => ui.toast("Пошту підтверджено"), 300);
  } catch (e) {
    if (e.intent?.hash) history.replaceState(history.state, "", `${location.pathname}${location.search}${e.intent.hash}`);
    if (e.code !== "access_denied") setTimeout(() => ui.toast(redirectErrorText(e)), 300);
  }
  addEventListener("hashchange", route);
  if (recovering && await signedIn()) {
    auth.email = me.email ?? "";
    $("[data-auth-form]").recoveryEmail.value = auth.email;
    await signIn({ at: "password" });
  }
  await route();
}

if (globalThis.document) start();
