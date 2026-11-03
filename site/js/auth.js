// Вхід на сайті (docs/organizers-1.5.md, 1.1; docs/web-auth.md): Supabase Auth напряму через REST, без бібліотек. Два
// входи на одній сесії: гості й учасники на /e/{id} (join.js) — Google або код з пошти; організатор у кабінеті
// (kabinet.js) — Google або пошта з паролем, з реєстрацією, «Забули пароль?» і зміною пароля, як у застосунку
// (`SupabaseAuthRepository`). Сесія — у localStorage `poriad.session`: її бачить кожна сторінка домену, тому воркер дає
// всім суворий CSP. Verifier PKCE для Google і намір («записатися на…») чекають повернення в sessionStorage вкладки, а
// verifier-и листів (реєстрація, відновлення) — у localStorage: посилання з листа відкривається в новій вкладці.
// Перевірка — `node tools/auth_test.mjs`.
import { SUPABASE } from "./poriad.js?v=16";

const SESSION = "poriad.session";
const PKCE = "poriad.pkce";
const MAIL = "poriad.pkce.mail";
// Посилання з листа живе хвилини (flow state Supabase — від 5 хв), тож старіший verifier уже нічого не відкриє.
const MAIL_TTL = 24 * 3600_000;

/** Ті самі межі, що `AccountRules` у застосунку; довше за 72 байти bcrypt пароль не приймає. */
export const MIN_PASSWORD = 8;
export const MAX_PASSWORD = 72;
export const isEmail = (value) => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(value ?? "").trim());
export const isPassword = (value) => typeof value === "string" && value.length >= MIN_PASSWORD && value.length <= MAX_PASSWORD;

const read = () => { try { return JSON.parse(localStorage.getItem(SESSION)); } catch { return null; } };
const write = (value) => { value ? localStorage.setItem(SESSION, JSON.stringify(value)) : localStorage.removeItem(SESSION); return value; };
/** Відповідь /verify чи /token → сесія в сховищі. */
const keep = (data) => write({
  access_token: data.access_token, refresh_token: data.refresh_token,
  expires_at: data.expires_at ?? Math.floor(Date.now() / 1000) + data.expires_in, user: data.user,
});
/** Свіжий рядок користувача (після PUT чи GET /user) — у збережену сесію того самого акаунта. */
function remember(user) {
  const current = read();
  if (current && user?.id && current.user?.id === user.id) write({ ...current, user });
  return user;
}

/**
 * Помилка Supabase: `code` — машинний код для тексту на сторінці (`otp_expired`, `invalid_credentials`,
 * `weak_password` з Auth, `AGE_REQUIRED` чи інший виняток бази з RPC), `status` — HTTP, `reasons` — чим слабкий пароль
 * (`length`, `characters`, `pwned`).
 */
async function failure(response) {
  const body = await response.json().catch(() => ({}));
  return Object.assign(new Error(body.msg || body.message || body.error_description || `HTTP ${response.status}`),
    { status: response.status, code: body.error_code || body.message || body.error || null, reasons: body.weak_password?.reasons ?? null });
}

async function auth(path, body, token = null, method = "POST") {
  const response = await fetch(`${SUPABASE.url}/auth/v1/${path}`, {
    method,
    headers: { apikey: SUPABASE.key, ...(body ? { "content-type": "application/json" } : {}), ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!response.ok) throw await failure(response);
  const text = await response.text();
  return text ? JSON.parse(text) : null;
}
const redirect = (path, returnTo) => `${path}?${new URLSearchParams({ redirect_to: returnTo })}`;

let refreshing = null;
/**
 * Чинна сесія або null. Ту, що протухла чи протухне за хвилину (або `force`), оновлює; відкликану сервером забуває.
 * Збій мережі — помилка, а сесія лишається. Одночасні виклики оновлюють один раз: refresh-токен одноразовий.
 * Поки йде оновлення, людина могла вийти, а інша вкладка — вже оновити ту саму сесію: тоді відповідь (і нову, і
 * «токен уже використано») не записуємо поверх, а віддаємо те, що тепер у сховищі.
 */
export async function session(force = false) {
  const current = read();
  if (!current) return null;
  if (!force && current.expires_at * 1000 - Date.now() > 60_000) return current;
  const same = () => read()?.refresh_token === current.refresh_token;
  refreshing ??= auth("token?grant_type=refresh_token", { refresh_token: current.refresh_token })
    .then((data) => same() ? keep(data) : read())
    .catch((error) => { if (![400, 401, 403].includes(error.status)) throw error; return same() ? write(null) : read(); })
    .finally(() => { refreshing = null; });
  return refreshing;
}

// ---- Гості й учасники: код з пошти.

/** Код на пошту; нової людини Supabase створює сам. Ліміт листів на годину — помилка `over_email_send_rate_limit`. */
export const sendCode = (email) => auth("otp", { email: email.trim(), create_user: true });

/** Код з листа → сесія. Ним же підтверджують нову реєстрацію з паролем: лист «Confirm signup» несе той самий код. */
export const verifyCode = async (email, code) => keep(await auth("verify", { type: "email", email: email.trim(), token: code.trim() }));

// ---- PKCE: Google і посилання з листів.

const base64url = (bytes) => btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
/** Verifier і S256-challenge, як `Pkce.kt` у застосунку. */
async function pkce() {
  const verifier = base64url(crypto.getRandomValues(new Uint8Array(32)));
  const challenge = base64url(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier))));
  return { verifier, params: { code_challenge: challenge, code_challenge_method: "s256" } };
}

