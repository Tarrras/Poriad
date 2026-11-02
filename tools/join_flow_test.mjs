// Машина станів шторки «Йду» (site/js/join.js, start) на фейковому DOM і фейковій базі: node tools/join_flow_test.mjs
import assert from "node:assert/strict";

const memory = () => {
  const data = new Map();
  return { getItem: (k) => data.get(k) ?? null, setItem: (k, v) => data.set(k, String(v)), removeItem: (k) => data.delete(k), clear: () => data.clear() };
};
for (const name of ["localStorage", "sessionStorage", "location", "history", "document"]) Object.defineProperty(globalThis, name, { value: null, writable: true, configurable: true });
localStorage = memory();
sessionStorage = memory();
location = { hostname: "poriad.app" }; // poriad.js бере prod-проєкт за хостом під час імпорту
const { start } = await import("../site/js/join.js");

const DB = "https://tzdogzdvctlumsqlqskr.supabase.co";
const ID = "a5000000-0000-4000-8000-0000000000a1";
const ORG = "d0000000-0000-4000-8000-000000000001";
const flush = async () => { for (let i = 0; i < 40; i++) await new Promise((r) => setImmediate(r)); };

/** Елемент з тим, що чіпає join.js: hidden, текст, значення, атрибути й обробники (`fire` чекає їх усіх). */
function element(props = {}) {
  const listeners = {};
  const attrs = {};
  return Object.assign({
    hidden: false, textContent: "", value: "", disabled: false, required: false, dataset: {}, innerHTML: "",
    addEventListener(type, fn) { (listeners[type] ??= []).push(fn); },
    async fire(type) { for (const fn of listeners[type] ?? []) await fn({ target: this, currentTarget: this, preventDefault() {} }); },
    setAttribute(k, v) { attrs[k] = String(v); }, removeAttribute(k) { delete attrs[k]; }, getAttribute(k) { return attrs[k] ?? null; },
    focus() { this.focused = true; }, reset() {}, querySelector: () => null,
  }, props);
}

/**
 * Сторінка події: шторка, кнопка внизу й адреса. `share` — ще «Поділитися з другом» угорі й прихована «Скопіювати
 * посилання» (`doc` — що зараз у документі: скрипт підміняє кнопку копією). `ready` — стартова задача start().
 */
function page({ minAge = 18, maxAge = "", search = "", share = false } = {}) {
  const els = new Map();
  const $ = (selector) => { if (!els.has(selector)) els.set(selector, element()); return els.get(selector); };
  const steps = ["start", "code", "profile", "status"].map((step, i) => Object.assign($(`[data-step="${step}"]`), { dataset: { step }, hidden: i > 0 }));
  $('[data-form="email"]').email = element();
  $('[data-form="code"]').code = element();
  Object.assign($('[data-form="profile"]'), { name: element(), birth: element() });
  $("[data-week]").querySelector = (s) => (s === "[data-cards]" ? $("[data-cards]") : null);
  const sheet = element({
    dataset: { event: ID, organizer: ORG, organizerName: "Марта", city: "Київ", minAge: String(minAge), maxAge: String(maxAge) },
    open: false, showModal() { this.open = true; }, close() { this.open = false; this.fire("close"); },
    querySelector: $, querySelectorAll: (s) => (s === "[data-step]" ? steps : []),
  });
  const bar = element({ textContent: "Йду" });
  const spots = element({ textContent: "0 з 6" });
  const doc = { "[data-join]": bar, ".bar [data-spots]": spots };
  if (share) {
    const original = element({ lastChild: { textContent: "Поділитися з другом" } });
    original.cloneNode = () => element({ lastChild: { textContent: original.lastChild.textContent } });
    original.replaceWith = (next) => { doc["[data-share]"] = next; };
    doc["[data-share]"] = original;
    doc["[data-copy-link]"] = element({ hidden: true, lastChild: { textContent: "Скопіювати посилання" } });
    doc["[data-afisha]"] = element();
  }
  document = { querySelector: (s) => doc[s] ?? null };
  location = { hostname: "poriad.app", origin: "https://poriad.app", pathname: `/e/${ID}`, href: `https://poriad.app/e/${ID}${search}` };
  history = { state: null, replaceState(state, title, url) { location.href = String(url); } };
  const step = () => steps.find((e) => !e.hidden)?.dataset.step;
  return { sheet, bar, spots, $, step, doc, ready: start(sheet) };
}

