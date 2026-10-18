// Спільне для лендингу й афіші: квитки подій, шторка події, шторка «У застосунку», поява під час прокрутки.
// Сайт — режим перегляду: дивитися, ділитися й купувати квиток можна тут, а піти, зберегти, нагадати й знайти
// компанію — у застосунку. Кожна така кнопка відкриває шторку з тим, що саме дасть застосунок.
import {
  APP_STORE_URL, PLAY_URL, CATEGORIES, cardsByIds, eventSafety, displayTitle, overline, dayLabel, timeOf, stubParts,
  price, sourceNote, httpsOrNull, esc, otherDays, qrPath, eventUrl, icsFile, googleCalendarUrl,
} from "./poriad.js?v=8";

const ua = navigator.userAgent;
export const isIOS = /iPhone|iPad|iPod/.test(ua) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
export const isAndroid = /Android/.test(ua);
/** Підписи платформ — за перемикачем Google Play у poriad.js. */
export const PLATFORMS = PLAY_URL
  ? { short: "iPhone і Android", long: "Для iPhone з iOS 17 і Android 8+.", camera: "телефону" }
  : { short: "Для iPhone", long: "Поки лише для iPhone з iOS 17.", camera: "iPhone" };

export const icon = (name, cls = "ico") => `<svg class="${cls}" aria-hidden="true"><use href="img/icons.svg#i-${name}"/></svg>`;

/** Картки за id з кешем: індекс приходить одразу, картки — порціями, коли їх видно. */
export const cards = new Map();
export async function ensureCards(ids) {
  const missing = ids.filter((id) => !cards.has(id));
  if (missing.length) for (const card of await cardsByIds(missing)) cards.set(card.id, card);
  return ids.map((id) => cards.get(id)).filter(Boolean);
}
export const remember = (list) => list.forEach((card) => cards.set(card.id, card));

/** Фото з джерела; не завантажилось — зникає, і квиток лишається друкованим. */
export const photo = (card, lazy = true) => `<img src="${esc(card.image_url)}" alt="" ${lazy ? 'loading="lazy" ' : ""}decoding="async" referrerpolicy="no-referrer" onerror="this.remove()">`;

/** Обкладинка шторки: фото врівень із краєм; без фото блок ховається, і назва друкується великим кеглем. */
export function art(card) {
  const image = httpsOrNull(card.image_url);
  return `<div class="art cat-${esc(card.category)}">${icon(card.category, "glyph")}${image ? photo(card, false) : ""}</div>`;
}

const placeOf = (card) => card.place_name || card.address || card.city || "";
const href = (card) => `afisha.html?e=${encodeURIComponent(card.id)}`;
const seatsOf = (card) => card.origin === "community" && card.capacity ? `${card.attendee_count ?? 0}/${card.capacity}` : null;
const stamp = (text, cls = "", glyph = null) => `<span class="stamp ${cls}">${glyph ? icon(glyph) : ""}${esc(text)}</span>`;

/** Друк корінця: година табличними цифрами, день, а в зустрічі від людей — місця «3/8». `qr` — знак над годиною. */
export function stubPrint(card, { row = false, qr = "" } = {}) {
  const [time, day] = stubParts(card);
  const seats = seatsOf(card);
  const label = `${overline(card, new Date(), true)}${seats ? `, учасників ${seats}` : ""}`;
  const small = `<small>${esc(day)}</small>${seats ? `<span class="seats">${icon("people")}${esc(seats)}</span>` : ""}`;
  return `<div class="stub" role="img" aria-label="${esc(label)}">${qr}<b class="t">${esc(time)}</b>${row ? `<span class="side">${small}</span>` : small}</div>`;
}

