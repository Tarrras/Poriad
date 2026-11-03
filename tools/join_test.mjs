// Правила шторки «Йду» (site/js/join.js) без браузера: node tools/join_test.mjs
import assert from "node:assert/strict";
import { outcome, STATUS, STAMPS, ageLimit, needsBirthDate, weekPool, weekPicks, weekRow, shareMode, unfollowTitle, statusKind, bubble } from "../site/js/join.js";

// Таблиця «Інші відповіді на запис» (docs/organizers-1.5.md, 1.1).
for (const [code, kind] of [
  ["AGE_REQUIRED", "profile"], ["EVENT_FULL", "full"], ["EVENT_STARTED", "closed"], ["EVENT_CANCELLED", "closed"],
  ["TOO_YOUNG", "age"], ["TOO_OLD", "age"], ["BLOCKED", "denied"], ["ACCOUNT_RESTRICTED", "denied"], ["session_expired", "start"],
]) assert.equal(outcome(code), kind, code);
assert.equal(outcome("boom"), null, "невідоме — текстом помилки");
assert.equal(outcome(undefined), null, "збій мережі — теж");
for (const code of ["EVENT_FULL", "EVENT_STARTED", "TOO_YOUNG", "BLOCKED", "TOO_MANY_JOINS", "ORGANIZER_CANNOT_JOIN"]) assert.ok(STATUS[outcome(code)], code);
assert.equal(STATUS.full.title + ". " + STATUS.full.text, "Місць уже нема. Якщо хтось відмовиться, напишемо.");
assert.equal(STATUS.closed.title, "Запис на цю подію закрито.");
assert.equal(STATUS.denied.title, "Записатися не вийшло.");
assert.equal(STATUS.requested.text, "Відповідь організатора прийде на пошту.");
assert.ok(STATUS.approved.ics && STATUS.approved.leave === "Скасувати запис" && STATUS.requested.leave === "Скасувати заявку");
assert.deepEqual([STATUS.left.title, STATUS.withdrawn.title, STATUS.unqueued.title], ["Запис скасовано", "Заявку скасовано", "Ви вийшли з черги"]);
assert.ok(STATUS.full.week && STATUS.waitlist.week && !STATUS.approved.week, "«Цього тижня» — лише коли місць нема");
assert.ok(!STATUS.closed.after && STATUS.approved.after && STATUS.full.after, "«Після запису» — після «Йду» чи коли місць нема");

assert.equal(ageLimit(21, 0), "Ця подія для 21+.");
assert.equal(ageLimit(0, 35), "Ця подія для 18–35.");
assert.equal(ageLimit(25, 40), "Ця подія для 25–40.");
assert.ok(!needsBirthDate(18, 0) && !needsBirthDate(undefined, undefined) && !needsBirthDate("18", ""), "18+ — галочки досить");
assert.ok(needsBirthDate("19", "") && needsBirthDate(0, "35"), "від 19 чи верхня межа — дата");

// «Цього тижня»: попереду, без цієї події, згорнуто, спершу зустрічі людей.
const now = Date.parse("2026-10-08T12:00:00Z");
const entry = (id, startsAt, origin = "import", title = id) => ({ id, startsAt, origin, title, tz: "Europe/Kyiv", lat: 50.45, lng: 30.52 });
const index = [
  entry("past", "2026-10-08T10:00:00Z"), entry("self", "2026-10-08T15:00:00Z", "community"),
  entry("gig", "2026-10-08T16:00:00Z", "import", "Концерт"), entry("gig2", "2026-10-09T16:00:00Z", "import", "Концерт"),
  entry("club", "2026-10-10T16:00:00Z", "community"),
];
assert.deepEqual(weekPool(index, "self", now), ["club", "gig"], "минуле й ця подія — геть, сеанси згорнуто, люди першими");

const card = (id, extra = {}) => ({ id, title: id, starts_at: "2026-10-09T16:00:00Z", time_zone: "Europe/Kyiv", origin: "import", category: "music", ...extra });
const picks = weekPicks([
  card("a", { starts_at: "2026-10-09T18:00:00Z" }), card("b", { origin: "community", organizer_name: "Олена" }),
  card("c", { origin: "community", organizer_name: "Інший клуб", starts_at: "2026-10-12T16:00:00Z" }),
  card("d", { status: "cancelled" }), card("e", { state: "postponed" }), card("f", { import_status: "withdrawn" }),
  card("self"), card("old", { starts_at: "2026-10-01T16:00:00Z" }), card("g", { starts_at: "2026-10-09T17:00:00Z" }), card("h"),
], { id: "self", organizer: "Олена", now });
assert.deepEqual(picks.map((c) => c.id), ["c", "h", "g"], "три: інші організатори першими, далі афіша за часом; без скасованого й свого");

