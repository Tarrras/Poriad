// Сторінки міст (/afisha/{місто}[/{розділ}]): node worker/cities.test.mjs. Лише афіша, лише те, що попереду, готовий
// HTML з розміткою.
import assert from "node:assert/strict";
import worker, { cityResponse, cityPage, eventPage } from "./index.mjs";
import { base, now, env, ctx } from "./fixtures.mjs";

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
  { id, title, category, starts_at, time_zone: "Europe/Kyiv", city: "Київ", address: "Хрещатик, 1", place_name: "Палац", price_min: 300, canonical_url: "https://concert.ua/x", image_url: "https://storage.concert.ua/p.jpg", origin }]));
let discoverBody = null;
const urls = [];
globalThis.fetch = async (url, init) => {
  urls.push(url);
  if (url.endsWith("/discover_events")) { discoverBody = JSON.parse(init.body); return new Response(JSON.stringify({ index: cityIndex, cards: [] }), { status: 200 }); }
  if (url.endsWith("/event_cards_by_ids")) return new Response(JSON.stringify(JSON.parse(init.body).p_ids.map((id) => cityCards[id])), { status: 200 });
  return new Response("{}", { status: 404 });
};
const week = await cityResponse("kyiv", "", env, cityNow);
const weekHtml = await week.text();
assert.equal(week.status, 200);
assert.ok(urls.length === 2 && urls.every((url) => url.startsWith(`${env.SUPABASE_URL}/rest/v1/rpc/`)), "база — з env воркера (dev чи prod), а не prod із poriad.js");
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
assert.ok(!ld.itemListElement.some(({ item }) => "image" in item), "постер продавця в розмітку для Google не віддаємо");
assert.ok(!weekHtml.includes("</script><b>"), "назва в розмітці не закриває скрипт");
assert.equal(discoverBody.p_cards, 0, "індекс без карток: картки — лише для показаних");

const today = await (await cityResponse("kyiv", "sohodni", env, cityNow)).text();
assert.ok(today.includes("<h1>Куди піти в Києві сьогодні</h1>") && today.includes("Стендап «Вечір»") && !today.includes("Вистава"));
assert.ok(today.includes('content="noindex, follow"'), "тонку сторінку пошуковику не пропонуємо");
const weekend = await (await cityResponse("kyiv", "vykhidni", env, cityNow)).text();
assert.ok(weekend.includes("Концерт &lt;/script&gt;&lt;b&gt;") && weekend.includes("Вистава") && !weekend.includes("Стендап «Вечір»"), "вихідні — субота й неділя");
await cityResponse("kyiv", "kontserty", env, cityNow);
assert.equal(discoverBody.p_category, "music", "категорію фільтрує сервер");
const lviv = cityPage("lviv", "sohodni", [], 0, cityNow);
assert.ok(lviv.includes("Куди піти у Львові сьогодні") && lviv.includes("Тут поки тихо") && lviv.includes('href="/afisha/lviv">Афіша Львова'));
assert.ok(eventPage(base, now).includes('href="/afisha/kyiv"'), "сторінки подій посилаються на міста");

const puts = [];
globalThis.caches = { default: { match: async () => undefined, put: async (key) => { puts.push(key.url); } } };
const go = (path) => worker.fetch(new Request(`https://poriad.app${path}`), env, ctx);
assert.equal((await go("/afisha/kyiv/")).headers.get("location"), "https://poriad.app/afisha/kyiv");
assert.equal((await go("/afisha/")).headers.get("location"), "https://poriad.app/afisha.html");
assert.equal((await go("/afisha/rome")).status, 404);
assert.equal((await go("/afisha/kyiv/constructor")).status, 404, "розділ — лише з переліку");
assert.equal((await go("/afisha/Kyiv/Sohodni")).status, 200);
assert.deepEqual(puts, ["https://poriad.app/afisha/kyiv/sohodni"], "кеш — за шляхом у нижньому регістрі");
assert.ok(weekHtml.includes("ct=city&") && weekHtml.includes('utm_campaign%3Dcity"') && weekHtml.includes('href="/app?from=city"'), "без мітки — city");
const cachedPage = () => new Response(weekHtml, { status: 200, headers: { "content-type": "text/html; charset=utf-8", "content-length": "1" } });
globalThis.caches.default.match = async () => cachedPage();
const labeled = await (await go("/afisha/lviv/vykhidni?from=mlvmapa")).text();
assert.ok(!labeled.includes("ct=city") && !labeled.includes("%3Dcity") && !labeled.includes("from=city"), "мітка реклами — в усіх кнопках");
assert.equal(labeled.split("ct=mlvmapa&").length - 1, 2, "смуга Safari й кнопка App Store");
assert.ok(labeled.includes('utm_campaign%3Dmlvmapa"') && labeled.includes('href="/app?from=mlvmapa"'));
for (const junk of ["MLV", "a-b", "x".repeat(13), "<b>", ""]) assert.equal(await (await go(`/afisha/lviv?from=${encodeURIComponent(junk)}`)).text(), weekHtml, `мітка «${junk}» не проходить`);
assert.equal(puts.length, 1, "сторінка з кешу в кеш не лягає вдруге");
globalThis.caches.default.match = async () => undefined;
globalThis.fetch = async () => new Response("{}", { status: 500 });
const down = await go("/afisha/lviv");
assert.equal(down.status, 503);
assert.equal(down.headers.get("cache-control"), "no-store");
assert.equal(puts.length, 1, "збій бази в кеш не лягає");
console.log("cities ok");