/** Вертикальний квиток (PosterCard): обкладинка 4:5 зі штампом і ціною або друкована сторона; корінець 52 знизу. */
export function poster(card, entry) {
  const image = httpsOrNull(card.image_url);
  const more = otherDays(entry?.sessions);
  const cost = price(card);
  const mark = card.status === "cancelled" ? ["Скасовано", "danger"] : card.origin === "community" ? ["Від людей", ""] : null;
  return `<article class="ticket v poster cat-${esc(card.category)}${image ? "" : " bare"}" data-id="${esc(card.id)}" data-ui>
  <a class="face" href="${href(card)}">
    ${image ? `<div class="cover">${photo(card)}${mark ? stamp(mark[0], `photo ${mark[1]}`) : ""}${cost ? `<span class="price">${esc(cost)}</span>` : ""}</div>`
      : `<div class="printed">${mark ? stamp(mark[0], mark[1]) : ""}</div>`}
    <h3>${esc(displayTitle(card.title))}</h3>
    <div class="where"><span class="dot"></span><span>${esc(placeOf(card))}</span></div>
    ${!image && cost ? `<div class="note">${esc(cost)}</div>` : ""}
    <div class="note">${more ? `Ще ${more} ${more === 1 ? "день" : more < 5 ? "дні" : "днів"} · ` : ""}${esc(sourceNote(card))}</div>
  </a>
  <button class="save" type="button" data-lock="save" aria-label="Зберегти в застосунку">${icon("bookmark")}</button>
  ${stubPrint(card, { row: true })}
</article>`;
}

export const skeletons = (n) => Array.from({ length: n }, () =>
  `<div class="ticket v poster skeleton" aria-hidden="true"><div class="face"><div class="cover"></div><div class="bar wide"></div><div class="bar"></div><div class="bar short"></div></div><div class="stub"></div></div>`).join("");

/** Великий горизонтальний квиток (EventHeroCard) для стрічки «Не пропустіть»: на корінці «зберегти» й час. */
export const heroCard = (card) => `<article class="ticket hero-ticket cat-${esc(card.category)}" data-id="${esc(card.id)}" data-ui>
  <a class="face" href="${href(card)}"><div class="cover">${photo(card)}${card.status === "cancelled" ? stamp("Скасовано", "photo danger") : ""}${price(card) ? `<span class="price">${esc(price(card))}</span>` : ""}</div>
    <h3>${esc(displayTitle(card.title))}</h3><div class="where"><span class="dot"></span><span>${esc(placeOf(card))}</span></div>
    <div class="note"><span class="genre-word">${esc(CATEGORIES[card.category] || "Подія")}</span> · ${esc(sourceNote(card))}</div></a>
  <div class="stub"><button class="save" type="button" data-lock="save" aria-label="Зберегти в застосунку">${icon("bookmark")}</button>
    <div role="img" aria-label="${esc(overline(card, new Date(), true))}"><b class="t">${esc(stubParts(card)[0])}</b><small>${esc(stubParts(card)[1])}</small></div></div>
</article>`;

/** Малий корінець рядка (StubTile): година й дата числом на плитці кольору жанру. */
export function stubTile(card) {
  const [time, day] = stubParts(card, new Date(), true);
  return `<div class="ticket v stub-tile cat-${esc(card.category)}" aria-hidden="true" data-ui><div class="face"><b class="t">${esc(time)}</b></div><div class="stub"><small>${esc(day)}</small></div></div>`;
}

/** Клік по квитку відкриває шторку, кнопка «зберегти» — шторку застосунку. Посилання лишається справжнім. */
export function bindCards(root, entryOf = () => null) {
  root.addEventListener("click", (event) => {
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.button !== 0) return;
    const lock = event.target.closest("[data-lock]");
    const target = event.target.closest("[data-id]");
    if (!target) return;
    event.preventDefault();
    const card = cards.get(target.dataset.id);
    if (lock) openInstall(lock.dataset.lock, card);
    else openEvent(target.dataset.id, entryOf(target.dataset.id));
  });
}

// ---- Шторки

function dialog(cls, close = () => el.close()) {
  const el = document.createElement("dialog");
  el.className = cls;
  document.body.append(el);
  // Клік по затемненню (сам <dialog>, не його вміст) закриває.
  el.addEventListener("click", (event) => { if (event.target === el) close(); });
  return el;
}

