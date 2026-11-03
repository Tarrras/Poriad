// Таблиця маршрутів: що воркер віддає сам, а що бере з Pages. node worker/routes.test.mjs
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import worker from "./index.mjs";
import { base, env, ctx, detailsOk } from "./fixtures.mjs";

let passed = [];
const pagesFetch = async (request) => { passed.push(request); return new Response("pages", { headers: { "content-type": "text/plain" } }); };
globalThis.caches = { default: { match: async () => undefined, put: async () => {} } };
const go = (path, init) => worker.fetch(new Request(`https://poriad.app${path}`, init), env, ctx);

globalThis.fetch = pagesFetch;
const apple = await (await go("/.well-known/apple-app-site-association")).json();
assert.deepEqual(apple.applinks.details[0].appIDs, ["QTYQMJ94D2.app.poriad.ios"]);
assert.deepEqual(apple.applinks.details[0].components, [{ "/": "/e/*" }]);
const android = await (await go("/.well-known/assetlinks.json")).json();
assert.equal(android[0].target.package_name, "app.poriad.android");
assert.equal(passed.length, 0, "файли застосунків воркер віддає сам");

assert.equal((await go(`/e/${base.id}`, { method: "POST" })).status, 405);
assert.equal((await go("/afisha/kyiv", { method: "POST" })).status, 405);
assert.equal(passed.length, 0);

// Решта — на Pages тим самим запитом: метод, шлях і заголовки не міняються, а запит у власну зону йде на origin.
for (const path of ["/", "/afisha.html", "/afisha", "/app?from=event", "/e/x/y", "/js/poriad.js?v=14", "/kabinet"]) {
  passed = [];
  const request = new Request(`https://poriad.app${path}`, { headers: { "if-none-match": '"x"' } });
  assert.equal(await (await worker.fetch(request, env, ctx)).text(), "pages", path);
  assert.equal(passed.length, 1, path);
  assert.equal(passed[0], request, `${path} — той самий запит`);
}
passed = [];
await go("/", { method: "POST" });
assert.equal(passed[0].method, "POST", "що робити з POST на сторінку, вирішує Pages");

globalThis.fetch = detailsOk;
assert.equal((await go(`/e/${base.id}/`)).status, 200, "сторінка події й зі скісною рискою");

// wrangler dev --env dev: сторінки — з локальної теки site/ (assets), а не з інтернету.
passed = [];
globalThis.fetch = async () => { throw new Error("у dev не ходимо на prod-сайт"); };
const dev = { ...env, ASSETS: { fetch: pagesFetch } };
assert.equal(await (await worker.fetch(new Request("http://localhost:8787/afisha.html"), dev, ctx)).text(), "pages");
assert.equal(passed.length, 1);

// Маршрути wrangler.toml (prod): кожна сторінка сайту, з рядком запиту теж (?fbclid з Threads та Instagram, utm з
// реклами), іде через воркер, інакше лишиться без CSP. Зіставлення — як у Cloudflare (docs: Routes, Matching behavior):
// шаблон без * — уся адреса разом із запитом, * у кінці — будь-яке продовження.
const toml = readFileSync(new URL("./wrangler.toml", import.meta.url), "utf8").split("[env.")[0];
const patterns = [...toml.matchAll(/pattern = "([^"]+)"/g)].map((m) => m[1]);
const routed = (url) => patterns.some((p) => p.endsWith("*") ? url.startsWith(p.slice(0, -1)) : url === p);
const pages = readdirSync(new URL("../site/", import.meta.url)).filter((f) => f.endsWith(".html")).map((f) => f.slice(0, -5));
assert.ok(pages.includes("index") && pages.includes("afisha"));
for (const page of pages) {
  const forms = [`/${page}.html`, `/${page}`, ...(page === "index" ? ["/"] : [])];
  for (const path of forms.flatMap((f) => [f, `${f}?fbclid=x`])) assert.ok(routed(`poriad.app${path}`), `site/${page}.html: ${path} без маршруту — без CSP`);
}
for (const path of ["/e/a1000000-0000-4000-8000-000000000005?by=x", "/afisha/kyiv", "/.well-known/assetlinks.json", "/kabinet", "/kabinet.html?fbclid=x"]) assert.ok(routed(`poriad.app${path}`), path);
console.log("routes ok");
