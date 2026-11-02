// Сторінка події без Cloudflare: node worker/event.test.mjs
import assert from "node:assert/strict";
import { eventPage, eventResponse, esc } from "./index.mjs";
import { base, now, shelters, env, detailsOk } from "./fixtures.mjs";

const community = eventPage(base, now);
assert.ok(!community.includes("<script>alert"), "назва екранується");
assert.ok(community.includes("<small>Учасники</small><span data-spots>5 з 8</span>"), "місця — під міткою, як ціна: поруч коротке «Йду»");
assert.ok(community.includes("19:00"), "час у зоні події, а не UTC");
assert.ok(!community.includes('src="javascript:'), "лише https-зображення");
assert.ok(community.includes('content="https://poriad.app/img/og.png"'), "запасне прев'ю");
assert.ok(community.includes("poriad://event/a1000000-0000-4000-8000-000000000005"));
assert.ok(community.includes('name="robots" content="noindex"'));

const imported = eventPage({ ...base, origin: "import", canonical_url: "https://concert.ua/x", source_name: "Concert.ua", price_min: 450.4, organizer_name: "Concert.ua" }, now);
assert.ok(imported.includes('rel="canonical" href="https://concert.ua/x"'));
assert.ok(imported.includes('class="btn primary" href="https://concert.ua/x?utm_source=poriad"'), "кнопка квитків — з міткою, canonical — без");
assert.ok(imported.includes("від 450 ₴"));
assert.ok(!imported.includes("Учасників"), "в імпорті місць нема");

// Ціна від людей (1.7): точна, поруч з учасниками й з «Оплата — напряму організатору»; на панелі — ціна.
const priced = eventPage({ ...base, price_min: 1500 }, now);
assert.ok(priced.includes("<b data-spots>5 з 8</b>"), "учасники лишаються фактом");
assert.ok(priced.includes("<span class=\"overline\">Ціна</span><b>1\u00a0500 ₴</b><small>Оплата — напряму організатору</small>"));
assert.ok(priced.includes("<small>Ціна</small><span>1\u00a0500 ₴</span>"), "на панелі — ціна");
assert.ok(!priced.includes("від 1"), "від людей — без «від»");
assert.ok(!community.includes("Оплата — напряму"), "безкоштовна — без ціни");

const withShelters = eventPage(base, now, shelters);
assert.ok(withShelters.includes("Укриття поруч") && withShelters.includes("Метро · 66 м · Є пандус"));
assert.ok(!withShelters.includes("<b>»"), "адреса укриття екранується");
assert.ok(!eventPage(base, now).includes("Укриття поруч"), "без даних секції нема");
assert.ok(!eventPage({ ...base, status: "cancelled" }, now, shelters).includes("Укриття поруч"), "скасованій — ні");
assert.ok(eventPage({ ...base, status: "cancelled" }, now).includes("Подію скасовано."));
assert.ok(eventPage(base, new Date("2026-10-05T00:00:00Z")).includes("вже минула"));
const companion = eventPage({ ...base, title: "Йдемо разом: Концерт", companion_of: "b2000000-0000-4000-8000-000000000001", companion_of_title: "Концерт <b>" }, now);
assert.ok(companion.includes('Разом на: <a href="/e/b2000000-0000-4000-8000-000000000001">Концерт &lt;b&gt;</a>'), "супутник веде на афішу");
assert.ok(!eventPage({ ...base, companion_of: "javascript:alert(1)" }, now).includes("Разом на"), "лише uuid у href");
assert.ok(!community.includes("Разом на"), "звичайна подія без рядка");
assert.ok(eventPage({ ...base, title: "СТЕНДАП \"ПЕРЕВІРКА\"" }, now).includes("<h1>Стендап «Перевірка»</h1>"), "назва — як у застосунку");
assert.ok(imported.includes("Квитки на Concert.ua"), "головна дія афіші — квитки в джерела");
assert.ok(community.includes("data-join>Йду</button>") && !community.includes("Приєднатися в застосунку"), "зустріч людей — запис просто на сторінці (1.5)");
// База без фази 4: знята — «не знайшли в продажу», без тривоги й без кнопки квитків.
const withdrawn = eventPage({ ...base, origin: "import", canonical_url: "https://concert.ua/x", source_name: "Concert.ua", import_status: "withdrawn" }, now, shelters);
assert.ok(withdrawn.includes('class="notice calm">Не знайшли в продажу'), "знята з афіші — нейтрально");
assert.ok(!withdrawn.includes("Квитки на"), "і без кнопки квитків");
assert.ok(!withdrawn.includes("Укриття поруч"), "і без укриттів");
assert.ok(withdrawn.includes("<h2>Якщо купили квиток</h2>") && withdrawn.includes('href="https://concert.ua/x"'), "куди по повернення");