/** Фейкова база: маршрут за назвою RPC чи шляхом → [статус, тіло] (можна проміс). `calls` — назви по черзі. */
let calls = [];
function backend(routes) {
  calls = [];
  globalThis.fetch = async (url, init = {}) => {
    const path = url.slice(DB.length).split("?")[0];
    const name = path.replace("/rest/v1/rpc/", "");
    calls.push(init.method === "PATCH" ? `PATCH ${name}` : name);
    const [status, body] = await (routes[name]?.(init.body ? JSON.parse(init.body) : null) ?? [200, null]);
    return new Response(body == null ? null : JSON.stringify(body), { status });
  };
}
const failure = (code) => [400, { code: "P0001", message: code }];
const signIn = (providers = ["email"]) => localStorage.setItem("poriad.session", JSON.stringify({
  access_token: "t", refresh_token: "r", expires_at: Math.floor(Date.now() / 1000) + 3600, user: { id: "u1", app_metadata: { providers } },
}));
const reset = () => { localStorage.clear(); sessionStorage.clear(); };
/** Стан учасника, що міняють запис і скасування, — як у базі. */
function members(initial = "none") {
  let membership = initial;
  return {
    join_event_web: () => { membership = "approved"; return [200]; },
    leave_event: () => { membership = "none"; return [200]; },
    event_details: () => [200, [{ membership, attendee_count: membership === "approved" ? 2 : 1, capacity: 6 }]],
    my_waitlist: () => [200, []], my_follows: () => [200, []],
  };
}

// Повернення від Google з наміром: код → сесія → запис без другого «Йду», код прибрано з адреси.
reset();
sessionStorage.setItem("poriad.pkce", JSON.stringify({ verifier: "v", intent: { event: ID, action: "join" } }));
backend({ ...members(), "/auth/v1/token": () => [200, { access_token: "t", refresh_token: "r", expires_in: 3600, user: { id: "u1", app_metadata: { providers: ["google"] } } }] });
let p = page({ search: "?code=abc" });
await p.ready; await flush();
assert.deepEqual(calls.slice(0, 3), ["/auth/v1/token", "join_event_web", "event_details"]);
assert.equal(p.step(), "status");
assert.equal(p.$("[data-title]").textContent, "Ви в списку");
assert.equal(p.bar.textContent, "Ви в списку");
assert.equal(p.spots.textContent, "2 з 6", "свіжі місця з бази");
assert.equal(p.$("[data-google-hint]").hidden, false, "увійшли Google — рядок про Google у застосунку");
assert.ok(!location.href.includes("code="), "код прибрано з адреси");

// Намір з іншої події — не наш: сторінка лише показує стан.
reset();
sessionStorage.setItem("poriad.pkce", JSON.stringify({ verifier: "v", intent: { event: "other", action: "join" } }));
backend({ ...members(), "/auth/v1/token": () => [200, { access_token: "t", refresh_token: "r", expires_in: 3600, user: { id: "u1" } }] });
p = page({ search: "?code=abc" });
await p.ready; await flush();
assert.ok(!calls.includes("join_event_web") && !p.sheet.open);

// Код у пошті: перезавантаження повертає крок з кодом; закрили шторку — більше не повертає; старий за 15 хв — теж.
reset();
backend(members());
sessionStorage.setItem("poriad.join", JSON.stringify({ email: "a@b.c", event: ID, action: "join", sentAt: Date.now() - 59_500 }));
p = page();
await p.ready; await flush();
assert.equal(p.step(), "code");
assert.equal(p.$("[data-email]").textContent, "a@b.c");
assert.equal(p.$("[data-resend]").disabled, true, "«Надіслати ще раз» — через хвилину від листа");
p.sheet.close();
assert.equal(sessionStorage.getItem("poriad.join"), null, "закрили шторку — пошту забули");
sessionStorage.setItem("poriad.join", JSON.stringify({ email: "a@b.c", event: ID, action: "join", sentAt: Date.now() - 16 * 60_000 }));
p = page();
await p.ready; await flush();
assert.equal(p.sheet.open, false, "код старший за 15 хв шторку не відкриває");
assert.equal(sessionStorage.getItem("poriad.join"), null);

