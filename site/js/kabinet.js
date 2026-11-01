// Кабінет організатора poriad.app/kabinet (docs/organizers-1.5.md, 1.2, 1.4, 1.5): створити й вести спільнотну подію з
// комп'ютера. Маршрути в #: «#/» — мої події, «#/new», «#/e/{id}» — дії й учасники, «#/e/{id}/edit». Вхід — auth.js, дані —
// ті самі функції бази, що в застосунку; сторінка перевіряє лише очевидне, решту каже сервер. Чисті правила вгорі (дати,
// тривалість, медіа, текст для Threads) перевіряє `node tools/kabinet_test.mjs`; DOM — нижче, лише в браузері.
import { SUPABASE, CATEGORIES, CITIES, cityOf, displayTitle, esc, overline, mapStyle } from "./poriad.js?v=12";
import { session, sendCode, verifyCode, google, completeRedirect, rpc, upload, signOut, inAppBrowser } from "./auth.js?v=12";

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
export const MEDIA = { max: 5, side: 2048, photoBytes: 5 * 1024 * 1024, videoBytes: 50 * 1024 * 1024, videoSeconds: 30 };
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
/** Розмір кадру з довшою стороною до `max`. */
export function fit(width, height, max = MEDIA.side) {
  const k = Math.min(1, max / Math.max(width, height));
  return [Math.round(width * k), Math.round(height * k)];
}

// ---- «Пост для Threads» (1.5) — той самий текст, що `ThreadsPost` у застосунку.
const WEEKDAYS = ["пн", "вт", "ср", "чт", "пт", "сб", "нд"];
const MONTHS = ["січня", "лютого", "березня", "квітня", "травня", "червня", "липня", "серпня", "вересня", "жовтня", "листопада", "грудня"];
export const ABOUT_MAX = 200;
export function threadsPost(event) {
  const { date, time } = local(event.starts_at, event.time_zone || TZ);
  const [y, m, d] = date.split("-").map(Number);
  const when = `${WEEKDAYS[(new Date(Date.UTC(y, m - 1, d)).getUTCDay() + 6) % 7]}, ${d} ${MONTHS[m - 1]}, ${time}`;
  const place = event.place_name || event.address || event.city || "";
  const description = (event.description ?? "").trim();
  const about = event.blurb?.trim() || (description.length <= ABOUT_MAX ? description : description.slice(0, ABOUT_MAX).trimEnd() + "…");
  return [`${displayTitle(event.title)}\n${[when, place].filter(Boolean).join(" · ")}`, about, `Запис: poriad.app/e/${event.id}`]
    .filter(Boolean).join("\n\n");
}
/** Інтент Threads приймає лише текст; фото організатор перетягує сам. */
export const threadsIntent = (text) => `https://www.threads.net/intent/post?text=${encodeURIComponent(text)}`;

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
  START_MUST_BE_FUTURE: "Початок — дата й час у майбутньому",
  CAPACITY_BELOW_ATTENDANCE: "Не можна зменшити кількість місць нижче за тих, хто вже йде",
  EVENT_CANCELLED: "Подію скасовано",
  EVENT_NOT_FOUND: "Подія недоступна",
  NOT_ORGANIZER: "Ця дія доступна лише організатору",
  EVENT_FULL: "Вільних місць уже немає",
  TOO_MANY_MOVES: "Забагато спроб. Спробуйте трохи пізніше",
  otp_expired: "Код не підійшов або застарів. Надішліть новий",
  over_email_send_rate_limit: "Забагато спроб. Спробуйте трохи пізніше",
  over_request_rate_limit: "Забагато спроб. Спробуйте трохи пізніше",
  email_address_invalid: "Вкажіть коректний email",
  validation_failed: "Вкажіть коректний email",
};
export function errorText(error) {
  if (ERRORS[error?.code]) return ERRORS[error.code];
  const status = error?.status;
  if (!status) return "Немає звʼязку. Перевірте інтернет і спробуйте ще раз";
  if (status === 401) return SESSION;
  if (status === 403) return ERRORS.NOT_ORGANIZER;
  if (status === 429) return ERRORS.TOO_MANY_MOVES;
  return status < 500 ? "Не вдалося виконати дію. Перевірте дані та час події" : "Сервіс тимчасово недоступний. Спробуйте ще раз";
}

