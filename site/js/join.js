// «Йду» з вебу (docs/organizers-1.5.md, 1.1). Шторку малює воркер (worker/index.mjs, joinSheet) однаковою для всіх і
// кешує зі сторінкою, а цей скрипт входить (auth.js), записує, показує стан запису й «Після запису». Він же робить
// `?unfollow` з листа. На сторінці без шторки (афіша) нічого не робить. Правила без DOM — експорти, перевірка —
// `node tools/join_test.mjs`.
import { session, sendCode, verifyCode, google, completeRedirect, rpc, signOut, inAppBrowser, browserLinks } from "./auth.js?v=21";
import { SUPABASE, discover, fold, cardsByIds, esc, displayTitle, stubParts, timeOf, CATEGORIES, price, priceText, threadsPost, threadsIntent, plural, POST_MONTHS } from "./poriad.js?v=21";
import { threadFeed, sendProof, forgetProofs, openProof, payStage } from "./chat.js?v=21";

/** Відповідь бази на запис → стан шторки (таблиця «Інші відповіді на запис»). Невідома — null: показуємо помилку. */
const OUTCOMES = {
  AGE_REQUIRED: "profile", EVENT_FULL: "full",
  EVENT_CANCELLED: "closed", EVENT_STARTED: "closed", EVENT_NOT_FOUND: "closed", IMPORTED_EVENT: "closed",
  TOO_YOUNG: "age", TOO_OLD: "age", UNDERAGE: "age",
  ACCOUNT_RESTRICTED: "denied", BLOCKED: "denied", TOO_MANY_JOINS: "rate", ORGANIZER_CANNOT_JOIN: "own",
  session_expired: "start",
};
export const outcome = (code) => OUTCOMES[code] ?? null;

/** Стани шторки: заголовок, підпис і що з дій видно. `leave` — текст скасування. */
export const STATUS = {
  approved: { title: "Ви в списку", ics: true, leave: "Скасувати запис", after: true, ask: true },
  requested: { title: "Заявку надіслано", text: "Відповідь організатора прийде на пошту.", leave: "Скасувати заявку", after: true, ask: true },
  // Оплата онлайн (docs/organizer-events.md): заявка — це розмова про оплату; заголовок і текст — за нею (payStatus).
  requestedPay: { title: "Чекає оплати", leave: "Скасувати заявку", after: true, ask: true },
  approvedPay: { title: "Оплачено — ви в списку", ics: true, leave: "Скасувати запис", after: true, ask: true },
  full: { title: "Місць уже нема", text: "Якщо хтось відмовиться, напишемо.", waitlist: true, after: true, week: true },
  waitlist: { title: "Ви в черзі", text: "Якщо хтось відмовиться, напишемо.", leave: "Вийти з черги", after: true, week: true, ask: true },
  closed: { title: "Запис на цю подію закрито." },
  age: { title: "" }, // ageLimit
  denied: { title: "Записатися не вийшло." },
  rate: { title: "Записатися не вийшло.", text: "Забагато записів за годину. Спробуйте пізніше." },
  own: { title: "Це ваша подія." },
  left: { title: "Запис скасовано" }, withdrawn: { title: "Заявку скасовано" }, unqueued: { title: "Ви вийшли з черги" },
  unfollowAsk: { title: "", text: "Листів про нові події цього організатора більше не буде.", unfollow: true }, // unfollowTitle
  unfollowed: { title: "Ви більше не стежите", text: "Листів про нові події цього організатора не буде." },
  signedOut: { title: "Ви вийшли", text: "На цьому пристрої сторінка більше не памʼятає вашого акаунта." },
};
/** Напис на кнопці внизу сторінки. */
const LABELS = { none: "Йду", approved: "Ви в списку", approvedPay: "Ви в списку", requested: "Заявку надіслано", requestedPay: "Чекає оплати", waitlist: "Ви в черзі" };
/** Штамп стану на квитку шторки й панелі (DESIGN.md, Ticket Stamp): участь — success, запит і черга — штампова фарба. */
export const STAMPS = { approved: ["Ви йдете", "success"], approvedPay: ["Ви йдете", "success"], requested: ["Запит", "accent"],
  requestedPay: ["Чекає оплати", "accent"], waitlist: ["Черга", "accent"] };
/** Стан для шторки й кнопки: у події з оплатою онлайн заявка — «Чекає оплати», запис — «Оплачено». */
export const statusKind = (state, payOnline) => (payOnline && (state === "requested" || state === "approved") ? `${state}Pay` : state);
/** Заявка з оплатою онлайн за розмовою (chat.js, payStage): заголовок шторки й що робити далі. `sum` — «250 ₴». */
export const payStatus = (stage, sum = "") => ({
  details: { title: "Чекає оплати", text: `Організатор напише в розмові, як оплатити${sum ? ` ${sum}` : ""}. Лист прийде на пошту.` },
  payment: { title: "Реквізити в розмові", text: `Оплатіть${sum ? ` ${sum}` : ""} за реквізитами й надішліть скріншот у розмові.` },
  proof: { title: "Оплату перевіряє організатор", text: "Коли гроші прийдуть, організатор підтвердить заявку — і ви в списку." },
}[stage]);
/**
 * Тому, хто платить: хто організатор — довіра замість тривоги, як у шапці розмови в застосунку («Марта · На «Поряд» з
 * вересня 2026 · 3 події організовано»). `card` — рядок `profile_card`.
 */