let eventDialog, installDialog;

/** Шторка події. Історія браузера: «Назад» закриває шторку, а посилання `?e=` можна скопіювати. */
export async function openEvent(id, entry = null) {
  eventDialog ??= setupEventDialog();
  const card = cards.get(id);
  eventDialog.innerHTML = `<div class="sheet-box"><button class="round close" type="button" data-close aria-label="Закрити">${icon("close")}</button><div class="sheet-scroll"></div></div>`;
  eventDialog.querySelector("[data-close]").onclick = closeEvent;
  if (!eventDialog.open) eventDialog.showModal();
  const url = new URL(location.href);
  url.searchParams.set("e", id);
  if (history.state?.event) history.replaceState({ event: id }, "", url);
  else {
    // Відкрито за посиланням `?e=`: під шторку кладемо сторінку без події, щоб «Назад» лишав людину на сайті.
    const under = new URL(location.href);
    under.searchParams.delete("e");
    history.replaceState(null, "", under);
    history.pushState({ event: id }, "", url);
  }
  try {
    const [full] = card ? [card] : await ensureCards([id]);
    if (!full) throw new Error("not found");
    renderEvent(full, entry);
  } catch {
    eventDialog.querySelector(".sheet-scroll").innerHTML = `<div class="detail" style="padding-top:72px"><div class="empty"><b>Подію не знайдено</b>
      <span>Її могли приховати, або вона вже минула.</span><button class="btn secondary" type="button" data-close>Повернутися до афіші</button></div></div>`;
    eventDialog.querySelectorAll("[data-close]").forEach((b) => { b.onclick = closeEvent; });
  }
}

function setupEventDialog() {
  const el = dialog("event-sheet", () => closeEvent());
  el.addEventListener("cancel", (event) => { event.preventDefault(); closeEvent(); });
  el.addEventListener("close", () => { document.title = baseTitle; });
  addEventListener("popstate", () => { if (!history.state?.event && el.open) el.close(); });
  return el;
}
const baseTitle = document.title;

function closeEvent() {
  if (history.state?.event) history.back();
  else eventDialog.close();
}

