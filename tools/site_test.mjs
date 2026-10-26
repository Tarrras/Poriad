// Правила сайту, що мають збігатися із застосунком: node tools/site_test.mjs
import assert from "node:assert/strict";
import { displayTitle, overline, inWhen, fold, soonFirst, otherDays, plural, EVENTS, price, qrPath, icsFile, googleCalendarUrl } from "../site/js/poriad.js";

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
assert.ok(inWhen(e("2026-10-08T14:00:00Z"), "evening", now), "17:00 за Києвом (14:00 UTC) — уже вечір");
assert.ok(!inWhen(e("2026-10-08T13:59:00Z"), "evening", now) && !inWhen(e("2026-10-08T08:00:00Z"), "evening", now), "16:59 і ранок — ні");
assert.ok(inWhen(e("2026-10-08T20:30:00Z"), "evening", now), "23:30 сьогодні — вечір");
assert.ok(!inWhen(e("2026-10-08T21:30:00Z"), "evening", now) && !inWhen(e("2026-10-09T16:00:00Z"), "evening", now), "00:30 і завтрашній вечір — ні");

// QR: той самий знак poriad.app/app, що друкувався раніше з `npx qrcode` (рівень M), і посилання на подію — версія 4.
assert.equal(qrPath("https://poriad.app/app").path, "M0 0.5h7m1 0h3m3 0h1m1 0h1m1 0h7M0 1.5h1m5 0h1m1 0h3m1 0h1m1 0h1m3 0h1m5 0h1M0 2.5h1m1 0h3m1 0h1m3 0h1m2 0h1m2 0h1m1 0h1m1 0h3m1 0h1M0 3.5h1m1 0h3m1 0h1m1 0h4m1 0h1m1 0h2m1 0h1m1 0h3m1 0h1M0 4.5h1m1 0h3m1 0h1m2 0h1m3 0h4m1 0h1m1 0h3m1 0h1M0 5.5h1m5 0h1m3 0h1m3 0h1m3 0h1m5 0h1M0 6.5h7m1 0h1m1 0h1m1 0h1m1 0h1m1 0h1m1 0h7M8 7.5h5M0 8.5h1m1 0h2m1 0h3m4 0h1m1 0h1m1 0h1m1 0h1m2 0h1m1 0h2M0 9.5h2m2 0h2m2 0h2m1 0h2m3 0h1m2 0h1m3 0h1M0 10.5h1m1 0h1m3 0h1m2 0h1m1 0h2m1 0h1m3 0h1m1 0h1M1 11.5h1m1 0h1m3 0h1m2 0h1m2 0h3m1 0h3m1 0h2M0 12.5h3m1 0h4m5 0h2m2 0h4m1 0h3M2 13.5h1m2 0h1m2 0h1m1 0h2m3 0h1m2 0h3m3 0h1M1 14.5h1m1 0h1m2 0h1m2 0h1m2 0h2m2 0h1m3 0h1m1 0h2M0 15.5h1m3 0h1m2 0h3m2 0h1m2 0h2m2 0h2m3 0h1M2 16.5h1m2 0h7m1 0h1m2 0h9M8 17.5h1m1 0h1m1 0h3m1 0h1m3 0h1m1 0h1m1 0h1M0 18.5h7m1 0h1m1 0h3m3 0h1m1 0h1m1 0h1m1 0h3M0 19.5h1m5 0h1m1 0h1m1 0h1m1 0h1m1 0h3m3 0h1m2 0h2M0 20.5h1m1 0h3m1 0h1m2 0h1m1 0h3m2 0h6m1 0h1M0 21.5h1m1 0h3m1 0h1m1 0h3m1 0h2m3 0h2m1 0h5M0 22.5h1m1 0h3m1 0h1m1 0h1m2 0h3m3 0h2m1 0h1m1 0h2M0 23.5h1m5 0h1m2 0h1m8 0h1m1 0h1m1 0h1M0 24.5h7m1 0h2m2 0h1m1 0h1m2 0h8");
assert.equal(qrPath("https://poriad.app/e/3f2a9c1e-7b4d-4e8a-9c0f-1a2b3c4d5e6f").size, 33);
assert.equal(qrPath("x".repeat(107)), null, "довше за версію 6 — без коду");

// Календар: година від початку, якщо кінця нема (як у застосунку), нагадування за годину, коми екрановано, рядки ≤ 75 байтів.
const gig = { id: "e1", title: "ГУРТ CRAZY TRAIN, ЖИВИЙ ЗВУК: ДОВГА НАЗВА КОНЦЕРТУ ДЛЯ ПЕРЕВІРКИ ЗГОРТАННЯ РЯДКА", starts_at: "2026-10-08T16:00:00Z", ends_at: null, place_name: "Атлас", address: "вул. Січових Стрільців, 37", city: "Київ" };
const ics = icsFile(gig, now);
assert.ok(ics.includes("DTSTART:20261008T160000Z\r\nDTEND:20261008T170000Z\r\n") && ics.includes("TRIGGER:-PT1H"));
assert.ok(ics.replace(/\r\n /g, "").includes("LOCATION:Атлас\\, вул. Січових Стрільців\\, 37\\, Київ"));
assert.ok(ics.split("\r\n").every((line) => new TextEncoder().encode(line).length <= 75));
assert.match(icsFile({ ...gig, place_name: "Центральний будинок художника", address: "вул. Січових Стрільців, 1-5, Центральний Будинок Художника, Київ" }).replace(/\r\n /g, ""),
  /LOCATION:вул. Січових Стрільців\\, 1-5\\, Центральний Будинок Художника\\, Київ\r\n/, "заклад і місто вже в адресі");
