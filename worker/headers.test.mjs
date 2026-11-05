// Заголовки безпеки й CSP кожного маршруту: node worker/headers.test.mjs
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import worker, { eventPage, eventResponse } from "./index.mjs";
import { base, now, shelters, env, ctx, detailsOk } from "./fixtures.mjs";

const directive = (response, name) => response.headers.get("content-security-policy").split("; ").find((d) => d.startsWith(`${name} `));

// CSP пропускає лише скрипт із цим хешем: правка тексту кнопки «Поділитися» без нового хеша її б вимкнула.
const community = eventPage(base, now);
const moved = eventPage({ ...base, origin: "import", canonical_url: "https://concert.ua/x", source_name: "Concert.ua", state: "scheduled",
  previous_starts_at: "2026-10-03T16:00:00Z", offers: [{ source: "Concert.ua", url: "https://concert.ua/x", price_min: 400, live: true }] }, now);
const scripts = [...community.matchAll(/<script>([\s\S]*?)<\/script>/g)].map((m) => m[1]);
assert.equal(scripts.length, 1, "один вбудований скрипт");
const share = `'sha256-${createHash("sha256").update(scripts[0]).digest("base64")}'`;
assert.ok(!/<style|\sstyle=|\son[a-z]+=/i.test(moved + eventPage(base, now, shelters) + community), "без вбудованих стилів і обробників — їх CSP теж не пустить");

globalThis.fetch = detailsOk;
const page = await eventResponse(base.id, env);
assert.equal(directive(page, "img-src"), "img-src 'self' https: data: blob:", "скріншот оплати з приватного бакета — через blob:");
assert.equal(directive(page, "script-src"), `script-src 'self' https://static.cloudflareinsights.com ${share}`, "хеш у CSP — від цього скрипта");
assert.equal(directive(page, "connect-src"), "connect-src 'self' https://cloudflareinsights.com https://db.invalid", "запис з вебу — у Supabase напряму");
assert.equal(directive(page, "media-src"), "media-src https://db.invalid/storage/v1/object/public/", "відео — лише з публічного сховища");
assert.equal(directive(page, "style-src"), "style-src 'self'");
assert.ok(page.headers.get("content-security-policy").includes("form-action 'none'; frame-ancestors 'none'"));
assert.equal(directive(page, "worker-src"), undefined, "без мапи — без blob:");
assert.equal(page.headers.get("x-frame-options"), "DENY");
assert.equal(page.headers.get("strict-transport-security"), "max-age=31536000");
const lost = await eventResponse("not-a-uuid", {});
assert.equal(lost.headers.get("cache-control"), "public, max-age=60", "404 кешується на хвилину");
assert.ok(!lost.headers.get("content-security-policy").includes("undefined"), "без env — без адреси бази, а не «undefined»");
globalThis.fetch = async () => new Response("{}", { status: 500 });
assert.equal((await eventResponse(base.id, env)).headers.get("cache-control"), "no-store", "збій бази — без кешу");

// Сторінка міста: лише свій домен, «Поділитися» з layout і маячок — без бази й сховища.
globalThis.caches = { default: { match: async () => undefined, put: async () => {} } };
const city = await worker.fetch(new Request("https://poriad.app/afisha/rome"), env, ctx);
assert.equal(directive(city, "script-src"), `script-src 'self' https://static.cloudflareinsights.com ${share}`);
assert.equal(directive(city, "connect-src"), "connect-src 'self' https://cloudflareinsights.com");
assert.equal(directive(city, "media-src"), undefined);

// Сторінки Pages: HTML отримує заголовки й CSP з мапою й Supabase, решта йде як є.
const upstream = { "/afisha.html": ["<!doctype html>", "text/html; charset=utf-8"], "/js/afisha.js": ["export {}", "application/javascript; charset=utf-8"] };
globalThis.fetch = async (request) => {
  const [body, type] = upstream[new URL(request.url).pathname];
  return new Response(body, { headers: { "content-type": type, "cache-control": "max-age=600", etag: '"pages"' } });
};
const afisha = await worker.fetch(new Request("https://poriad.app/afisha.html"), env, ctx);
assert.equal(await afisha.text(), "<!doctype html>");
assert.equal(afisha.headers.get("cache-control"), "max-age=600", "кеш Pages не чіпаємо");
assert.equal(afisha.headers.get("etag"), '"pages"');
assert.equal(afisha.headers.get("x-frame-options"), "DENY");
assert.equal(directive(afisha, "script-src"), "script-src 'self' https://static.cloudflareinsights.com", "на сторінках Pages жодних inline-скриптів");
assert.equal(directive(afisha, "connect-src"), "connect-src 'self' https://cloudflareinsights.com https://tiles.openfreemap.org https://db.invalid");
assert.equal(directive(afisha, "img-src"), "img-src 'self' https: data: blob:");
assert.equal(directive(afisha, "worker-src"), "worker-src blob:");
assert.equal(directive(afisha, "child-src"), "child-src blob:");
assert.equal(directive(afisha, "style-src"), "style-src 'self'");
assert.equal(directive(afisha, "media-src"), "media-src https://db.invalid/storage/v1/object/public/ blob:", "відео зі сховища й прев'ю в кабінеті");
const script = await worker.fetch(new Request("https://poriad.app/js/afisha.js"), env, ctx);
assert.equal(script.headers.get("content-security-policy"), null, "js, css і шрифти — без заголовків сторінки");
assert.equal(await script.text(), "export {}");

for (const response of [page, city, afisha]) {
  const policy = response.headers.get("content-security-policy");
  assert.ok(!policy.includes("unsafe-inline") && !policy.includes("unsafe-eval") && !policy.includes("unpkg"), policy);
}
console.log("headers ok");
