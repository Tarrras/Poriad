// Правила кабінету організатора без браузера: node tools/kabinet_test.mjs
import assert from "node:assert/strict";
import {
  instant, local, repeatTimes, endAfter, durationLabel, DURATIONS, mediaProblem, videoTooLong, fit, MEDIA,
  threadsPost, threadsIntent, firstLine, rosterText, errorText, publishPlan, writeDraft, forgetDraft, recolorStub,
} from "../site/js/kabinet.js";
import { readFileSync } from "node:fs";

// Місцевий час Києва ↔ UTC, і в обидва боки переходу на зимовий (25.10.2026, 04:00 → 03:00).
assert.equal(instant("2026-10-24", "19:00"), "2026-10-24T16:00:00.000Z", "літній час, UTC+3");
assert.equal(instant("2026-10-31", "19:00"), "2026-10-31T17:00:00.000Z", "зимовий, UTC+2");
assert.equal(instant("", "19:00"), null);
assert.deepEqual(local("2026-10-31T17:00:00Z"), { date: "2026-10-31", time: "19:00" });
assert.deepEqual(local("2026-10-31T22:30:00Z"), { date: "2026-11-01", time: "00:30" }, "після опівночі — наступна дата");

// «Повторити»: +7 днів, поки не в майбутньому; година та сама й через перехід на зимовий час.
const now = Date.parse("2026-11-01T12:00:00Z");
assert.deepEqual(repeatTimes("2026-10-24T16:00:00Z", "2026-10-24T19:00:00Z", "Europe/Kyiv", now),
  { start: { date: "2026-11-07", time: "19:00" }, end: { date: "2026-11-07", time: "22:00" } }, "минула — два тижні, 31.10 уже минуло");
assert.deepEqual(repeatTimes("2026-11-03T17:00:00Z", "2026-11-03T19:00:00Z", "Europe/Kyiv", now).start, { date: "2026-11-10", time: "19:00" }, "майбутня — рівно на тиждень");
assert.deepEqual(repeatTimes("2026-10-25T20:00:00Z", "2026-10-25T22:30:00Z", "Europe/Kyiv", now).end, { date: "2026-11-02", time: "00:30" }, "кінець після опівночі їде разом");
assert.deepEqual(repeatTimes("2026-11-01T11:00:00Z", "2026-11-01T13:00:00Z", "Europe/Kyiv", now).start, { date: "2026-11-08", time: "13:00" }, "та, що вже почалась, — на тиждень");

// Тривалість: чипи 1–3 год, як у застосунку; кінець через північ.
assert.deepEqual(DURATIONS, [1, 2, 3]);
assert.deepEqual(endAfter("2026-11-07", "23:00", 120), { date: "2026-11-08", time: "01:00" });
assert.deepEqual(endAfter("2026-11-07", "19:00", 90), { date: "2026-11-07", time: "20:30" });
assert.equal(endAfter("2026-11-07", "", 60), null);
assert.equal(durationLabel(120), "2 год");
assert.equal(durationLabel(90), "1 год 30 хв");
assert.equal(durationLabel(45), "45 хв");

// Фото й відео: до 5; фото будь-яке, яке відкриє браузер (далі canvas → JPEG); відео — mp4 до 50 МБ і 30 с.
assert.equal(MEDIA.max, 5);
assert.equal(mediaProblem({ type: "image/heic", size: 30e6 }, 0), null, "фото стискаємо, тож розмір вихідного не важить");
assert.equal(mediaProblem({ type: "video/mp4", size: 49e6 }, 4), null);
assert.equal(mediaProblem({ type: "image/jpeg", size: 1 }, 5), "Уже 5 файлів — більше не можна");
assert.equal(mediaProblem({ type: "video/quicktime", size: 1 }, 0), "Відео — лише mp4");
assert.equal(mediaProblem({ type: "video/mp4", size: 51 * 1024 * 1024 }, 0), "Відео до 30 секунд і 50 МБ.");
assert.equal(mediaProblem({ type: "application/pdf", size: 1 }, 0), "Лише фото чи відео mp4");
assert.ok(!videoTooLong(30) && !videoTooLong(30.4), "30 с з округленням контейнера — можна");
assert.ok(videoTooLong(31) && videoTooLong(NaN) && videoTooLong(Infinity), "довше чи невідомо — ні");
assert.deepEqual(fit(4000, 3000), [2048, 1536], "довша сторона — 2048");
assert.deepEqual(fit(3024, 4032), [1536, 2048], "вертикальне — теж за довшою");
assert.deepEqual(fit(800, 600), [800, 600], "менші не збільшуємо");

// «Пост для Threads» — шаблон зі спеки 1.5, як `ThreadsPost` у застосунку.
const event = { id: "e1", title: "НАСТОЛКИ \"КАРКАСОН\"", starts_at: "2026-11-02T17:00:00Z", time_zone: "Europe/Kyiv", address: "Хрещатик, 22", city: "Київ",
  description: "Граємо в Каркасон і Колонізаторів. Правила пояснимо." };