const row = weekRow(card("x\"><img>", { title: "КОНЦЕРТ <b>", place_name: "Атлас", is_free: true }), new Date(now));
assert.ok(row.includes('href="/e/x&quot;&gt;&lt;img&gt;"') && row.includes("<b>КОНЦЕРТ &lt;b&gt;</b>"), "id і назва екрановані");
assert.ok(row.includes("19:00 · Музика · Атлас · Безкоштовно"), "час у поясі події, жанр, місце, ціна");
assert.ok(weekRow(card("y", { origin: "community" }), new Date(now)).includes("Від людей"));

// Хто чим ділиться (1.6) — та сама умова, що ShareRules.mode у застосунку.
const at = Date.parse("2026-11-02T12:00:00Z");
const mine = { origin: "community", organizer_id: "me", status: "published", starts_at: "2026-11-04T17:00:00Z", ends_at: "2026-11-04T20:00:00Z" };
assert.equal(shareMode(mine, "me", at), "promote", "організатор своєї події");
assert.equal(shareMode(mine, null, at), "friend", "гість");
assert.equal(shareMode(mine, "other", at), "friend", "інший акаунт");
assert.equal(shareMode({ ...mine, companion_of: "x" }, "me", at), "friend", "творець «Шукаю компанію»");
assert.equal(shareMode({ ...mine, status: "cancelled" }, "me", at), "friend", "скасована");
assert.equal(shareMode(mine, "me", Date.parse("2026-11-04T20:00:00Z")), "friend", "завершилась — кінець уже настав");
assert.equal(shareMode(mine, "me", Date.parse("2026-11-04T18:00:00Z")), "promote", "триває — ще можна кликати");
assert.equal(shareMode({ ...mine, ends_at: null }, "me", at), "promote", "без кінця — не завершена");
assert.equal(shareMode({ ...mine, origin: "import", organizer_id: null }, "me", at), "friend", "афіша");
assert.equal(shareMode(null, "me", at), "friend");

assert.equal(unfollowTitle("Марта"), "Не стежити за організатором Марта?", "імʼя прикладкою — без відмінювання");
assert.equal(unfollowTitle(""), "Не стежити за організатором?");
assert.ok(STATUS.unfollowAsk.unfollow && !STATUS.unfollowed.unfollow, "кнопка підтвердження — лише в питанні");

// Оплата онлайн (docs/organizer-events.md): заявка — «Чекає оплати», з розмовою й застереженням.
assert.equal(statusKind("requested", true), "requestedPay");
assert.equal(statusKind("requested", false), "requested");
assert.equal(statusKind("approved", true), "approved");
assert.equal(STATUS.requestedPay.title, "Чекає оплати");
assert.ok(STATUS.requestedPay.text.includes("не відповідає за неї") && STATUS.requestedPay.ask && STATUS.requestedPay.leave);
assert.deepEqual(STAMPS.requestedPay, ["Оплата", "accent"]);
assert.ok(STATUS.approved.ask && STATUS.waitlist.ask && !STATUS.closed.ask, "розмова — тим, хто записався");

// Повідомлення: текст лише текстом; під чужими реквізитами — застереження й скарга, під своїми — ні.
const msg = { id: "m1", author_id: "org", author_name: "Олена", body: "Картка 4111 <b>1111</b>\nhttps://evil.example", created_at: "2026-11-03T10:00:00Z", payment_details: true };
const theirs = bubble(msg, "me", "org", new Date("2026-11-03T12:00:00Z"));
assert.ok(theirs.startsWith('<div class="msg" data-id="m1"><small>Організатор · 12:00</small>'), "час за Києвом, сьогодні — без дати");
assert.ok(theirs.includes("&lt;b&gt;1111&lt;/b&gt;") && !theirs.includes("<a "), "без розмітки й посилань");
assert.ok(theirs.includes("«Поряд» не приймає оплату й не відповідає за неї") && theirs.includes('data-report="m1"'));
const own = bubble({ ...msg, author_id: "me" }, "me", "org", new Date("2026-11-05T12:00:00Z"));
assert.ok(own.startsWith('<div class="msg mine" data-id="m1"><small>Ви · 3 лист') && !own.includes("pay-warn"), "своє — без застереження, інший день — з датою");
assert.ok(!bubble({ ...msg, payment_details: false }, "me", "org").includes("pay-warn"));
// Скріншот оплати: лише шлях у data-атрибуті (src — з токеном, blob:), без прямого посилання на сховище.
const shot = bubble({ ...msg, author_id: "me", payment_details: false, image: "me/e1/f.jpg", body: "Скріншот оплати" }, "me", "org");
assert.ok(shot.includes('<button class="proof" type="button" data-proof-open><img alt="Скріншот оплати" data-proof-path="me/e1/f.jpg"></button>'));
assert.ok(!shot.includes("src=") && !shot.includes("storage/v1"));
assert.ok(!bubble({ ...msg, image: null }, "me", "org").includes("data-proof"));

console.log("join rules ok");
