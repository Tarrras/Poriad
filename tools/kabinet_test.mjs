// Правила кабінету організатора без браузера: node tools/kabinet_test.mjs
import assert from "node:assert/strict";
import {
  instant, local, repeatTimes, endAfter, durationLabel, DURATIONS, mediaProblem, videoTooLong, fit, MEDIA,
  threadsPost, threadsIntent, firstLine, cleanText, rosterText, errorText, publishPlan, writeDraft, forgetDraft, recolorStub,
  priceProblem, priceParam, PRICE_TEXT, eventDraft, params, repeatDraft, passwordProblem, passwordMode, providersText, editorDefaults, sinceText,
  weakPasswordText, redirectErrorText, payPlan, payProblems, payLimitsText, TALK_PAYMENT_DETAILS, TALK_PAY_OFF, talkStatus, talkFacts, payWords, declineQuestion, nameProblem, contactOk,
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
// Невидиме з буфера не йде ні до функції, ні в запасний опис; емодзі з ZWJ і FE0F лишаються.
const tags = [..."ignore all"].map((c) => String.fromCodePoint(0xE0000 + c.codePointAt(0))).join("");
assert.equal(cleanText(`Настолки\u200B в «Граніті»\u202E\uFEFF${tags}\r\nсубота\u{E0101}\u3164 👩‍💻️\tдо 12`),
  "Настолки в «Граніті»\nсубота 👩‍💻️\tдо 12");
assert.equal(cleanText("a\u034Fb\u2800c\u{E0080}d\uE000e\u{F0000}f\uD800g\u2065h\u180Ei"), "abcdefghi");
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
// Ціна (1.7): лише ціна, порожньо — безкоштовно; p_price завжди явно (0 прибирає), правка й «Повторити» її не гублять.
assert.equal(priceProblem(""), null);
assert.equal(priceProblem("300"), null);
assert.equal(priceProblem("100000"), null);
assert.equal(priceProblem("0"), PRICE_TEXT);
assert.equal(priceProblem("12.5"), PRICE_TEXT, "цілі гривні");
assert.equal(priceProblem("100001"), PRICE_TEXT);
assert.equal(priceParam(""), 0);
assert.equal(priceParam(" 450 "), 450);
const pricedEvent = { ...event, category: "games", latitude: 50.45, longitude: 30.52, ends_at: "2026-11-02T19:00:00Z", capacity: 8, min_age: 18, price_min: "450", origin: "community" };
assert.equal(eventDraft(pricedEvent).price, "450", "PostgREST може віддати numeric рядком");
assert.equal(priceParam(eventDraft(pricedEvent).price), 450, "правка шле ту саму ціну");
assert.equal(priceParam(repeatDraft(pricedEvent).price), 450, "«Повторити» теж");
assert.equal(eventDraft({ ...pricedEvent, price_min: null }).price, "");
assert.equal(errorText({ status: 400, code: "INVALID_PRICE" }), PRICE_TEXT);
assert.equal(threadsPost(pricedEvent), "Настолки «Каркасон»\nпн, 2 листопада, 19:00 · Хрещатик, 22\nВхід — 450 ₴, оплата на зустрічі\n\nГраємо в Каркасон і Колонізаторів. Правила пояснимо.\n\nЗапис: poriad.app/e/e1");
assert.ok(threadsPost({ ...pricedEvent, pay_online: true }).includes("Вхід — 450 ₴, оплата онлайн\n"), "пост не каже «на місці» про оплату онлайн");
assert.ok(threadsPost({ ...pricedEvent, prepay: true }).includes("Вхід — 450 ₴, передоплата\n"), "коли платять — одразу в пості");
assert.ok(!threadsPost({ ...pricedEvent, origin: "import" }).includes("Вхід"), "ціна продавця в афіші — «від», не пишемо");

// Вхід і акаунт організатора.
assert.equal(passwordProblem("1234567"), "Пароль — щонайменше 8 символів");
assert.equal(passwordProblem("x".repeat(73)), "Пароль — до 72 символів");
assert.equal(passwordProblem("secret123", "secret124"), "Паролі не збігаються");
assert.equal(passwordProblem("secret123", "secret123"), "");
assert.equal(passwordMode(["recovery"]), "recovery", "з листа відновлення — без поточного");
assert.equal(passwordMode(["password"]), "change");
assert.equal(passwordMode(["oauth"]), "set");
assert.equal(passwordMode(["otp"]), "set");
assert.equal(passwordMode([]), "set");
assert.equal(providersText({ identities: [{ provider: "google" }, { provider: "email" }], app_metadata: { providers: ["email", "google"] } }), "пошта · Google");
assert.equal(providersText({ identities: [], app_metadata: { providers: ["apple"] } }), "Apple");
assert.equal(providersText(null), "—");
assert.deepEqual(editorDefaults({ kabinet: { city: "Львів", contact: "https://t.me/club", approval: true } }), { city: "Львів", contact: "https://t.me/club", approval: true });
assert.deepEqual(editorDefaults({ kabinet: { city: "Москва", contact: "javascript:alert(1)", approval: "так" } }), {}, "чуже з метаданих не тягнемо в подію");
assert.deepEqual(editorDefaults({ kabinet: { contact: "https://t.me/a b" } }), {});
assert.deepEqual(editorDefaults(undefined), {});
assert.equal(sinceText("2026-09-30T22:30:00Z"), "з нами з жовтня 2026", "місяць — за Києвом");
assert.equal(sinceText(null), "");
assert.equal(nameProblem("Олена"), "");
assert.match(nameProblem("О"), /від 2 до 60/);
assert.ok(contactOk("https://t.me/club") && !contactOk("http://t.me/club") && !contactOk("https://t.me/a b"));
assert.match(weakPasswordText(["pwned"]), /витоках/);
assert.match(weakPasswordText(["characters"]), /літери/);
assert.equal(errorText({ status: 422, code: "weak_password", reasons: ["length"] }), "Пароль — щонайменше 8 символів");
assert.match(errorText({ status: 400, code: "invalid_credentials" }), /Забули пароль/);
assert.equal(errorText({ status: 400, code: "same_password" }), "Новий пароль збігається з поточним");
assert.match(redirectErrorText({ code: "otp_expired" }), /Посилання застаріло/, "протухле посилання — не «код не підійшов»");
assert.match(redirectErrorText({ code: "flow_state_expired" }), /Посилання застаріло/);
assert.match(errorText({ code: "otp_expired" }), /Код не підійшов/);
// Як платять (docs/organizer-events.md): лише з ціною; онлайн — завжди за підтвердженням.
assert.deepEqual(payPlan("", true), { paid: false, online: false, hint: "" }, "без ціни — нема про що");
assert.equal(payPlan("300", false).online, false);
assert.equal(payPlan("300", false).hint, "", "без онлайн — без рядка під вибором: описи варіантів кажуть досить (05.11)");
assert.equal(payPlan("300", true).online, true);
assert.match(payPlan("300", true).hint, /не приймає оплату й не відповідає/);
assert.equal(eventDraft({ ...pricedEvent, pay_online: true }).payOnline, true, "правка несе спосіб оплати");
// Коли платять (20261125190000): правка несе передоплату, а збереження шле її завжди — false повертає «на зустрічі».
assert.equal(eventDraft({ ...pricedEvent, prepay: true }).prepay, true);
assert.equal(params(eventDraft({ ...pricedEvent, prepay: true }), "e1").p_prepay, true);
assert.equal(params(eventDraft(pricedEvent), "e1").p_prepay, false);
assert.equal(params({ ...eventDraft(pricedEvent), prepay: true, payOnline: true }, "e1").p_prepay, false, "онлайн — своє");
assert.equal(eventDraft(pricedEvent).payOnline, false);
assert.equal(repeatDraft({ ...pricedEvent, pay_online: true, starts_at: "2026-10-01T16:00:00Z", ends_at: "2026-10-01T19:00:00Z" }).payOnline, true, "«Повторити» — з тим самим способом");
assert.match(errorText({ status: 400, code: "PAYMENT_DETAILS" }), /у чаті учасників \(Telegram\)/, "реквізити — у чаті учасників (05.11)");
assert.match(TALK_PAYMENT_DETAILS, /«Як платять» → «Онлайн»/);
assert.ok(TALK_PAY_OFF.includes("чаті учасників") && !TALK_PAY_OFF.includes("«Онлайн»"), "вимкнено — реквізити в чаті учасників, не радимо вмикати");
assert.match(errorText({ code: "PAY_ONLINE_OFF" }), /Оновіть сторінку/);
// Безпека оплати онлайн: правила повернення, згода, межі рівня — лише для нової онлайн-події чи зміненої ціни й місць.
const lvl0 = { enabled: true, level: 0, max_price: 500, max_capacity: 10, held: 0, terms: false, next: { held: 1, days: 30, max_price: 1500, max_capacity: 30 } };
assert.deepEqual(payProblems({ price: "300", capacity: 10, refund: "before_48h", payTerms: true }, lvl0), []);
assert.deepEqual(payProblems({ price: "300", capacity: 10, refund: "", payTerms: false }, lvl0), ["Оберіть, як повертаєте гроші", "Погодьтеся з Правилами оплати онлайн"]);
assert.equal(payProblems({ price: "600", capacity: 12, refund: "cancel_only", payTerms: true }, lvl0).length, 2, "price and capacity over the tier");
assert.deepEqual(payProblems({ price: "600", capacity: 12, refund: "cancel_only" }, { ...lvl0, terms: true }, { pay_online: true, price_min: 600, capacity: 12 }), [],
  "unchanged online event above the tier stays editable");
assert.deepEqual(payProblems({ price: "300", capacity: 5, refund: "cancel_only" }, { ...lvl0, enabled: false }), ["Оплату онлайн для вас призупинено. Оберіть «На місці»"]);
assert.deepEqual(payProblems({ price: "300", capacity: 5, refund: "cancel_only" }, null), [], "guest: limits come after sign-in");
assert.match(payLimitsText(lvl0), /^Вам зараз — до 500 ₴ за людину й до 10 місць\. Після 1 проведеної події з учасниками й 30 днів на «Поряд» — до 1\s500 ₴ і 30 місць\.$/);
assert.match(payLimitsText({ ...lvl0, enabled: false }), /призупинено/);
assert.equal(payLimitsText(null), "");

// Хто в розмові (кабінет): стан на події й рядки картки.
const people = { roster: [{ user_id: "a", joined_at: "2026-11-02T10:00:00Z", via: "app" }], requests: [{ user_id: "g", joined_at: "2026-11-03T09:00:00Z", via: "web" }] };
assert.deepEqual(talkStatus("g", { ...people, payOnline: true }), { stamp: "Чекає оплати", tone: "accent", at: "2026-11-03T09:00:00Z", via: "web", pending: true });
assert.equal(talkStatus("a", { ...people, payOnline: true }).stamp, "Оплачено");
assert.equal(talkStatus("g", { ...people, payOnline: true, stage: "proof" }).stamp, "Скріншот надіслано", "надіслала скріншот — звірити з банком");
assert.equal(talkStatus("g", { ...people, stage: "proof" }).stamp, "Заявка", "на місці стадій оплати нема");
assert.equal(talkStatus("a", people).stamp, "У списку");
assert.equal(payWords(true).approve, "Оплату отримано", "таблиця й розмова — тими самими словами");
assert.equal(payWords(false).done, "Схвалено");
assert.equal(declineQuestion("Іра", false), "Відхилити заявку? Іра отримає сповіщення, що заявку відхилено.");
assert.ok(declineQuestion("Іра", true).endsWith("поверніть гроші: «Поряд» цього не робить."), "оплата онлайн — про повернення");
assert.ok(declineQuestion("", false).includes("Учасник отримає"), "без імені — як handle_new_user");
assert.equal(talkStatus("g", people).stamp, "Заявка");
assert.deepEqual(talkStatus("x", people), { stamp: "Питає", tone: "", at: null, via: null, pending: false });
assert.deepEqual(talkFacts({ member_since: "2026-09-12T10:00:00Z", attended: 3, organized: 0 }, talkStatus("g", { ...people, payOnline: true })),
  { profile: "з нами з вересня 2026 · відвідано подій: 3", joined: "Заявка 3 листопада о 11:00 · з вебу" });
assert.equal(talkFacts(null, talkStatus("x", people)).joined, "Ще не записались на подію");
assert.equal(talkFacts(null, talkStatus("x", people)).profile, "");

console.log("kabinet ok");
