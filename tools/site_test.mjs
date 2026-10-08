// Правила сайту, що мають збігатися із застосунком: node tools/site_test.mjs
import assert from "node:assert/strict";
import { displayTitle, overline, inWhen, fold, soonFirst, otherDays, plural, EVENTS, price } from "../site/js/poriad.js";

// Ті самі випадки, що TitleRulesTest (core/domain).
for (const [raw, shown] of [
  ["СТЕНДАП ПЕРЕВІРКА", "Стендап Перевірка"], ["ВЕЧІР У ТЕАТРІ", "Вечір у Театрі"], ["У ТЕАТРІ", "У Театрі"],
  ["КОНЦЕРТ: У ПОШУКАХ РИТМУ", "Концерт: У Пошуках Ритму"], ["DJ SET", "DJ SET"], ["ГУРТ CRAZY TRAIN", "Гурт Crazy Train"],
  ["КІНО 3D ДЛЯ ДІТЕЙ", "Кіно 3D для Дітей"], ["ДІМ", "ДІМ"], ["СТЕНДАП (acoustic)", "СТЕНДАП (acoustic)"],
  ['Шоу "Не проблема"', "Шоу «Не проблема»"], ["Клуб “Бувальщина” у Modi", "Клуб «Бувальщина» у Modi"],
  ['Екран 5" у кіно', 'Екран 5" у кіно'], ["П'ятниця, м'ясо, В'ячеслав", "П’ятниця, м’ясо, В’ячеслав"],
  ["Прем`єра. Мар´яна", "Прем’єра. Мар’яна"], ["Клуб 'Модi'", "Клуб 'Модi'"],
  ['ШОУ "НЕ ПРОБЛЕМА" П\'ЯТНИЦЯ', "Шоу «Не Проблема» П’ятниця"],
]) assert.equal(displayTitle(raw), shown, raw);

// Середа, 8 жовтня 2026, 15:00 у Києві.
const now = new Date("2026-10-08T12:00:00Z");
const tz = "Europe/Kyiv";
const at = (iso) => ({ starts_at: iso, ends_at: null, time_zone: tz });
assert.equal(overline(at("2026-10-08T16:00:00Z"), now), "Сьогодні · 19:00");
assert.equal(overline(at("2026-10-08T21:30:00Z"), now), "Завтра · 00:30", "день — у поясі події, не UTC");
assert.equal(overline(at("2026-10-10T15:00:00Z"), now), "У суботу · 18:00");
assert.match(overline(at("2026-10-23T16:00:00Z"), now), /^пт, 23 жовт\.? · 19:00$/);
assert.equal(overline({ ...at("2026-08-06T09:00:00Z"), ends_at: "2026-10-31T16:00:00Z" }, now), "до 31 жовтня");
assert.equal(overline({ ...at("2026-10-08T11:00:00Z"), ends_at: "2026-10-08T14:00:00Z" }, now), "Триває зараз");

const e = (startsAt, extra = {}) => ({ id: startsAt, startsAt, tz, lat: 50.45, lng: 30.52, title: "Концерт", origin: "import", ...extra });
assert.ok(inWhen(e("2026-10-08T18:00:00Z"), "today", now));
assert.ok(!inWhen(e("2026-10-08T22:00:00Z"), "today", now), "01:00 9 жовтня за Києвом — вже завтра");
assert.ok(inWhen(e("2026-10-09T10:00:00Z"), "tomorrow", now));
assert.ok(inWhen(e("2026-10-10T10:00:00Z"), "weekend", now) && inWhen(e("2026-10-11T20:00:00Z"), "weekend", now));
assert.ok(!inWhen(e("2026-10-12T08:00:00Z"), "weekend", now) && !inWhen(e("2026-10-09T10:00:00Z"), "weekend", now));
assert.ok(inWhen(e("2026-10-11T10:00:00Z"), "weekend", new Date("2026-10-11T08:00:00Z")), "у неділю вихідні — сьогодні");

const folded = fold([
  e("2026-10-09T16:00:00Z", { id: "a" }), e("2026-10-10T16:00:00Z", { id: "b" }), e("2026-10-10T18:00:00Z", { id: "c" }),
  e("2026-10-09T16:00:00Z", { id: "d", title: "Екскурсія «Концерт»" }),
  e("2026-10-09T16:00:00Z", { id: "x", title: "Інше" }),
  e("2026-10-09T16:00:00Z", { id: "r1", origin: "community" }), e("2026-10-10T16:00:00Z", { id: "r2", origin: "community" }),
]);
assert.deepEqual(folded.map((x) => x.id), ["a", "x", "r1", "r2"], "прокат і дубль продавця згорнуто, кімнати людей — ні");
assert.deepEqual(folded[0].sessions.map((s) => s.id), ["a", "b", "c"]);
assert.equal(otherDays(folded[0].sessions), 1);

const order = soonFirst([e("2026-08-06T09:00:00Z", { id: "run" }), e("2026-10-08T16:00:00Z", { id: "tonight" }), e("2026-10-09T16:00:00Z", { id: "tomorrow" })], now.getTime());
assert.deepEqual(order.map((x) => x.id), ["tonight", "run", "tomorrow"], "виставка, що йде, — після вечора, але перед завтра");

assert.equal(plural(1340, EVENTS), "1 340 подій".replace(" ", " "));
assert.equal(plural(21, EVENTS), "21 подія");
assert.equal(plural(3, EVENTS), "3 події");
assert.equal(price({ price_min: 449.6 }), "від 450 ₴");
assert.equal(price({ is_free: true, price_min: 0 }), "Безкоштовно");
console.log("ok");