/** Потоки листів, що чекають посилання: `{ signup?, recovery? }` → `{ verifier, email, intent, at }`. Прострочені — геть. */
function mailFlows() {
  let all = null;
  try { all = JSON.parse(localStorage.getItem(MAIL)); } catch {}
  const now = Date.now();
  return Object.fromEntries(Object.entries(all ?? {}).filter(([, flow]) => flow?.verifier && now - flow.at < MAIL_TTL));
}
function saveFlows(flows) {
  try { Object.keys(flows).length ? localStorage.setItem(MAIL, JSON.stringify(flows)) : localStorage.removeItem(MAIL); } catch {}
}
function forgetFlow(name) {
  const flows = mailFlows();
  delete flows[name];
  saveFlows(flows);
}
/** Новий verifier потоку: новий лист робить старе посилання недійсним, тож і старий verifier не потрібен. */
async function mailFlow(name, email, intent) {
  const { verifier, params } = await pkce();
  saveFlows({ ...mailFlows(), [name]: { verifier, email: email.trim(), intent, at: Date.now() } });
  return params;
}

/**
 * «Продовжити з Google»: PKCE S256, як у застосунку (Pkce.kt). Verifier і `intent` (будь-що, що лягає в JSON) — у
 * sessionStorage, далі Google і повернення на `returnTo` з `?code=` (адреса має бути в Redirect URLs Supabase).
 */
export async function google(returnTo, intent = null) {
  const { verifier, params } = await pkce();
  sessionStorage.setItem(PKCE, JSON.stringify({ verifier, intent }));
  location.assign(`${SUPABASE.url}/auth/v1/authorize?${new URLSearchParams({ provider: "google", redirect_to: returnTo, ...params })}`);
}

/**
 * Повернення з `?code=`: від Google (verifier у sessionStorage цієї вкладки) або з листа реєстрації чи відновлення
 * (verifier-и в localStorage). Лист не каже, якого він потоку, тож пробуємо verifier-и по черзі: чужий сервер
 * відхиляє як `bad_code_verifier`, не спалюючи код (як `handleCallback` у застосунку). Міняє код на сесію, прибирає
 * його з адреси й повертає намір: для Google — той, з яким людина пішла, для листа — `{ ...намір, flow }`
 * (`flow` — `signup` чи `recovery`). Не повернення — null. Відмова Google, протухле посилання чи інша вкладка без
 * verifier-а — помилка з `code` і `intent`. Неявний потік (токени у фрагменті) не приймаємо — лише прибираємо з адреси:
 * так закрито session fixation, як у застосунку.
 */
export async function completeRedirect() {
  const url = new URL(location.href);
  const hash = new URLSearchParams(url.hash.slice(1));
  const code = url.searchParams.get("code");
  // GoTrue кладе помилку і в запит, і у фрагмент (`#error=…&sb`); неявний потік — лише у фрагмент. Код у запиті
  // важить більше за старий фрагмент.
  const error = url.searchParams.get("error_code") || url.searchParams.get("error") || (code ? null : hash.get("error_code") || hash.get("error"));
  const foreign = hash.has("access_token") || hash.has("error_code") || hash.has("error") || hash.has("sb");
  if (!code && !error) {
    if (foreign) { url.hash = ""; history.replaceState(history.state, "", url); }
    return null;
  }
  for (const key of ["code", "error", "error_code", "error_description"]) url.searchParams.delete(key);
  if (foreign) url.hash = "";
  history.replaceState(history.state, "", url);
  let pending = null;
  try { pending = JSON.parse(sessionStorage.getItem(PKCE)); } catch {}
  sessionStorage.removeItem(PKCE);
  const fail = (code, message, intent = pending?.intent ?? null) => Object.assign(new Error(message), { code, intent });
  if (error) throw fail(error, `Auth: ${error}`);
  const flows = mailFlows();
  const candidates = [
    ...(pending?.verifier ? [{ flow: "google", verifier: pending.verifier, intent: pending.intent ?? null }] : []),
    ...["recovery", "signup"].filter((name) => flows[name]).map((name) => ({ flow: name, verifier: flows[name].verifier, intent: flows[name].intent ?? null })),
  ];
  for (const candidate of candidates) {
    try {
      keep(await auth("token?grant_type=pkce", { auth_code: code, code_verifier: candidate.verifier }));
    } catch (e) {
      if (e.code === "bad_code_verifier") continue;
      if (candidate.flow !== "google") forgetFlow(candidate.flow);
      throw Object.assign(e, { intent: candidate.intent });
    }
    if (candidate.flow === "google") return candidate.intent;
    forgetFlow(candidate.flow);
    return { ...(candidate.intent ?? {}), flow: candidate.flow };
  }
  throw fail("pkce_missing", "Вхід почався в іншій вкладці чи браузері");
}

