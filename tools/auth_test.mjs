// Вхід на сайті без браузера й Supabase: node tools/auth_test.mjs
import assert from "node:assert/strict";
import { createHash } from "node:crypto";

const memory = () => {
  const data = new Map();
  return { getItem: (k) => data.get(k) ?? null, setItem: (k, v) => data.set(k, String(v)), removeItem: (k) => data.delete(k) };
};
for (const name of ["localStorage", "sessionStorage", "location", "history"]) Object.defineProperty(globalThis, name, { value: null, writable: true, configurable: true });
localStorage = memory();
sessionStorage = memory();
location = { hostname: "poriad.app", href: "https://poriad.app/e/1", assign(url) { this.assigned = url; } };
history = { state: null, replaceState(state, title, url) { location.href = String(url); } };
const { session, sendCode, verifyCode, google, completeRedirect, rpc, upload, signOut, inAppBrowser, browserLinks, signInWithPassword, signUp,
  resendSignup, requestRecovery, updatePassword, reauthenticate, updateMetadata, currentUser, verifyPassword, signInMethods, isEmail } = await import("../site/js/auth.js");

const DB = "https://tzdogzdvctlumsqlqskr.supabase.co";
let calls = [];
const respond = (routes) => { calls = []; globalThis.fetch = async (url, init) => {
  calls.push({ url, auth: init.headers.authorization, body: typeof init.body === "string" ? JSON.parse(init.body) : init.body });
  const [status, body] = routes(url.slice(DB.length), init, calls.length);
  return new Response(body === undefined ? null : JSON.stringify(body), { status });
}; };
const stored = () => JSON.parse(localStorage.getItem("poriad.session"));
const at = (seconds) => Math.floor(Date.now() / 1000) + seconds;

// Код з пошти.
respond(() => [200, {}]);
await sendCode(" olena@example.com ");
assert.deepEqual(calls[0], { url: `${DB}/auth/v1/otp`, auth: undefined, body: { email: "olena@example.com", create_user: true } });
respond(() => [429, { code: 429, error_code: "over_email_send_rate_limit", msg: "email rate limit exceeded" }]);
await assert.rejects(sendCode("a@b.c"), { status: 429, code: "over_email_send_rate_limit" }, "ліміт листів — кодом, щоб сторінка сказала людською");
respond(() => [200, { access_token: "a1", refresh_token: "r1", expires_in: 3600, user: { id: "u1" } }]);
const fresh = await verifyCode("olena@example.com", " 123456 ");
assert.deepEqual(calls[0].body, { type: "email", email: "olena@example.com", token: "123456" });
assert.equal(fresh.access_token, "a1");
assert.ok(Math.abs(stored().expires_at - at(3600)) <= 1, "expires_at з expires_in, якщо Supabase його не дав");
assert.deepEqual(stored().user, { id: "u1" });
respond(() => [403, { error_code: "otp_expired", msg: "Token has expired or is invalid" }]);
await assert.rejects(verifyCode("olena@example.com", "000000"), { code: "otp_expired" });
assert.equal(stored().access_token, "a1", "хибний код старої сесії не стирає");

// RPC: токен людини, помилки бази — кодом.
respond(() => [200, [{ ok: true }]]);
assert.deepEqual(await rpc("join_event_web", { p_event: "e1" }), [{ ok: true }]);
assert.deepEqual(calls[0], { url: `${DB}/rest/v1/rpc/join_event_web`, auth: "Bearer a1", body: { p_event: "e1" } });
respond(() => [400, { code: "P0001", message: "AGE_REQUIRED", details: null, hint: null }]);
await assert.rejects(rpc("join_event_web", { p_event: "e1" }), { status: 400, code: "AGE_REQUIRED" });
respond(() => [204]);
assert.equal(await rpc("confirm_adult"), null, "void-функція — null");

