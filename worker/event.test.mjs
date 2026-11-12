// Сторінка події без Cloudflare: node worker/event.test.mjs
import assert from "node:assert/strict";
import { eventPage, eventResponse, esc, curfewNote } from "./index.mjs";
import { base, now, shelters, env, detailsOk } from "./fixtures.mjs";

const community = eventPage(base, now);
assert.ok(!community.includes("<script>alert"), "назва екранується");
assert.ok(community.includes("<small>Учасники</small><span data-spots>5 з 8</span>"), "місця — під міткою, як ціна: поруч коротке «Йду»");
assert.ok(community.includes("19:00"), "час у зоні події, а не UTC");
assert.ok(!community.includes('src="javascript:'), "лише https-зображення");
assert.ok(community.includes('content="https://poriad.app/img/og.png"'), "запасне прев'ю");
assert.ok(community.includes("poriad://event/a1000000-0000-4000-8000-000000000005"));
assert.ok(community.includes('name="robots" content="noindex"'));

const imported = eventPage({ ...base, origin: "import", canonical_url: "https://concert.ua/x", source_name: "Concert.ua", price_min: 450.4, organizer_name: "Concert.ua" }, now);
assert.ok(imported.includes('rel="canonical" href="https://concert.ua/x"'));
assert.ok(imported.includes('class="btn primary" href="https://concert.ua/x?utm_source=poriad"'), "кнопка квитків — з міткою, canonical — без");
assert.ok(imported.includes("від 450 ₴"));
assert.ok(!imported.includes("Учасників"), "в імпорті місць нема");

// Ціна від людей (1.7): точна, поруч з учасниками; коли платять — передоплата чи на зустрічі, поза «Поряд» (05.11); на панелі — ціна.
const priced = eventPage({ ...base, price_min: 1500 }, now);
assert.ok(priced.includes("<b data-spots>5 з 8</b>"), "учасники лишаються фактом");
// Як платити — за ⓘ біля ціни, у спливному вікні (popover), а не текстом під сумою (власник 05.11).
assert.ok(priced.includes('<span class="overline">Ціна</span><b>1\u00a0500 ₴ <button class="info" type="button" popovertarget="fact-info" aria-label="Як платити">'));
assert.ok(priced.includes('<div class="info-pop" id="fact-info" popover>Платите організатору на зустрічі. «Поряд» не приймає оплату й не відповідає за неї.</div>'));
// Коли платять — під ціною одразу й на панелі (власник 05.11): передоплата чи на зустрічі.
assert.ok(priced.includes("<small>Оплата на зустрічі</small>") && priced.includes("<small>Ціна · оплата на зустрічі</small>"));
const prepaid = eventPage({ ...base, price_min: 300, prepay: true }, now);
assert.ok(prepaid.includes("<small>Передоплата</small>") && prepaid.includes("<small>Ціна · передоплата</small>")
  && prepaid.includes("Організатор попросить заплатити заздалегідь і сам напише, як і коли. «Поряд» не приймає оплату й не відповідає за неї."), "передоплата: підпис, панель і ⓘ");
assert.ok(!priced.includes("без передоплати"), "передоплату поза «Поряд» не виключаємо");

assert.ok(priced.includes("<small>Ціна · оплата на зустрічі</small><span>1\u00a0500 ₴</span>"), "на панелі — ціна й коли платять");
assert.ok(!priced.includes("від 1"), "від людей — без «від»");
assert.ok(!community.includes("Оплата — напряму"), "безкоштовна — без ціни");

// Оплата онлайн (docs/organizer-events.md): підпис і застереження «Поряд не відповідає» — раз на сторінці (у розмові —
// під реквізитами, chat.js); у шторці — рядок довіри й смуга заявки з сумою.
const online = eventPage({ ...base, price_min: 300, approval_required: true, pay_online: true, refund_policy: "before_48h" }, now);
assert.ok(online.includes('<div class="info-pop" id="fact-info" popover>Оплата онлайн організатору</div>'));
assert.equal(online.split("«Поряд» не приймає оплату й не відповідає за неї.").length - 1, 2, "на сторінці й у кроці згоди перед заявкою — не на кожному кроці");
// Перед заявкою — умови й правила повернення (20261125170000_pay_online_safety).
assert.ok(online.includes('data-step="pay"') && online.includes("data-pay-agree") && online.includes("за 48 год до початку. Скасує організатор — поверне все."),
  "згода платника з правилами повернення");
const cancelledOnline = eventPage({ ...base, price_min: 300, approval_required: true, pay_online: true, refund_policy: "cancel_only", status: "cancelled",
  organizer_id: "c3000000-0000-4000-8000-000000000003" }, now);
