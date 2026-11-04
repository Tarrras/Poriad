// «Йду» з вебу, фото й відео і .ics на сторінці події (docs/organizers-1.5.md, 1.1 і 1.3): node worker/join.test.mjs
import assert from "node:assert/strict";
import worker, { eventPage } from "./index.mjs";
import { base, now, env, ctx } from "./fixtures.mjs";

const inline = /<style|\sstyle=|\son[a-z]+=/i;
const organizer = "c3000000-0000-4000-8000-000000000003";

// Спільнотна подія, що не почалась: «Йду» замість застосунку, дрібне «Відкрити», шторка й скрипт.
const open = eventPage({ ...base, organizer_id: organizer }, now);
assert.ok(open.includes('<button class="btn primary" type="button" data-join>Йду</button>'));
assert.ok(open.includes(`<a class="open-app" href="poriad://event/${base.id}">Уже є застосунок? Відкрити</a>`));
assert.ok(open.includes("<b>У застосунку ще зручніше</b>") && !open.includes("Приєднатися"), "блок під описом — з новим заголовком");
assert.ok(open.includes('<script type="module" src="/js/join.js?v=18"></script>'), "скрипт — файлом з того самого домену");
assert.ok(open.includes(`data-event="${base.id}" data-organizer="${organizer}" data-organizer-name="Олена" data-city="Київ"`));
assert.ok(open.includes("data-follow") && open.includes(`href="/e/${base.id}.ics"`), "«Стежити» й календар");
assert.ok(open.includes("<h2>Цього тижня в Києві</h2>") && open.includes('href="/afisha/kyiv">Уся афіша Києва'), "«Цього тижня» — лише для п’яти міст");
assert.ok(open.indexOf('data-step="start"') < open.indexOf('data-step="status"') && /data-step="status" hidden/.test(open), "до запису видно лише вхід");
assert.ok(open.includes('autocomplete="one-time-code"') && open.includes('inputmode="numeric"'), "код з листа підставляє клавіатура");
assert.ok(!inline.test(open), "без вбудованих стилів і обробників");
assert.equal([...open.matchAll(/<script>/g)].length, 1, "inline — лише «Поділитися» з хешем");

// Без организатора чи з чужим id — без «Стежити»; поза п’ятьма містами — без «Цього тижня».
const odd = eventPage({ ...base, organizer_id: "javascript:1", organizer_name: "Ла <b>", city: "Рим", min_age: 21, max_age: 35 }, now);
assert.ok(!odd.includes("data-follow") && odd.includes('data-organizer=""') && odd.includes('data-organizer-name="Ла &lt;b&gt;"'));
assert.ok(!odd.includes("data-week") && odd.includes('data-city="Рим" data-min-age="21" data-max-age="35"'));

// Закрито: минула, скасована, уже почалась. Шторка лишається — `?unfollow` з листа.
for (const [label, event, at] of [
  ["минула", base, new Date("2026-10-05T00:00:00Z")],
  ["скасована", { ...base, status: "cancelled" }, now],
  ["почалась", base, new Date("2026-10-04T17:00:00Z")],
]) {
  const page = eventPage(event, at);
  assert.ok(page.includes('<p class="closed">Запис на цю подію закрито</p>'), label);
  assert.ok(!page.includes("data-join") && !page.includes("Уже є застосунок"), `${label}: без «Йду»`);
  assert.ok(page.includes("join-sheet") && page.includes("/js/join.js"), `${label}: «Не стежити» працює`);
}

// Імпорт — як був: квитки й «Підете? Не забудьте», без запису.
const imported = eventPage({ ...base, origin: "import", canonical_url: "https://concert.ua/x", source_name: "Concert.ua" }, now);
assert.ok(imported.includes("Квитки на Concert.ua") && imported.includes("Підете? Не забудьте"));
assert.ok(!imported.includes("join-sheet") && !imported.includes("join.js") && !imported.includes("data-join"));

// Хто чим ділиться (1.6): сторінка однакова для всіх — «Поділитися з другом»; «Поширити анонс» і «Скопіювати посилання»
// організатору вмикає скрипт після входу, тож друга кнопка в розмітці прихована, а на афіші її нема.
assert.ok(open.includes("</i>Поділитися з другом</button>") && open.includes("data-copy-link hidden>") && open.includes("Скопіювати посилання"));
assert.ok(open.includes("data-invite>") && !open.includes("Покликати з собою"), "після запису — теж «Поділитися з другом»");
assert.ok(imported.includes("</i>Поділитися з другом</button>") && !imported.includes("data-copy-link"));

// Аудит безпеки: «Не стежити» — кнопкою підтвердження, «Вийти» — у шторці; обидва приховані до скрипта.
assert.ok(open.includes('data-unfollow hidden>Не стежити</button>') && open.includes("data-account hidden>") && open.includes("data-signout>Вийти</button>"));

// Запрошення несе токен і в «Відкрити».
assert.ok(eventPage(base, now, [], { by: "AbCdEfGhIjKlMnOpQrSt_-", name: "Тарас" }).includes(`poriad://event/${base.id}?by=AbCdEfGhIjKlMnOpQrSt_-">Уже є застосунок?`));