function renderEvent(card, entry) {
  const title = displayTitle(card.title);
  document.title = `${title} — Поряд`;
  const imported = card.origin === "import";
  const ticket = imported ? httpsOrNull(card.canonical_url) : null;
  const where = [card.place_name, card.address].filter(Boolean);
  const maps = `https://www.google.com/maps/dir/?api=1&destination=${Number(card.latitude)},${Number(card.longitude)}`;
  const sessions = entry?.sessions?.length > 1 ? entry.sessions : null;
  const cost = price(card);
  const spots = !imported && card.capacity ? `${card.attendee_count ?? 0} з ${card.capacity}` : null;
  const artists = card.artists ?? [];

  eventDialog.innerHTML = `<div class="sheet-box">
  <button class="round close" type="button" data-close aria-label="Закрити">${icon("close")}</button>
  <button class="round bookmark" type="button" data-lock="save" aria-label="Зберегти">${icon("bookmark")}</button>
  <div class="sheet-scroll">
    <header class="cover-big cat-${esc(card.category)}">${art(card)}
      ${card.status === "cancelled" ? `<div class="state">${stamp("Скасовано", "danger")}</div>` : ""}
      <p class="quiet"><span class="genre-word">${esc(CATEGORIES[card.category] || "Подія")}</span> · ${esc(sourceNote(card))}${card.min_age ? ` · ${Number(card.min_age)}+` : ""}</p><h2 id="sheet-title" tabindex="-1">${esc(title)}</h2>
    </header>
    <div class="detail">
      <div class="actions">
        <button type="button" data-lock="remind"><i>${icon("bell")}</i>Нагадати</button>
        <a href="${maps}" target="_blank" rel="noopener"><i>${icon("pin")}</i>Маршрут</a>
        <button type="button" data-share><i>${icon("share")}</i>Поділитися</button>
      </div>
      ${artists.length ? `<div class="block"><h3>Хто виступає</h3><div class="artist-chips">${artists.map((a) =>
        `<button type="button" data-lock="artist" data-name="${esc(a.name)}">${esc(a.name)}${icon("bell")}</button>`).join("")}</div></div>` : ""}
      <div class="facts">
        <div><span class="overline">Коли</span><b>${esc(overline(card, new Date(), true))}</b>${sessions ? `<small>Дат у прокаті: ${sessions.length}</small>` : ""}</div>
        ${imported ? "" : `<div><span class="overline">Організовує</span><b>${esc(card.organizer_name || "Організатор")}</b></div>`}
      </div>
      ${sessions ? `<div class="block"><h3>Інші дати</h3><div class="sessions">${sessions.slice(0, 12).map((s) =>
        `<button type="button" data-session="${esc(s.id)}"${s.id === card.id ? ' aria-current="true"' : ""}>${esc(dayLabel(new Date(s.startsAt), s.tz))} · ${esc(timeOf(new Date(s.startsAt), s.tz))}</button>`).join("")}
        ${sessions.length > 12 ? `<span>і ще ${sessions.length - 12}</span>` : ""}</div></div>` : ""}
      ${card.description ? `<div class="block"><h3>Опис</h3><p class="description clamped">${esc(card.description)}</p><button class="more" type="button" hidden>Читати далі</button></div>` : ""}
      <div class="block"><h3>Місце</h3><div class="rows">
        <a class="row" href="${maps}" target="_blank" rel="noopener"><i>${icon("pin")}</i><div class="txt"><b>${esc(where[0] || card.city || "На мапі")}</b>
          <span>${esc(where[1] && where[1] !== where[0] ? where[1] : "Прокласти маршрут")}</span></div></a>
        ${card.place_id ? `<div class="row"><i>${icon("bell")}</i><div class="txt"><span>Скажемо, коли тут з’явиться щось нове</span></div>
          <button class="act" type="button" data-lock="follow">${icon("bell")}Стежити</button></div>` : ""}
      </div></div>
      <div class="block safety" hidden></div>
      <div class="ticket app-only" data-ui>
        <div class="face"><b>У застосунку ця подія — не просто сторінка</b>
          <ul><li>${icon("bell")}Нагадування за годину до початку</li><li>${icon("people")}«Шукаю компанію» — знайдіть, з ким піти</li>
            <li>${icon("bookmark")}«Мої події» й експорт у календар</li><li>${icon("map")}Мапа: що ще відбувається поряд</li></ul>
          <button class="btn primary" type="button" data-lock="app">Завантажити «Поряд»</button></div>
        <div class="stub">${icon("ticket")}</div>
      </div>
    </div>
  </div>
  <div class="bar"><div class="ticket cat-${esc(card.category)}" data-ui>
    <div class="face"><div class="top"><div class="meta"><small>${spots ? "Учасників" : "Ціна"}</small><span>${esc(spots || cost || "Уточнюйте")}</span></div>
      ${ticket ? `<a class="btn primary" href="${esc(ticket)}" target="_blank" rel="noopener nofollow">Купити квиток</a>`
        : `<button class="btn primary" type="button" data-lock="join">${card.approval_required ? "Подати заявку" : "Приєднатися"}</button>`}</div>
      ${imported ? `<button class="btn secondary" type="button" data-lock="company">${icon("people")}Шукаю компанію</button>` : ""}</div>
    ${stubPrint(card)}
  </div></div>
</div>`;

  const description = eventDialog.querySelector(".description");
  if (description) requestAnimationFrame(() => {
    const more = description.nextElementSibling;
    more.hidden = description.scrollHeight <= description.clientHeight + 2;
    more.onclick = () => { description.classList.remove("clamped"); more.remove(); };
  });
  eventDialog.querySelector("[data-close]").onclick = closeEvent;
  eventDialog.setAttribute("aria-labelledby", "sheet-title");
  eventDialog.querySelector("#sheet-title").focus({ preventScroll: true });
  eventDialog.querySelector("[data-share]").onclick = () => share(card);
  eventDialog.querySelectorAll("[data-session]").forEach((button) => {
    button.onclick = () => { if (button.dataset.session !== card.id) openEvent(button.dataset.session, entry); };
  });
  eventDialog.querySelectorAll("[data-lock]").forEach((button) => {
    button.onclick = () => openInstall(button.dataset.lock, card, button.dataset.name);
  });
  renderSafety(card);
}