assert.ok(cancelledOnline.includes("організатор має повернути гроші") && cancelledOnline.includes("data-ask>") && cancelledOnline.includes(" data-cancelled"),
  "скасована онлайн-подія — про повернення й розмова відкрита");
assert.ok(online.includes(' data-pay-online data-price="300">') && !online.includes("Участь за підтвердженням організатора."), "замість загального рядка — про оплату");
assert.ok(online.includes("data-trust hidden") && online.includes("data-pay-bar hidden"), "довіра й стан заявки — у розмові");
assert.ok(!priced.includes("data-pay-online") && !priced.includes('data-step="pay"'), "на місці — без шторки оплати онлайн і кроку згоди");
assert.ok(online.includes('<input class="sr" type="file" accept="image/*" data-proof>') && online.includes("Скріншот бачите лише ви й організатор."),
  "скріншот оплати — лише онлайн, поле файлу досяжне з клавіатури");
assert.ok(!priced.includes("data-proof"), "на місці скріншотів нема");
// «Написати організатору» — подія від людей з організатором, ще не минула; розмова — у шторці.
const host = { ...base, organizer_id: "c3000000-0000-4000-8000-000000000003" };
assert.ok(eventPage(host, now).includes("data-ask>") && community.includes('data-step="ask"') && community.includes("data-open-ask"));
assert.ok(!community.includes("data-ask>"), "без організатора писати нікому");
assert.ok(!imported.includes("data-ask>"), "в афіші організатора нема");
assert.ok(!eventPage(host, new Date("2026-10-05T00:00:00Z")).includes("data-ask>"), "минула — без кнопки");

const withShelters = eventPage(base, now, shelters);
assert.ok(withShelters.includes("<h2>Безпека</h2>") && withShelters.includes("Метро · 66 м · Є пандус"));
assert.ok(!withShelters.includes("<b>»"), "адреса укриття екранується");
assert.ok(!eventPage(base, now).includes("<h2>Безпека</h2>"), "без даних секції нема");
assert.ok(!eventPage({ ...base, status: "cancelled" }, now, shelters).includes("<h2>Безпека</h2>"), "скасованій — ні");
// Комендантська — у всіх містах, навіть без укриттів; запас після події — як у застосунку (CurfewRules.note).
const curfew = { starts: "00:00", ends: "05:00" };
const night = eventPage({ ...base, curfew }, now);
assert.ok(night.includes("<h2>Безпека</h2>") && night.includes("Комендантська в місті · 00:00–05:00")
  && night.includes("Закінчиться о 22:00, до комендантської лишиться 2 год"), "кінець о 22:00 — 2 год до 00:00");
assert.ok(!night.includes("КМДА"), "без укриттів — без підпису про дані КМДА");
assert.ok(eventPage({ ...base, curfew: { starts: "23:00", ends: "05:00" } }, now).includes("Закінчиться о 22:00, до комендантської лишиться 1 год"));
assert.ok(eventPage({ ...base, curfew: { starts: "21:30", ends: "05:00" } }, now).includes("Закінчиться о 22:00, уже під час комендантської"));
assert.ok(eventPage({ ...base, ends_at: "2026-10-04T09:00:00Z", starts_at: "2026-10-04T07:00:00Z", curfew }, now).includes("<span>Комендантська в місті: 00:00–05:00</span>"),
  "вдень (понад 4 год до неї) — лише години");