// Протухла сесія: спершу оновлення, і одне на кілька одночасних запитів.
localStorage.setItem("poriad.session", JSON.stringify({ ...stored(), expires_at: at(30) }));
respond((path) => path.startsWith("/auth/v1/token") ? [200, { access_token: "a2", refresh_token: "r2", expires_at: at(3600), user: { id: "u1" } }] : [200, []]);
await Promise.all([rpc("a"), rpc("b")]);
assert.deepEqual(calls.map((c) => c.url.slice(DB.length)), ["/auth/v1/token?grant_type=refresh_token", "/rest/v1/rpc/a", "/rest/v1/rpc/b"]);
assert.deepEqual(calls[0].body, { refresh_token: "r1" });
assert.ok(calls.slice(1).every((c) => c.auth === "Bearer a2"));
assert.equal(stored().refresh_token, "r2");

// 401 на свіжий з виду токен (годинник телефона відстає): оновлюємо й повторюємо раз.
respond((path, init, n) => path.startsWith("/auth/v1/token") ? [200, { access_token: "a3", refresh_token: "r3", expires_at: at(3600) }]
  : n === 1 ? [401, { code: "PGRST303", message: "JWT expired" }] : [200, 1]);
assert.equal(await rpc("x"), 1);
assert.deepEqual(calls.map((c) => c.auth ?? "—"), ["Bearer a2", "—", "Bearer a3"]);

// Відкликаний refresh-токен — людина просто вийшла; збій мережі сесію не стирає.
localStorage.setItem("poriad.session", JSON.stringify({ ...stored(), expires_at: at(-10) }));
globalThis.fetch = async () => { throw new TypeError("network"); };
await assert.rejects(session(), TypeError);
assert.equal(stored().refresh_token, "r3");
respond(() => [400, { error_code: "refresh_token_not_found", msg: "Invalid Refresh Token" }]);
assert.equal(await session(), null);
assert.equal(localStorage.getItem("poriad.session"), null);
respond(() => [200, []]);
await rpc("discover_events", {});
assert.equal(calls[0].auth, undefined, "без сесії — як гість");

// Поки оновлення в дорозі, сховище змінилось — відповідь його не перезаписує.
const old = { access_token: "o", refresh_token: "ro", expires_at: at(-10) };
const other = { access_token: "t", refresh_token: "rt", expires_at: at(3600) };
const midway = (change, status, body) => respond(() => { change(); return [status, body]; });
localStorage.setItem("poriad.session", JSON.stringify(old));
midway(() => localStorage.removeItem("poriad.session"), 200, { access_token: "n", refresh_token: "rn", expires_at: at(3600) });
assert.equal(await session(), null, "людина вийшла під час оновлення — не повертаємо її назад");
assert.equal(localStorage.getItem("poriad.session"), null);
localStorage.setItem("poriad.session", JSON.stringify(old));
midway(() => localStorage.setItem("poriad.session", JSON.stringify(other)), 400, { error_code: "refresh_token_already_used" });
assert.deepEqual(await session(), other, "інша вкладка вже оновила: «токен використано» не стирає її свіжу сесію");
assert.deepEqual(stored(), other);
localStorage.setItem("poriad.session", JSON.stringify(old));
midway(() => localStorage.setItem("poriad.session", JSON.stringify(other)), 200, { access_token: "n", refresh_token: "rn", expires_at: at(3600) });
assert.deepEqual(await session(), other, "і успішна відповідь не перезаписує новішу сесію");

// 401, а оновити нема чим: помилка session_expired, а не той самий запис гостем.
localStorage.setItem("poriad.session", JSON.stringify(other));
respond((path) => path.startsWith("/auth/v1/token") ? [400, { error_code: "refresh_token_not_found" }] : [401, { code: "PGRST303", message: "JWT expired" }]);
await assert.rejects(rpc("join_event_web", { p_event: "e1" }), { status: 401, code: "session_expired" });
assert.deepEqual(calls.map((c) => c.url.slice(DB.length)), ["/rest/v1/rpc/join_event_web", "/auth/v1/token?grant_type=refresh_token"], "без третього запиту");
assert.equal(localStorage.getItem("poriad.session"), null);

