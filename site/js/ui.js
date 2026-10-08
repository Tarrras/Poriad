// Спільне для лендингу й афіші: картки, шторка події, шторка «У застосунку», поява під час прокрутки.
// Сайт — режим перегляду: дивитися, ділитися й купувати квиток можна тут, а піти, зберегти, нагадати й знайти
// компанію — у застосунку. Кожна така кнопка відкриває шторку з тим, що саме дасть застосунок.
import {
  APP_STORE_URL, PLAY_URL, CATEGORIES, cardsByIds, eventSafety, displayTitle, overline, dayLabel, timeOf,
  price, sourceNote, httpsOrNull, esc, otherDays,
} from "./poriad.js";

const ua = navigator.userAgent;
export const isIOS = /iPhone|iPad|iPod/.test(ua) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
export const isAndroid = /Android/.test(ua);

export const icon = (name, cls = "ico") => `<svg class="${cls}" aria-hidden="true"><use href="img/icons.svg#i-${name}"/></svg>`;

/** Картки за id з кешем: індекс приходить одразу, картки — порціями, коли їх видно. */
export const cards = new Map();
export async function ensureCards(ids) {
  const missing = ids.filter((id) => !cards.has(id));
  if (missing.length) for (const card of await cardsByIds(missing)) cards.set(card.id, card);
  return ids.map((id) => cards.get(id)).filter(Boolean);
}
export const remember = (list) => list.forEach((card) => cards.set(card.id, card));

/** Обкладинка: фото з джерела або EventArt (градієнт категорії й знак). */
export function art(card, extra = "") {
  const image = httpsOrNull(card.image_url);
  return `<div class="art cat-${esc(card.category)} ${extra}">${icon(card.category, "glyph")}${image
    ? `<img src="${esc(image)}" alt="" loading="lazy" decoding="async" referrerpolicy="no-referrer" class="loading" onload="this.classList.remove('loading')" onerror="this.remove()">` : ""}</div>`;
}

const placeOf = (card) => card.place_name || card.address || card.city || "";
const href = (card) => `afisha.html?e=${encodeURIComponent(card.id)}`;

/** Постер (PosterCard): обкладинка 4:5, бейдж ціни або місць, надрядок дати, назва, місце, джерело. */
export function poster(card, entry) {
  const more = otherDays(entry?.sessions);
  const spots = card.origin === "community" && card.capacity ? `${card.attendee_count ?? 0}/${card.capacity}` : null;
  const badge = price(card) || spots;
  const when = overline(card) + (more ? ` · ще ${more} ${more === 1 ? "день" : more < 5 ? "дні" : "днів"}` : "");
  return `<article class="poster cat-${esc(card.category)}" data-id="${esc(card.id)}">
  <a class="cover" href="${href(card)}" tabindex="-1" aria-hidden="true">${art(card)}${card.origin === "community" ? `<span class="badge top">Від людей</span>` : ""}
    ${badge ? `<span class="badge bottom">${esc(badge)}</span>` : ""}</a>
  <button class="save" type="button" data-lock="save" aria-label="Зберегти в застосунку">${icon("bookmark")}</button>
  <a class="caption" href="${href(card)}"><div class="when">${esc(when)}</div><h3>${esc(displayTitle(card.title))}</h3>
    <div class="where"><span class="dot"></span><span>${esc(placeOf(card))}</span></div><div class="note">${esc(sourceNote(card))}</div></a>
</article>`;
}

export const skeletons = (n) => Array.from({ length: n }, () =>
  `<div class="poster skeleton" aria-hidden="true"><div class="cover"></div><div class="caption"><div class="bar short"></div><div class="bar wide"></div><div class="bar"></div></div></div>`).join("");

/** Велика картка (EventHeroCard) для стрічки «Не пропустіть». */
export const heroCard = (card) => `<a class="hero-card cat-${esc(card.category)}" href="${href(card)}" data-id="${esc(card.id)}">${art(card)}
  <span class="badge">${esc(CATEGORIES[card.category] || "Подія")}</span>
  <div class="text"><div class="when">${esc(overline(card))}</div><h3>${esc(displayTitle(card.title))}</h3><div class="where">${esc(placeOf(card))}</div></div></a>`;