assert.match(googleCalendarUrl(gig), /dates=20261008T160000Z%2F20261008T170000Z/);

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

// Telegram-пост (tools/telegram_post.mjs): «Від людей» першими, решта порівну на два дні, у дні — різні категорії.
{
  const { pick, format, fit, CHANNELS } = await import("./telegram_post.mjs");
  const ev = (id, startsAt, category, origin = "import", source = "concert_ua") =>
    ({ id, startsAt, tz, category, origin, source, lat: 50 + id.charCodeAt(0) / 1000, lng: 30.52, title: "ВЕЧІР У ТЕАТРІ" });
  const sat = "2026-10-24T", sun = "2026-10-25T";
  const weekend = [
    ev("a", sat + "08:00:00Z", "music"), { ...ev("g", sat + "08:30:00Z", "comedy"), lat: 50.097 }, ev("b", sat + "09:00:00Z", "music"),
    ev("c", sat + "10:00:00Z", "art", "import", "badseller"), ev("d", sun + "08:00:00Z", "music"), ev("e", sun + "09:00:00Z", "comedy"),
    ev("f", sun + "12:00:00Z", "social", "community", null),
  ];
  assert.deepEqual(pick(weekend, [5, 5]).map((e) => e.id), ["f", "a", "c", "d", "e"], "людей першими, далі по дві на день різних категорій і закладів");
  const evening = ["a", "b", "c", "d"].map((id) => ev(id, sat + "15:00:00Z", "art")).concat(ev("m", sat + "16:00:00Z", "music"), ev("n", sat + "16:00:00Z", "music"), ev("s", sat + "16:30:00Z", "comedy"));
  assert.deepEqual(pick(evening, [5, 7]).map((e) => e.category).sort(), ["art", "art", "comedy", "music", "music"], "третє коло лише до мінімуму");
  const cards = new Map([["a", { place_name: 'Клуб "Х" & Co', price_min: 300, blurb: 'Бах "наживо" & свічки' }], ["c", { is_free: true, price_min: 0 }], ["d", { is_free: true, price_min: 0 }],
    ["e", { is_free: true, price_min: 0, offers: [{ is_free: true, price_min: 0 }, { is_free: false, price_min: 550 }] }], ["f", { organizer_name: "Марта" }]]);
  const text = format("Львів", "weekend", pick(weekend, [5, 5]), cards);
  assert.match(text, /^<b>Вихідні, 24 і 25 жовтня<\/b>\nНа вихідних у Львові є куди піти: концерти, мистецтво, стендап і зустрічі 👇\n\n<b>Від людей<\/b>\n🤝 <b>Нд 14:00<\/b> <a href="https:\/\/poriad\.app\/e\/f">Вечір у Театрі<\/a>\nЗбирає Марта\n\n<b>Субота<\/b>\n🎵 <b>11:00<\/b> <a href="https:\/\/poriad\.app\/e\/a">Вечір у Театрі<\/a>\nБах &quot;наживо&quot; &amp; свічки\nКлуб &quot;Х&quot; &amp; Co · від 300 ₴\n\n/, "люди першими, далі афіша по днях; речення «що це» під назвою");
  assert.match(text, /\n\n<b>Неділя<\/b>\n🎵 <b>10:00<\/b> <a href="https:\/\/poriad\.app\/e\/d">Вечір у Театрі<\/a>\nБезкоштовно\n/, "Concert.ua: нуль-заглушки виправлено");
  assert.match(text, /\/e\/c">Вечір у Театрі<\/a>\n\n/, "is_free з інших джерел — без «Безкоштовно»");
  assert.match(text, /\/e\/e">Вечір у Театрі<\/a>\n\n/, "нуль Concert.ua поряд із платним продавцем — не безкоштовно");
  assert.match(text, /\nБільше подій на мапі в <a href="https:\/\/poriad\.app\/app\?from=tgl">«Поряд»<\/a>\. Нема з ким піти\? На кожній події є «Шукаю компанію»\.$/);
  assert.doesNotMatch(text, /[—–]|уся афіша|решта афіші/i, "без тире й без обіцянки повноти");
  assert.match(format("Київ", "today", [ev("a", sat + "16:00:00Z", "music")], new Map()), /^<b>Субота, 24 жовтня<\/b>\nСьогодні в Києві є куди піти: концерти 👇\n\n🎵 <b>19:00<\/b> /);
  assert.match(format("Київ", "today", [ev("p", sat + "15:00:00Z", "games", "community", null), ev("a", sat + "16:00:00Z", "music")], new Map()),
    /👇\n\n<b>Від людей<\/b>\n🎲 <b>18:00<\/b> .*\n\n<b>Афіша<\/b>\n🎵 <b>19:00<\/b> /, "сьогодні з людьми — два блоки");
  assert.match(format("Одеса", "weekend", [ev("a", sat + "16:00:00Z", "music")], new Map()), /\nНа вихідних в Одесі є куди піти/);
  const long = Array.from({ length: 10 }, (_, i) => ({ ...ev(String.fromCharCode(97 + i), sat + `${10 + i}:00:00Z`, "music"), title: "Дуже довга назва ".repeat(40) }));
  const fitted = fit("Київ", "weekend", long, new Map());
  assert.ok(fitted.length < long.length && format("Київ", "weekend", fitted, new Map()).replace(/<[^>]+>/g, "").length <= 4096, "пост влазить у 4096 символів Bot API");
  for (const [, tag] of Object.values(CHANNELS)) assert.match(tag, /^[a-z]{1,12}$/, "site/app.html відкидає іншу мітку");
}
console.log("ok");
