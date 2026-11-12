// Кабінет організатора й підказки адрес: node worker/kabinet.test.mjs
import assert from "node:assert/strict";
import worker from "./index.mjs";
import { places, clientKey } from "./kabinet.mjs";
import { env, ctx } from "./fixtures.mjs";
import { readFileSync } from "node:fs";

const directive = (response, name) => response.headers.get("content-security-policy").split("; ").find((d) => d.startsWith(`${name} `));
const store = new Map();
globalThis.caches = { default: { match: async (r) => store.get(r.url)?.clone(), put: async (r, response) => { store.set(r.url, response); } } };

// Сторінка — з Pages тим самим запитом, але зі своєю політикою й без індексації.
let asked = [];
globalThis.fetch = async (request) => { asked.push(request); return new Response("<!doctype html>", { headers: { "content-type": "text/html; charset=utf-8" } }); };
for (const path of ["/kabinet", "/kabinet.html"]) {
  asked = [];
  const page = await worker.fetch(new Request(`https://poriad.app${path}`), env, ctx);
  assert.equal(await page.text(), "<!doctype html>");
  assert.equal(asked.length, 1, path);
  assert.equal(page.headers.get("x-robots-tag"), "noindex, nofollow");
  assert.equal(directive(page, "img-src"), "img-src 'self' data: blob: https://db.invalid/storage/v1/object/public/", "картинки — свої й зі сховища, не будь-який https");
  assert.equal(directive(page, "media-src"), "media-src https://db.invalid/storage/v1/object/public/ blob:", "відео зі сховища й перевірка вибраного");
  assert.equal(directive(page, "connect-src"), "connect-src 'self' https://cloudflareinsights.com https://tiles.openfreemap.org https://db.invalid");
  assert.equal(directive(page, "worker-src"), "worker-src blob:", "мапа");
  assert.equal(directive(page, "script-src"), "script-src 'self' https://static.cloudflareinsights.com");
  assert.ok(!page.headers.get("content-security-policy").includes("unsafe"));
  assert.equal(page.headers.get("x-frame-options"), "DENY");
}
assert.equal((await worker.fetch(new Request("https://poriad.app/kabinet", { method: "POST" }), env, ctx)).status, 405);

// meta-CSP у kabinet.html — друга лінія без воркера: та сама політика, що заголовок prod, плюс dev-проєкт (сайт на
// localhost ходить у dev, а meta й заголовок діють разом), без frame-ancestors (у meta не діє).
const [prod, dev] = [...readFileSync(new URL("./wrangler.toml", import.meta.url), "utf8").matchAll(/SUPABASE_URL = "([^"]+)"/g)].map((m) => m[1]);
const prodPage = await worker.fetch(new Request("https://poriad.app/kabinet"), { ...env, SUPABASE_URL: prod }, ctx);
const expected = prodPage.headers.get("content-security-policy").split("; ").filter((d) => !d.startsWith("frame-ancestors"))
  .map((d) => d.split(" ").flatMap((t) => t.startsWith(prod) ? [t, t.replace(prod, dev)] : [t]).join(" ")).join("; ");
const kabinetHtml = readFileSync(new URL("../site/kabinet.html", import.meta.url), "utf8");
const metaCsp = kabinetHtml.match(/<meta http-equiv="Content-Security-Policy" content="([^"]+)">/)?.[1];
assert.equal(metaCsp, expected, "meta-CSP розійшлася з CSP.kabinet — оновіть kabinet.html");
assert.ok(kabinetHtml.indexOf("Content-Security-Policy") < kabinetHtml.indexOf("<link"), "meta — до стилів і скриптів, інакше їх вона не охопить");
const afisha = await worker.fetch(new Request("https://poriad.app/afisha.html"), env, ctx);
assert.equal(afisha.headers.get("x-robots-tag"), null, "решта сайту індексується як була");