/** Клік по картці відкриває шторку, кнопка «зберегти» — шторку застосунку. Посилання лишається справжнім. */
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
  eventDialog.innerHTML = `<div class="sheet-box"><div class="sheet-scroll">${card ? "" : `<div class="cover-big art"></div>`}</div></div>`;
  if (!eventDialog.open) eventDialog.showModal();
  const url = new URL(location.href);
  url.searchParams.set("e", id);
  if (history.state?.event) history.replaceState({ event: id }, "", url);
  else {
    // Відкрито за посиланням `?e=`: під шторку кладемо афішу без події, щоб «Назад» лишав людину на сайті.
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
    eventDialog.querySelector(".sheet-scroll").innerHTML = `<div class="detail" style="margin:0;padding-top:72px"><div class="empty"><b>Подію не знайдено</b>
      <span>Її могли приховати, або вона вже минула.</span></div></div>`;
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
      <div class="badges"><span class="badge">${esc(CATEGORIES[card.category] || "Подія")}</span><span class="badge">${esc(sourceNote(card))}</span>
        ${card.min_age ? `<span class="badge">${Number(card.min_age)}+</span>` : ""}</div>
      <div class="when">${esc(overline(card))}</div><h2>${esc(title)}</h2>
    </header>
    <div class="detail">
      <div class="actions">
        <button type="button" data-lock="remind"><i>${icon("bell")}</i>Нагадати</button>
        <a href="${maps}" target="_blank" rel="noopener"><i>${icon("pin")}</i>Маршрут</a>
        <button type="button" data-share><i>${icon("share")}</i>Поділитися</button>
        <button type="button" data-lock="company"><i>${icon("people")}</i>Компанія</button>
      </div>
      ${artists.length ? `<div class="block"><h3>Хто виступає</h3><div class="artist-chips">${artists.map((a) =>
        `<button type="button" data-lock="artist" data-name="${esc(a.name)}">${esc(a.name)}${icon("bell")}</button>`).join("")}</div></div>` : ""}
      <div class="facts">
        <div><span class="overline">Коли</span><b>${esc(overline(card, new Date(), true))}</b>${sessions ? `<small>Дат у прокаті: ${sessions.length}</small>` : ""}</div>
        <div><span class="overline">Де</span><b>${esc(where[0] || card.city || "")}</b>${where[1] && where[1] !== where[0] ? `<small>${esc(where[1])}</small>` : ""}</div>
        <div><span class="overline">${spots ? "Учасників" : "Ціна"}</span><b>${esc(spots || cost || "Уточнюйте")}</b></div>
        <div><span class="overline">${imported ? "Джерело" : "Організовує"}</span><b>${esc(imported ? card.source_name || "Афіша" : card.organizer_name || "Організатор")}</b></div>
      </div>
      ${sessions ? `<div class="block"><h3>Інші дати</h3><div class="sessions">${sessions.slice(0, 12).map((s) =>
        `<span class="${s.id === card.id ? "on" : ""}">${esc(dayLabel(new Date(s.startsAt), s.tz))} · ${esc(timeOf(new Date(s.startsAt), s.tz))}</span>`).join("")}
        ${sessions.length > 12 ? `<span>ще ${sessions.length - 12}</span>` : ""}</div></div>` : ""}
      ${card.description ? `<div class="block"><h3>Опис</h3><p class="description clamped">${esc(card.description)}</p><button class="more" type="button" hidden>Читати далі</button></div>` : ""}
      <div class="block"><h3>Місце</h3><div class="rows">
        <a class="row" href="${maps}" target="_blank" rel="noopener"><i>${icon("pin")}</i><div class="txt"><b>${esc(where[0] || card.city || "На мапі")}</b>
          <span>${esc(where[1] && where[1] !== where[0] ? where[1] : "Прокласти маршрут")}</span></div></a>
        ${card.place_id ? `<div class="row"><i>${icon("bell")}</i><div class="txt"><span>Скажемо, коли тут з’явиться щось нове</span></div>
          <button class="act" type="button" data-lock="follow">${icon("bell")}Стежити</button></div>` : ""}
      </div></div>
      <div class="block safety" hidden></div>
      <div class="app-only"><b>У застосунку ця подія — не просто сторінка</b>
        <ul><li>${icon("bell")}Нагадування за годину до початку</li><li>${icon("people")}«Шукаю компанію» — знайдіть, з ким піти</li>
          <li>${icon("bookmark")}«Мої події» й експорт у календар</li><li>${icon("map")}Мапа: що ще відбувається поряд</li></ul>
        <button class="btn" type="button" data-lock="app">Завантажити «Поряд»</button></div>
    </div>
  </div>
  <div class="bar">
    <div class="top"><div class="meta"><small>${esc(overline(card))}</small><span>${esc(cost || spots && `Учасників: ${spots}` || "Вхід уточнюйте")}</span></div>
      ${ticket ? `<a class="btn primary" href="${esc(ticket)}" target="_blank" rel="noopener nofollow">Купити квиток</a>`
        : `<button class="btn primary" type="button" data-lock="join">${card.approval_required ? "Подати заявку" : "Приєднатися"}</button>`}</div>
    ${imported ? `<button class="btn secondary" type="button" data-lock="company">${icon("people")}Шукаю компанію</button>` : ""}
  </div>
</div>`;

  const description = eventDialog.querySelector(".description");
  if (description) requestAnimationFrame(() => {
    const more = description.nextElementSibling;
    more.hidden = description.scrollHeight <= description.clientHeight + 2;
    more.onclick = () => { description.classList.remove("clamped"); more.remove(); };
  });
  eventDialog.querySelector("[data-close]").onclick = closeEvent;
  eventDialog.querySelector("[data-share]").onclick = () => share(card);
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
  company: ["Шукаєте, з ким піти?", "Зберіть невелику компанію на цю подію: хто хоче долучитися, надсилає запит — ви вирішуєте, кого взяти."],
  join: ["Приєднатися — в застосунку", "Одна кнопка — і ви в списку. Немає місць — станете в чергу, і звільнене місце дістанеться першому."],
  follow: ["Стежте за цим місцем", "Скажемо, щойно тут з’явиться нова подія. Так само — за артистами й організаторами."],
  artist: ["Стежте за артистом", "Дізнавайтеся про нові концерти першими — Поряд надішле сповіщення."],
  create: ["Зберіть своїх", "Три кроки: опис, точка на мапі, час і кількість місць. Учасники, черга й чат — уже всередині."],
  app: ["Поряд у телефоні", "Афіша міста на мапі, нагадування, компанія для походу й свої зустрічі — завжди під рукою."],
};

export function openInstall(reason = "app", card = null, name = null) {
  installDialog ??= dialog("install");
  let [title, lead] = REASONS[reason] || REASONS.app;
  if (reason === "follow" && card?.place_name) title = `Стежте за «${card.place_name}»`;
  if (reason === "artist" && name) title = `Стежте за ${name}`;
  const stores = isAndroid ? [storeLink("play"), storeLink("ios")] : [storeLink("ios"), storeLink("play")];
  installDialog.innerHTML = `<div class="install-box">
  <button class="round" type="button" data-close aria-label="Закрити">${icon("close")}</button>
  <img class="app-icon" src="icon.png" alt="">
  <h2>${esc(title)}</h2><p class="lead">${esc(lead)}</p>
  <ul><li><i>${icon("bell")}</i>Нагадування й п’ятничний дайджест вихідних</li>
    <li><i>${icon("people")}</i>«Шукаю компанію» і чат учасників</li>
    <li><i>${icon("map")}</i>Мапа подій навколо вас і свої зустрічі</li></ul>
  ${card && (isIOS || isAndroid) ? `<a class="btn secondary open-app" href="poriad://event/${esc(card.id)}">Уже є застосунок? Відкрити подію</a>` : ""}
  <div class="get"><div class="stores">${stores.join("")}</div>${qr("Наведіть камеру телефону")}</div>
</div>`;
  installDialog.querySelector("[data-close]").onclick = () => installDialog.close();
  if (!installDialog.open) installDialog.showModal();
}

export function storeLink(kind) {
  return kind === "play"
    ? `<a class="store play" href="${PLAY_URL}" target="_blank" rel="noopener">${icon("play")}<span><small>Завантажити з</small>Google Play</span></a>`
    : `<a class="store" href="${APP_STORE_URL}" target="_blank" rel="noopener">${icon("apple")}<span><small>Завантажити в</small>App Store</span></a>`;
}

/** QR на poriad.app/app: сторінка сама веде в App Store чи Google Play. Згенеровано `npx qrcode`, рівень M. */
export const qr = (caption) => `<div class="qr"><svg viewBox="0 0 25 25" shape-rendering="crispEdges" role="img" aria-label="QR-код: poriad.app/app"><path stroke="currentColor" d="${QR_PATH}"/></svg><small>${esc(caption)}</small></div>`;
const QR_PATH = "M0 0.5h7m1 0h3m3 0h1m1 0h1m1 0h7M0 1.5h1m5 0h1m1 0h3m1 0h1m1 0h1m3 0h1m5 0h1M0 2.5h1m1 0h3m1 0h1m3 0h1m2 0h1m2 0h1m1 0h1m1 0h3m1 0h1M0 3.5h1m1 0h3m1 0h1m1 0h4m1 0h1m1 0h2m1 0h1m1 0h3m1 0h1M0 4.5h1m1 0h3m1 0h1m2 0h1m3 0h4m1 0h1m1 0h3m1 0h1M0 5.5h1m5 0h1m3 0h1m3 0h1m3 0h1m5 0h1M0 6.5h7m1 0h1m1 0h1m1 0h1m1 0h1m1 0h1m1 0h7M8 7.5h5M0 8.5h1m1 0h2m1 0h3m4 0h1m1 0h1m1 0h1m1 0h1m2 0h1m1 0h2M0 9.5h2m2 0h2m2 0h2m1 0h2m3 0h1m2 0h1m3 0h1M0 10.5h1m1 0h1m3 0h1m2 0h1m1 0h2m1 0h1m3 0h1m1 0h1M1 11.5h1m1 0h1m3 0h1m2 0h1m2 0h3m1 0h3m1 0h2M0 12.5h3m1 0h4m5 0h2m2 0h4m1 0h3M2 13.5h1m2 0h1m2 0h1m1 0h2m3 0h1m2 0h3m3 0h1M1 14.5h1m1 0h1m2 0h1m2 0h1m2 0h2m2 0h1m3 0h1m1 0h2M0 15.5h1m3 0h1m2 0h3m2 0h1m2 0h2m2 0h2m3 0h1M2 16.5h1m2 0h7m1 0h1m2 0h9M8 17.5h1m1 0h1m1 0h3m1 0h1m3 0h1m1 0h1m1 0h1M0 18.5h7m1 0h1m1 0h3m3 0h1m1 0h1m1 0h1m1 0h3M0 19.5h1m5 0h1m1 0h1m1 0h1m1 0h1m1 0h3m3 0h1m2 0h2M0 20.5h1m1 0h3m1 0h1m2 0h1m1 0h3m2 0h6m1 0h1M0 21.5h1m1 0h3m1 0h1m1 0h3m1 0h2m3 0h2m1 0h5M0 22.5h1m1 0h3m1 0h1m1 0h1m2 0h3m3 0h2m1 0h1m1 0h2M0 23.5h1m5 0h1m2 0h1m8 0h1m1 0h1m1 0h1M0 24.5h7m1 0h2m2 0h1m1 0h1m2 0h8";

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

/** Скляна шапка після першого пікселя прокрутки. */
export function navGlass() {
  const nav = document.querySelector(".nav");
  const update = () => nav.classList.toggle("scrolled", scrollY > 8);
  addEventListener("scroll", update, { passive: true });
  update();
}

/** Кнопки «Завантажити» з `data-lock` поза картками. */
export function bindLocks(root = document) {
  root.querySelectorAll("[data-lock]:not([data-id] [data-lock])").forEach((el) => {
    el.addEventListener("click", (event) => { event.preventDefault(); openInstall(el.dataset.lock); });
  });
}

/** Число, що набігає до значення. */
export function countUp(el, to, duration = 1200) {
  const from = Number(el.dataset.value || 0);
  el.dataset.value = to;
  if (matchMedia("(prefers-reduced-motion: reduce)").matches) { el.textContent = to.toLocaleString("uk-UA"); return; }
  const start = performance.now();
  const tick = (t) => {
    const k = Math.min(1, (t - start) / duration);
    el.textContent = Math.round(from + (to - from) * (1 - Math.pow(1 - k, 3))).toLocaleString("uk-UA");
    if (k < 1) requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
}

/** Місто, яке людина вибирала минулого разу. Сховище може бути недоступне — тоді Київ. */
export const savedCity = {
  get() { try { return localStorage.getItem("poriad.city"); } catch { return null; } },
  set(name) { try { localStorage.setItem("poriad.city", name); } catch { /* приватне вікно */ } },
};
