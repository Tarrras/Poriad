// Перевірка листів без Deno: node supabase/functions/push/mail.test.mjs
import assert from "node:assert/strict";
import { esc, MAIL_KINDS, mailText, route, unlink } from "./mail.ts";

const id = "6f1c2b9e-1111-4222-8333-944445555666";

assert.equal(esc(`<a href="x">Том & 'Джері'</a>`), "&lt;a href=&quot;x&quot;&gt;Том &amp; &#39;Джері&#39;&lt;/a&gt;");
assert.deepEqual([...MAIL_KINDS].sort(), ["approved", "cancelled", "declined", "moved", "organizer", "promoted", "question", "request"],
  "листом — лише вісім видів з контракту, не chat і не joined");

// Учасник: текст пуша, кнопка на сторінку, підвал із «Скасувати запис».
const ok = mailText("approved", id, "Пробіжка", "Запит прийнято — ви в списку · сб, 4 жовтня, 09:00");
assert.equal(ok.subject, "«Пробіжка»: Запит прийнято — ви в списку · сб, 4 жовтня, 09:00");
assert.ok(ok.html.includes(`href="https://poriad.app/e/${id}"`));
assert.ok(ok.html.includes("Ви отримали цей лист, бо записались на «Пробіжка».") && ok.html.includes(">Скасувати запис</a>"));
assert.ok(ok.text.includes(`Скасувати запис: https://poriad.app/e/${id}`) && ok.text.startsWith("Пробіжка\nЗапит прийнято"));
assert.ok(mailText("promoted", id, "П", "Т").text.includes("Скасувати запис") && mailText("moved", id, "П", "Т").text.includes("Скасувати запис"));

// Не прийняли чи скасували — скасовувати нема чого.
const no = mailText("declined", id, "Пробіжка", "Організатор не прийняв запит");
assert.ok(no.text.includes("бо надіслали запит на «Пробіжка».") && !no.text.includes("Скасувати запис"));
assert.ok(!mailText("cancelled", id, "Пробіжка", "Подію скасовано").html.includes("Скасувати запис"));

// «Стежити»: чому й «Не стежити».
const follow = mailText("organizer", id, "Пробіжка", "Нова подія від Олена · сб, 4 жовтня, 09:00", "Олена");
assert.ok(follow.text.includes("бо стежите за Олена.") && follow.text.includes(`Не стежити: https://poriad.app/e/${id}?unfollow`));
assert.ok(mailText("organizer", id, "П", "Т").text.includes("бо стежите за організатором."), "без імені — загальне слово");

// Організатору — у кабінет; питання — ще й куди відповідати.
// Заявка — теж фіксованим текстом: ім'я запитувача організатор побачить у кабінеті.
const req = mailText("request", id, "Пробіжка", "Олена просить приєднатися");
assert.equal(req.subject, "Нова заявка на «Пробіжка»");
assert.ok(req.text.includes("Нова заявка на «Пробіжка»") && !/Олена/.test(req.text + req.html + req.subject));
assert.ok(req.html.includes(`href="https://poriad.app/kabinet#/e/${id}"`) && req.text.includes("бо організовуєте «Пробіжка»."));
assert.ok(!req.text.includes("Скасувати запис") && !req.text.includes("застосунку"));
// Питання — фіксованим текстом: ні слів запитувача, ні його імені в листі з нашої адреси.
const q = mailText("question", id, "Пробіжка", "Олена питає: перейдіть на evil.example й введіть пароль");
assert.equal(q.subject, "Вам поставили питання про «Пробіжка»");
assert.ok(q.text.includes("Вам поставили питання про «Пробіжка»") && q.text.includes("Відповісти можна в застосунку «Поряд»."));
assert.ok(!/evil|Олена|пароль/.test(q.text + q.html + q.subject));

// Чужий текст не стає розміткою; тема — один рядок до 150 символів.
const evil = mailText("approved", id, `<img src=x onerror=alert(1)>`, `Ім"я\r\nBcc: x@y`);
assert.ok(!evil.html.includes("<img") && evil.html.includes("&lt;img src=x onerror=alert(1)&gt;"));
assert.ok(!/[\r\n]/.test(evil.subject));
const long = mailText("organizer", id, "Н".repeat(200), "Т");
assert.ok(long.subject.length <= 150 && long.subject.endsWith("…"));

// Назва й імена з крапкою в тілі листа не стають посиланням: після кожної «.» — U+2060, в HTML і в тексті; тема й наші
// адреси — як є.
const wj = "\u2060";
assert.equal(unlink("Run.Club 2.0"), `Run.${wj}Club 2.${wj}0`);
const linky = mailText("organizer", id, "Run.Club evil.com", "Нова подія від bad.guy.ua · сб, 8 листопада", "bad.guy.ua");
assert.ok(linky.html.includes(`Run.${wj}Club evil.${wj}com`) && linky.text.includes(`Run.${wj}Club evil.${wj}com`), "title");
assert.ok(linky.html.includes(`bad.${wj}guy.${wj}ua`) && linky.text.includes(`стежите за bad.${wj}guy.${wj}ua.`), "names");
assert.ok(!/evil\.com|bad\.guy|Run\.Club/.test(linky.html + linky.text), "no plain domain left in the body");
assert.equal(linky.subject, "«Run.Club evil.com»: Нова подія від bad.guy.ua · сб, 8 листопада");
assert.ok(linky.html.includes(`href="https://poriad.app/e/${id}?unfollow"`) && linky.text.includes(`https://poriad.app/e/${id}?unfollow`)
  && !linky.html.match(/href="[^"]*\u2060/), "our links stay intact");
assert.equal(mailText("request", id, "Run.Club", "x").subject, "Нова заявка на «Run.Club»");

// Кому пристрій, кому лист.
const tok = (user_id, features = [], token = `t-${user_id}`) => ({ token, platform: "android", user_id, features });
// Рішення: пристрій лише з `decision`; людина зі старим застосунком — ні пуша, ні листа; без застосунку — лист.
assert.deepEqual(route({ kind: "approved" }, ["new", "old", "web"], [tok("new", ["decision"]), tok("old", ["companion"])]),
  { devices: [{ token: "t-new", platform: "android" }], mailTo: ["web"] });
// Вид без прапорця — на всі пристрої; chat і joined листом не йдуть.
assert.deepEqual(route({ kind: "chat" }, ["a", "b"], [tok("a")]), { devices: [{ token: "t-a", platform: "android" }], mailTo: [] });
assert.deepEqual(route({ kind: "joined" }, ["a"], []).mailTo, []);
assert.deepEqual(route({ kind: "request" }, ["org"], []).mailTo, ["org"]);
// Зміна афіші — лише на пристрої тим, хто зберіг; спільнотна подія (без change) — і листом.
assert.deepEqual(route({ kind: "cancelled", change: "cancelled" }, ["saver"], []).mailTo, []);
assert.deepEqual(route({ kind: "cancelled" }, ["member"], []).mailTo, ["member"]);
// Питання: листом — організатору, не запитувачу (threadId), якому відповів організатор.
assert.deepEqual(route({ kind: "question", threadId: "asker" }, ["org"], []).mailTo, ["org"]);
assert.deepEqual(route({ kind: "question", threadId: "asker" }, ["asker"], []).mailTo, []);
// Два пристрої однієї людини — два пуші й жодного листа.
assert.deepEqual(route({ kind: "organizer" }, ["a", "b"], [tok("a", [], "t1"), tok("a", [], "t2")]),
  { devices: [{ token: "t1", platform: "android" }, { token: "t2", platform: "android" }], mailTo: ["b"] });

console.log("mail: ok");