// Підказки адрес: Photon з User-Agent, центр міста форми, кеш на добу за нормалізованим запитом.
const feature = (props, lon = 30.52, lat = 50.45) => ({ properties: { countrycode: "UA", ...props }, geometry: { coordinates: [lon, lat] } });
const photon = [
  feature({ street: "вулиця Хрещатик", housenumber: "22", district: "Центр", city: "Боярка" }),
  feature({ street: "вулиця Хрещатик", housenumber: "22", district: "Центр", city: "Київ" }),
  feature({ name: "Ощадбанк", street: "вулиця Хрещатик", housenumber: "22", district: "Центр", city: "Київ" }),
  feature({ street: "вулиця Хрещатик", housenumber: "22", district: "Центр", city: "Київ" }),
  feature({ name: "Москва", countrycode: "RU", city: "Москва" }),
  feature({ name: "Пекарня Протісто", city: "Київ" }),
  feature({ name: "Академмістечко", street: "вулиця Академіка Єфремова", district: "Академмістечко", city: "Київ" }),
  { properties: { name: "Без точки" } },
];
let calls = [];
globalThis.fetch = async (url, init) => { calls.push({ url: String(url), ua: init?.headers?.["user-agent"] }); return new Response(JSON.stringify({ features: photon })); };
const go = (query, init) => worker.fetch(new Request(`https://poriad.app/api/geocode?${query}`, init), env, ctx);

const first = await go("q=%20%D0%A5%D1%80%D0%B5%D1%89%D0%B0%D1%82%D0%B8%D0%BA%20%2022&city=%D0%9A%D0%B8%D1%97%D0%B2");
assert.equal(first.status, 200);
assert.equal(first.headers.get("cache-control"), "public, max-age=86400");
const list = await first.json();
assert.equal(calls.length, 1);
const sent = new URL(calls[0].url);
assert.equal(sent.origin + sent.pathname, "https://photon.komoot.io/api/");
assert.equal(sent.searchParams.get("q"), "хрещатик 22", "пробіли й регістр — один ключ кешу");
assert.deepEqual([sent.searchParams.get("lat"), sent.searchParams.get("lon")], ["50.4501", "30.5234"], "пріоритет — центр міста форми");
assert.match(calls[0].ua, /^PoriadKabinet\/.+hello@poriad\.app\)$/, "свій User-Agent: блок кабінету не зачепить імпорт (PoriadBot)");
assert.deepEqual(list.map((p) => [p.label, p.detail]), [
  ["вулиця Хрещатик, 22", "Центр, Київ"],
  ["вулиця Хрещатик, 22", "Ощадбанк, Центр, Київ"],
  ["Пекарня Протісто", "Київ"],
  ["вулиця Академіка Єфремова", "Академмістечко, Київ"],
  ["вулиця Хрещатик, 22", "Центр, Боярка"],
], "місто форми першим, без повторів (і в деталях), без виключених країн і рядків без точки");
assert.deepEqual(Object.keys(list[0]), ["label", "detail", "city", "lat", "lon"]);

await go("q=%D1%85%D1%80%D0%B5%D1%89%D0%B0%D1%82%D0%B8%D0%BA+22&city=%D0%9A%D0%B8%D1%97%D0%B2");
assert.equal(calls.length, 1, "той самий запит — з кешу");

for (const bad of ["q=ab&city=%D0%9A%D0%B8%D1%97%D0%B2", "q=%D1%85%D1%80%D0%B5%D1%89&city=Rome", `q=${"x".repeat(101)}&city=%D0%9A%D0%B8%D1%97%D0%B2`, ""]) {
  const response = await go(bad);
  assert.equal(response.status, 400, bad);
  assert.equal(response.headers.get("cache-control"), "no-store");
}
assert.equal(calls.length, 1, "погані параметри до Photon не йдуть");
assert.equal((await go("q=abc&city=%D0%9A%D0%B8%D1%97%D0%B2", { method: "POST" })).status, 405);

globalThis.fetch = async () => new Response("busy", { status: 503 });
const down = await go("q=%D1%81%D0%B0%D0%BA%D1%81%D0%B0%D0%B3%D0%B0%D0%BD%D1%81%D1%8C%D0%BA%D0%BE%D0%B3%D0%BE&city=%D0%9B%D1%8C%D0%B2%D1%96%D0%B2");
assert.deepEqual(await down.json(), [], "Photon ліг — підказок нема, крапку ставлять на мапі");
assert.equal(down.headers.get("cache-control"), "no-store", "збій не кешуємо");
assert.equal([...store.keys()].filter((k) => k.includes("geocode")).length, 1);
assert.equal(places([], "Київ").length, 0);

