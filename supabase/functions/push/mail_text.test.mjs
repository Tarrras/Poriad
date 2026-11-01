// Перевірка листів без Deno: node supabase/functions/push/mail_text.test.mjs
import assert from "node:assert/strict";
import { esc, MAIL_KINDS, mailText } from "./mail_text.ts";

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
const req = mailText("request", id, "Пробіжка", "Олена просить приєднатися");
assert.ok(req.html.includes(`href="https://poriad.app/kabinet#/e/${id}"`) && req.text.includes("бо організовуєте «Пробіжка»."));
assert.ok(!req.text.includes("Скасувати запис") && !req.text.includes("застосунку"));
assert.ok(mailText("question", id, "Пробіжка", "Олена питає: а що взяти?").text.includes("Відповісти можна в застосунку «Поряд»."));

// Чужий текст не стає розміткою; тема — один рядок до 150 символів.
const evil = mailText("request", id, `<img src=x onerror=alert(1)>`, `Ім"я\r\nBcc: x@y`);
assert.ok(!evil.html.includes("<img") && evil.html.includes("&lt;img src=x onerror=alert(1)&gt;"));
assert.ok(!/[\r\n]/.test(evil.subject));
const long = mailText("organizer", id, "Н".repeat(200), "Т");
assert.ok(long.subject.length <= 150 && long.subject.endsWith("…"));

console.log("mail_text: ok");