// Google: PKCE S256 і повернення з ?code=.
await google("https://poriad.app/e/1?ref=threads", { join: "e1" });
const pending = JSON.parse(sessionStorage.getItem("poriad.pkce"));
assert.match(pending.verifier, /^[A-Za-z0-9_-]{43}$/, "32 випадкові байти в base64url");
assert.deepEqual(pending.intent, { join: "e1" });
const go = new URL(location.assigned);
assert.equal(go.origin + go.pathname, `${DB}/auth/v1/authorize`);
assert.equal(go.searchParams.get("provider"), "google");
assert.equal(go.searchParams.get("redirect_to"), "https://poriad.app/e/1?ref=threads");
assert.equal(go.searchParams.get("code_challenge_method"), "s256");
assert.equal(go.searchParams.get("code_challenge"), createHash("sha256").update(pending.verifier).digest("base64url"));

location.href = "https://poriad.app/e/1?ref=threads&code=c1";
respond(() => [200, { access_token: "g1", refresh_token: "gr1", expires_at: at(3600), user: { id: "u2" } }]);
assert.deepEqual(await completeRedirect(), { join: "e1" }, "намір повертається: «Йду» вдруге не треба");
assert.deepEqual(calls[0], { url: `${DB}/auth/v1/token?grant_type=pkce`, auth: undefined, body: { auth_code: "c1", code_verifier: pending.verifier } });
assert.equal(location.href, "https://poriad.app/e/1?ref=threads", "код з адреси прибрано");
assert.equal(stored().access_token, "g1");
assert.equal(sessionStorage.getItem("poriad.pkce"), null, "verifier одноразовий");
assert.equal(await completeRedirect(), null, "звичайне відкриття сторінки — не повернення");

location.href = "https://poriad.app/e/1?code=c2";
await assert.rejects(completeRedirect(), { code: "pkce_missing" }, "інша вкладка — без verifier-а код нічого не дає");
await google("https://poriad.app/e/1", "join");
location.href = "https://poriad.app/e/1?error=access_denied&error_code=access_denied&error_description=cancelled";
await assert.rejects(completeRedirect(), { code: "access_denied", intent: "join" }, "відмова Google — з наміром, щоб відкрити шторку знову");
assert.equal(location.href, "https://poriad.app/e/1");

// Організатор: пошта з паролем.
const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
const jwt = (...methods) => `${b64({ alg: "HS256" })}.${b64({ sub: "u3", amr: methods.map((method) => ({ method, timestamp: 1 })) })}.sig`;
respond(() => [200, { access_token: jwt("password"), refresh_token: "p1", expires_in: 3600, user: { id: "u3", email: "olena@example.com" } }]);
await signInWithPassword(" olena@example.com ", "secret123");
assert.deepEqual(calls[0], { url: `${DB}/auth/v1/token?grant_type=password`, auth: undefined, body: { email: "olena@example.com", password: "secret123" } });
assert.deepEqual(signInMethods(stored()), ["password"], "amr — як відкрито сесію");
assert.deepEqual(signInMethods({ access_token: "битий" }), []);
respond(() => [400, { code: 400, error_code: "invalid_credentials", msg: "Invalid login credentials" }]);
await assert.rejects(signInWithPassword("olena@example.com", "nope"), { status: 400, code: "invalid_credentials" });
assert.equal(stored().refresh_token, "p1", "хибний пароль сесії не чіпає");
assert.ok(isEmail(" a@b.ua ") && !isEmail("a@b"));

