// Перевірка рендеру без Cloudflare: node worker/test.mjs
import assert from "node:assert/strict";
import worker, { eventPage, eventResponse, esc } from "./index.mjs";

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


// CSP пропускає лише скрипт із цим хешем: правка тексту кнопки «Поділитися» без нового хеша її б вимкнула.
const { createHash } = await import("node:crypto");
const scripts = [...community.matchAll(/<script>([\s\S]*?)<\/script>/g)].map((m) => m[1]);
assert.equal(scripts.length, 1, "один вбудований скрипт");
assert.ok(!/<style|\sstyle=|\son[a-z]+=/i.test(movedAfisha + withShelters + community), "без вбудованих стилів і обробників — їх CSP теж не пустить");
const page = await eventResponse(base.id, { SUPABASE_URL: "https://db.invalid", SUPABASE_KEY: "k" });
assert.ok(page.headers.get("content-security-policy").includes(`'sha256-${createHash("sha256").update(scripts[0]).digest("base64")}'`), "хеш у CSP — від цього скрипта");
assert.equal(page.headers.get("x-frame-options"), "DENY");
assert.equal((await eventResponse("not-a-uuid", {})).headers.get("cache-control"), "public, max-age=60", "404 кешується на хвилину");
globalThis.fetch = async () => new Response("{}", { status: 500 });
assert.equal((await eventResponse(base.id, { SUPABASE_URL: "https://db.invalid", SUPABASE_KEY: "k" })).headers.get("cache-control"), "no-store", "збій бази — без кешу");
console.log("headers ok");

// «Покликати з собою» (docs/invites.md): ?by= персоналізує сторінку, але не спільний кеш.
const token = "AbCdEfGhIjKlMnOpQrSt_-";
const invited = eventPage(base, now, [], { by: token, name: "Тарас <b>" });
assert.ok(invited.includes("<b>Тарас &lt;b&gt;</b> кличе тебе"), "хто кличе — над назвою, екрановано");
assert.ok(invited.includes('property="og:title" content="Тарас &lt;b&gt; кличе тебе: Настолки'), "і в прев'ю месенджера");
assert.ok(invited.includes(`poriad://event/${base.id}?by=${token}`), "«У застосунку» несе токен");
assert.ok(invited.includes(`app-argument=https://poriad.app/e/${base.id}?by=${token}`), "банер Safari теж");
assert.ok(invited.includes("ct=invite") && invited.includes("utm_campaign%3Dinvite") && invited.includes("/app?from=invite"), "завантаження з запрошень — своєю міткою");
assert.ok(invited.includes(`property="og:url" content="https://poriad.app/e/${base.id}"`), "адреса прев'ю — без токена");
assert.ok(!community.includes("кличе тебе") && community.includes("ct=event") && !community.includes("ct=invite"), "звичайна сторінка — як була");

const env = { SUPABASE_URL: "https://db.invalid", SUPABASE_KEY: "k" };
const puts = [];
let calls = [];
globalThis.caches = { default: { match: async () => undefined, put: async (key) => { puts.push(key.url); } } };
const ctx = { waitUntil: (p) => p };
const rpc = (inviter) => async (url, init) => {
  calls.push(url.split("/").pop());
  if (url.endsWith("/invite_inviter")) return new Response(JSON.stringify(inviter), { status: 200 });
  return new Response(url.endsWith("/event_details") ? JSON.stringify([base]) : "{}", { status: 200 });
};
globalThis.fetch = rpc([{ name: "Тарас", avatar_url: null }]);
const personal = await worker.fetch(new Request(`https://poriad.app/e/${base.id}?by=${token}`), env, ctx);
assert.equal(personal.status, 200);
assert.equal(personal.headers.get("cache-control"), "private, max-age=300", "особиста сторінка — не для проміжних кешів");
assert.ok((await personal.text()).includes("кличе тебе"));
assert.equal(puts.length, 0, "особиста сторінка не лягає в кеш краю");

globalThis.fetch = rpc([]);
calls = [];
const stale = await worker.fetch(new Request(`https://poriad.app/e/${base.id}?by=${token}`), env, ctx);
assert.ok(!(await stale.text()).includes("кличе тебе"), "невідомий токен — звичайна сторінка");
assert.equal(stale.headers.get("cache-control"), "public, max-age=300");
assert.deepEqual(puts, [`https://poriad.app/e/${base.id}`], "і вона кешується як звичайна, за шляхом");
calls = [];
await worker.fetch(new Request(`https://poriad.app/e/${base.id}?by=not-a-token`), env, ctx);
assert.ok(!calls.includes("invite_inviter"), "токен не того формату в базу не ходить");
globalThis.fetch = async () => { throw new Error("network"); };
globalThis.caches.default.match = async () => new Response("cached", { status: 200 });
assert.equal(await (await worker.fetch(new Request(`https://poriad.app/e/${base.id}?by=${token}`), env, ctx)).text(), "cached", "збій бази — звичайна сторінка з кешу");

// Злита подія: стара адреса запрошення переїжджає разом з токеном.
globalThis.fetch = rpc([{ name: "Тарас" }]);
const movedInvite = await eventResponse(oldId, env, { by: token, name: "Тарас" });
assert.equal(movedInvite.headers.get("location"), `https://poriad.app/e/${base.id}?by=${token}`);
console.log("invites ok");

// Сторінки міст (/afisha/{місто}[/{розділ}]): лише афіша, лише те, що попереду, готовий HTML з розміткою.
const { cityResponse, cityPage } = await import("./index.mjs");
const cityNow = new Date("2026-10-30T09:00:00Z"); // пт, 12:00 у Києві
const cityIds = ["d4000000-0000-4000-8000-000000000001", "d4000000-0000-4000-8000-000000000002", "d4000000-0000-4000-8000-000000000003",
  "d4000000-0000-4000-8000-000000000004", "d4000000-0000-4000-8000-000000000005"];