// ================= Сторінка =================

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const DEFAULT_NAME = "Учасник"; // так `handle_new_user` називає акаунт без імені: людина ще не назвалась
const $ = (selector, root = document) => root.querySelector(selector);
const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
let ui; // site/js/ui.js: квитки, значки й тост. Динамічно — тест імпортує цей файл без DOM.

let me = null; // { id, email }
let ready = null; // id, для якого імʼя й вік уже є
const busy = new Set();

async function signedIn() {
  me = (await session().catch(() => null))?.user ?? null;
  $("[data-signout]").hidden = !me;
  return Boolean(me);
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

// ---- Вхід: Google (крім вбудованих браузерів) або код з пошти; вперше — імʼя й «Мені вже є 18».

const auth = { dialog: null, done: null, email: "" };

function step(name) {
  for (const el of $$("[data-step]", auth.dialog)) el.hidden = el.dataset.step !== name;
  $("[data-auth-error]", auth.dialog).textContent = "";
  $(`[data-step="${name}"] input`, auth.dialog)?.focus();
}

/** Вікно входу; true — людина ввійшла й має імʼя та вік. `profile` — одразу крок імені й галочки. */
function signIn({ lead = null, profile = false, intent = null } = {}) {
  auth.intent = intent;
  $("[data-auth-lead]", auth.dialog).textContent = lead ?? "Тією самою поштою чи Google, що й у застосунку, — і ви побачите свої події.";
  step(profile ? "profile" : "start");
  if (!auth.dialog.open) auth.dialog.showModal();
  return new Promise((resolve) => { auth.done = resolve; });
}
function finishAuth(ok) {
  const done = auth.done;
  auth.done = null;
  if (auth.dialog.open) auth.dialog.close();
  done?.(ok);
}

/** Чи має акаунт імʼя (вік перевіряє створення події: `AGE_REQUIRED`). */
async function profileReady() {
  if (ready === me.id) return true;
  const [card] = await rpc("profile_card", { p_user_id: me.id }) ?? [];
  $("[name=name]", auth.dialog).value = card?.display_name && card.display_name !== DEFAULT_NAME ? card.display_name : "";
  if (card?.display_name && card.display_name !== DEFAULT_NAME) ready = me.id;
  return ready === me.id;
}

/** Вхід перед дією: true — можна. */
async function account(options = {}) {
  if (await signedIn() && await profileReady()) return true;
  return signIn({ ...options, profile: Boolean(me) });
}

function setupAuth() {
  auth.dialog = $("[data-auth]");
  const form = $("[data-auth-form]");
  const error = (e) => { $("[data-auth-error]").textContent = typeof e === "string" ? e : errorText(e); };
  const inApp = inAppBrowser();
  $("[data-google]").hidden = inApp;
  $("[data-google-or]").hidden = inApp;
  $("[data-auth-close]").addEventListener("click", () => finishAuth(false));
  auth.dialog.addEventListener("cancel", () => finishAuth(false));
  $("[data-google]").addEventListener("click", () => google(`${location.origin}/kabinet`, { hash: location.hash, ...auth.intent }));
  $("[data-other-email]").addEventListener("click", () => step("start"));
  $("[data-resend]").addEventListener("click", () => sendCode(auth.email).then(() => ui.toast("Надіслали новий код"), error));

  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    const current = $$("[data-step]", form).find((el) => !el.hidden).dataset.step;
    const button = $(`[data-step="${current}"] [type=submit]`, form);
    if (button.disabled) return;
    button.disabled = true;
    try {
      if (current === "start") {
        const email = form.email.value.trim();
        if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return error("Вкажіть коректний email");
        await sendCode(email);
        auth.email = email;
        $("[data-email]", form).textContent = email;
        form.code.value = "";
        step("code");
      } else if (current === "code") {
        const code = form.code.value.replace(/\s/g, "");
        if (!code) return error("Введіть код з листа");
        await verifyCode(auth.email, code);
        await signedIn();
        if (await profileReady()) finishAuth(true); else step("profile");
      } else {
        const name = form.name.value.trim();
        if (name.length < 2 || name.length > 60) return error("Вкажіть імʼя від 2 до 60 символів");
        if (!form.adult.checked) return error("Позначте, що вам уже є 18: «Поряд» — для дорослих");
        await authed(`/rest/v1/profiles?id=eq.${me.id}`, { method: "PATCH", body: JSON.stringify({ display_name: name }) });
        await rpc("confirm_adult");
        ready = me.id;
        finishAuth(true);
      }
    } catch (e) {
      error(e);
    } finally {
      button.disabled = false;
    }
  });

  $("[data-signout]").addEventListener("click", async () => {
    forgetDraft();
    media = [];
    await signOut();
    me = null;
    ready = null;
    route();
  });
}