// «Не стежити» з листа — лише після підтвердження: посилання могли відкрити випадково чи підсунути. Свіжий код у
// вкладці не заважає; стан запису підтягується.
reset();
signIn();
sessionStorage.setItem("poriad.join", JSON.stringify({ email: "a@b.c", event: ID, action: "join", sentAt: Date.now() }));
backend({ ...members("approved"), unfollow: (body) => { assert.deepEqual(body, { p_kind: "organizer", p_target: ORG }); return [200]; } });
p = page({ search: "?unfollow" });
await p.ready; await flush();
assert.ok(!calls.includes("unfollow"), "без тапу не відписуємо");
assert.equal(p.$("[data-title]").textContent, "Не стежити за організатором Марта?");
assert.equal(p.$("[data-unfollow]").hidden, false);
assert.equal(p.bar.textContent, "Ви в списку", "кнопка внизу знає, що людина записана");
assert.ok(!location.href.includes("unfollow"));
await p.$("[data-unfollow]").fire("click"); await flush();
assert.ok(calls.includes("unfollow"));
assert.equal(p.$("[data-title]").textContent, "Ви більше не стежите");
assert.equal(p.$("[data-unfollow]").hidden, true);
// Закрили питання — нічого не сталося.
backend({ ...members("approved"), unfollow: () => [200] });
p = page({ search: "?unfollow" });
await p.ready; await flush();
p.sheet.close(); await flush();
assert.ok(!calls.includes("unfollow"));
// Без входу — шторка входу з «Не стежити», після коду — те саме питання, і лише тап відписує.
reset();
backend({ ...members(), unfollow: () => [200], "/auth/v1/otp": () => [200, {}], "/auth/v1/verify": () => [200, { access_token: "t", refresh_token: "r", expires_in: 3600, user: { id: "u1" } }] });
p = page({ search: "?unfollow" });
await p.ready; await flush();
assert.equal(p.step(), "start");
assert.equal(p.$("[data-head]").textContent, "Не стежити за організатором");
p.$('[data-form="email"]').email.value = " a@b.c ";
await p.$('[data-form="email"]').fire("submit");
p.$('[data-form="code"]').code.value = "123456";
await p.$('[data-form="code"]').fire("submit"); await flush();
assert.deepEqual(calls.filter((c) => !["event_details", "my_waitlist"].includes(c)), ["/auth/v1/otp", "/auth/v1/verify"]);
assert.equal(p.$("[data-title]").textContent, "Не стежити за організатором Марта?");
assert.equal(sessionStorage.getItem("poriad.join"), null, "код підтверджено — пошту забули");
await p.$("[data-unfollow]").fire("click"); await flush();
assert.ok(calls.includes("unfollow"));
assert.equal(p.$("[data-title]").textContent, "Ви більше не стежите");

// «Вийти» в шторці: за спільним компʼютером видно, чий акаунт, і після виходу сторінка забуває все особисте.
reset();
localStorage.setItem("poriad.session", JSON.stringify({ access_token: "t", refresh_token: "r", expires_at: Math.floor(Date.now() / 1000) + 3600,
  user: { id: "u1", email: "olena@example.com", app_metadata: { providers: ["email"] } } }));
backend({ ...members("approved") });
p = page();
await p.ready; await flush();
await p.bar.fire("click"); await flush();
assert.equal(p.$("[data-account]").hidden, false, "після входу — рядок акаунта");
assert.equal(p.$("[data-account-email]").textContent, "olena@example.com");
await p.$("[data-signout]").fire("click"); await flush();
assert.ok(calls.includes("/auth/v1/logout"), "сесію відкликано на сервері");
assert.equal(localStorage.getItem("poriad.session"), null);
assert.equal(p.$("[data-title]").textContent, "Ви вийшли");
assert.equal(p.bar.textContent, "Йду");
assert.equal(p.$("[data-account]").hidden, true);
assert.equal(p.$("[data-account-email]").textContent, "", "пошти попереднього в сторінці не лишилось");
await p.bar.fire("click"); await flush();
assert.equal(p.step(), "start", "наступна людина починає з входу");
assert.equal(p.$("[data-account]").hidden, true, "на кроці входу рядка акаунта нема");

// Повна подія → черга; між тапами звільнилось місце (EVENT_HAS_SPACE) — записуємо звичайно.
reset();
signIn();
backend({ ...members(), join_waitlist_web: () => failure("EVENT_HAS_SPACE") });
p = page();
await p.ready; await flush();
await p.$("[data-waitlist]").fire("click"); await flush();
assert.deepEqual(calls.slice(calls.indexOf("join_waitlist_web"), calls.indexOf("join_waitlist_web") + 3), ["join_waitlist_web", "join_event_web", "event_details"]);
assert.equal(p.$("[data-title]").textContent, "Ви в списку");

