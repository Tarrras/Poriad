// Сторінки закладу й артиста (/p/{id}, /a/{id}): node worker/profile.test.mjs. Рядок і події — з бази воркера,
// скасоване не показуємо, сторінка лише за посиланням.
import assert from "node:assert/strict";
import worker, { profileResponse } from "./index.mjs";
import { env, ctx } from "./fixtures.mjs";

const now = new Date("2026-10-30T09:00:00Z"); // пт, 12:00 у Києві
const id = "b2000000-0000-4000-8000-000000000001";
const card = (n, extra) => ({ id: `d5000000-0000-4000-8000-00000000000${n}`, title: `Вечір ${n}`, category: "music", starts_at: `2026-10-3${n}T17:00:00Z`,
  time_zone: "Europe/Kyiv", city: "Київ", address: "Хрещатик, 22", place_name: "Кафе <b>", origin: "community", is_free: true, ...extra });
const cards = [card(0, { starts_at: "2026-10-01T07:00:00Z", ends_at: "2026-11-20T17:00:00Z", title: "Виставка" }), card(1), card(2, { status: "cancelled" })];
const calls = [];
let row = [{ id, name: "Кафе <b>", city: "Київ", address: "Хрещатик, 22", latitude: 50.45, longitude: 30.52 }];
globalThis.fetch = async (url, init) => {
  calls.push([url, init.body]);
  return new Response(JSON.stringify(url.includes("/rpc/") ? cards : row), { status: 200 });
};

const page = await profileResponse("p", id, env, now);
const html = await page.text();
assert.equal(page.status, 200);
assert.deepEqual(calls.map(([url]) => url.replace(env.SUPABASE_URL, "")),
  [`/rest/v1/places?id=eq.${id}&select=id,name,city,address,latitude,longitude,slug`, "/rest/v1/rpc/place_events"]);
assert.ok(html.includes(`property="og:url" content="https://poriad.app/p/${id}"`), "без короткої адреси — id");
assert.equal(calls[1][1], JSON.stringify({ p_place_id: id }));
assert.ok(html.includes("<h1>Кафе &lt;b&gt;</h1>") && html.includes("Заклад · Київ") && !html.includes("<b>\""), "назва екранована");
assert.ok(html.includes("Київ, Хрещатик, 22. 2 події попереду."), "скасоване не рахуємо");
assert.ok(html.includes("<h2>Сьогодні</h2>") && html.includes("Виставка"), "те, що триває, — під «Сьогодні»");
assert.ok(html.includes("20:00 · Музика · Безкоштовно") || html.includes("19:00 · Музика · Безкоштовно"), "у рядку закладу назву закладу не повторюємо");
assert.ok(html.includes('content="noindex, follow"') && html.includes("ct=place&") && html.includes('href="/app?from=place"'));
assert.ok(html.includes('href="/afisha/kyiv"') && html.includes("destination=50.45,30.52") && html.includes("data-share"));

row = [{ id, name: "Гурт Тест", kind: "group" }];
calls.length = 0;
const artist = await (await profileResponse("a", id, env, now)).text();
assert.equal(calls[1][1], JSON.stringify({ p_artist_id: id }));
assert.ok(artist.includes('<p class="overline">Гурт</p>') && artist.includes("· Кафе &lt;b&gt; ·") && !artist.includes("Маршрут"), "в артиста рядок каже, де");

// Коротка адреса: рядок шукаємо за slug, події — за його id; адреса сторінки — коротка.
row = [{ id, name: "Гурт Тест", kind: "group", slug: "hurt-test" }];
calls.length = 0;
const short = await (await profileResponse("a", "Hurt-Test", env, now)).text();
assert.equal(calls[0][0], `${env.SUPABASE_URL}/rest/v1/artists?slug=eq.hurt-test&select=id,name,kind,slug`);
assert.equal(calls[1][1], JSON.stringify({ p_artist_id: id }));
assert.ok(short.includes('property="og:url" content="https://poriad.app/a/hurt-test"'));

row = [];
assert.equal((await profileResponse("p", id, env, now)).status, 404);
assert.equal((await profileResponse("p", "nema-takoho", env, now)).status, 404);
for (const junk of ["x", "ab", "-abc", "abc-", "a_b", "кафе", "a".repeat(33), "a&select=*", `${id}x`]) {
  calls.length = 0;
  assert.equal((await profileResponse("a", junk, env, now)).status, 404, junk);
  assert.equal(calls.length, 0, `«${junk}» — у базу не ходимо`);
}

const puts = [];
globalThis.caches = { default: { match: async () => undefined, put: async (key) => { puts.push(key.url); } } };
const go = (path, init) => worker.fetch(new Request(`https://poriad.app${path}`, init), env, ctx);
row = [{ id, name: "Гурт Тест", kind: null }];
assert.equal((await go(`/a/${id.toUpperCase()}/`)).status, 200);
assert.equal((await go("/a/Hurt-Test")).status, 200);
assert.deepEqual(puts, [`https://poriad.app/a/${id}`, "https://poriad.app/a/hurt-test"], "кеш — за шляхом у нижньому регістрі, без риски");
assert.equal((await go(`/p/${id}`, { method: "POST" })).status, 405);
globalThis.fetch = async () => new Response("{}", { status: 500 });
const down = await go(`/p/${id}`);
assert.equal(down.status, 503);
assert.equal(down.headers.get("cache-control"), "no-store");
console.log("profile ok");