// Фото й відео: карусель замість обкладинки, відео без автозапуску й без попереднього завантаження.
const store = "https://db.invalid/storage/v1/object/public";
const media = eventPage({ ...base, image_url: `${store}/event-images/a.jpg`, media: [
  { kind: "photo", url: `${store}/event-images/a.jpg` },
  { kind: "video", url: `${store}/event-videos/v.mp4`, poster: `${store}/event-images/p.jpg` },
  { kind: "video", url: "http://evil.example/v.mp4" }, { kind: "gif", url: "https://x.example/a.gif" }, null,
  { kind: "photo", url: `${store}/event-images/"onerror=x.jpg` },
] }, now);
assert.ok(media.includes('<div class="art media many cat-social">'));
assert.ok(media.includes(`<video src="${store}/event-videos/v.mp4" poster="${store}/event-images/p.jpg" controls playsinline preload="none"></video>`));
assert.ok(!/autoplay/.test(media) && !media.includes("evil.example") && !media.includes("a.gif"), "лише https і лише фото й відео");
assert.ok(media.includes("&quot;onerror=x.jpg") && !inline.test(media), "адреса екранується");
assert.ok(!media.includes('class="glyph"'), "з медіа — без обкладинки-заглушки");
assert.ok(!eventPage({ ...base, media: [{ kind: "photo", url: `${store}/event-images/a.jpg` }] }, now).includes(" many"), "один кадр — без підглядання наступного");
assert.ok(eventPage({ ...base, media: [] }, now).includes('<div class="art cat-social">'), "без медіа — обкладинка, як була");

// .ics: маршрут перед /e/{id}, нагадування за 3 години.
const calls = [];
globalThis.fetch = async (url, init) => {
  calls.push([url, JSON.parse(init.body)]);
  return new Response(JSON.stringify([{ ...base, title: "Настолки, кава; вечір" }]), { status: 200 });
};
const ics = await worker.fetch(new Request(`https://poriad.app/e/${base.id}.ics`), env, ctx);
const text = (await ics.text()).replace(/\r\n /g, ""); // розгорнути довгі рядки
assert.equal(ics.status, 200);
assert.equal(ics.headers.get("content-type"), "text/calendar; charset=utf-8");
assert.equal(ics.headers.get("content-disposition"), `attachment; filename="poriad-${base.id}.ics"`);
assert.deepEqual(calls[0], [`${env.SUPABASE_URL}/rest/v1/rpc/event_details`, { p_event_id: base.id }]);
assert.ok(text.includes("TRIGGER:-PT3H") && !text.includes("TRIGGER:-PT1H"), "нагадування за 3 години");
assert.ok(text.includes(`UID:${base.id}@poriad.app`) && text.includes("DTSTART:20261004T160000Z") && text.includes("DTEND:20261004T190000Z"));
assert.ok(text.includes("SUMMARY:Настолки\\, кава\\; вечір") && text.includes("LOCATION:Хрещатик\\, 22\\, Київ"), "текст екрановано");
assert.ok(text.includes(`URL:https://poriad.app/e/${base.id}`));
// Одиночний \r чи інший керівний символ у назві й адресі не додає файлу своїх властивостей.
globalThis.fetch = async () => new Response(JSON.stringify([{ ...base, title: "Зустріч\rURL:https://evil.example\rBEGIN:VALARM", address: "Хрещатик\r\nATTENDEE:x\u0000\u0007, 22" }]), { status: 200 });
const evil = await (await worker.fetch(new Request(`https://poriad.app/e/${base.id}.ics`), env, ctx)).text();
const lines = evil.replace(/\r\n /g, "").split("\r\n");
assert.ok(!/\r(?!\n)|[\u0000-\u0008\u000b\u000c\u000e-\u001f]/.test(evil), "жодного сирого \\r чи керівного символу");
assert.ok(!lines.some((l) => l.startsWith("URL:https://evil") || l.startsWith("ATTENDEE")), "чужих властивостей нема");
assert.equal(lines.filter((l) => l === "BEGIN:VALARM").length, 1, "одне нагадування — наше");
assert.ok(lines.includes("SUMMARY:Зустріч\\nURL:https://evil.example\\nBEGIN:VALARM"), "розриви — текстом \\n");
assert.equal((await worker.fetch(new Request("https://poriad.app/e/abc.ics"), env, ctx)).status, 404);
assert.equal((await worker.fetch(new Request(`https://poriad.app/e/${base.id}.ics`, { method: "POST" }), env, ctx)).status, 405);
for (const body of ["[]", "{}", "null", "not json"]) {
  globalThis.fetch = async () => new Response(body, { status: 200 });
  assert.equal((await worker.fetch(new Request(`https://poriad.app/e/${base.id}.ics`), env, ctx)).status, 404, `відповідь ${body} — 404, а не 500`);
}
globalThis.fetch = async () => new Response("{}", { status: 500 });
const down = await worker.fetch(new Request(`https://poriad.app/e/${base.id}.ics`), env, ctx);
assert.equal(down.status, 503);
assert.equal(down.headers.get("cache-control"), "no-store");

console.log("join ok");
