// «Йду» з вебу (docs/organizers-1.5.md, 1.1). Шторку малює воркер (worker/index.mjs, joinSheet) однаковою для всіх і
// кешує зі сторінкою, а цей скрипт входить (auth.js), записує, показує стан запису й «Після запису». Він же робить
// `?unfollow` з листа. На сторінці без шторки (афіша) нічого не робить. Правила без DOM — експорти, перевірка —
// `node tools/join_test.mjs`.
import { session, sendCode, verifyCode, google, completeRedirect, rpc, inAppBrowser, browserLinks } from "./auth.js?v=12";
import { SUPABASE, discover, fold, cardsByIds, esc, displayTitle, stubParts, timeOf, CATEGORIES, price } from "./poriad.js?v=12";

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
  approved: { title: "Ви в списку", ics: true, leave: "Скасувати запис", after: true },
  requested: { title: "Заявку надіслано", text: "Відповідь організатора прийде на пошту.", leave: "Скасувати заявку", after: true },
  full: { title: "Місць уже нема", text: "Якщо хтось відмовиться, напишемо.", waitlist: true, after: true, week: true },
  waitlist: { title: "Ви в черзі", text: "Якщо хтось відмовиться, напишемо.", leave: "Вийти з черги", after: true, week: true },
  closed: { title: "Запис на цю подію закрито." },
  age: { title: "" }, // ageLimit
  denied: { title: "Записатися не вийшло." },
  rate: { title: "Записатися не вийшло.", text: "Забагато записів за годину. Спробуйте пізніше." },
  own: { title: "Це ваша подія." },
  left: { title: "Запис скасовано" }, withdrawn: { title: "Заявку скасовано" }, unqueued: { title: "Ви вийшли з черги" },
  unfollowed: { title: "Ви більше не стежите", text: "Листів про нові події цього організатора не буде." },
};
/** Напис на кнопці внизу сторінки. */
const LABELS = { none: "Йду", approved: "Ви в списку", requested: "Заявку надіслано", waitlist: "Ви в черзі" };

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
};

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
  let action = "join"; // що зробити після входу: join чи unfollow
  let state = "none";
  let shown = null; // що зараз у шторці
  let version = 0; // скільки разів мінявся стан: тихе оновлення не перезаписує свіжішого
  let working = false;
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
    if (step === "start") $("[data-head]").textContent = action === "unfollow" ? "Не стежити за організатором" : "Записатися";
    if (!sheet.open) sheet.showModal();
  }
  function error(text) {
    const el = $("[data-error]");
    el.textContent = text;
    el.hidden = false;
  }
  function fail(e) {
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
    if (bar) bar.textContent = LABELS[next];
  }
  function show(kind) {
    const s = STATUS[kind];
    shown = kind;
    $("[data-title]").textContent = kind === "age" ? ageLimit(Number(data.minAge), Number(data.maxAge)) : s.title;
    const text = $("[data-text]");
    text.textContent = s.text ?? "";
    text.hidden = !s.text;
    $("[data-waitlist]").hidden = !s.waitlist;
    $("[data-ics]").hidden = !s.ics;
    const leave = $("[data-leave]");
    leave.textContent = s.leave ?? "";
    leave.hidden = !s.leave;
    $("[data-after]").hidden = !s.after;
    const week = $("[data-week]");
    if (week && !s.week) week.hidden = true;
    open("status");
    if (s.after) after().catch(() => {});
    if (s.week) thisWeek().catch(() => {});
  }

  // ---- Запис
  async function proceed() {
    if (!(await session())) return open("start");
    return action === "unfollow" ? unfollow() : join();
  }
  async function join(waitlist = false) {
    try {
      await rpc(waitlist ? "join_waitlist_web" : "join_event_web", { p_event: id });
    } catch (e) {
      if (waitlist && e.code === "EVENT_HAS_SPACE") return join();
      if (e.code !== "ALREADY_MEMBER") throw e;
    }
    // Запит пройшов, а в списку людини нема: не «нема звʼязку», а «не вийшло».
    if (!(await refresh())) throw Object.assign(new Error("Після запису людини нема в списку"), { status: 200 });
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
    const spots = document.querySelector("[data-spots]");
    if (spots && Number.isInteger(event?.attendee_count)) spots.textContent = event.capacity ? `${event.attendee_count} з ${event.capacity}` : `${event.attendee_count}`;
    let next = ["approved", "requested"].includes(event?.membership) ? event.membership : "none";
    if (next === "none" && event?.capacity && ((await rpc("my_waitlist")) ?? []).includes(id)) next = "waitlist";
    if (quiet && (working || version !== seen)) return state !== "none";
    setState(next);
    return next !== "none";
  }
  async function leave() {
    const was = state;
    await rpc(was === "waitlist" ? "leave_waitlist" : "leave_event", { p_event_id: id });
    setState("none");
    show({ approved: "left", requested: "withdrawn", waitlist: "unqueued" }[was]);
  }
  async function unfollow() {
    if (data.organizer) await rpc("unfollow", { p_kind: "organizer", p_target: data.organizer });
    show("unfollowed");
    await refresh().catch(() => {}); // з листа: кнопка внизу має знати, що людина записана
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

  /** Крок 3: новий акаунт — імʼя й галочка; подія з віком від 19 чи верхньою межею — ще й дата. */
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
  async function invite(button) {
    const url = location.origin + location.pathname;
    if (navigator.share) { try { await navigator.share({ title: document.querySelector("h1")?.textContent || document.title, url }); } catch {} return; }
    try {
      await navigator.clipboard.writeText(url);
      const label = button.lastChild;
      const was = label.textContent;
      label.textContent = "Посилання скопійовано";
      setTimeout(() => { label.textContent = was; }, 2000);
    } catch { prompt("Посилання на подію", url); }
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
  // Закрили шторку — передумали: наступне перезавантаження не відкриває крок з кодом.
  sheet.addEventListener("close", () => sessionStorage.removeItem(PENDING));
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
    // Спершу дата: якщо їй менше 18, set_birth_date каже UNDERAGE, і галочки ми вже не ставимо.
    if (needsBirthDate(data.minAge, data.maxAge)) {
      await rpc("set_birth_date", { p_birth: form.birth.value }).catch((e) => { if (e.code !== "AGE_ALREADY_SET") throw e; });
    }
    await rpc("confirm_adult");
    await profile("PATCH", { display_name: name });
    await join();
  }));
  $("[data-waitlist]").addEventListener("click", task(() => join(true)));
  $("[data-leave]").addEventListener("click", task(leave));
  $("[data-follow]")?.addEventListener("click", task(async () => {
    await rpc("follow", { p_kind: "organizer", p_target: data.organizer });
    follows = null;
    followed($("[data-follow]"));
  }));
  $("[data-invite]").addEventListener("click", (event) => invite(event.currentTarget));

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
    const unfollowing = url.searchParams.has("unfollow");
    if (unfollowing) {
      url.searchParams.delete("unfollow");
      history.replaceState(history.state, "", url);
      action = "unfollow";
      if (await session()) { await unfollow(); return true; }
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
