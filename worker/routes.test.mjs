// Таблиця маршрутів: що воркер віддає сам, а що бере з Pages. node worker/routes.test.mjs
import assert from "node:assert/strict";
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
for (const path of ["/", "/afisha.html", "/afisha", "/app?from=event", "/e/x/y", "/js/poriad.js?v=12", "/kabinet"]) {
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
console.log("routes ok");
