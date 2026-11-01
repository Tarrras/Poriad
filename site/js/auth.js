// Вхід на сайті (docs/organizers-1.5.md, 1.1): Supabase Auth напряму через REST, без бібліотек. Ним користуються запис
// з вебу (join.js) і кабінет організатора (kabinet.js). Сесія — у localStorage `poriad.session`: її бачить кожна сторінка
// домену, тому воркер дає всім суворий CSP. Verifier PKCE і намір («записатися на…») чекають повернення від Google у
// sessionStorage вкладки. Перевірка — `node tools/auth_test.mjs`.
import { SUPABASE } from "./poriad.js?v=11";

const SESSION = "poriad.session";
const PKCE = "poriad.pkce";

const read = () => { try { return JSON.parse(localStorage.getItem(SESSION)); } catch { return null; } };
const write = (value) => { value ? localStorage.setItem(SESSION, JSON.stringify(value)) : localStorage.removeItem(SESSION); return value; };
/** Відповідь /verify чи /token → сесія в сховищі. */
const keep = (data) => write({
  access_token: data.access_token, refresh_token: data.refresh_token,
  expires_at: data.expires_at ?? Math.floor(Date.now() / 1000) + data.expires_in, user: data.user,
});

/**
 * Помилка Supabase: `code` — машинний код для тексту на сторінці (`otp_expired`, `over_email_send_rate_limit` з Auth,
 * `AGE_REQUIRED` чи інший виняток бази з RPC), `status` — HTTP.
 */
async function failure(response) {
  const body = await response.json().catch(() => ({}));
  return Object.assign(new Error(body.msg || body.message || body.error_description || `HTTP ${response.status}`),
    { status: response.status, code: body.error_code || body.message || body.error || null });
}

async function auth(path, body, token = null) {
  const response = await fetch(`${SUPABASE.url}/auth/v1/${path}`, {
    method: "POST",
    headers: { apikey: SUPABASE.key, "content-type": "application/json", ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: JSON.stringify(body),
  });
  if (!response.ok) throw await failure(response);
  const text = await response.text();
  return text ? JSON.parse(text) : null;
}

let refreshing = null;
/**
 * Чинна сесія або null. Ту, що протухла чи протухне за хвилину (або `force`), оновлює; відкликану сервером забуває.
 * Збій мережі — помилка, а сесія лишається. Одночасні виклики оновлюють один раз: refresh-токен одноразовий.
 */
export async function session(force = false) {
  const current = read();
  if (!current) return null;
  if (!force && current.expires_at * 1000 - Date.now() > 60_000) return current;
  refreshing ??= auth("token?grant_type=refresh_token", { refresh_token: current.refresh_token })
    .then(keep)
    .catch((error) => { if (![400, 401, 403].includes(error.status)) throw error; return write(null); })
    .finally(() => { refreshing = null; });
  return refreshing;
}

/** Код на пошту; нової людини Supabase створює сам. Ліміт листів на годину — помилка `over_email_send_rate_limit`. */
export const sendCode = (email) => auth("otp", { email: email.trim(), create_user: true });

/** Код з листа → сесія. */
export const verifyCode = async (email, code) => keep(await auth("verify", { type: "email", email: email.trim(), token: code.trim() }));

const base64url = (bytes) => btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

/**
 * «Продовжити з Google»: PKCE S256, як у застосунку (Pkce.kt). Verifier і `intent` (будь-що, що лягає в JSON) — у
 * sessionStorage, далі Google і повернення на `returnTo` з `?code=` (адреса має бути в Redirect URLs Supabase).
 */
export async function google(returnTo, intent = null) {
  const verifier = base64url(crypto.getRandomValues(new Uint8Array(32)));
  const challenge = base64url(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier))));
  sessionStorage.setItem(PKCE, JSON.stringify({ verifier, intent }));
  location.assign(`${SUPABASE.url}/auth/v1/authorize?${new URLSearchParams({
    provider: "google", redirect_to: returnTo, code_challenge: challenge, code_challenge_method: "s256",
  })}`);
}

/**
 * Повернення від Google: міняє `?code=` на сесію, прибирає код з адреси й повертає намір, з яким людина пішла. Не
 * повернення — null. Відмова Google, протухлий код чи інша вкладка без verifier-а — помилка з `code` і `intent`.
 */
export async function completeRedirect() {
  const url = new URL(location.href);
  const code = url.searchParams.get("code");
  const error = url.searchParams.get("error_code") || url.searchParams.get("error");
  if (!code && !error) return null;
  for (const key of ["code", "error", "error_code", "error_description"]) url.searchParams.delete(key);
  history.replaceState(history.state, "", url);
  let pending = null;
  try { pending = JSON.parse(sessionStorage.getItem(PKCE)); } catch {}
  sessionStorage.removeItem(PKCE);
  const fail = (code, message) => Object.assign(new Error(message), { code, intent: pending?.intent ?? null });
  if (error) throw fail(error, `Google: ${error}`);
  if (!pending?.verifier) throw fail("pkce_missing", "Вхід почався в іншій вкладці чи браузері");
  try {
    keep(await auth("token?grant_type=pkce", { auth_code: code, code_verifier: pending.verifier }));
  } catch (e) {
    throw Object.assign(e, { intent: pending.intent ?? null });
  }
  return pending.intent ?? null;
}

const headers = (current, extra) => ({ apikey: SUPABASE.key, ...(current ? { authorization: `Bearer ${current.access_token}` } : {}), ...extra });

/** Запит від імені людини (без сесії — як гість). 401 — токен відкликали чи годинник телефона відстає: оновлюємо й повторюємо раз. */
async function signed(send) {
  const current = await session();
  let response = await send(current);
  if (response.status === 401 && current) response = await send(await session(true));
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

/** Вихід: сесію забуваємо одразу, а відкликаємо на сервері як вийде — без мережі людина теж виходить. */
export async function signOut() {
  const current = read();
  write(null);
  if (current) await auth("logout?scope=local", {}, current.access_token).catch(() => {});
}

/** Вбудований браузер Threads (Barcelona), Instagram чи Facebook: Google там вхід не пускає (disallowed_useragent). */
export const inAppBrowser = (ua = navigator.userAgent) => /Instagram|Barcelona|FBAN|FBAV/.test(ua);

/** «Відкрити в браузері» з вбудованого: Android — intent:// (типовий браузер), iOS — x-safari-https:// (Safari). */
export function browserLinks(href = location.href) {
  const url = new URL(href);
  const rest = url.host + url.pathname + url.search;
  return { android: `intent://${rest}#Intent;scheme=https;end`, ios: `x-safari-https://${rest}` };
}