// Запит пройшов, а в списку людини нема — «Не вийшло», а не «Нема звʼязку».
reset();
signIn();
backend({ ...members(), join_event_web: () => [200] });
p = page();
await p.ready; await flush();
await p.bar.fire("click"); await flush();
assert.equal(p.$("[data-error]").hidden, false);
assert.equal(p.$("[data-error]").textContent, "Не вийшло. Спробуйте ще раз.");

// Заявка: повторний візит одразу «Заявку надіслано»; скасування — «Заявку скасовано» і знову «Йду».
reset();
signIn();
backend(members("requested"));
p = page();
await p.ready; await flush();
assert.equal(p.bar.textContent, "Заявку надіслано");
await p.bar.fire("click");
assert.equal(p.$("[data-leave]").textContent, "Скасувати заявку");
await p.$("[data-leave]").fire("click"); await flush();
assert.equal(p.$("[data-title]").textContent, "Заявку скасовано");
assert.equal(p.bar.textContent, "Йду");

// Тап на «Йду», поки повторний візит ще вантажить стан, не губиться, а застаріла відповідь його не перезаписує.
reset();
signIn();
let release;
const slow = new Promise((r) => { release = r; });
let first = true;
const base = members();
backend({ ...base, event_details: () => (first ? (first = false, slow.then(() => [200, [{ membership: "none", attendee_count: 1, capacity: 6 }]])) : base.event_details()) });
p = page();
await p.ready;
await p.bar.fire("click"); await flush();
assert.equal(p.$("[data-title]").textContent, "Ви в списку", "тап спрацював, поки стан ще вантажився");
release(); await flush();
assert.equal(p.bar.textContent, "Ви в списку", "стара відповідь «не записаний» не перезаписала свіжого стану");

// Крок 3: імʼя з пробілів — жодного виклику; дата < 18 (UNDERAGE) — галочки не ставимо; порядок — дата, галочка, імʼя, запис.
reset();
signIn();
backend({ ...members(), join_event_web: () => failure("AGE_REQUIRED"), "/rest/v1/profiles": () => [200, [{ display_name: "Учасник" }]] });
p = page({ minAge: 21 });
await p.ready; await flush();
await p.bar.fire("click"); await flush();
assert.equal(p.step(), "profile");
assert.equal(p.$("[data-birth]").hidden, false);
assert.equal(p.$('[data-form="profile"]').birth.required, true);
assert.equal(p.$('[data-form="profile"]').name.value, "", "«Учасник» людина впише сама");
const form = p.$('[data-form="profile"]');
form.name.value = "   ";
const before = calls.length;
await form.fire("submit");
assert.equal(calls.length, before, "імʼя з пробілів — до бази не йдемо");
assert.equal(p.$("[data-error]").textContent, "Напишіть, як вас звати.");
assert.ok(form.name.focused);
backend({ ...members(), set_birth_date: () => failure("UNDERAGE") });
form.name.value = " Оксана ";
form.birth.value = "2010-01-01";
await form.fire("submit"); await flush();
assert.deepEqual(calls, ["set_birth_date"], "UNDERAGE — confirm_adult не кличемо");
assert.equal(p.$("[data-title]").textContent, "Ця подія для 21+.");
let name = null;
backend({ ...members(), set_birth_date: () => [200], confirm_adult: () => [200], "/rest/v1/profiles": (body) => { name = body.display_name; return [204]; } });
form.birth.value = "1990-01-01";
await form.fire("submit"); await flush();
assert.deepEqual(calls.slice(0, 5), ["set_birth_date", "confirm_adult", "PATCH /rest/v1/profiles", "join_event_web", "event_details"]);
assert.equal(name, "Оксана", "імʼя обрізане");
assert.equal(p.$("[data-title]").textContent, "Ви в списку");

// Хто чим ділиться (1.6). Організатор своєї події після входу — «Поширити анонс» і «Скопіювати посилання».
const { threadsPost, threadsIntent } = await import("../site/js/poriad.js");
const soon = (hours) => new Date(Date.now() + hours * 36e5).toISOString();
const own = { id: ID, membership: "none", attendee_count: 1, capacity: 6, origin: "community", organizer_id: "u1", status: "published",
  title: "Настолки й чай", starts_at: soon(48), ends_at: soon(51), time_zone: "Europe/Kyiv", address: "вул. Велика Васильківська, 72", description: "Граємо." };