// Реєстрація: імʼя й 18+ у метаданих, PKCE на кабінет, verifier — у localStorage (лист відкриють у новій вкладці).
const mail = () => JSON.parse(localStorage.getItem("poriad.pkce.mail") ?? "{}");
respond(() => [200, { id: "u4", email: "marta@example.com", identities: [{ provider: "email" }] }]);
assert.deepEqual(await signUp("marta@example.com ", "martapass", " Марта ", "https://poriad.app/kabinet", { hash: "#/new", publish: true }), { confirm: true });
assert.equal(calls[0].url, `${DB}/auth/v1/signup?redirect_to=${encodeURIComponent("https://poriad.app/kabinet")}`);
assert.deepEqual(calls[0].body.data, { display_name: "Марта", adult_confirmed: true });
assert.equal(calls[0].body.code_challenge, createHash("sha256").update(mail().signup.verifier).digest("base64url"));
assert.deepEqual(mail().signup.intent, { hash: "#/new", publish: true });
respond(() => [200, { id: "x", email: "taken@example.com", identities: [] }]);
assert.deepEqual(await signUp("taken@example.com", "takenpass", "Т", "https://poriad.app/kabinet"), { exists: true }, "зайнята пошта: GoTrue без identities і без листа");
assert.equal(mail().signup, undefined, "verifier зайнятої пошти не лишаємо");
respond(() => [422, { error_code: "user_already_exists" }]);
assert.deepEqual(await signUp("taken@example.com", "takenpass", "Т", "https://poriad.app/kabinet"), { exists: true }, "з автопідтвердженням — помилкою");
respond(() => [422, { error_code: "weak_password", msg: "Password is known to be weak", weak_password: { reasons: ["pwned"] } }]);
await assert.rejects(signUp("new@example.com", "password1", "Н", "https://poriad.app/kabinet"), { code: "weak_password", reasons: ["pwned"] });
respond(() => [200, { access_token: "s1", refresh_token: "sr1", expires_in: 3600, user: { id: "u5" } }]);
assert.deepEqual(await signUp("auto@example.com", "autopass1", "А", "https://poriad.app/kabinet"), { session: true }, "без підтвердження пошти — одразу вхід");
assert.equal(stored().access_token, "s1");
respond(() => [200, {}]);
await resendSignup("marta@example.com", "https://poriad.app/kabinet", { hash: "#/" });
assert.equal(calls[0].body.type, "signup");
assert.equal(calls[0].body.code_challenge_method, "s256");
assert.ok(calls[0].url.startsWith(`${DB}/auth/v1/resend?redirect_to=`));

// «Забули пароль?» → посилання з листа в новій вкладці (sessionStorage порожній) → сесія відновлення.
await requestRecovery("olena@example.com", "https://poriad.app/kabinet", { hash: "#/account" });
assert.equal(calls.at(-1).url, `${DB}/auth/v1/recover?redirect_to=${encodeURIComponent("https://poriad.app/kabinet")}`);
assert.equal(calls.at(-1).body.email, "olena@example.com");
const recoveryVerifier = mail().recovery.verifier;
sessionStorage.removeItem("poriad.pkce");
location.href = "https://poriad.app/kabinet?code=rc1";
respond((path, init) => JSON.parse(init.body).code_verifier === recoveryVerifier
  ? [200, { access_token: jwt("recovery"), refresh_token: "rr1", expires_in: 3600, user: { id: "u3" } }]
  : [400, { error_code: "bad_code_verifier" }]);
assert.deepEqual(await completeRedirect(), { hash: "#/account", flow: "recovery" }, "verifier-и по черзі: чужий не спалює код");
assert.deepEqual(calls.map((c) => c.body.code_verifier), [recoveryVerifier], "відновлення — першим");
assert.equal(location.href, "https://poriad.app/kabinet");
assert.equal(mail().recovery, undefined, "verifier одноразовий");
assert.ok(mail().signup, "лист реєстрації чекає далі");
assert.deepEqual(signInMethods(stored()), ["recovery"]);
// Той самий код у вкладці, де ще й Google чекав: Google-verifier не підходить — далі лист реєстрації.
sessionStorage.setItem("poriad.pkce", JSON.stringify({ verifier: "g".repeat(43), intent: { hash: "#/" } }));
const signupVerifier = mail().signup.verifier;
location.href = "https://poriad.app/kabinet?code=sc1";
respond((path, init) => JSON.parse(init.body).code_verifier === signupVerifier
  ? [200, { access_token: jwt("otp"), refresh_token: "sr2", expires_in: 3600, user: { id: "u4" } }] : [400, { error_code: "bad_code_verifier" }]);
