// Перевірка текстів пушів про підписки без Deno: node supabase/functions/push/follow_text.test.mjs
import assert from "node:assert/strict";
import { organizerText, placeText, plural } from "./follow_text.ts";

const forms = (n) => plural(n, "подія", "події", "подій");
assert.deepEqual([1, 2, 4, 5, 11, 12, 14, 21, 22, 25, 101, 111].map(forms),
  ["подія", "події", "події", "подій", "подій", "подій", "подій", "подія", "події", "подій", "подія", "подій"]);

const club = { id: "p1", name: "Клуб", n: 3 };
const bar = { id: "p2", name: "Джаз-бар", n: 1 };
const ev = (id, title) => ({ id, title, when: "пт, 3 жовтня, 19:00" });

// Одна подія: її назва, тап веде на неї й знає заклад.
assert.deepEqual(placeText(1, 1, [{ ...club, n: 1 }], [ev("e1", "Стендап")]), {
  title: "Стендап", body: "Нова подія у «Клуб» · пт, 3 жовтня, 19:00", placeId: "p1", eventId: "e1" });

// Кілька в одному закладі: формула з завдання, тап — на стос закладу.
const many = placeText(3, 1, [club], [ev("e1", "А"), ev("e2", "Б"), ev("e3", "В")]);
assert.equal(many.title, "У «Клуб» 3 нові події");
assert.equal(many.body, "А, Б, В");
assert.equal(many.eventId, undefined, "кілька подій — не одна подія");
assert.equal(many.placeId, "p1");
assert.equal(placeText(5, 1, [club], [ev("e1", "А"), ev("e2", "Б"), ev("e3", "В")]).title, "У «Клуб» 5 нових подій");
assert.equal(placeText(5, 1, [club], [ev("e1", "А"), ev("e2", "Б"), ev("e3", "В")]).body, "А, Б, В та ще 2");

// У кількох закладах: один пуш, заклад-лідер — цільовий.
const across = placeText(4, 2, [club, bar], [ev("e1", "А")]);
assert.equal(across.title, "4 нові події у місцях, за якими ви стежите");
assert.equal(across.body, "«Клуб», «Джаз-бар»");
assert.equal(across.placeId, "p1");
assert.equal(placeText(9, 5, [club, bar, { id: "p3", name: "Галерея", n: 1 }, { id: "p4", name: "Х", n: 1 }], []).body,
  "«Клуб», «Джаз-бар», «Галерея» та ще 2");

// Порожнє нічого не шле; довгий текст обрізається.
assert.equal(placeText(2, 1, [], [ev("e1", "А")]), null);
assert.equal(placeText(0, 0, [club], []), null);
assert.ok(placeText(3, 1, [club], [ev("e1", "х".repeat(100)), ev("e2", "у".repeat(100)), ev("e3", "з".repeat(100))]).body.length <= 180);

assert.deepEqual(organizerText("Пробіжка", "Олена", "сб, 4 жовтня, 09:00"),
  { title: "Пробіжка", body: "Нова подія від Олена · сб, 4 жовтня, 09:00" });
assert.equal(organizerText("Пробіжка", "", "сб").body, "Нова подія · сб");

console.log("follow_text: ok");
