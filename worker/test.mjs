// Перевірка рендеру без Cloudflare: node worker/test.mjs
import assert from "node:assert/strict";
import { eventPage, eventResponse, esc } from "./index.mjs";

const now = new Date("2026-09-28T12:00:00Z");
const base = {
  id: "a1000000-0000-4000-8000-000000000005", title: "Настолки <script>alert(1)</script>", description: "Рядок 1\nРядок 2",
  city: "Київ", address: "Хрещатик, 22", latitude: 50.45, longitude: 30.52, starts_at: "2026-10-04T16:00:00Z",
  ends_at: "2026-10-04T19:00:00Z", time_zone: "Europe/Kyiv", status: "published", origin: "community",
  capacity: 8, attendee_count: 5, organizer_name: "Олена", image_url: "javascript:alert(1)", approval_required: true,
};

const community = eventPage(base, now);
assert.ok(!community.includes("<script>alert"), "назва екранується");
assert.ok(community.includes("Учасників: 5 з 8"));
assert.ok(community.includes("19:00"), "час у зоні події, а не UTC");
assert.ok(!community.includes('src="javascript:'), "лише https-зображення");
assert.ok(community.includes('content="https://poriad.app/img/og.png"'), "запасне прев'ю");
assert.ok(community.includes("poriad://event/a1000000-0000-4000-8000-000000000005"));
assert.ok(community.includes('name="robots" content="noindex"'));

const imported = eventPage({ ...base, origin: "import", canonical_url: "https://concert.ua/x", source_name: "Concert.ua", price_min: 450.4, organizer_name: "Concert.ua" }, now);
assert.ok(imported.includes('rel="canonical" href="https://concert.ua/x"'));
assert.ok(imported.includes("від 450 ₴"));
assert.ok(!imported.includes("Учасників"), "в імпорті місць нема");

const shelters = [{ kind: "metro", address: "ст. м. «Контрактова <b>»", distance_m: 66, accessible: true, hours: null, latitude: 50.46, longitude: 30.51 }];
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
assert.ok(community.includes('href="/app?from=event">Приєднатися в застосунку'), "кімната людей — у застосунок");
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
assert.ok(many.includes("Афіша · Concert.ua, Karabas &lt;b&gt;"), "підпис — усі живі продавці, екрановано");
assert.ok(many.includes("<h2>Квитки</h2>") && many.includes("від 450 ₴") && many.includes('href="https://karabas.com/y"'), "рядок і ціна кожного");
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
console.log("ok");

// Старий id злитої події: 301 на живу, а не друга копія сторінки.
const oldId = "c3000000-0000-4000-8000-000000000001";
globalThis.fetch = async (url) => new Response(url.endsWith("/event_details") ? JSON.stringify([base]) : "{}", { status: 200 });
const moved = await eventResponse(oldId, { SUPABASE_URL: "https://db.invalid", SUPABASE_KEY: "k" });
assert.equal(moved.status, 301);
assert.equal(moved.headers.get("location"), `https://poriad.app/e/${base.id}`);
assert.equal((await eventResponse(base.id, { SUPABASE_URL: "https://db.invalid", SUPABASE_KEY: "k" })).status, 200, "живий id — сторінка");