export function organizerTrust(card) {
  if (!card) return "";
  const at = new Date(card.member_since ?? "");
  const organized = Number(card.organized) || 0;
  return [card.display_name, Number.isNaN(at.getTime()) ? "" : `На «Поряд» з ${POST_MONTHS[at.getUTCMonth()]} ${at.getUTCFullYear()}`,
    organized ? plural(organized, ["подію організовано", "події організовано", "подій організовано"]) : ""].filter(Boolean).join(" · ");
}
/** Смуга над розмовою — ті самі слова, що в застосунку (`pay_thread_*_mine`). */
export const PAY_BAR = {
  details: "Чекає оплати: організатор напише тут, як оплатити.",
  payment: "Оплатіть за реквізитами й надішліть сюди скріншот.",
  proof: "Скріншот надіслано: організатор звірить оплату й підтвердить заявку.",
  paid: "Оплачено — ви в списку.",
  cancelled: "Подію скасовано. Якщо ви вже оплатили, організатор має повернути гроші — напишіть йому тут.",
};

/** Помилки входу й дрібних дій — текстом під формою. */
const MESSAGES = {
  otp_expired: "Код не підходить або вже застарів. Перевірте лист чи надішліть новий.",
  over_email_send_rate_limit: "Забагато листів за годину. Спробуйте трохи пізніше.",
  over_request_rate_limit: "Забагато спроб. Спробуйте за кілька хвилин.",
  email_address_invalid: "Перевірте адресу пошти.", validation_failed: "Перевірте адресу пошти.",
  pkce_missing: "Вхід почався в іншій вкладці. Спробуйте ще раз тут.",
  access_denied: "Вхід через Google скасовано.",
  INVALID_BIRTH_DATE: "Перевірте дату народження.",
  FOLLOW_UNAVAILABLE: "Стежити за цим організатором зараз не можна.", TOO_MANY_FOLLOWS: "Ви вже стежите за 200 організаторами й місцями.",
  // Розмова з організатором.
  PAYMENT_DETAILS: "Реквізити тут не надсилаються: про оплату домовляйтеся з організатором у чаті учасників чи на місці.",
  TOO_MANY_MESSAGES: "Забагато повідомлень. Зачекайте хвилину.", CHAT_CLOSED: "Розмову закрито: подія давно минула.",
  INVALID_MESSAGE: "Повідомлення — до 2000 символів.", OBJECTIONABLE_CONTENT: "Текст містить слова, які ми не публікуємо. Перепишіть, будь ласка.",
  NOT_MEMBER: "Написати організатору зараз не можна.",
  NOT_IMAGE: "Оберіть зображення — скріншот оплати.", TOO_BIG: "Скріншот завеликий навіть після стиснення.",
  INVALID_IMAGE: "Скріншот не вдалося надіслати. Спробуйте ще раз.",
};

/**
 * Хто чим ділиться (docs/organizers-1.5.md, 1.6) — та сама умова, що `ShareRules.mode` у застосунку: «Поширити анонс»
 * (promote) — лише організатор власної звичайної спільнотної події без companion_of, не скасованої, не завершеної й не
 * «лише за посиланням» (публічний пост суперечив би вибору).
 * Решта — «Поділитися з другом» (friend). `event` — рядок event_details, `me` — id акаунта (null — гість).
 */
export function shareMode(event, me, now = Date.now()) {
  const ended = event?.ends_at ? Date.parse(event.ends_at) <= now : false;
  return me && event?.origin === "community" && !event.companion_of && event.organizer_id === me && !event.link_only && event.status !== "cancelled" && !ended
    ? "promote" : "friend";
}

/** Питання перед відпискою з листа: імʼя — прикладкою, щоб не відмінювати («за організатором Марта»). */
export const unfollowTitle = (name) => (name ? `Не стежити за організатором ${name}?` : "Не стежити за організатором?");

/** «Ця подія для 21+.» чи «…для 18–35.» — з меж події. */
export const ageLimit = (min, max) => `Ця подія для ${max ? `${min || 18}–${max}` : `${min || 18}+`}.`;
/** Дату народження питаємо лише для віку від 19 чи верхньої межі: решті досить галочки. */
export const needsBirthDate = (min, max) => Number(min) > 18 || Boolean(Number(max));

/**
 * «Цього тижня в {місті}»: та сама вибірка, що /afisha/{місто} (попереду, згорнута, на 7 днів), але й зустрічі людей —
 * першими, бо мірило 1.5 — запис на подію іншого організатора. Індекс → id карток, які варто дотягнути.
 */