assert.equal(threadsPost(event), "Настолки «Каркасон»\nпн, 2 листопада, 19:00 · Хрещатик, 22\n\nГраємо в Каркасон і Колонізаторів. Правила пояснимо.\n\nЗапис: poriad.app/e/e1");
const long = threadsPost({ ...event, description: `${"а".repeat(199)} бвгд` });
assert.ok(long.includes(`\n\n${"а".repeat(199)}…\n\n`), "перші 200 символів, без пробілу перед три крапки");
assert.ok(threadsPost({ ...event, blurb: "Настолки для новачків." }).includes("\n\nНастолки для новачків.\n\n"), "blurb — замість опису");
assert.equal(threadsPost({ ...event, description: "  ", address: "" }), "Настолки «Каркасон»\nпн, 2 листопада, 19:00 · Київ\n\nЗапис: poriad.app/e/e1", "без опису — без абзацу");
const intent = new URL(threadsIntent(threadsPost(event)));
assert.equal(intent.origin + intent.pathname, "https://www.threads.net/intent/post");
assert.equal(intent.searchParams.get("text"), threadsPost(event));
assert.ok(!threadsIntent("a b").includes("+"), "пробіл — %20: плюс інтент міг би лишити плюсом");

// Анонс не розібрали: перший рядок без емодзі й хештегів — назва.
assert.equal(firstLine("\n🎲 Настолки в п’ятницю! #настолки #київ\nДалі опис"), "Настолки в п’ятницю!");
assert.equal(firstLine("x".repeat(200)).length, 120);
assert.equal(rosterText([{ display_name: "Олена" }, { display_name: "" }]), "1. Олена\n2. Учасник");

// Помилки — тексти застосунку; невідомий код падає до статусу.
assert.equal(errorText({ status: 400, code: "TOO_MANY_EVENTS" }), "Забагато подій за добу. Спробуйте завтра");
assert.equal(errorText({ status: 400, code: "START_MUST_BE_FUTURE" }), "Початок — дата й час у майбутньому");
assert.equal(errorText({ status: 400, code: "SOMETHING_NEW" }), "Не вдалося виконати дію. Перевірте дані та час події");
assert.equal(errorText({ status: 503 }), "Сервіс тимчасово недоступний. Спробуйте ще раз");
assert.equal(errorText(new TypeError("Failed to fetch")), "Немає звʼязку. Перевірте інтернет і спробуйте ще раз");
assert.equal(errorText({ status: 403, code: "otp_expired" }), "Код не підійшов або застарів. Надішліть новий");
// Конвеєр публікації: p_media null (сервер медіа не чіпає) проти списку, навіть порожнього; update на повторі після збою.
const photo = (url) => ({ kind: "photo", url });
assert.deepEqual(publishPlan({ items: [] }), { create: true, upload: false, update: false }, "нова без медіа — один create_event");
assert.deepEqual(publishPlan({ items: [{ kind: "photo", blob: {} }] }), { create: true, upload: true, update: true });
assert.deepEqual(publishPlan({ existed: true, items: [] }), { create: true, upload: false, update: true }, "повтор після збою — update, щоб правки не загубились");
assert.deepEqual(publishPlan({ existed: true, items: [photo("a")] }), { create: true, upload: true, update: true }, "уже вивантажене з минулої спроби — у p_media");
assert.deepEqual(publishPlan({ items: [{ ...photo("a"), copied: true }] }), { create: true, upload: true, update: true }, "«Повторити» копіює файли");
assert.deepEqual(publishPlan({ editing: true, items: [photo("a"), photo("b")], original: "a b" }), { create: false, upload: false, update: true }, "правка без медіа — p_media null");
assert.deepEqual(publishPlan({ editing: true, items: [photo("b"), photo("a")], original: "a b" }).upload, true, "переставили — новий список");
assert.deepEqual(publishPlan({ editing: true, items: [], original: "a b" }), { create: false, upload: true, update: true }, "прибрали всі — p_media [], обкладинка зникає");

// Вихід з акаунта забуває чернетку й файли: на спільному комп'ютері наступний їх не побачить.
const store = new Map();
globalThis.localStorage = { getItem: (k) => store.get(k) ?? null, setItem: (k, v) => store.set(k, String(v)), removeItem: (k) => store.delete(k) };
const deleted = [];
globalThis.indexedDB = { deleteDatabase: (name) => deleted.push(name) };
writeDraft({ title: "Настолки", contact: "https://t.me/x" });
assert.ok(store.has("poriad.kabinet.draft"));
forgetDraft();
assert.equal(store.size, 0);
assert.deepEqual(deleted, ["poriad.kabinet"]);
globalThis.indexedDB = undefined;
forgetDraft(); // без IndexedDB (приватне вікно) — без помилки
// Анімації публікації (1.6): копії сайту — ті самі файли, що в design/lottie; корінець — кольором жанру.
const lottieFile = (dir, name) => readFileSync(new URL(`../${dir}/${name}.json`, import.meta.url), "utf8");
for (const name of ["publishing", "publishing_dark", "published", "published_dark"]) {
  assert.equal(lottieFile("site/vendor/lottie", name), lottieFile("design/lottie", name), `site/vendor/lottie/${name}.json розійшовся з design/lottie`);
}
const colors = (data, layer) => JSON.stringify(data.layers.find((l) => l.nm === layer)).match(/"c":\{"a":0,"k":\[[^\]]*\]/g).join();
const music = JSON.parse(lottieFile("design/lottie", "publishing"));
const games = recolorStub(music, "#2957AC");
const games_k = [0x29, 0x57, 0xac].map((v) => v / 255);
assert.ok(colors(music, "Stub").includes("0.376") && !colors(games, "Stub").includes("0.376"), "колір музики з корінця зник");
assert.ok(colors(games, "Stub").includes(String(games_k[0])), "корінець — кольором ігор");
assert.equal(colors(games, "Body"), colors(music, "Body"), "квиток не чіпаємо");
assert.ok(colors(music, "Stub").includes("0.376"), "вихідні дані не змінено");
assert.equal(recolorStub(music, ""), music, "жанру нема (CSS-змінна порожня) — як є");
console.log("kabinet ok");
