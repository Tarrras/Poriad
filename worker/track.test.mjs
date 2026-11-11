// Аналітика кабінету: node worker/track.test.mjs
import assert from "node:assert/strict";
import worker from "./index.mjs";
import { tracked, TRACKED } from "./track.mjs";
import { env, ctx } from "./fixtures.mjs";

const device = "3f2b8c1e-9a4d-4e6f-8b7a-1c2d3e4f5a6b";
let sent = [];
globalThis.fetch = async (url, init) => { sent.push({ url: String(url), body: JSON.parse(init.body) }); return new Response("{}"); };
const post = (body, { origin = "https://poriad.app", extra = env } = {}) => worker.fetch(new Request("https://poriad.app/api/t", {
  method: "POST", headers: { "content-type": "application/json", ...(origin ? { origin } : {}) }, body: typeof body === "string" ? body : JSON.stringify(body),
}), extra, ctx);
const keyed = { ...env, AMPLITUDE_KEY: "k" };

// Наша подія з ключем іде в Amplitude; зайві параметри, текст і чужі типи — ні.
const ok = await post({ name: "kab_publish", device, props: { mode: "new", media: 2, mobile: true, title: "Настолки", code: "x", from: "Привіт усім" } }, { extra: keyed });
assert.equal(ok.status, 204);
assert.equal(sent.length, 1);
assert.equal(sent[0].url, "https://api2.amplitude.com/2/httpapi");
const [event] = sent[0].body.events;
assert.equal(sent[0].body.api_key, "k");
assert.equal(event.event_type, "kab_publish");
assert.equal(event.device_id, device);
assert.equal(event.platform, "Web");
assert.deepEqual(event.event_properties, { mode: "new", media: 2, mobile: true }, "лише параметри цієї події");
assert.ok(!("user_id" in event) && !("ip" in event), "без акаунта й адреси людини");

// Значення — слово, число чи прапорець: речення, об'єкт і надто довге відкидаються, подія лишається.
assert.deepEqual(tracked({ name: "kab_failed", device, props: { code: "AGE_REQUIRED", mode: { a: 1 } } }).event_properties, { code: "AGE_REQUIRED" });
assert.deepEqual(tracked({ name: "kab_open", device, props: { from: "x".repeat(41), guest: false } }).event_properties, { guest: false });
assert.deepEqual(tracked({ name: "kab_open", device, props: { from: "a b" } }).event_properties, {});

// Без ключа (dev) — 204 і тиша.
sent = [];
assert.equal((await post({ name: "kab_open", device, props: {} })).status, 204);
assert.equal(sent.length, 0);

// Не наше: невідома подія, чужий пристрій, не JSON, завелике тіло, чужий сайт, не POST.
for (const body of [{ name: "purchase", device }, { name: "kab_open", device: "x" }, { name: "kab_open" }, "не json", JSON.stringify({ name: "kab_open", device, pad: "x".repeat(3000) })]) {
  assert.equal((await post(body, { extra: keyed })).status, 400, JSON.stringify(body).slice(0, 60));
}
assert.equal((await post({ name: "kab_open", device }, { origin: "https://evil.example", extra: keyed })).status, 403);
assert.equal((await post({ name: "kab_open", device }, { origin: null, extra: keyed })).status, 403);
assert.equal((await worker.fetch(new Request("https://poriad.app/api/t"), keyed, ctx)).status, 405);
assert.equal(sent.length, 0);

// Ліміт на адресу — до розбору тіла.
const limited = { ...keyed, TRACK_LIMIT: { limit: async ({ key }) => ({ success: key !== "203.0.113.7" }) } };
const from = (ip) => worker.fetch(new Request("https://poriad.app/api/t", {
  method: "POST", headers: { origin: "https://poriad.app", "cf-connecting-ip": ip }, body: JSON.stringify({ name: "kab_open", device }),
}), limited, ctx);
assert.equal((await from("203.0.113.7")).status, 429);
assert.equal((await from("203.0.113.8")).status, 204);

// Кабінет шле лише події зі словника: назви в kabinet.js і тут не розходяться.
const { readFileSync } = await import("node:fs");
const used = [...readFileSync(new URL("../site/js/kabinet.js", import.meta.url), "utf8").matchAll(/\btrack\("(\w+)"/g)].map((m) => m[1]);
assert.ok(used.length > 0, "кабінет нічого не шле");
for (const name of used) assert.ok(TRACKED[name], `${name} нема в словнику воркера`);
for (const name of Object.keys(TRACKED)) assert.ok(used.includes(name), `${name} є у словнику, але кабінет її не шле`);

console.log("track ok");