export function weekPool(index, id, now = Date.now()) {
  const list = fold(index.filter((e) => e.id !== id && Date.parse(e.startsAt) >= now));
  return [...list.filter((e) => e.origin === "community"), ...list.filter((e) => e.origin !== "community")].slice(0, 12).map((e) => e.id);
}
// ponytail: картки не несуть organizer_id, тож події організатора відсіюємо за іменем; тезка ховає й свою подію —
// додати organizer_id в event_cards, якщо заважатиме.
export function weekPicks(cards, { id, organizer, now = Date.now() }) {
  const live = cards.filter((c) => c.id !== id && c.organizer_name !== organizer && Date.parse(c.starts_at) >= now
    && c.status !== "cancelled" && c.import_status !== "withdrawn" && !["cancelled", "postponed", "unknown"].includes(c.state));
  const rank = (c) => (c.origin === "community" ? 0 : 1);
  return live.sort((a, b) => rank(a) - rank(b) || Date.parse(a.starts_at) - Date.parse(b.starts_at)).slice(0, 3);
}

/** Рядок «Цього тижня» — як рядок сторінки міста (worker/index.mjs, cityRow). */
export function weekRow(card, now = new Date()) {
  const category = CATEGORIES[card.category] ? card.category : "social";
  const [time, day] = stubParts(card, now, true);
  const meta = [timeOf(new Date(card.starts_at), card.time_zone || "Europe/Kyiv"), card.origin === "community" ? "Від людей" : CATEGORIES[category],
    card.place_name || card.address, price(card)].filter(Boolean).join(" · ");
  return `<a class="row" href="/e/${esc(card.id)}"><div class="ticket v stub-tile cat-${category}" aria-hidden="true"><div class="face"><b class="t">${esc(time)}</b></div><div class="stub"><small>${esc(day)}</small></div></div>
    <div class="txt"><small>${esc(meta)}</small><b>${esc(displayTitle(card.title))}</b></div></a>`;
}

const PENDING = "poriad.join"; // пошта, на яку пішов код: Threads може перезавантажити сторінку, поки людина в пошті
const PENDING_TTL = 15 * 60_000; // старий код однаково протух, а шторка не має вискакувати на кожному перезавантаженні
const sheet = globalThis.document?.querySelector(".join-sheet");
if (sheet) start(sheet);

