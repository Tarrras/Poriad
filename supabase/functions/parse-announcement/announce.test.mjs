// Перевірка розбору анонсу без Deno й мережі: node supabase/functions/parse-announcement/announce.test.mjs
import assert from "node:assert/strict";
import { announce, clientIp, describe, fields, firstLine, readInput, request } from "./announce.ts";

const text = `🏃 Ранкова пробіжка з «Біжимо разом»
Субота, 8 листопада, 09:00, старт біля Пекарні Протісто, Академмістечко.
До 20 людей, 18+. Чат: t.me/run_together

#біг #київ #ранок`;
const input = { text, city: "Київ", today: "2026-11-01", tz: "Europe/Kyiv" };
const now = new Date("2026-11-01T10:00:00Z"); // 12:00 у Києві
const answer = (o, extra = {}) => ({ stop_reason: "tool_use", content: [{ type: "tool_use", id: "t1", name: "fill_event", input: o }], ...extra });

// Вхід.
assert.deepEqual(readInput(input), input);
assert.deepEqual(readInput({ ...input, text: "   " }), { error: "text" });
assert.deepEqual(readInput({ ...input, text: "х".repeat(3001) }), { error: "too long" });
assert.deepEqual(readInput({ ...input, today: "2026-02-30" }), { error: "today" });
assert.deepEqual(readInput({ ...input, tz: "Mars/Olympus" }), { error: "tz" });
assert.deepEqual(readInput(null), { error: "text" });
assert.equal(clientIp("203.0.113.7, 10.0.0.1"), "203.0.113.7");
assert.equal(clientIp("2001:db8::1"), "2001:db8::1");
assert.equal(clientIp(null), null);
assert.equal(clientIp("'; drop table x"), null);

// Опис — текст як є без хештегів наприкінці; назва з першого рядка — без емодзі.
assert.equal(describe(text), text.split("\n\n#")[0]);
assert.equal(describe("Приходьте! #біг"), "Приходьте!");
assert.equal(describe("Тег #посередині лишається"), "Тег #посередині лишається");
assert.equal(firstLine("\n✨🎉 Вечір настолок 🎲\nдалі"), "Вечір настолок");

// Усе, що модель знайшла й що проходить перевірку.
assert.deepEqual(fields(answer({
  title: "Ранкова пробіжка з «Біжимо разом» 🏃", category: "sport", starts_at: "2026-11-08T09:00", ends_at: "2026-11-08T10:30",
  place: " Пекарня Протісто, Академмістечко ", capacity: 20, min_age: 18, contact_url: "https://t.me/run_together",
}), input, now), {
  title: "Ранкова пробіжка з «Біжимо разом»", description: describe(text), category: "sport",
  starts_at: "2026-11-08T09:00", ends_at: "2026-11-08T10:30", place: "Пекарня Протісто, Академмістечко",
  capacity: 20, min_age: 18, contact_url: "https://t.me/run_together",
});

// Модель помилилась — поле лишається порожнім, а не хибним.
const bad = fields(answer({
  title: "", category: "party", starts_at: "2026-11-01T11:59", ends_at: "2026-11-01T13:00", place: "  ",
  capacity: 0, min_age: 16, contact_url: "https://t.me/someone_else",
}), input, now);
assert.deepEqual(bad, { title: "Ранкова пробіжка з «Біжимо разом»", description: describe(text) },
  "no title → first line; unknown genre, past start (and so no end), empty place, 0 seats, 16+, link not in the text — all dropped");
const f = (o, t = text) => fields(answer(o), { ...input, text: t }, now);
assert.equal(f({ starts_at: "2026-11-01T12:30" }).starts_at, "2026-11-01T12:30", "later today in Kyiv is still the future");
assert.equal(f({ starts_at: "2026-11-08T09:00", ends_at: "2026-11-08T08:00" }).ends_at, undefined, "end before start");
assert.equal(f({ starts_at: "2026-11-31T09:00" }).starts_at, undefined, "no such date");
assert.equal(f({ starts_at: "8 листопада о 9" }).starts_at, undefined, "not the local format");
assert.equal(f({ ends_at: "2026-11-08T10:00" }).ends_at, undefined, "an end without a start");
assert.equal(f({ capacity: 2.5 }).capacity, undefined);
assert.equal(f({ contact_url: "https://instagram.com/club.kyiv/?igsh=abc" }, "Пишіть: www.instagram.com/club.kyiv").contact_url,
  "https://instagram.com/club.kyiv", "instagram link from the text, tracking stripped");
assert.equal(f({ contact_url: "https://t.me.evil.com/run_together" }).contact_url, undefined, "only t.me and instagram");
assert.equal(f({ contact_url: "http://t.me/run_together" }).contact_url, undefined, "https only");
assert.equal(f({ contact_url: "https://t.me/" }).contact_url, undefined, "a bare host is not a chat");
assert.equal(f({ title: "Н".repeat(130) }).title.length, 120);

// Не за схемою — null: клієнт сам кладе текст в опис і перший рядок у назву.
assert.equal(fields(answer({ title: "Х" }, { stop_reason: "refusal" }), input, now), null);
assert.equal(fields(answer({ title: "Х" }, { stop_reason: "max_tokens" }), input, now), null);
assert.equal(fields({ stop_reason: "end_turn", content: [{ type: "text", text: "{}" }] }, input, now), null);
assert.equal(fields(null, input, now), null);

// Запит: модель, заголовки, примусовий інструмент, без temperature; текст анонсу в тегах, з днем тижня для «у суботу».
let sent;
const ok = await announce(input, "sk-test", async (url, init) => {
  sent = { url, init, body: JSON.parse(init.body) };
  return new Response(JSON.stringify(answer({ title: "Пробіжка", starts_at: "2026-11-08T09:00" })), { status: 200 });
}, now);
assert.deepEqual(ok, { title: "Пробіжка", description: describe(text), starts_at: "2026-11-08T09:00" });
assert.equal(sent.url, "https://api.anthropic.com/v1/messages");
assert.equal(sent.init.headers["x-api-key"], "sk-test");
assert.equal(sent.init.headers["anthropic-version"], "2023-06-01");
assert.equal(sent.body.model, "claude-haiku-5-5");
assert.deepEqual(sent.body.tool_choice, { type: "tool", name: "fill_event" });
assert.equal(sent.body.temperature, undefined);
assert.deepEqual(sent.body.tools[0].input_schema.properties.category.enum,
  ["music", "sport", "art", "food", "games", "outdoors", "social", "comedy", "kids", "tours", "conference", "cinema"]);
assert.ok(sent.body.messages[0].content.includes(`<announcement>\n${text}\n</announcement>`));
assert.ok(sent.body.messages[0].content.includes("Сьогодні: 2026-11-01, неділя"));
assert.deepEqual(request(input), sent.body);

// Збій мережі чи API — null, без винятку.
const quiet = console.error;
console.error = () => {};
assert.equal(await announce(input, "k", async () => { throw new Error("offline"); }, now), null);
assert.equal(await announce(input, "k", async () => new Response("{}", { status: 529 }), now), null);
assert.equal(await announce(input, "k", async () => new Response("not json", { status: 200 }), now), null);
console.error = quiet;

console.log("announce: ok");