assert.deepEqual(await completeRedirect(), { hash: "#/", flow: "signup" });
assert.equal(calls.length, 2);
location.href = "https://poriad.app/kabinet?code=zz";
respond(() => [400, { error_code: "bad_code_verifier" }]);
await assert.rejects(completeRedirect(), { code: "pkce_missing" }, "посилання з іншого браузера");
// Протухле посилання: помилка і в запиті, і у фрагменті GoTrue — фрагмент теж прибираємо (кабінет живе в #).
location.href = "https://poriad.app/kabinet?error=access_denied&error_code=otp_expired&error_description=x#error=access_denied&error_code=otp_expired&sb=";
await assert.rejects(completeRedirect(), { code: "otp_expired" });
assert.equal(location.href, "https://poriad.app/kabinet");
location.href = "https://poriad.app/kabinet#access_token=stolen&refresh_token=x&type=signup";
assert.equal(await completeRedirect(), null, "неявний потік не приймаємо");
assert.equal(location.href, "https://poriad.app/kabinet", "токени з адреси прибрано");
location.href = "https://poriad.app/kabinet#/e/1";
assert.equal(await completeRedirect(), null);
assert.equal(location.href, "https://poriad.app/kabinet#/e/1", "маршрут кабінету не чіпаємо");

// Зміна пароля: поточний і код повторної автентифікації — лише якщо є; свіжий рядок — у сесію.
localStorage.setItem("poriad.session", JSON.stringify({ access_token: jwt("password"), refresh_token: "p2", expires_at: at(3600), user: { id: "u3", email: "olena@example.com" } }));
respond(() => [200, { id: "u3", email: "olena@example.com", user_metadata: { kabinet: { city: "Львів" } } }]);
await updatePassword("newsecret1", { current: "secret123" });
await updatePassword("newsecret2");
await updatePassword("newsecret3", { nonce: "123456" });
assert.deepEqual(calls.map((c) => c.body), [{ password: "newsecret1", current_password: "secret123" }, { password: "newsecret2" }, { password: "newsecret3", nonce: "123456" }]);
assert.ok(calls.every((c) => c.url === `${DB}/auth/v1/user` && c.auth === `Bearer ${jwt("password")}`));
assert.deepEqual(stored().user.user_metadata, { kabinet: { city: "Львів" } }, "рядок користувача — у сесії");
respond(() => [400, { error_code: "reauthentication_needed" }]);
await assert.rejects(updatePassword("newsecret4"), { code: "reauthentication_needed" });
respond(() => [200, {}]);
await reauthenticate();
assert.deepEqual(calls[0], { url: `${DB}/auth/v1/reauthenticate`, auth: `Bearer ${jwt("password")}`, body: undefined });
respond(() => [200, { id: "u3", user_metadata: { kabinet: { approval: true } } }]);
await updateMetadata({ kabinet: { approval: true } });
assert.deepEqual(calls[0].body, { data: { kabinet: { approval: true } } });
respond(() => [200, { id: "u3", identities: [{ provider: "google" }] }]);
assert.deepEqual((await currentUser()).identities, [{ provider: "google" }]);
// Перевірка пароля: окремий вхід і одразу logout саме цієї зайвої сесії.
respond((path) => path.startsWith("/auth/v1/token") ? [200, { access_token: "proof", refresh_token: "pr" }] : [204]);
await verifyPassword("olena@example.com", "newsecret3");
assert.deepEqual(calls.map((c) => [c.url.slice(DB.length), c.auth ?? "—"]), [["/auth/v1/token?grant_type=password", "—"], ["/auth/v1/logout?scope=local", "Bearer proof"]]);
assert.equal(stored().refresh_token, "p2", "перевірка не підміняє сесію");
respond(() => [400, { error_code: "invalid_credentials" }]);
await assert.rejects(verifyPassword("olena@example.com", "nope"), { code: "invalid_credentials" });
localStorage.removeItem("poriad.session");
await assert.rejects(updatePassword("newsecret5"), { code: "session_expired" }, "без сесії — не гостем");
respond(() => [204]);
localStorage.setItem("poriad.session", JSON.stringify({ access_token: "e1", refresh_token: "e1", expires_at: at(3600) }));
await requestRecovery("olena@example.com", "https://poriad.app/kabinet");
await signOut({ everywhere: true });
assert.equal(calls.at(-1).url, `${DB}/auth/v1/logout?scope=global`, "на всіх пристроях");
assert.equal(localStorage.getItem("poriad.pkce.mail"), null, "після виходу пошти в сховищі не лишаємо");
localStorage.setItem("poriad.session", JSON.stringify({ access_token: "g1", refresh_token: "gr1", expires_at: at(3600) }));