assert.equal(curfewNote({ ...base, ends_at: "2026-10-04T21:15:00Z" }, curfew, now).left, 0, "00:15 — уже під час");
assert.equal(curfewNote({ ...base, ends_at: "2026-10-04T20:20:00Z" }, curfew, now).left, 40, "23:20 — 40 хв");
assert.equal(curfewNote({ ...base, starts_at: "2026-10-01T16:00:00Z" }, curfew, now), null, "прокат на кілька днів — без рядка");
assert.equal(curfewNote({ ...base, ends_at: null }, curfew, now), null, "без кінця — без рядка");
assert.equal(curfewNote(base, { starts: "x", ends: "05:00" }, now), null, "зламані години — без рядка");
// «Шукаю компанію» — друга дія афішної події, шторкою з event.js; на зустрічі людей і минулій — нема.
const company = eventPage({ ...base, origin: "import", canonical_url: "https://concert.ua/x", source_name: "Concert.ua" }, now);
assert.ok(company.includes('data-lock="company">') && company.includes('<script type="module" src="/js/event.js?v=21"></script>'));
assert.ok(company.indexOf("Квитки на Concert.ua") < company.indexOf('data-lock="company"'), "квитки — головна, компанія — під ними");
assert.ok(!community.includes('data-lock="company"') && !community.includes("/js/event.js"), "зустріч людей — без неї");
assert.ok(!eventPage({ ...base, origin: "import", canonical_url: "https://concert.ua/x" }, new Date("2026-10-05T00:00:00Z")).includes('data-lock="company"'), "минула — ні");
assert.ok(eventPage({ ...base, status: "cancelled" }, now).includes("Подію скасовано."));
assert.ok(eventPage(base, new Date("2026-10-05T00:00:00Z")).includes("вже минула"));
const companion = eventPage({ ...base, title: "Йдемо разом: Концерт", companion_of: "b2000000-0000-4000-8000-000000000001", companion_of_title: "Концерт <b>" }, now);
assert.ok(companion.includes('Разом на: <a href="/e/b2000000-0000-4000-8000-000000000001">Концерт &lt;b&gt;</a>'), "супутник веде на афішу");
assert.ok(!eventPage({ ...base, companion_of: "javascript:alert(1)" }, now).includes("Разом на"), "лише uuid у href");
assert.ok(!community.includes("Разом на"), "звичайна подія без рядка");
assert.ok(eventPage({ ...base, title: "СТЕНДАП \"ПЕРЕВІРКА\"" }, now).includes("<h1>Стендап «Перевірка»</h1>"), "назва — як у застосунку");
assert.ok(imported.includes("Квитки на Concert.ua"), "головна дія афіші — квитки в джерела");
assert.ok(community.includes("data-join>Йду</button>") && !community.includes("Приєднатися в застосунку"), "зустріч людей — запис просто на сторінці (1.5)");
// База без фази 4: знята — «не знайшли в продажу», без тривоги й без кнопки квитків.
const withdrawn = eventPage({ ...base, origin: "import", canonical_url: "https://concert.ua/x", source_name: "Concert.ua", import_status: "withdrawn" }, now, shelters);
assert.ok(withdrawn.includes('class="notice calm">Не знайшли в продажу'), "знята з афіші — нейтрально");
assert.ok(!withdrawn.includes("Квитки на"), "і без кнопки квитків");
assert.ok(!withdrawn.includes("Укриття поруч"), "і без укриттів");
assert.ok(withdrawn.includes("<h2>Якщо купили квиток</h2>") && withdrawn.includes('href="https://concert.ua/x"'), "куди по повернення");

// Фаза 4: стан і всі продавці (docs/event-offers.md R11).
const afisha = { ...base, origin: "import", canonical_url: "https://concert.ua/x", source_name: "Concert.ua", price_min: 400, import_status: "live" };
const offers = [
  { source: "Concert.ua", url: "https://concert.ua/x", price_min: 400, live: true },
  { source: "Karabas <b>", url: "https://karabas.com/y", price_min: 450, live: true },
  { source: "Badseller", url: "https://badseller.net/z", price_min: 300, live: false },
  { source: "Http", url: "http://evil.example/", live: true },
];
const many = eventPage({ ...afisha, state: "scheduled", offers, checked_at: "2026-09-28T06:00:00Z" }, now);
assert.ok(many.includes('<span class="overline">Джерело</span><b>Concert.ua, Karabas &lt;b&gt;</b>'), "джерело на квитку — усі живі продавці, екрановано");
assert.ok(many.includes("<h2>Квитки</h2>") && many.includes("від 450 ₴") && many.includes('href="https://karabas.com/y?utm_source=poriad"'), "рядок і ціна кожного, з міткою для продавця");
assert.ok(!many.includes("badseller.net") && !many.includes("evil.example"), "знятий продавець і не-https — без рядка");
assert.ok(many.includes("Перевірено пн, 28 вересня о 09:00."), "перевірено — датою в поясі події");
assert.ok(many.includes("Квитки на Concert.ua"), "головна кнопка — основний продавець");
const cancelledAfisha = eventPage({ ...afisha, state: "cancelled", offers }, now, shelters);
assert.ok(cancelledAfisha.includes('class="notice">Подію скасовано: продавець'), "скасована — червоним, з поясненням");
assert.ok(cancelledAfisha.includes("<h2>Якщо купили квиток</h2>") && cancelledAfisha.includes("badseller.net"), "повернення — у кожного, де могли купити");
assert.ok(!cancelledAfisha.includes("Квитки на") && !cancelledAfisha.includes("від 450"), "без кнопки й цін");
assert.ok(eventPage({ ...afisha, state: "postponed", offers }, now).includes("Подію відкладено, нової дати ще нема"));
const movedAfisha = eventPage({ ...afisha, state: "scheduled", previous_starts_at: "2026-10-03T16:00:00Z", offers }, now);
assert.ok(movedAfisha.includes('class="notice calm">Перенесено: було сб, 3 жовтня о 19:00.'), "перенесена — стара дата, без тривоги");
assert.ok(movedAfisha.includes("Квитки на Concert.ua"), "перенесена жива — з квитками");
assert.ok(!eventPage({ ...afisha, state: "cancelled" }, new Date("2026-10-05T00:00:00Z")).includes("Якщо купили"), "минула — без продавців");
assert.ok(!community.includes("<h2>Квитки</h2>"), "кімната людей — без продавців");
assert.equal(esc(`"'<&>`), "&quot;&#39;&lt;&amp;&gt;");