const entry = (id, category, startsAt, title, origin = "import") => [id, 50.45, 30.52, category, startsAt, "Europe/Kyiv", title, origin, "Concert.ua", null, 0];
const cityIndex = [
  entry(cityIds[0], "music", "2026-10-30T07:00:00Z", "Ранок, що вже почався"),
  entry(cityIds[1], "comedy", "2026-10-30T16:00:00Z", "СТЕНДАП \"ВЕЧІР\""),
  entry(cityIds[2], "games", "2026-10-30T17:00:00Z", "Настолки від людей", "community"),
  entry(cityIds[3], "music", "2026-10-31T17:00:00Z", "Концерт </script><b>"),
  entry(cityIds[4], "art", "2026-11-01T15:00:00Z", "Вистава"),
];
const cityCards = Object.fromEntries(cityIndex.map(([id, , , category, starts_at, , title, origin]) => [id,
  { id, title, category, starts_at, time_zone: "Europe/Kyiv", city: "Київ", address: "Хрещатик, 1", place_name: "Палац", price_min: 300, canonical_url: "https://concert.ua/x", origin }]));
let discoverBody = null;
globalThis.fetch = async (url, init) => {
  if (url.endsWith("/discover_events")) { discoverBody = JSON.parse(init.body); return new Response(JSON.stringify({ index: cityIndex, cards: [] }), { status: 200 }); }
  if (url.endsWith("/event_cards_by_ids")) return new Response(JSON.stringify(JSON.parse(init.body).p_ids.map((id) => cityCards[id])), { status: 200 });
  return new Response("{}", { status: 404 });
};
const week = await cityResponse("kyiv", "", cityNow);
const weekHtml = await week.text();
assert.equal(week.status, 200);
assert.ok(weekHtml.includes("<h1>Афіша Києва</h1>") && weekHtml.includes("<title>Афіша Києва на тиждень: куди піти — Поряд</title>"));
assert.ok(weekHtml.includes('rel="canonical" href="https://poriad.app/afisha/kyiv"'));
assert.ok(weekHtml.includes('name="robots" content="index, follow"'), "три події — сторінку індексуємо");
assert.ok(!weekHtml.includes("Настолки від людей"), "зустрічі людей — лише за посиланням");
assert.ok(!weekHtml.includes("Ранок, що вже почався"), "те, що почалось, — ні");
assert.ok(weekHtml.includes("Стендап «Вечір»") && weekHtml.includes("18:00 · Стендап · Палац · від 300 ₴"), "назва й час — як у застосунку, у поясі події");
assert.ok(weekHtml.includes(`href="/e/${cityIds[1]}"`), "рядок веде на сторінку події");
const ld = JSON.parse(weekHtml.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/)[1]);
assert.equal(ld.itemListElement.length, 3);
assert.equal(ld.itemListElement[0].item.offers.price, 300);
assert.ok(!weekHtml.includes("</script><b>"), "назва в розмітці не закриває скрипт");
assert.equal(discoverBody.p_cards, 0, "індекс без карток: картки — лише для показаних");

const today = await (await cityResponse("kyiv", "sohodni", cityNow)).text();
assert.ok(today.includes("<h1>Куди піти в Києві сьогодні</h1>") && today.includes("Стендап «Вечір»") && !today.includes("Вистава"));
assert.ok(today.includes('content="noindex, follow"'), "тонку сторінку пошуковику не пропонуємо");
const weekend = await (await cityResponse("kyiv", "vykhidni", cityNow)).text();
assert.ok(weekend.includes("Концерт &lt;/script&gt;&lt;b&gt;") && weekend.includes("Вистава") && !weekend.includes("Стендап «Вечір»"), "вихідні — субота й неділя");
await cityResponse("kyiv", "kontserty", cityNow);
assert.equal(discoverBody.p_category, "music", "категорію фільтрує сервер");
const lviv = cityPage("lviv", "sohodni", [], 0, cityNow);
assert.ok(lviv.includes("Куди піти у Львові сьогодні") && lviv.includes("Тут поки тихо") && lviv.includes('href="/afisha/lviv">Уся афіша Львова'));
assert.ok(community.includes('href="/afisha/kyiv"'), "сторінки подій посилаються на міста");

globalThis.caches = { default: { match: async () => undefined, put: async (key) => { puts.push(key.url); } } };
puts.length = 0;
const go = (path) => worker.fetch(new Request(`https://poriad.app${path}`), env, ctx);
assert.equal((await go("/afisha/kyiv/")).headers.get("location"), "https://poriad.app/afisha/kyiv");
assert.equal((await go("/afisha/")).headers.get("location"), "https://poriad.app/afisha.html");
assert.equal((await go("/afisha/rome")).status, 404);
assert.equal((await go("/afisha/kyiv/constructor")).status, 404, "розділ — лише з переліку");
assert.equal((await go("/afisha/Kyiv/Sohodni")).status, 200);
assert.deepEqual(puts, ["https://poriad.app/afisha/kyiv/sohodni"], "кеш — за шляхом у нижньому регістрі");
globalThis.fetch = async () => new Response("{}", { status: 500 });
const down = await go("/afisha/lviv");
assert.equal(down.status, 503);
assert.equal(down.headers.get("cache-control"), "no-store");
assert.equal(puts.length, 1, "збій бази в кеш не лягає");
console.log("cities ok");