// Storage і вихід.
respond(() => [200, { Key: "event-images/u2/1 photo.jpg" }]);
const blob = new Blob(["x"], { type: "image/jpeg" });
assert.equal(await upload("event-images", "u2/1 photo.jpg", blob), `${DB}/storage/v1/object/public/event-images/u2/1%20photo.jpg`);
assert.deepEqual(calls[0], { url: `${DB}/storage/v1/object/event-images/u2/1%20photo.jpg`, auth: "Bearer g1", body: blob });
respond(() => [204]);
await signOut();
assert.deepEqual(calls[0], { url: `${DB}/auth/v1/logout?scope=local`, auth: "Bearer g1", body: {} });
assert.equal(localStorage.getItem("poriad.session"), null);
globalThis.fetch = async () => { throw new TypeError("network"); };
localStorage.setItem("poriad.session", JSON.stringify({ access_token: "z", refresh_token: "z", expires_at: at(3600) }));
await signOut();
assert.equal(localStorage.getItem("poriad.session"), null, "вихід і без мережі");

// Вбудовані браузери (перевірка 4 у спеці; site/ua.html — для телефона).
const threads = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/22B83 Barcelona 361.0.0.32.111 (iPhone15,3; iOS 18_1; uk_UA; uk; scale=3.00; 1290x2796; 676585183)";
const instagram = "Mozilla/5.0 (Linux; Android 14; Pixel 8 Build/AP2A.240905.003; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/129.0.6668.100 Mobile Safari/537.36 Instagram 352.0.0.42.110 Android";
const facebook = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 [FBAN/FBIOS;FBAV/482.0.0.38.109;FBBV/650143633]";
const webview = "Mozilla/5.0 (Linux; Android 14; SM-S918B Build/UP1A.231005.007; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/130.0.6723.58 Mobile Safari/537.36";
const tiktokIos = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 musical_ly_35.1.0 JsSdk/2.0 NetType/WIFI Channel/App Store ByteLocale/uk Region/UA";
const tiktokAndroid = "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/129.0.6668.100 Mobile Safari/537.36 trill_350102 BytedanceWebview/d8a21c6";
const telegram = "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.6723.107 Mobile Safari/537.36 Telegram-Android/11.4.2 (Google Pixel 8; Android 14; SDK 34; HIGH)";
const safari = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 Safari/604.1";
const chrome = "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36";
for (const ua of [threads, instagram, facebook, webview, tiktokIos, tiktokAndroid, telegram]) assert.ok(inAppBrowser(ua), ua);
assert.ok(![safari, chrome].some((ua) => inAppBrowser(ua)));
assert.deepEqual(browserLinks("https://poriad.app/e/1?by=AbC#top"), {
  android: "intent://poriad.app/e/1?by=AbC#Intent;scheme=https;end",
  ios: "x-safari-https://poriad.app/e/1?by=AbC",
});
console.log("auth ok");