// Пошук закладу (`kind=venue`): рамка міста, без вулиць і зупинок; назва — підказка, адреса — деталь; свій ключ кешу.
calls = [];
globalThis.fetch = async (url) => { calls.push(String(url)); return new Response(JSON.stringify({ features: photon })); };
const venues = await (await go("q=%D0%BF%D1%80%D0%BE%D1%82%D1%96%D1%81%D1%82%D0%BE&city=%D0%9A%D0%B8%D1%97%D0%B2&kind=venue")).json();
const venueAsk = new URL(calls[0]);
assert.equal(venueAsk.searchParams.get("bbox"), "30.0734,50.1501,30.9734,50.7501");
assert.deepEqual(venueAsk.searchParams.getAll("osm_tag"), ["!highway", "!railway", "!public_transport", "!place", "!boundary", "!landuse"]);
assert.deepEqual(venues.map((p) => [p.label, p.detail]), [
  ["Ощадбанк", "вулиця Хрещатик, 22"], ["Пекарня Протісто", ""], ["Академмістечко", "вулиця Академіка Єфремова"],
], "без назви — не заклад");
await go("q=%D0%BF%D1%80%D0%BE%D1%82%D1%96%D1%81%D1%82%D0%BE&city=%D0%9A%D0%B8%D1%97%D0%B2");
assert.equal(calls.length, 2, "адреса й заклад з тим самим запитом — різні відповіді в кеші");
assert.equal(places([{ properties: { name: "Я".repeat(150), countrycode: "UA" }, geometry: { coordinates: [30, 50] } }], "Київ", true)[0].label.length, 120, "назва в межах add_my_place");

// Ліміт на адресу (GEOCODE_LIMIT): лише запити повз кеш, ключ — cf-connecting-ip; понад ліміт — 429 без Photon.
const keys = [];
const limited = (success) => ({ ...env, GEOCODE_LIMIT: { limit: async ({ key }) => { keys.push(key); return { success }; } } });
calls = [];
globalThis.fetch = async (url) => { calls.push(String(url)); return new Response(JSON.stringify({ features: photon })); };
const ask = (q, environment) => worker.fetch(new Request(`https://poriad.app/api/geocode?${new URLSearchParams({ q, city: "Київ" })}`, { headers: { "cf-connecting-ip": "203.0.113.7" } }), environment, ctx);
const blocked = await ask("нова адреса", limited(false));
assert.equal(blocked.status, 429);
assert.equal(blocked.headers.get("cache-control"), "no-store");
assert.equal(calls.length, 0, "понад ліміт — до komoot не йдемо");
assert.deepEqual(keys, ["203.0.113.7"]);
assert.equal((await ask("хрещатик 22", limited(false))).status, 200, "з кешу — без ліміту");
assert.equal(keys.length, 1, "кеш ліміту не рахує");
assert.equal((await ask("нова адреса", limited(true))).status, 200);
assert.equal(calls.length, 1);

// Загальна стеля (GEOCODE_GLOBAL, ключ "global"): спрацьовує, навіть коли окрема адреса в ліміті.
const both = { ...limited(true), GEOCODE_GLOBAL: { limit: async ({ key }) => { keys.push(key); return { success: false }; } } };
keys.length = 0;
calls = [];
assert.equal((await ask("ще одна адреса", both)).status, 429);
assert.deepEqual(keys, ["203.0.113.7", "global"]);
assert.equal(calls.length, 0);

// Ключ на людину: IPv6 — мережа /64 у повній формі, хоч як записано адресу.
assert.equal(clientKey("203.0.113.7"), "203.0.113.7");
assert.equal(clientKey("2001:db8:abcd:12:1:2:3:4"), "2001:db8:abcd:12::/64");
assert.equal(clientKey("2001:0db8:abcd:0012:ffff::1"), "2001:db8:abcd:12::/64", "та сама /64 з іншою адресою й нулями");
assert.equal(clientKey("2001:db8::1"), "2001:db8:0:0::/64", "стиснення :: — нулі");
assert.equal(clientKey("::1"), "0:0:0:0::/64");
assert.equal(clientKey("::ffff:203.0.113.7"), "::ffff:203.0.113.7", "IPv4 у формі IPv6 — як є");
assert.equal(clientKey(null), "local");
console.log("kabinet ok");