const SHELTER_KINDS = { metro: "Метро", underpass: "Підземний перехід", parking: "Підземний паркінг", basement: "Укриття" };

/** Безпека — як у застосунку: найближчі укриття (відкриті дані КМДА) і комендантська. Збій лише ховає блок. */
async function renderSafety(card) {
  const block = eventDialog.querySelector(".safety");
  try {
    const safety = await eventSafety(card.id);
    if (!block.isConnected) return;
    const shelters = safety?.shelters ?? [];
    const curfew = safety?.curfew;
    if (!shelters.length && !curfew) return;
    block.innerHTML = `<h3>Безпека</h3><div class="rows">
      ${curfew ? `<div class="row"><i>${icon("clock")}</i><div class="txt"><span>Комендантська в місті: ${esc(curfew.starts)}–${esc(curfew.ends)}</span></div></div>` : ""}
      ${shelters.map((s) => `<a class="row" href="https://www.google.com/maps/dir/?api=1&destination=${Number(s.latitude)},${Number(s.longitude)}&travelmode=walking" target="_blank" rel="noopener">
        <i>${icon("shield")}</i><div class="txt"><small>${esc(SHELTER_KINDS[s.kind] || "Укриття")} · ${Number(s.distance_m)} м${s.accessible ? " · є пандус" : ""}</small><b>${esc(s.address)}</b></div></a>`).join("")}
    </div>${shelters.length ? `<p class="fine">Укриття — за відкритими даними КМДА (CC BY). Тап відкриває маршрут.</p>` : ""}`;
    block.hidden = false;
  } catch { /* блок лишається прихованим */ }
}

export async function share(card) {
  const url = `https://poriad.app/e/${card.id}`;
  const title = displayTitle(card.title);
  if (navigator.share) {
    try { await navigator.share({ title, text: `${title} — ${overline(card)}`, url }); } catch { /* скасовано */ }
    return;
  }
  try { await navigator.clipboard.writeText(url); toast("Посилання скопійовано"); }
  catch { prompt("Посилання на подію", url); }
}

let toastTimer;
export function toast(text) {
  let el = document.querySelector(".toast");
  if (!el) { el = document.createElement("div"); el.className = "toast"; el.setAttribute("role", "status"); document.body.append(el); }
  el.textContent = text;
  el.classList.add("on");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.classList.remove("on"), 2200);
}

// ---- «У застосунку»: що саме дасть застосунок у цю мить, і як його поставити.

const REASONS = {
  save: ["Збережіть на потім", "Подія чекатиме в «Моїх подіях», а за годину до початку прийде нагадування."],
  remind: ["Нагадаємо вчасно", "Застосунок нагадає за годину до початку й додасть подію в календар одним дотиком."],
  company: ["Шукаєте, з ким піти?", "Зберіть невелику компанію на цю подію: хто хоче долучитися, надсилає запит, а ви вирішуєте, кого взяти."],
  join: ["Приєднатися — в застосунку", "Одна кнопка, і ви в списку. Немає місць — станете в чергу, і звільнене місце дістанеться першому."],
  follow: ["Стежте за цим місцем", "Скажемо, щойно тут з’явиться нова подія. Так само — за артистами й організаторами."],
  artist: ["Стежте за артистом", "Дізнавайтеся про нові концерти першими: Поряд надішле сповіщення."],
  create: ["Зберіть своїх", "Три кроки: опис, точка на мапі, час і кількість місць. Учасники, черга й чат уже всередині."],
  app: ["Поряд у телефоні", "Афіша міста на мапі, нагадування, компанія для походу й свої зустрічі завжди під рукою."],
};