// Старий id злитої події: 301 на живу, а не друга копія сторінки.
globalThis.fetch = detailsOk;
const moved = await eventResponse("c3000000-0000-4000-8000-000000000001", env);
assert.equal(moved.status, 301);
assert.equal(moved.headers.get("location"), `https://poriad.app/e/${base.id}`);
assert.equal((await eventResponse(base.id, env)).status, 200, "живий id — сторінка");

// Подія організатора без запису (origin = 'partner'): оголошення з «Квитками» чи «Вхід без запису», без «Йду» й місць.
const venue = { ...base, title: "Джаз у кафе", origin: "partner", capacity: null, attendee_count: 0, approval_required: false, organizer_name: "Кафе Тест",
  canonical_url: "https://tickets.example/jazz", price_min: 300 };
const ticketed = eventPage(venue, now);
assert.ok(ticketed.includes('href="https://tickets.example/jazz') && ticketed.includes(">Квитки</a>"), "кнопка «Квитки» веде на сторінку продажу");
assert.ok(!ticketed.includes("data-join") && !ticketed.includes("/js/join.js") && !ticketed.includes("data-spots"), "ні «Йду», ні місць");
assert.ok(ticketed.includes('<span class="overline">Організовує</span><b>Кафе Тест</b>') && ticketed.includes("від 300 ₴"), "організатор і ціна «від»");
assert.ok(!ticketed.includes('rel="canonical"') && !ticketed.includes("Джерело"), "не афіша з кас: без продавців і canonical на них");
const walkIn = eventPage({ ...venue, canonical_url: null, price_min: null, is_free: true }, now);
assert.ok(walkIn.includes('<p class="closed">Вхід без запису</p>') && walkIn.includes("Безкоштовно") && !walkIn.includes("data-join"), "вільний вхід");
assert.ok(eventPage({ ...venue, canonical_url: null, status: "cancelled" }, now).includes("Подію скасовано."), "скасована — словами організатора");

// Склад («Хто виступає»): імена з картки ведуть на сторінку артиста; без складу чи зі збоєм картки сторінка та сама.
const lineup = [{ id: "d4000000-0000-4000-8000-000000000001", name: "Гурт <b>", kind: "group", role: "performer" },
  { id: "javascript:alert(1)", name: "Без сторінки" }];
const staged = eventPage({ ...venue, artists: lineup }, now);
assert.ok(staged.includes('<h2>Хто виступає</h2><div class="artist-chips"><a class="chip" href="/a/d4000000-0000-4000-8000-000000000001">Гурт &lt;b&gt;</a></div>'),
  "ім'я екрановано й веде на /a/{id}; лише uuid у href");
assert.ok(eventPage({ ...base, artists: lineup }, now).includes("Хто виступає") && eventPage({ ...afisha, artists: lineup }, now).includes("Хто виступає"), "і від людей, і в афіші з кас");
assert.equal(eventPage({ ...base, artists: [] }, now), community, "порожній склад — сторінка без змін");
assert.equal(eventPage({ ...base, artists: "x" }, now), community, "сміття замість складу — теж");
const withCards = (cards) => async (url, init) => url.endsWith("/event_cards_by_ids")
  ? (assert.deepEqual(JSON.parse(init.body), { p_ids: [base.id] }), cards()) : detailsOk(url);