const opened = [];
let clipboard = null, shared = null;
for (const name of ["window", "navigator"]) Object.defineProperty(globalThis, name, { value: null, writable: true, configurable: true });
window = { open: (url, target, features) => opened.push([url, target, features]) };
navigator = { userAgent: "test", clipboard: { writeText: async (text) => { clipboard = text; } } };
reset();
signIn();
backend({ event_details: () => [200, [own]], my_waitlist: () => [200, []], create_invite: () => [200, "AbCdEfGhIjKlMnOpQrSt_-"] });
p = page({ share: true });
const original = p.doc["[data-share]"];
await p.ready; await flush();
assert.notEqual(p.doc["[data-share]"], original, "кнопку взяв скрипт — без обробника вбудованого");
assert.equal(p.doc["[data-share]"].lastChild.textContent, "Поширити анонс");
assert.equal(p.doc["[data-copy-link]"].hidden, false);
assert.equal(p.doc["[data-afisha]"].hidden, true, "чотири дії в ряд: «Афішу» організатору ховаємо");
assert.ok(!calls.includes("create_invite"), "організатору запрошення не треба");
await p.doc["[data-share]"].fire("click"); await flush();
assert.deepEqual(opened, [[threadsIntent(threadsPost(own)), "_blank", "noopener"]], "Threads з текстом поста");
assert.equal(clipboard, threadsPost(own), "текст — і в буфер");
assert.ok(clipboard.endsWith(`Запис: poriad.app/e/${ID}`));
assert.equal(p.doc["[data-share]"].lastChild.textContent, "Текст скопійовано");
await p.doc["[data-copy-link]"].fire("click"); await flush();
assert.equal(clipboard, `https://poriad.app/e/${ID}`, "посилання для запису — без ?by=");
assert.equal(p.doc["[data-copy-link]"].lastChild.textContent, "Посилання скопійовано");
// Організатор вийшов — сторінка знову як для гостя.
await p.$("[data-signout]").fire("click"); await flush();
assert.equal(p.doc["[data-share]"].lastChild.textContent, "Поділитися з другом");
assert.equal(p.doc["[data-copy-link]"].hidden, true);
assert.equal(p.doc["[data-afisha]"].hidden, false);

// Гість з входом на чужій події — «Поділитися з другом» з особистим ?by=, без «Скопіювати посилання».
navigator = { userAgent: "test", share: async (data) => { shared = data; } };
reset();
signIn();
backend({ event_details: () => [200, [{ ...own, organizer_id: ORG }]], my_waitlist: () => [200, []], create_invite: () => [200, "AbCdEfGhIjKlMnOpQrSt_-"] });
p = page({ share: true });
await p.ready; await flush();
assert.equal(p.doc["[data-share]"].lastChild.textContent, "Поділитися з другом");
assert.equal(p.doc["[data-copy-link]"].hidden, true);
assert.equal(p.doc["[data-afisha]"].hidden, false);
await p.doc["[data-share]"].fire("click");
assert.equal(shared.url, `https://poriad.app/e/${ID}?by=AbCdEfGhIjKlMnOpQrSt_-`);
// Сервер не дав токена — звичайне посилання: збій лише знеособлює.
backend({ event_details: () => [200, [{ ...own, organizer_id: ORG }]], my_waitlist: () => [200, []], create_invite: () => failure("TOO_MANY_INVITES") });
p = page({ share: true });
await p.ready; await flush();
await p.doc["[data-share]"].fire("click");
assert.equal(shared.url, `https://poriad.app/e/${ID}`);
// Творець «Шукаю компанію» на своєму зборі й організатор скасованої — теж з другом.
for (const event of [{ ...own, companion_of: "b2000000-0000-4000-8000-000000000001" }, { ...own, status: "cancelled" }]) {
  backend({ event_details: () => [200, [event]], my_waitlist: () => [200, []], create_invite: () => [200, "AbCdEfGhIjKlMnOpQrSt_-"] });
  p = page({ share: true });
  await p.ready; await flush();
  assert.equal(p.doc["[data-share]"].lastChild.textContent, "Поділитися з другом");
  assert.equal(p.doc["[data-copy-link]"].hidden, true);
}
// Без входу кнопку лишаємо вбудованому скрипту сторінки: адреса без запрошення.
reset();
backend({ create_invite: () => [200, "AbCdEfGhIjKlMnOpQrSt_-"] });
p = page({ share: true });
const guestButton = p.doc["[data-share]"];
await p.ready; await flush();
assert.equal(p.doc["[data-share]"], guestButton);
assert.ok(!calls.includes("create_invite") && p.doc["[data-copy-link]"].hidden);

console.log("join flow ok");