/** Штамп, який квиток отримав би в застосунку після цієї дії (`eventState`; DESIGN.md: штамп — лише стан). */
function stateAfter(reason, card) {
  if (card.status === "cancelled") return ["Скасовано", "danger"];
  if (reason === "join") return card.approval_required ? ["Запит надіслано", "accent", "queue"] : ["Ви йдете", "success", "check"];
  return { remind: ["Нагадаємо за годину", "", "bell"], company: ["Шукаю компанію", "", "people"], follow: ["Ви стежите", "", "check"], artist: ["Ви стежите", "", "check"] }[reason];
}

/** Квиток події в шторці: штамп стану, назва, місце; на корінці — QR на poriad.app/e/{id} (на телефоні — лише час). */
function passTicket(card, reason) {
  const state = stateAfter(reason, card);
  return `<div class="ticket pass cat-${esc(card.category)}" data-ui>
    <div class="face">${state ? stamp(...state) : ""}<b class="name">${esc(displayTitle(card.title))}</b>
      <div class="where"><span class="dot"></span><span>${esc(placeOf(card))}</span></div>
      <div class="note"><span class="genre-word">${esc(CATEGORIES[card.category] || "Подія")}</span> · ${esc(sourceNote(card))}</div></div>
    ${stubPrint(card, { qr: qrSvg(eventUrl(card)) })}
  </div>`;
}