// ---- Маршрути

function view(name) {
  for (const el of $$("[data-view]")) el.hidden = el.dataset.view !== name;
  scrollTo(0, 0);
}

async function route() {
  const [, page, id, sub] = location.hash.split("/");
  try {
    if (page === "new") return await showEditor(null);
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
  return `<a class="kab-event" href="#/e/${esc(e.id)}">${ui.stubTile(e)}
  <div class="kab-text"><h3>${esc(displayTitle(e.title))}</h3><p>${esc(overline(e, new Date(), true))} · ${esc(e.address || e.city || "")}</p><p class="kab-stats">${stats}</p></div>
  ${ui.icon("chevron", "ico kab-go")}</a>`;
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
  $("[data-event-place]").textContent = [event.address, event.city].filter(Boolean).join(", ");
  $("[data-open]").href = `/e/${event.id}`;
  $("[data-edit]").href = `#/e/${event.id}/edit`;
  const live = event.status === "published" && Date.parse(event.starts_at) > Date.now();
  $("[data-edit]").hidden = !live;
  $("[data-cancel]").hidden = !live;
  $("[data-threads]").hidden = event.status !== "published" || ended(event);
  current = event;
  await loadPeople(event);
}

let current = null; // подія на екрані «Подія»
let roster = [];

async function loadPeople(event) {
  const [approved, requested] = await Promise.all([
    rpc("event_attendees", { p_event_id: event.id, p_limit: 100 }),
    event.approval_required ? rpc("event_requests", { p_event_id: event.id, p_limit: 100 }) : [],
  ]);
  roster = approved ?? [];
  const when = (iso) => new Intl.DateTimeFormat("uk-UA", { timeZone: event.time_zone || TZ, day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" }).format(new Date(iso));
  const from = (via) => via === "web" ? "Веб" : "Застосунок";
  const line = (p, state, actions = "") => `<tr><th scope="row">${esc(p.display_name || DEFAULT_NAME)}</th><td>${state}</td><td>${esc(when(p.joined_at))}</td><td>${from(p.via)}</td><td class="kab-act">${actions}</td></tr>`;
  $("[data-people]").innerHTML = (requested ?? []).map((p) => line(p, `<span class="stamp accent">Заявка</span>`,
    `<button class="btn small primary" type="button" data-approve="${esc(p.user_id)}">Схвалити</button><button class="btn small" type="button" data-decline="${esc(p.user_id)}">Відхилити</button>`)).join("")
    + roster.map((p) => line(p, `<span class="stamp success">У списку</span>`)).join("");
  $("[data-people-title]").textContent = `Учасники · ${roster.length}${event.capacity ? ` з ${event.capacity}` : ""}${requested?.length ? ` · заявок ${requested.length}` : ""}`;
  $("[data-people-empty]").hidden = Boolean(roster.length || requested?.length);
  $(".kab-table-wrap").hidden = !$("[data-people-empty]").hidden;
  $("[data-copy]").hidden = !roster.length;
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
    button.disabled = true;
    const approve = "approve" in button.dataset;
    try {
      await rpc(approve ? "approve_member" : "decline_member", { p_event_id: current.id, p_user_id: button.dataset.approve ?? button.dataset.decline });
      ui.toast(approve ? "Схвалено" : "Відхилено");
      await loadPeople(current);
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
const stop = (container) => { playing.get(container)?.destroy(); playing.delete(container); };

/** `publishing` — петлею, стоп-кадр 0; `published` — раз, стоп-кадр — останній (штамп уже стоїть). Збій — без анімації. */
async function animate(container, name, category) {
  stop(container);
  const still = matchMedia("(prefers-reduced-motion: reduce)").matches;
  try {
    const [lottie, data] = await Promise.all([loadLottie(), fetch(`vendor/lottie/${name}${isDark() ? "_dark" : ""}.json?v=12`).then((r) => r.json())]);
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
  $("[data-done-event]").textContent = `${displayTitle(event.title)} · ${overline(event, new Date(), true)}`;
  $("[data-done-note]").textContent = fresh.failed
    ? `Не вдалося додати ${fresh.failed} ${fresh.failed === 1 ? "файл" : fresh.failed < 5 ? "файли" : "файлів"}. Спробуйте ще раз у редагуванні.` : "";
  $("[data-done-ics]").href = `/e/${event.id}.ics`;
  $("[data-done-ready]").href = `#/e/${event.id}`;
  animate($("[data-done-anim]"), "published", event.category);
}

// ---- Редактор: одна сторінка, чернетка в localStorage, файли — в IndexedDB (localStorage не тримає Blob, а вхід
// через Google перезавантажує сторінку).

let editing = null; // подія, яку редагуємо; null — нова
let media = []; // [{ key, kind, url?, poster?, blob?, posterBlob?, copied? }]
let place = { lat: null, lon: null, placed: false };
let minutes = 120; // тривалість, яку тримають чипи й зсув початку
let original = ""; // адреси медіа події до правки: незмінний список шлемо як p_media null
let repeatFiles = null; // медіа «Повторити» — одразу в редактор, не чекаючи IndexedDB
let map, marker, mapLoading;

const form = () => $("[data-form]");
const blank = () => ({ title: "", description: "", category: null, city: ui.savedCity.get() || CITIES[0].name, address: "", lat: null, lon: null, placed: false,
  startDate: "", startTime: "", endDate: "", endTime: "", capacity: 10, minAge: 18, maxAge: "", approval: false, contact: "", id: null });

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
function repeatDraft(e) {
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

function eventDraft(e) {
  const tz = e.time_zone || TZ;
  const start = local(e.starts_at, tz);
  const end = local(e.ends_at ?? new Date(Date.parse(e.starts_at) + 2 * HOUR).toISOString(), tz);
  return { ...blank(), title: e.title, description: e.description ?? "", category: e.category, city: e.city, address: e.address ?? "",
    lat: e.latitude, lon: e.longitude, placed: true, startDate: start.date, startTime: start.time, endDate: end.date, endTime: end.time,
    capacity: e.capacity ?? 10, minAge: e.min_age ?? 18, maxAge: e.max_age ?? "", approval: Boolean(e.approval_required), contact: e.contact_url ?? "", tz };
}

/** Чернетка → форма. */
function fill(d) {
  const f = form();
  for (const name of ["title", "description", "address", "startDate", "startTime", "endDate", "endTime", "capacity", "minAge", "maxAge", "contact"]) f[name].value = d[name] ?? "";
  f.city.value = CITIES.some((c) => c.name === d.city) ? d.city : CITIES[0].name;
  f.approval.checked = Boolean(d.approval);
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
  const d = { id: f.dataset.id || null, tz: f.dataset.tz || TZ, category: f.dataset.category || null, approval: f.approval.checked, city: f.city.value, ...place };
  for (const name of ["title", "description", "address", "startDate", "startTime", "endDate", "endTime", "capacity", "minAge", "maxAge", "contact"]) d[name] = f[name].value;
  return d;
}

let saveTimer;
function changed() {
  clearTimeout(saveTimer);
  saveTimer = setTimeout(() => { if (!editing) writeDraft(draft()); preview(); }, 300);
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
    time_zone: d.tz, address: d.address.trim() || d.city, city: d.city, origin: "community", capacity: +d.capacity || null, attendee_count: 0, image_url: cover };
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
const jpeg = (source, [width, height], quality) => new Promise((resolve, reject) => {
  const canvas = Object.assign(document.createElement("canvas"), { width, height });
  canvas.getContext("2d").drawImage(source, 0, 0, width, height);
  canvas.toBlob((blob) => (blob ? resolve(blob) : reject(new Error("Не вдалося додати цей файл"))), "image/jpeg", quality);
});

/** Фото: canvas → JPEG, довша сторона до 2048, до 5 МБ. Перекодування заодно прибирає метадані (як `pickedJPEG`). */
async function photoItem(file) {
  // createImageBitmap, а не <img>.decode(): decode у фоновій вкладці може не завершитись; поворот з EXIF — як у браузера.
  const bitmap = await createImageBitmap(file).catch(() => { throw new Error("Не вдалося відкрити це фото"); });
  try {
    const size = fit(bitmap.width, bitmap.height);
    let blob;
    for (const quality of [0.86, 0.75, 0.6]) if ((blob = await jpeg(bitmap, size, quality)).size <= MEDIA.photoBytes) break;
    if (blob.size > MEDIA.photoBytes) throw new Error("Фото завелике навіть після стиснення");
    return { key: crypto.randomUUID(), kind: "photo", blob };
  } finally {
    bitmap.close();
  }
}

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
  const text = $("[data-announce]").value.trim();
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
  return out;
}

const params = (d, id) => ({
  p_id: id, p_title: d.title.trim(), p_description: d.description.trim(), p_category: d.category, p_city: d.city, p_address: d.address.trim(),
  p_latitude: d.lat, p_longitude: d.lon, p_starts_at: instant(d.startDate, d.startTime, d.tz), p_ends_at: instant(d.endDate, d.endTime, d.tz),
  p_time_zone: d.tz, p_capacity: Math.round(+d.capacity), p_image_url: editing?.image_url ?? null, p_min_age: Math.round(+d.minAge || 18),
  p_max_age: d.maxAge === "" ? null : Math.round(+d.maxAge), p_approval_required: d.approval, p_contact_url: d.contact.trim() || null,
});

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
    if (e.code === "AGE_REQUIRED" && await signIn({ profile: true, lead: null })) { busy.delete("publish"); button.disabled = false; return publish(); }
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
  f.addEventListener("change", changed);
  f.addEventListener("submit", (event) => { event.preventDefault(); publish(); });
  $("[data-publishing]").addEventListener("cancel", (event) => event.preventDefault());
  $("[data-fill]").addEventListener("click", fillFromAnnouncement);
  setupMedia();
  setupPlace();
}

async function start() {
  ui = await import("./ui.js?v=12");
  window.poriadReady = true;
  setupAuth();
  setupEvent();
  setupEditor();
  $("[data-signin]").addEventListener("click", () => signIn().then((ok) => ok && route()));
  // Повернення від Google: намір несе маршрут і «опублікувати», з якими людина пішла.
  try {
    const intent = await completeRedirect();
    if (intent?.hash) history.replaceState(history.state, "", `${location.pathname}${location.search}${intent.hash}`);
    pendingPublish = Boolean(intent?.publish);
  } catch (e) {
    if (e.intent?.hash) history.replaceState(history.state, "", `${location.pathname}${location.search}${e.intent.hash}`);
    if (e.code !== "access_denied") setTimeout(() => ui.toast(e.code === "pkce_missing" ? "Вхід почався в іншій вкладці. Спробуйте ще раз тут." : errorText(e)), 300);
  }
  addEventListener("hashchange", route);
  await route();
}

if (globalThis.document) start();