// Фаза 4: стан і всі продавці (docs/event-offers.md R11).
const afisha = { ...base, origin: "import", canonical_url: "https://concert.ua/x", source_name: "Concert.ua", price_min: 400, import_status: "live" };
const offers = [
  { source: "Concert.ua", url: "https://concert.ua/x", price_min: 400, live: true },
  { source: "Karabas <b>", url: "https://karabas.com/y", price_min: 450, live: true },
  { source: "Badseller", url: "https://badseller.net/z", price_min: 300, live: false },
  { source: "Http", url: "http://evil.example/", live: true },
];
const many = eventPage({ ...afisha, state: "scheduled", offers, checked_at: "2026-09-28T06:00:00Z" }, now);
assert.ok(many.includes('<span class="overline">Джерело</span><b>Concert.ua, Karabas &lt;b&gt;</b>'), "джерело на квитку — усі живі продавці, екрановано");
assert.ok(many.includes("<h2>Квитки</h2>") && many.includes("від 450 ₴") && many.includes('href="https://karabas.com/y?utm_source=poriad"'), "рядок і ціна кожного, з міткою для продавця");
assert.ok(!many.includes("badseller.net") && !many.includes("evil.example"), "знятий продавець і не-https — без рядка");
assert.ok(many.includes("Перевірено пн, 28 вересня о 09:00."), "перевірено — датою в поясі події");
assert.ok(many.includes("Квитки на Concert.ua"), "головна кнопка — основний продавець");
const cancelledAfisha = eventPage({ ...afisha, state: "cancelled", offers }, now, shelters);
assert.ok(cancelledAfisha.includes('class="notice">Подію скасовано: продавець'), "скасована — червоним, з поясненням");
assert.ok(cancelledAfisha.includes("<h2>Якщо купили квиток</h2>") && cancelledAfisha.includes("badseller.net"), "повернення — у кожного, де могли купити");
assert.ok(!cancelledAfisha.includes("Квитки на") && !cancelledAfisha.includes("від 450"), "без кнопки й цін");
assert.ok(eventPage({ ...afisha, state: "postponed", offers }, now).includes("Подію відкладено, нової дати ще нема"));
const movedAfisha = eventPage({ ...afisha, state: "scheduled", previous_starts_at: "2026-10-03T16:00:00Z", offers }, now);
assert.ok(movedAfisha.includes('class="notice calm">Перенесено: було сб, 3 жовтня о 19:00.'), "перенесена — стара дата, без тривоги");
assert.ok(movedAfisha.includes("Квитки на Concert.ua"), "перенесена жива — з квитками");
assert.ok(!eventPage({ ...afisha, state: "cancelled" }, new Date("2026-10-05T00:00:00Z")).includes("Якщо купили"), "минула — без продавців");
assert.ok(!community.includes("<h2>Квитки</h2>"), "кімната людей — без продавців");
assert.equal(esc(`"'<&>`), "&quot;&#39;&lt;&amp;&gt;");

// Старий id злитої події: 301 на живу, а не друга копія сторінки.
globalThis.fetch = detailsOk;
const moved = await eventResponse("c3000000-0000-4000-8000-000000000001", env);
assert.equal(moved.status, 301);
assert.equal(moved.headers.get("location"), `https://poriad.app/e/${base.id}`);
assert.equal((await eventResponse(base.id, env)).status, 200, "живий id — сторінка");
console.log("event ok");