/** Шторка на сторінці: обробники й стан. Експорт — для tools/join_test.mjs (фейковий DOM). */
export function start(sheet) {
  const $ = (selector) => sheet.querySelector(selector);
  const box = $(".install-box");
  const data = sheet.dataset;
  const id = data.event;
  const bar = document.querySelector("[data-join]");
  let action = "join"; // що зробити після входу: join, unfollow чи ask (написати організатору)
  const payOnline = "payOnline" in data;
  const sum = Number(data.price) > 0 ? priceText(data.price) : "";
  let stage = "details"; // оплата онлайн: де заявка за розмовою (payStage)
  let person = null; // чия розмова з організатором відкрита: моя заявка
  let talked = false; // у розмові вже щось є: порожню пояснює її власний текст, смуга лише повторила б його
  let agreed = false; // оплата онлайн: людина погодилась на умови цієї події (accept_pay_terms) — можна подавати заявку
  let state = "none";
  let shown = null; // що зараз у шторці
  let version = 0; // скільки разів мінявся стан: тихе оновлення не перезаписує свіжішого
  let working = false;
  let fresh = false; // щойно записались: штамп на панелі ще не падав
  let resendTimer;

  /** Одна дія за раз: подвійний тап не шле двох листів і не записує двічі. */
  const task = (fn) => async (event) => {
    event?.preventDefault();
    if (working) return;
    working = true;
    for (const el of [box, bar]) el?.setAttribute("aria-busy", "true");
    try { await fn(event); } catch (e) { fail(e); } finally {
      working = false;
      for (const el of [box, bar]) el?.removeAttribute("aria-busy");
    }
  };

  function open(step) {
    for (const section of sheet.querySelectorAll("[data-step]")) section.hidden = section.dataset.step !== step;
    $("[data-error]").hidden = true;
    if (step === "start") $("[data-head]").textContent = action === "unfollow" ? "Не стежити за організатором" : action === "ask" ? "Написати організатору" : "Записатися";
    // Назва вікна для читача екрана — заголовок кроку, який видно, а не загальне «Запис на подію».
    sheet.setAttribute("aria-label", $(`[data-step="${step}"] h2`)?.textContent || "Запис на подію");
    if (!sheet.open) sheet.showModal();
    signedInAs(step).catch(() => {});
  }
  /** «Ви ввійшли як … · Вийти» під кроками після входу: за спільним компʼютером видно, чий акаунт, і є як вийти. */
  async function signedInAs(step) {
    const line = $("[data-account]");
    if (!line) return;
    const current = step === "start" || step === "code" ? null : await session();
    line.hidden = !current;
    $("[data-account-email]").textContent = current?.user?.email ?? ""; // після виходу пошти в сторінці не лишаємо
  }
  function error(text) {
    const el = $("[data-error]");
    el.textContent = text;
    el.hidden = false;
  }
  function fail(e) {
    // Сервер не знайшов згоди на оплату онлайн (інша вкладка, стара сторінка) — показуємо умови ще раз.
    if (e?.code === "PAY_TERMS_REQUIRED" && payOnline) { agreed = false; return open("pay"); }
    const kind = outcome(e?.code);
    if (kind === "profile") return askProfile();
    if (kind === "start") return open("start");
    if (kind) return show(kind);
    if (!sheet.open) open("start");
    error(MESSAGES[e?.code] ?? (e?.status ? "Не вийшло. Спробуйте ще раз." : "Нема звʼязку. Спробуйте ще раз."));
  }

  function setState(next) {
    state = next;
    version += 1;
    if (bar) bar.textContent = LABELS[statusKind(next, payOnline)];
    const proofPick = $("[data-proof-pick]");
    if (proofPick) proofPick.hidden = next !== "requested"; // оплачено — скріншот більше не потрібен
    paintPayBar();
    // Записаний — на квитку штамп, а «Йду» стає тоновою: головна дія вже зроблена.
    document.querySelector(".bar")?.setAttribute("data-state", next);
    const [word, tone] = STAMPS[statusKind(next, payOnline)] ?? ["", ""];
    for (const stamp of [$("[data-going]"), document.querySelector(".bar [data-going]")]) {
      if (!stamp) continue;
      stamp.textContent = word;
      stamp.className = `stamp ${tone}`;
      stamp.hidden = !word;
    }
  }
  function show(kind) {
    kind = statusKind(kind, payOnline);
    const s = kind === "requestedPay" ? { ...STATUS.requestedPay, ...payStatus(stage, sum) } : STATUS[kind];
    shown = kind;
    $("[data-title]").textContent = kind === "age" ? ageLimit(Number(data.minAge), Number(data.maxAge))
      : kind === "unfollowAsk" ? unfollowTitle(data.organizer ? data.organizerName : "") : s.title;
    const text = $("[data-text]");
    text.textContent = s.text ?? "";
    text.hidden = !s.text;
    $("[data-waitlist]").hidden = !s.waitlist;
    $("[data-ics]").hidden = !s.ics;
    const unfollowButton = $("[data-unfollow]"); // сторінка з кешу могла прийти ще без цієї кнопки
    if (unfollowButton) unfollowButton.hidden = !s.unfollow;
    const askButton = $("[data-open-ask]");
    if (askButton) askButton.hidden = !s.ask || !feed;
    const leave = $("[data-leave]");
    leave.textContent = s.leave ?? "";
    leave.hidden = !s.leave;
    $("[data-after]").hidden = !s.after;
    const week = $("[data-week]");
    if (week && !s.week) week.hidden = true;
    open("status");
    if (kind === "requestedPay") readStage().catch(() => {});
    if (s.after) after().catch(() => {});
    if (s.week) thisWeek().catch(() => {});
  }

  // ---- Запис
  async function proceed() {
    if (!(await session())) return open("start");
    return action === "unfollow" ? askUnfollow() : action === "ask" ? openAsk() : join();
  }

  // ---- Розмова з організатором («Поряд» — міст: пошти й телефону одне одного не видно). Стрічка — chat.js.
  const threadBox = $("[data-thread]"); // сторінка з кешу могла прийти ще без розмови
  const feed = threadBox && threadFeed(threadBox, {
    empty: `<p class="fine" data-empty>${payOnline ? "Організатор напише тут, як оплатити. Можете й самі спитати щось про подію." : "Спитайте про подію — відповідь прийде сюди й на пошту."}</p>`,
    alive: () => sheet.open && !$('[data-step="ask"]').hidden,
    changed: (rows) => {
      if (talked !== rows.length > 0) { talked = rows.length > 0; paintPayBar(); }
      setStage(payStage(rows, person));
    },
    live: $("[data-thread-live]"),
  });
  /** Де заявка з оплатою онлайн: смуга над розмовою, а відкрита шторка стану — новим заголовком. */
  function setStage(next) {
    if (next === stage) return;
    stage = next;
    paintPayBar();
    if (shown === "requestedPay" && !$('[data-step="status"]').hidden) show("requestedPay");
  }
  /** Шторка стану без відкритої розмови: стадію читаємо з тієї ж розмови. */
  async function readStage() {
    const me = (await session())?.user?.id;
    if (!me) return;
    person = me;
    const rows = (await rpc("event_messages", { p_event_id: id, p_after: null, p_limit: 100, p_thread: me })) ?? [];
    setStage(payStage(rows, me));
  }
  /** Хто організатор — один раз за сторінку: картка не змінюється, поки людина в розмові. */
  async function showTrust() {
    const line = payOnline && data.organizer && $("[data-trust]");
    if (!line || line.textContent) return;
    const rows = await rpc("profile_card", { p_user_id: data.organizer });
    line.textContent = organizerTrust(rows?.[0]);
    line.hidden = !line.textContent;
  }
  /** Смуга над розмовою (оплата онлайн): що зараз із заявкою і скільки платити — як у застосунку. */
  function paintPayBar() {
    const payBar = payOnline && $("[data-pay-bar]");
    if (!payBar) return;
    const text = "cancelled" in data && state !== "none" ? PAY_BAR.cancelled
      : state === "approved" ? PAY_BAR.paid : state === "requested" && talked ? PAY_BAR[stage] : "";
    payBar.hidden = !text;
    payBar.querySelector("span").textContent = text;
    payBar.querySelector("b").textContent = sum;
    payBar.classList.toggle("done", state === "approved");
    // Реквізити прийшли — наступний крок людини скріншот: кнопка над полем стає головною.
    const pick = $(".proof-pick");
    pick?.classList.toggle("primary", state === "requested" && stage === "payment");
    pick?.classList.toggle("secondary", !(state === "requested" && stage === "payment"));
  }
  async function openAsk() {
    if (!feed) return;
    const me = (await session())?.user?.id;
    if (!me) { action = "ask"; return open("start"); }
    // З листа розмову відкривають без стану запису, а скріншот можна лише записаним (як `can_upload_proof`).
    if (state === "none") refresh().catch(() => {});
    person = me;
    open("ask");
    showTrust().catch(() => {});
    await feed.show({ event: id, thread: me, me, organizer: data.organizer });
    $('[data-form="ask"] textarea')?.focus();
  }
  /** «Не стежити» з листа — лише після підтвердження: посилання могли відкрити випадково чи підсунути. */
  function askUnfollow() {
    show("unfollowAsk");
    refresh().catch(() => {}); // кнопка внизу має знати, що людина записана
  }
  async function join(waitlist = false) {
    // Онлайн-подія: спершу умови оплати напряму й правила повернення (згода зберігається на сервері).
    if (payOnline && !waitlist && !agreed) return open("pay");
    try {
      await rpc(waitlist ? "join_waitlist_web" : "join_event_web", { p_event: id });
    } catch (e) {
      if (waitlist && e.code === "EVENT_HAS_SPACE") return join();
      if (e.code !== "ALREADY_MEMBER") throw e;
    }
    // Запит пройшов, а в списку людини нема: не «нема звʼязку», а «не вийшло».
    if (!(await refresh())) throw Object.assign(new Error("Після запису людини нема в списку"), { status: 200 });
    // Штамп на панелі падає, коли шторку закриють: за шторкою його не видно (web.css, slam).
    document.querySelector(".bar")?.removeAttribute("data-fresh");
    fresh = true;
    show(state);
  }
  /**
   * Стан людини на цій події з бази: власний рядок учасника, інакше черга. Повертає, чи вона десь у списку. Заразом
   * свіжі місця в панелі: сторінка з кешу могла показати «0 з 6» тому, хто вже записаний. `quiet` — повторний візит без
   * замка: якщо людина тим часом натиснула «Йду» чи стан уже змінився, застарілу відповідь відкидаємо.
   */
  async function refresh(quiet = false) {
    const seen = version;
    const [event] = (await rpc("event_details", { p_event_id: id })) ?? [];
    await claimShare(event);
    // Учасники — у факті квитка й на панелі (з ціною на панелі — ціна, тож лише у факті).
    for (const spots of [document.querySelector(".facts [data-spots]"), document.querySelector(".bar [data-spots]")]) {
      if (spots && Number.isInteger(event?.attendee_count)) spots.textContent = event.capacity ? `${event.attendee_count} з ${event.capacity}` : `${event.attendee_count}`;
    }
    let next = ["approved", "requested"].includes(event?.membership) ? event.membership : "none";
    if (next === "none" && event?.capacity && ((await rpc("my_waitlist")) ?? []).includes(id)) next = "waitlist";
    if (quiet && (working || version !== seen)) return state !== "none";
    setState(next);
    return next !== "none";
  }
  async function leave() {
    const was = state;
    // Гроші повертає організатор, не «Поряд»: хто, можливо, вже заплатив, має це знати до скасування.
    if (payOnline && (was === "approved" || stage !== "details")
      && !confirm(`${STATUS[statusKind(was, payOnline)].leave}? Якщо ви вже оплатили, про повернення грошей домовтеся з організатором у розмові.`)) return;
    await rpc(was === "waitlist" ? "leave_waitlist" : "leave_event", { p_event_id: id });
    setState("none");
    show({ approved: "left", requested: "withdrawn", waitlist: "unqueued" }[was]);
  }
  async function unfollow() {
    if (data.organizer) await rpc("unfollow", { p_kind: "organizer", p_target: data.organizer });
    follows = null;
    show("unfollowed");
  }
  /** Вихід: сесію забуває auth.js, а сторінка — усе особисте (стан, запрошення, «Стежити», «Поширити анонс»). */
  async function leaveAccount() {
    await signOut();
    sessionStorage.removeItem(PENDING);
    invite = null;
    details = null;
    follows = null;
    mode = "friend";
    feed?.clear();
    forgetProofs();
    person = null;
    stage = "details";
    talked = false;
    const ask = document.querySelector("[data-ask]");
    if (ask) ask.hidden = false;
    if (shareButton) shareButton.lastChild.textContent = "Поділитися з другом";
    const copyLink = document.querySelector("[data-copy-link]");
    if (copyLink) copyLink.hidden = true;
    const afisha = document.querySelector("[data-afisha]");
    if (afisha) afisha.hidden = false;
    const follow = $("[data-follow]");
    if (follow) Object.assign(follow, { textContent: "Стежити", disabled: false });
    setState("none");
    show("signedOut");
  }

  // ---- Вхід
  function pending() {
    let p = null;
    try { p = JSON.parse(sessionStorage.getItem(PENDING)); } catch {}
    if (p && Date.now() - p.sentAt < PENDING_TTL) return p;
    sessionStorage.removeItem(PENDING);
    return null;
  }
  function codeStep(p) {
    $("[data-email]").textContent = p.email;
    open("code");
    const resend = $("[data-resend]");
    resend.disabled = true;
    clearTimeout(resendTimer);
    resendTimer = setTimeout(() => { resend.disabled = false; }, Math.max(0, p.sentAt + 60_000 - Date.now()));
  }
  async function send(email) {
    await sendCode(email);
    const p = { email, event: id, action, sentAt: Date.now() };
    sessionStorage.setItem(PENDING, JSON.stringify(p));
    codeStep(p);
  }

  /**
   * Крок 3: новий акаунт — імʼя (його бачить організатор); подія з віком від 19 чи верхньою межею — ще й дата. Вік 18+
   * підтверджує рядок згоди на першому кроці, тож `confirm_adult` — мовчки, без галочки (власник 02.11).
   */
  async function askProfile() {
    const form = $('[data-form="profile"]');
    const birth = needsBirthDate(data.minAge, data.maxAge);
    $("[data-birth]").hidden = !birth;
    form.birth.required = birth;
    if (!form.name.value) {
      const [row] = (await profile("GET").catch(() => null)) ?? [];
      // «Учасник» — імʼя акаунта з пошти за замовчуванням (handle_new_user): його людина впише сама.
      if (row?.display_name && row.display_name !== "Учасник") form.name.value = row.display_name;
    }
    open("profile");
  }
  /** Свій рядок profiles (політика profiles_update): RPC для імені нема. */
  async function profile(method, body) {
    const current = await session();
    if (!current) throw Object.assign(new Error("Сесія закінчилась"), { code: "session_expired" });
    const response = await fetch(`${SUPABASE.url}/rest/v1/profiles?id=eq.${current.user.id}${method === "GET" ? "&select=display_name" : ""}`, {
      method, body: body && JSON.stringify(body),
      headers: { apikey: SUPABASE.key, authorization: `Bearer ${current.access_token}`, "content-type": "application/json", prefer: "return=minimal" },
    });
    if (!response.ok) throw Object.assign(new Error(`profiles: ${response.status}`), { status: response.status });
    return method === "GET" ? response.json() : null;
  }

  // ---- Після запису
  let follows = null;
  async function after() {
    const current = await session();
    $("[data-google-hint]").hidden = !current?.user?.app_metadata?.providers?.includes("google");
    const button = $("[data-follow]");
    if (!button || !current) return;
    follows ??= await rpc("my_follows");
    if (follows.some((f) => f.kind === "organizer" && f.id === data.organizer)) followed(button);
  }
  function followed(button) {
    button.textContent = "Ви стежите";
    button.disabled = true;
  }

  // ---- Хто чим ділиться (1.6). Сторінка однакова для всіх: «Поділитися з другом» угорі гостю веде вбудований скрипт
  // сторінки (адреса без запрошення), а з входом кнопку бере цей скрипт — особисте посилання чи «Поширити анонс».
  const plain = () => location.origin + location.pathname;
  let details = null; // останній event_details: текст анонсу
  let mode = "friend";
  let invite = null; // особисте ?by= — готуємо заздалегідь: Safari не дає navigator.share після очікування мережі
  let shareButton = null;
  async function claimShare(event) {
    const me = (await session().catch(() => null))?.user?.id;
    if (!event || !me) return;
    details = event;
    mode = shareMode(event, me);
    if (!shareButton) {
      const original = document.querySelector("[data-share]");
      if (!original) return;
      // Копія без обробника вбудованого скрипта: інакше один тап ділився б двічі.
      shareButton = original.cloneNode(true);
      original.replaceWith(shareButton);
      shareButton.addEventListener("click", () => (mode === "promote" ? promote() : shareWithFriend(shareButton)));
    }
    shareButton.lastChild.textContent = mode === "promote" ? "Поширити анонс" : "Поділитися з другом";
    const copyLink = document.querySelector("[data-copy-link]");
    if (copyLink) copyLink.hidden = mode !== "promote";
    // Чотири дії в ряд на телефоні: організатору на своїй сторінці «Скопіювати посилання» замість «Афіші».
    const afisha = document.querySelector("[data-afisha]");
    if (afisha) afisha.hidden = mode === "promote";
    // Організатор на своїй сторінці: собі не пишуть, розмови з людьми — у кабінеті.
    const ask = document.querySelector("[data-ask]");
    if (ask) ask.hidden = event.organizer_id === me;
    if (mode === "friend") prepareInvite();
  }
  /** Токен запрошення; збій (мережа, ліміт, подія минула) лише знеособлює посилання, як у застосунку. */
  async function prepareInvite() {
    if (invite) return;
    try {
      const token = await rpc("create_invite", { p_event_id: id });
      if (typeof token === "string" && /^[A-Za-z0-9_-]{22}$/.test(token)) invite = `${plain()}?by=${token}`;
    } catch {}
  }
  const copy = (text) => navigator.clipboard?.writeText(text).then(() => true, () => false) ?? Promise.resolve(false);
  function flash(button, text) {
    const label = button.lastChild;
    const was = label.textContent;
    label.textContent = text;
    setTimeout(() => { label.textContent = was; }, 2000);
  }
  async function shareWithFriend(button) {
    const url = invite ?? plain();
    if (navigator.share) { try { await navigator.share({ title: document.querySelector("h1")?.textContent || document.title, url }); } catch {} return; }
    if (await copy(url)) flash(button, "Посилання скопійовано"); else prompt("Посилання на подію", url);
  }
  /** «Пост для Threads»: вкладку — першою й без await (Safari блокує window.open після очікування), текст — і в буфер. */
  function promote() {
    const text = threadsPost(details);
    window.open(threadsIntent(text), "_blank", "noopener");
    copy(text).then((ok) => { if (ok) flash(shareButton, "Текст скопійовано"); });
  }
  async function thisWeek() {
    const week = $("[data-week]");
    if (!week) return;
    if (!week.dataset.loaded) {
      week.dataset.loaded = "1";
      const now = Date.now();
      try {
        const { index } = await discover(data.city, { cards: 0, to: new Date(now + 7 * 864e5).toISOString() });
        const picks = weekPicks(await cardsByIds(weekPool(index, id, now)), { id, organizer: data.organizerName, now });
        week.querySelector("[data-cards]").innerHTML = picks.map((card) => weekRow(card)).join("");
      } catch (e) {
        delete week.dataset.loaded;
        throw e;
      }
    }
    // Поки вантажилось, людина могла вийти з черги.
    week.hidden = !STATUS[shown]?.week || !week.querySelector(".row");
  }

  // ---- Обробники
  bar?.addEventListener("click", task(() => {
    if (state !== "none") return show(state);
    action = "join";
    return proceed();
  }));
  $("[data-close]").addEventListener("click", () => sheet.close());
  document.querySelector("[data-ask]")?.addEventListener("click", task(() => {
    action = "ask";
    return proceed();
  }));
  $("[data-open-ask]")?.addEventListener("click", task(openAsk));
  $('[data-form="ask"]')?.addEventListener("submit", task(async (event) => {
    const form = event.target;
    const body = form.body.value.trim();
    if (!body) return;
    const me = (await session())?.user?.id;
    if (!me) { action = "ask"; return open("start"); }
    $("[data-error]").hidden = true;
    await rpc("send_message", { p_event_id: id, p_body: body, p_thread: me });
    form.reset();
    await feed.load();
  }));
  // Скріншот оплати — з текстом поля.
  $("[data-proof]")?.addEventListener("change", task(async (event) => {
    const file = event.target.files?.[0];
    event.target.value = "";
    if (!file) return;
    const me = (await session())?.user?.id;
    if (!me) { action = "ask"; return open("start"); }
    $("[data-error]").hidden = true;
    const form = $('[data-form="ask"]');
    await sendProof({ event: id, me, file, body: form.body.value.trim() });
    form.reset();
    await feed.load();
  }));
  threadBox?.addEventListener("click", (event) => { if (openProof(event)) event.preventDefault(); });
  // Номер з реквізитів — у буфер без пробілів: не всі банки приймають групи. Браузер не дав буфера — виділяємо номер,
  // щоб скопіювати вручну.
  threadBox?.addEventListener("click", async (event) => {
    const button = event.target.closest("[data-copy-number]");
    if (!button) return;
    if (await copy(button.dataset.copyNumber)) flash(button, "Скопійовано");
    else getSelection()?.selectAllChildren(button.previousElementSibling);
  });
  threadBox?.addEventListener("click", task(async (event) => {
    const button = event.target.closest("[data-report]");
    if (!button) return;
    if (!confirm("Поскаржитись на це повідомлення як на шахрайство? Модератори побачать його текст.")) return;
    await rpc("report_message", { p_message_id: button.dataset.report, p_reason: "scam" });
    button.replaceWith(Object.assign(document.createElement("span"), { textContent: "Скаргу надіслано" }));
  }));
  // Закрили шторку — передумали: наступне перезавантаження не відкриває крок з кодом.
  sheet.addEventListener("close", () => {
    feed?.stop();
    sessionStorage.removeItem(PENDING);
    if (fresh) document.querySelector(".bar")?.setAttribute("data-fresh", "");
    fresh = false;
  });
  sheet.addEventListener("click", (event) => { if (event.target === sheet) sheet.close(); });
  $("[data-google]").addEventListener("click", task(() => google(location.origin + location.pathname, { event: id, action })));
  $('[data-form="email"]').addEventListener("submit", task((event) => send(event.target.email.value.trim())));
  $('[data-form="code"]').addEventListener("submit", task(async (event) => {
    const p = pending();
    if (!p) return open("start");
    await verifyCode(p.email, event.target.code.value);
    sessionStorage.removeItem(PENDING);
    event.target.reset();
    await proceed();
  }));
  $("[data-resend]").addEventListener("click", task(() => send(pending()?.email ?? "")));
  $("[data-back]").addEventListener("click", () => {
    $('[data-form="email"]').email.value = pending()?.email ?? "";
    sessionStorage.removeItem(PENDING);
    open("start");
  });
  $('[data-form="profile"]').addEventListener("submit", task(async (event) => {
    const form = event.target;
    const name = form.name.value.trim();
    if (!name) {
      form.name.focus();
      return error("Напишіть, як вас звати.");
    }
    // Спершу дата: якщо їй менше 18, set_birth_date каже UNDERAGE, і 18+ із згоди ми вже не ставимо.
    if (needsBirthDate(data.minAge, data.maxAge)) {
      await rpc("set_birth_date", { p_birth: form.birth.value }).catch((e) => { if (e.code !== "AGE_ALREADY_SET") throw e; });
    }
    await rpc("confirm_adult");
    await profile("PATCH", { display_name: name });
    await join();
  }));
  $("[data-waitlist]").addEventListener("click", task(() => join(true)));
  $("[data-pay-agree]")?.addEventListener("click", task(async () => {
    await rpc("accept_pay_terms", { p_role: "payer", p_event_id: id });
    agreed = true;
    await join();
  }));
  $("[data-leave]").addEventListener("click", task(leave));
  $("[data-unfollow]")?.addEventListener("click", task(unfollow));
  $("[data-signout]")?.addEventListener("click", task(leaveAccount));
  $("[data-follow]")?.addEventListener("click", task(async () => {
    await rpc("follow", { p_kind: "organizer", p_target: data.organizer });
    follows = null;
    followed($("[data-follow]"));
  }));
  $("[data-invite]").addEventListener("click", (event) => shareWithFriend(event.currentTarget));
  document.querySelector("[data-copy-link]")?.addEventListener("click", async (event) => {
    const button = event.currentTarget;
    if (await copy(plain())) flash(button, "Посилання скопійовано"); else prompt("Посилання на подію", plain());
  });

  // Вбудований браузер Threads чи Instagram: Google туди вхід не пускає — кличемо в Safari чи Chrome.
  if (inAppBrowser()) {
    const links = browserLinks();
    $("[data-google]").hidden = true;
    $("[data-in-app]").hidden = false;
    $("[data-browser]").href = /Android/i.test(navigator.userAgent) ? links.android : links.ios;
  }

  // ---- Звідки прийшли: повернення від Google, «Не стежити» з листа, код у пошті. Повертає, чи щось зроблено.
  async function arrive() {
    try {
      const intent = await completeRedirect();
      if (intent?.event === id) { action = intent.action; await proceed(); return true; }
    } catch (e) {
      if (e.intent?.event === id) { action = e.intent.action; open("start"); throw e; }
    }
    const url = new URL(location.href);
    // «Відкрити розмову» з листа: організатор написав.
    if (url.searchParams.has("ask") && feed) {
      url.searchParams.delete("ask");
      history.replaceState(history.state, "", url);
      action = "ask";
      if (await session()) await openAsk(); else open("start");
      return true;
    }
    const unfollowing = url.searchParams.has("unfollow");
    if (unfollowing) {
      url.searchParams.delete("unfollow");
      history.replaceState(history.state, "", url);
      action = "unfollow";
      if (await session()) { askUnfollow(); return true; }
    }
    const p = pending();
    if (p?.event === id) {
      if (!unfollowing) action = p.action;
      codeStep(p);
      return true;
    }
    if (unfollowing) open("start");
    return unfollowing;
  }
  return task(async () => {
    if (await arrive()) return;
    // Повторний візит: сесія в localStorage — одразу «Ви в списку». Поза замком: тап на «Йду», поки стан вантажиться,
    // не губиться. Збій мережі тут мовчить: кнопка лишається «Йду».
    if (await session().catch(() => null)) refresh(true).catch(() => {});
  })();
}
