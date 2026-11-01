// «Покликати з собою» (docs/invites.md): node worker/invites.test.mjs. ?by= персоналізує сторінку, але не спільний кеш.
import assert from "node:assert/strict";
import worker, { eventPage, eventResponse } from "./index.mjs";
import { base, now, env, ctx } from "./fixtures.mjs";

const community = eventPage(base, now);
const token = "AbCdEfGhIjKlMnOpQrSt_-";
const invited = eventPage(base, now, [], { by: token, name: "Тарас <b>" });
assert.ok(invited.includes("<b>Тарас &lt;b&gt;</b> кличе тебе"), "хто кличе — над назвою, екрановано");
assert.ok(invited.includes('property="og:title" content="Тарас &lt;b&gt; кличе тебе: Настолки'), "і в прев'ю месенджера");
assert.ok(invited.includes(`poriad://event/${base.id}?by=${token}`), "«У застосунку» несе токен");
assert.ok(invited.includes(`app-argument=https://poriad.app/e/${base.id}?by=${token}`), "банер Safari теж");
assert.ok(invited.includes("ct=invite") && invited.includes("utm_campaign%3Dinvite") && invited.includes("/app?from=invite"), "завантаження з запрошень — своєю міткою");
assert.ok(invited.includes(`property="og:url" content="https://poriad.app/e/${base.id}"`), "адреса прев'ю — без токена");
assert.ok(!community.includes("кличе тебе") && community.includes("ct=event") && !community.includes("ct=invite"), "звичайна сторінка — як була");

const puts = [];
let calls = [];
globalThis.caches = { default: { match: async () => undefined, put: async (key) => { puts.push(key.url); } } };
const rpc = (inviter) => async (url) => {
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
const movedInvite = await eventResponse("c3000000-0000-4000-8000-000000000001", env, { by: token, name: "Тарас" });
assert.equal(movedInvite.headers.get("location"), `https://poriad.app/e/${base.id}?by=${token}`);
console.log("invites ok");