// ---- Організатор: пошта з паролем.

/** Вхід поштою й паролем. Хибна пара — `invalid_credentials`, непідтверджена пошта — `email_not_confirmed`. */
export const signInWithPassword = async (email, password) => keep(await auth("token?grant_type=password", { email: email.trim(), password }));

/**
 * Реєстрація поштою й паролем, як `signUp` у застосунку: імʼя й 18+ — у метаданих, тригер акаунта пише їх у профіль.
 * Без підтвердження пошти — одразу сесія (`{ session: true }`). З ним — `{ confirm: true }`: лист «Confirm signup» несе
 * код (`verifyCode`) і посилання (PKCE на `returnTo`). Пошта вже зайнята — `{ exists: true }`: GoTrue тоді відповідає
 * користувачем без identities і листа не шле (з автопідтвердженням — помилка `user_already_exists`).
 */
export async function signUp(email, password, name, returnTo, intent = null) {
  const params = await mailFlow("signup", email, intent);
  let data;
  try {
    data = await auth(redirect("signup", returnTo), { email: email.trim(), password, data: { display_name: name.trim(), adult_confirmed: true }, ...params });
  } catch (e) {
    forgetFlow("signup");
    if (e.code === "user_already_exists") return { exists: true };
    throw e;
  }
  if (data?.access_token) {
    forgetFlow("signup");
    keep(data);
    return { session: true };
  }
  const user = data?.user ?? data;
  if (Array.isArray(user?.identities) && user.identities.length === 0) {
    forgetFlow("signup");
    return { exists: true };
  }
  return { confirm: true };
}

/** Лист підтвердження ще раз (нова реєстрація або вхід паролем з `email_not_confirmed`). */
export async function resendSignup(email, returnTo, intent = mailFlows().signup?.intent ?? null) {
  const params = await mailFlow("signup", email, intent);
  await auth(redirect("resend", returnTo), { type: "signup", email: email.trim(), ...params });
}

/**
 * «Забули пароль?»: лист «Reset Password» з посиланням (PKCE) на `returnTo`. Сесія з нього — відновлення (`amr`
 * `recovery`): новий пароль сервер приймає без поточного. Невідома пошта — теж успіх: сервер не каже, чи є акаунт.
 * Так само задає перший пароль той, хто досі входив кодом з пошти.
 */
export async function requestRecovery(email, returnTo, intent = null) {
  const params = await mailFlow("recovery", email, intent);
  await auth(redirect("recover", returnTo), { email: email.trim(), ...params });
}

/** Запит до /auth/v1 від імені людини; без сесії — `session_expired`. */
async function own(method, path = "user", body = null) {
  if (!(await session())) throw Object.assign(new Error("Сесія закінчилась, увійдіть ще раз"), { status: 401, code: "session_expired" });
  const response = await signed((current) => fetch(`${SUPABASE.url}/auth/v1/${path}`, {
    method, headers: headers(current, body ? { "content-type": "application/json" } : {}), body: body ? JSON.stringify(body) : undefined,
  }));
  const text = await response.text();
  return text ? JSON.parse(text) : null;
}

/** Свій рядок Auth: пошта, `identities` (якими провайдерами входить), `user_metadata`. */
export const currentUser = async () => remember(await own("GET"));

/**
 * Новий пароль (PUT /user). `current` — поточний: з «Require current password when updating» сервер без нього
 * відмовляє (`current_password_required`, хибний — `current_password_mismatch`), крім сесії з листа відновлення й
 * першого пароля акаунта. `nonce` — код з листа `reauthenticate()`, коли «Secure password change» каже
 * `reauthentication_needed` (вхід старший за добу). Решту сесій акаунта сервер після зміни закриває.
 */