let icsUrl;
/** «Нагадати» на сайті теж працює: файл .ics із нагадуванням за годину або Google Календар. */
function calendarLinks(card) {
  if (icsUrl) URL.revokeObjectURL(icsUrl);
  icsUrl = URL.createObjectURL(new Blob([icsFile(card)], { type: "text/calendar;charset=utf-8" }));
  const file = displayTitle(card.title).replace(/[\\/:*?"<>|]+/g, " ").replace(/\s+/g, " ").trim().slice(0, 60) || "poriad";
  return `<div class="cal"><a class="btn secondary" href="${icsUrl}" download="${esc(file)}.ics">${icon("calendar")}Додати в календар</a>
    <a class="btn secondary" href="${esc(googleCalendarUrl(card))}" target="_blank" rel="noopener">Google Календар</a></div>`;
}

export function openInstall(reason = "app", card = null, name = null) {
  installDialog ??= dialog("install");
  let [title, lead] = REASONS[reason] || REASONS.app;
  if (reason === "follow" && card?.place_name) title = `Стежте за «${card.place_name}»`;
  if (reason === "artist" && name) title = `Стежте за ${name}`;
  const calendar = reason === "remind" && card && card.status !== "cancelled";
  if (calendar) lead = "Додайте подію у свій календар: нагадування спрацює за годину до початку. А застосунок нагадає сам.";
  installDialog.innerHTML = `<div class="install-box">
  <button class="round" type="button" data-close aria-label="Закрити">${icon("close")}</button>
  ${card ? "" : `<img class="app-icon" src="icon.png" alt="">`}
  <h2>${esc(title)}</h2><p class="lead">${esc(lead)}</p>
  ${card ? passTicket(card, reason) : `<ul><li><i>${icon("bell")}</i>Нагадування й п’ятничний дайджест вихідних</li>
    <li><i>${icon("people")}</i>«Шукаю компанію» і чат учасників</li>
    <li><i>${icon("map")}</i>Мапа подій навколо вас і свої зустрічі</li></ul>`}
  ${calendar ? calendarLinks(card) : ""}
  ${card && isIOS ? `<a class="btn secondary open-app" href="poriad://event/${esc(card.id)}">Уже є застосунок? Відкрити подію</a>` : ""}
  <div class="get"><div class="stores">${storeLink()}<small>${PLATFORMS.long.slice(0, -1)}</small></div>
    ${card ? `<small class="scan">Наведіть камеру ${PLATFORMS.camera} на корінець, і подія відкриється на телефоні</small>` : qr(`Наведіть камеру ${PLATFORMS.camera}`)}</div>
</div>`;
  installDialog.querySelector("[data-close]").onclick = () => installDialog.close();
  if (!installDialog.open) installDialog.showModal();
}

const appStoreBadge = () => `<a class="store" href="${APP_STORE_URL}" target="_blank" rel="noopener">${icon("apple")}<span><small>Завантажити в</small>App Store</span></a>`;
const playBadge = (cls = "store") => `<a class="${cls}" href="${PLAY_URL}" target="_blank" rel="noopener">${icon("play")}<span><small>Завантажити з</small>Google Play</span></a>`;
/** Значки сторів: на Android Google Play першим; поки Play вимкнено — лише App Store. */
export const storeLink = () => !PLAY_URL ? appStoreBadge() : isAndroid ? playBadge() + appStoreBadge() : appStoreBadge() + playBadge();

/** Статична розмітка лендингу: значок Google Play поруч із кожним `[data-store]` і підписи `[data-platforms]`. */
export function applyStores(root = document) {
  if (!PLAY_URL) return;
  root.querySelectorAll("[data-store]").forEach((a) => a.insertAdjacentHTML(isAndroid ? "beforebegin" : "afterend", playBadge(a.className)));
  root.querySelectorAll("[data-platforms]").forEach((el) => { el.textContent = PLATFORMS[el.dataset.platforms]; });
}

/** QR-код посилання; без `label` він прихований від екранного читача, бо підпис стоїть поруч. */
function qrSvg(url, label = null) {
  const code = qrPath(url);
  return code ? `<svg class="code" viewBox="0 0 ${code.size} ${code.size}" shape-rendering="crispEdges" ${label ? `role="img" aria-label="QR-код: ${esc(label)}"` : 'aria-hidden="true"'}><path stroke="currentColor" d="${code.path}"/></svg>` : "";
}
/** QR на poriad.app/app: сторінка сама веде в потрібний стор. */
export const qr = (caption) => `<div class="qr">${qrSvg("https://poriad.app/app", "poriad.app/app")}<small>${esc(caption)}</small></div>`;

// ---- Дрібне спільне

/** Поява блоків під час прокрутки. Без IntersectionObserver усе видно одразу. */
export function reveal(root = document) {
  window.poriadReady = true;
  const items = root.querySelectorAll(".reveal:not(.in)");
  if (!("IntersectionObserver" in window)) { items.forEach((el) => el.classList.add("in")); return; }
  const io = new IntersectionObserver((entries) => entries.forEach((e) => {
    if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); }
  }), { rootMargin: "0px 0px -8% 0px" });
  items.forEach((el) => io.observe(el));
}

/** Шапка — проста смуга кольору полотна; після першого пікселя прокрутки під нею з’являється волосина. */
export function navLine() {
  const nav = document.querySelector(".nav");
  const update = () => nav.classList.toggle("scrolled", scrollY > 8);
  addEventListener("scroll", update, { passive: true });
  update();
}

/** Кнопки «Завантажити» з `data-lock` поза картками. */
export function bindLocks(root = document) {
  root.querySelectorAll("[data-lock]:not([data-id] [data-lock])").forEach((el) => {
    if (el.dataset.lock === "app" && el.href && (isIOS || (isAndroid && PLAY_URL))) { el.href = isIOS ? APP_STORE_URL : PLAY_URL; return; }
    el.addEventListener("click", (event) => { event.preventDefault(); openInstall(el.dataset.lock); });
  });
}

/** Місто, яке людина вибирала минулого разу. Сховище може бути недоступне — тоді Київ. */
export const savedCity = {
  get() { try { return localStorage.getItem("poriad.city"); } catch { return null; } },
  set(name) { try { localStorage.setItem("poriad.city", name); } catch { /* приватне вікно */ } },
};