globalThis.fetch = withCards(() => new Response(JSON.stringify([{ id: base.id, artists: lineup }])));
assert.ok((await (await eventResponse(base.id, env)).text()).includes('href="/a/d4000000-0000-4000-8000-000000000001">Гурт &lt;b&gt;</a>'), "склад приходить з картки");
for (const cards of [() => new Response("boom", { status: 500 }), () => { throw new Error("мережа"); }, () => new Response(JSON.stringify([{ id: base.id }]))]) {
  globalThis.fetch = withCards(cards);
  const page = await eventResponse(base.id, env);
  assert.ok(page.status === 200 && !(await page.text()).includes("Хто виступає"), "збій картки чи подія без складу — сторінка як була");
}
// Групи «Йдемо разом» на афішу (критика сайту 12.11): спершу приєднатися до наявної, свою — у застосунку.
const groups = [
  { id: "c5000000-0000-4000-8000-000000000001", starts_at: "2026-10-04T15:30:00Z", time_zone: "Europe/Kyiv", meet_note: "Біля <входу>", capacity: 4, attendee_count: 1 },
  { id: "javascript:alert(1)", starts_at: "2026-10-04T15:30:00Z", capacity: 4 },
];
const together = eventPage({ ...afisha, offers, companions: groups }, now);
assert.ok(together.includes('<div class="block" id="company"><h2>Уже шукають компанію · 1</h2>'), "блок з числом груп; лише uuid");
assert.ok(together.includes('<a class="row" href="/e/c5000000-0000-4000-8000-000000000001">') && together.includes("Біля &lt;входу&gt;")
  && together.includes("вільно 3 місця"), "група веде на свою сторінку, примітка екранована, скільки вільно");
assert.ok(together.includes('href="#company">') && together.includes("Шукаю компанію · 1") && together.includes('data-lock="company">'),
  "кнопка в панелі веде до груп, «Зібрати свою групу» — шторка застосунку");
const lonely = eventPage({ ...afisha, offers }, now);
assert.ok(!lonely.includes("Уже шукають") && !lonely.includes('href="#company"') && lonely.includes('data-lock="company">'), "без груп — шторка, як було");
assert.ok(!eventPage({ ...base, companions: groups }, now).includes("Уже шукають"), "у кімнати людей груп нема");
// eventResponse бере справжній годинник: афіша — у майбутньому, інакше вона минула й груп не показує.
const soon = { ...afisha, starts_at: new Date(Date.now() + 3 * 864e5).toISOString(), ends_at: new Date(Date.now() + 3 * 864e5 + 2 * 36e5).toISOString() };
globalThis.fetch = async (url) => new Response(url.endsWith("/event_details") ? JSON.stringify([soon]) : url.endsWith("/companions") ? JSON.stringify(groups) : "{}");
assert.ok((await (await eventResponse(base.id, env)).text()).includes("Уже шукають компанію · 1"), "групи приходять з companions");
globalThis.fetch = async (url) => url.endsWith("/companions") ? new Response("boom", { status: 500 }) : new Response(url.endsWith("/event_details") ? JSON.stringify([soon]) : "{}");
const failed = await eventResponse(base.id, env);
assert.ok(failed.status === 200 && !(await failed.text()).includes("Уже шукають"), "збій груп — сторінка без блоку");

// Промокод (docs/promo-pins-2026-11.md): рядок-корінець із «Скопіювати» над діями, скрипт — лише з ним; на минулій,
// скасованій і без коду — нема.
const promoted = eventPage({ ...afisha, category: "music", promo_code: "PORIAD15", promo_note: "−15% на квитки <b>", promo_until: afisha.starts_at }, now);
assert.ok(promoted.includes('<div class="ticket promo cat-music"><div class="face"><small>Промокод</small>'), "корінець кольору жанру");
assert.ok(promoted.includes("<b>PORIAD15</b> · −15% на квитки &lt;b&gt;</p>"), "код і що дає, текст екранований");
assert.ok(promoted.includes('data-promo="PORIAD15" data-event=') && promoted.includes("Скопіювати</button>"));
assert.ok(promoted.indexOf("data-promo=") < promoted.indexOf('class="actions"') && promoted.indexOf("data-promo=") < promoted.indexOf("Квитки на Concert.ua"),
  "над діями й квитками");
assert.ok(promoted.includes('<script type="module" src="/js/promo.js?v=21"></script>'), "кнопка — файлом з домену, без inline");
assert.ok(eventPage({ ...base, promo_code: "PORIAD15" }, now).includes("<b>PORIAD15</b></p>"), "без «що дає» — лише код, і на події від людей");
for (const [why, e, at] of [["без коду", afisha, now], ["минула", { ...afisha, promo_code: "X1" }, new Date("2026-10-05T00:00:00Z")],
  ["скасована", { ...afisha, promo_code: "X1", status: "cancelled" }, now]]) {
  const page = eventPage(e, at);
  assert.ok(!page.includes("data-promo") && !page.includes("promo.js"), why);
}

console.log("event ok");