export async function updatePassword(password, { current = null, nonce = null } = {}) {
  return remember(await own("PUT", "user", { password, ...(current ? { current_password: current } : {}), ...(nonce ? { nonce } : {}) }));
}

/** Код на пошту для `updatePassword({ nonce })`. */
export const reauthenticate = () => own("GET", "reauthenticate");

/** Свої метадані Auth (`data` зливається з наявними; null ключа — видаляє). Так кабінет памʼятає налаштування нових подій. */
export const updateMetadata = async (data) => remember(await own("PUT", "user", { data }));

/**
 * Чи це пароль власника — як `verifyPassword` у застосунку: окремий вхід без запису, і одразу закриваємо саме цю
 * зайву сесію (`scope=local`). Хибний — `invalid_credentials`.
 */
export async function verifyPassword(email, password) {
  const proof = await auth("token?grant_type=password", { email: email.trim(), password });
  if (proof?.access_token) await auth("logout?scope=local", {}, proof.access_token).catch(() => {});
}

/**
 * Чим відкрито сесію (claim `amr` токена): `password`, `oauth`, `otp`, `recovery`… Оновлення токена його не міняє.
 * Як `UserSession.methods` у застосунку.
 */
export function signInMethods(current) {
  try {
    const part = current.access_token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
    const claims = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(part), (c) => c.charCodeAt(0))));
    return Array.isArray(claims.amr) ? claims.amr.map((a) => a?.method).filter(Boolean) : [];
  } catch {
    return [];
  }
}

const headers = (current, extra) => ({ apikey: SUPABASE.key, ...(current ? { authorization: `Bearer ${current.access_token}` } : {}), ...extra });

/**
 * Запит від імені людини (без сесії — як гість). 401 — токен відкликали чи годинник телефона відстає: оновлюємо й
 * повторюємо раз. Сесії вже нема — помилка `session_expired`, а не той самий запит гостем.
 */
async function signed(send) {
  const current = await session();
  let response = await send(current);
  if (response.status === 401 && current) {
    const renewed = await session(true);
    if (!renewed) throw Object.assign(new Error("Сесія закінчилась, увійдіть ще раз"), { status: 401, code: "session_expired" });
    response = await send(renewed);
  }
  if (!response.ok) throw await failure(response);
  return response;
}

/** RPC бази з токеном людини. Порожня відповідь (void) — null. */
export async function rpc(name, args = {}) {
  const response = await signed((current) => fetch(`${SUPABASE.url}/rest/v1/rpc/${name}`, {
    method: "POST", headers: headers(current, { "content-type": "application/json" }), body: JSON.stringify(args),
  }));
  const text = await response.text();
  return text ? JSON.parse(text) : null;
}

/** Файл у Storage (REST) → публічна адреса: бакети подій публічні. Наявний файл не перезаписує. */
export async function upload(bucket, path, blob) {
  const target = `${encodeURIComponent(bucket)}/${path.split("/").map(encodeURIComponent).join("/")}`;
  await signed((current) => fetch(`${SUPABASE.url}/storage/v1/object/${target}`, {
    method: "POST", headers: headers(current, { "content-type": blob.type || "application/octet-stream" }), body: blob,
  }));
  return `${SUPABASE.url}/storage/v1/object/public/${target}`;
}

/**
 * Вихід: сесію й листи, що чекають (з поштою), забуваємо одразу, а відкликаємо на сервері як вийде — без мережі людина
 * теж виходить. `everywhere` — усі сесії акаунта, і в застосунку теж (`scope=global`).
 */
export async function signOut({ everywhere = false } = {}) {
  const current = read();
  write(null);
  saveFlows({});
  if (current) await auth(`logout?scope=${everywhere ? "global" : "local"}`, {}, current.access_token).catch(() => {});
}

/**
 * Вбудований браузер: Threads (Barcelona), Instagram, Facebook, TikTok (musical_ly, BytedanceWebview), Telegram і
 * будь-який Android WebView (`; wv)`). Google туди вхід не пускає (disallowed_useragent).
 */
export const inAppBrowser = (ua = navigator.userAgent) => /Instagram|Barcelona|FBAN|FBAV|; wv\)|musical_ly|BytedanceWebview|Telegram/.test(ua);

/** «Відкрити в браузері» з вбудованого: Android — intent:// (типовий браузер), iOS — x-safari-https:// (Safari). */
export function browserLinks(href = location.href) {
  const url = new URL(href);
  const rest = url.host + url.pathname + url.search;
  return { android: `intent://${rest}#Intent;scheme=https;end`, ios: `x-safari-https://${rest}` };
}
