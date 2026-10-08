// «Живі» екрани застосунку для лендингу: та сама розмітка й класи, що в ds-bundle (app-ui.css — рецепти 1:1 зі SwiftUI),
// і справжні події з prod. Екран малюється в точках iPhone 16 Pro (402×874) і масштабується під рамку телефона.
import { CATEGORIES, displayTitle, overline, timeOf, price, sourceNote, httpsOrNull, esc, plural, EVENTS } from "./poriad.js";

const ico = (name, size = 22) => `<svg width="${size}" height="${size}" aria-hidden="true"><use href="img/icons.svg#i-${name}"/></svg>`;

/** Обкладинка як EventArt: градієнт категорії, знак за кутом і фото, якщо є. */
const art = (card) => `<div class="p-art">${ico(card.category, 220).replace("<svg", '<svg class="glyph"')}${httpsOrNull(card.image_url)
  ? `<img src="${esc(card.image_url)}" alt="" referrerpolicy="no-referrer" loading="lazy">` : ""}</div>`;

const statusBar = (light = false) => `<div class="sb${light ? " light" : ""}"><span>9:41</span><span class="sb-icons">
  <svg width="18" height="12" viewBox="0 0 18 12"><rect x="0" y="8" width="3" height="4" rx="1"/><rect x="5" y="5.5" width="3" height="6.5" rx="1"/><rect x="10" y="3" width="3" height="9" rx="1"/><rect x="15" y="0" width="3" height="12" rx="1"/></svg>
  <svg width="16" height="12" viewBox="0 0 16 12"><path d="M8 2.2c2.3 0 4.4.9 6 2.4l1.2-1.3A10.4 10.4 0 0 0 8 .4 10.4 10.4 0 0 0 .8 3.3L2 4.6a8.6 8.6 0 0 1 6-2.4Zm0 3.6c1.3 0 2.5.5 3.4 1.3l1.3-1.3A6.7 6.7 0 0 0 8 4a6.7 6.7 0 0 0-4.7 1.8l1.3 1.3c.9-.8 2.1-1.3 3.4-1.3Zm0 3.6c-.5 0-1 .2-1.3.5L8 11.6l1.3-1.7c-.3-.3-.8-.5-1.3-.5Z"/></svg>
  <svg width="27" height="13" viewBox="0 0 27 13"><rect x=".5" y=".5" width="23" height="12" rx="3.5" fill="none" stroke="currentColor" opacity=".4"/><rect x="2" y="2" width="20" height="9" rx="2.2"/><path d="M25 4.5v4c.8-.3 1.3-1.1 1.3-2s-.5-1.7-1.3-2Z" opacity=".5"/></svg>
</span></div><div class="island"></div>`;

const when = (card) => overline(card).toUpperCase();

/** «Головна»: шапка, «Організувати подію», «У місті» з гортанням великих карток, чипи й сітка постерів, скляний таб-бар. */
export function homeScreen({ city, total, heroes, posters }) {
  return `<div class="canvas home-screen p-glow" data-theme="dark">${statusBar()}
  <div class="feed">
    <header class="p-page-header gutter"><div><h1>Що поруч</h1><p>${esc(city)} ⌄</p></div>
      <div class="pills"><span class="p-icon-pill">${ico("search", 20)}</span><span class="p-icon-pill">${ico("person", 20)}</span></div></header>
    <div class="gutter"><div class="p-create-card"><span class="p-create-card__icon">${ico("plus", 18)}</span>
      <div><div class="p-create-card__title">Організувати подію</div><div class="p-create-card__sub">Зберіть людей на настолки, пробіжку чи кіно</div></div>${ico("arrow", 18)}</div></div>
    <h2 class="p-section-title gutter">У місті <a>Усі ${total.toLocaleString("uk-UA")}</a></h2>
    <div class="pager"><div class="pager-track">${heroes.map((card) => `<article class="p-hero cat-${esc(card.category)}" data-id="${esc(card.id)}">${art(card)}
      <span class="p-badge p-badge--on-photo">${esc(sourceNote(card))}</span><span class="p-save">${ico("bookmark", 16)}</span>
      <div class="p-hero__text"><div class="p-overline" style="color:rgba(255,255,255,.75)">${esc(CATEGORIES[card.category] || "")}</div>
        <h3 class="p-hero__title">${esc(displayTitle(card.title))}</h3>
        <div><div class="p-hero__when">${esc(when(card))}</div><div class="p-hero__where">${esc(card.place_name || card.address || "")}</div></div></div></article>`).join("")}</div></div>
    <div class="p-chip-row gutter"><span class="p-chip p-chip--selected">Усе</span><span class="p-chip">Сьогодні</span><span class="p-chip">Завтра</span><span class="p-chip">Вихідні</span></div>
    <div class="p-poster-grid gutter">${posters.map((card) => `<article class="p-poster cat-${esc(card.category)}" data-id="${esc(card.id)}">
      <div class="p-poster__art">${art(card)}${price(card) ? `<span class="p-badge p-badge--on-photo bottom">${esc(price(card))}</span>` : ""}<span class="p-save">${ico("bookmark", 16)}</span></div>
      <div class="p-poster__caption"><div class="p-overline">${esc(overline(card))}</div><h3 class="p-card-name">${esc(displayTitle(card.title))}</h3>
        <div class="p-descriptor"><span class="p-dot p-cat-ink"></span><span>${esc(card.place_name || "")}</span></div><div class="p-poster__note">${esc(sourceNote(card))}</div></div></article>`).join("")}</div>
  </div>
  <div class="p-tabbar-wrap"><nav class="p-tabbar p-glass">
    <span class="p-tab" aria-selected="true">${ico("home", 20)}Головна</span><span class="p-tab">${ico("map", 20)}Мапа</span>
    <span class="p-tab">${ico("calendar", 20)}Мої події</span><span class="p-tab">${ico("person", 20)}Профіль</span></nav>
    <span class="p-create">${ico("plus", 24)}</span></div>
</div>`;
}

/** Сторінка події: обкладинка на весь верх, аркуш з діями й фактами, скляна панель з ціною й квитками. */
export function detailScreen(card) {
  const cost = price(card);
  return `<div class="canvas detail-screen">
  <div class="d-cover cat-${esc(card.category)}">${art(card)}${statusBar(true)}
    <span class="d-round left">${ico("chevron", 20)}</span><span class="d-round right">${ico("bookmark", 18)}</span>
    <div class="d-text"><div class="d-badges"><span class="p-badge p-badge--on-photo">${esc(CATEGORIES[card.category] || "Подія")}</span><span class="p-badge p-badge--on-photo">${esc(sourceNote(card))}</span></div>
      <div class="p-overline" style="color:var(--accent-on-photo)">${esc(when(card))}</div><h2>${esc(displayTitle(card.title))}</h2></div></div>
  <div class="d-sheet">
    <div class="d-actions">${[["calendar", "Календар"], ["arrow", "Маршрут"], ["share", "Поділитися"], ["map", "На мапі"]].map(([i, t]) =>
      `<div class="p-round-action"><span>${ico(i, 22)}</span><span>${t}</span></div>`).join("")}</div>
    <h3 class="p-section-title">Коли й де</h3>
    <div class="d-facts"><div><span class="p-overline">Коли</span><b>${esc(overline(card, new Date(), true))}</b></div>
      <div><span class="p-overline">Де</span><b>${esc(card.place_name || card.city || "")}</b></div>
      <div><span class="p-overline">Ціна</span><b>${esc(cost || "Уточнюйте")}</b></div><div><span class="p-overline">Джерело</span><b>${esc(card.source_name || "Афіша")}</b></div></div>
  </div>
  <div class="d-bar p-glass"><div class="d-bar-top"><div><div class="p-overline">${esc(when(card))}</div><span>${esc(cost || "")}</span></div>
    <span class="p-btn p-btn--primary">Купити квиток</span></div><span class="p-btn p-btn--secondary">${ico("people", 20)}Шукаю компанію</span></div>
</div>`;
}

/** Шторка «Шукаю компанію» поверх події. Кнопки −/+ справжні: час кроком 15 хвилин, людей від 2 до 8. */
export function companionsScreen(card) {
  const start = new Date(Date.parse(card.starts_at) - 30 * 60e3);
  return `<div class="canvas companions-screen">
  <div class="c-under cat-${esc(card.category)}">${art(card)}${statusBar(true)}</div>
  <div class="p-sheet c-sheet"><div class="p-sheet__grabber"></div>
    <h2>Шукаю компанію</h2><h3>${esc(displayTitle(card.title))}</h3>
    <p>Зберіть невелику компанію й ідіть разом. Хто хоче долучитися, надсилає запит — ви вирішуєте, кого взяти. Лише 18+.</p>
    <div class="c-card"><div><span class="p-overline">Час зустрічі</span><b data-time="${start.getTime()}" data-tz="${esc(card.time_zone || "Europe/Kyiv")}">${timeOf(start, card.time_zone || "Europe/Kyiv")}</b><small data-before>За 30 хв до початку</small></div>
      <button type="button" data-step="time:-1" aria-label="Раніше">−</button><button type="button" data-step="time:1" aria-label="Пізніше">+</button></div>
    <span class="p-overline c-label">Де зустрітись</span><div class="c-field">Біля головного входу</div>
    <div class="c-card"><div><span class="p-overline">Скільки людей шукаєте</span><b data-count>4</b></div>
      <button type="button" data-step="count:-1" aria-label="Менше">−</button><button type="button" data-step="count:1" aria-label="Більше">+</button></div>
    <span class="p-btn p-btn--primary">${ico("share", 20)}Опублікувати й поділитися</span>
  </div>
</div>`;
}

export function bindCompanions(root, card) {
  root.addEventListener("click", (event) => {
    const button = event.target.closest("[data-step]");
    if (!button) return;
    const [what, delta] = button.dataset.step.split(":");
    if (what === "count") {
      const el = root.querySelector("[data-count]");
      el.textContent = Math.min(8, Math.max(2, Number(el.textContent) + Number(delta)));
    } else {
      const el = root.querySelector("[data-time]");
      const start = Date.parse(card.starts_at);
      const t = Math.min(start, Math.max(start - 180 * 60e3, Number(el.dataset.time) + Number(delta) * 15 * 60e3));
      el.dataset.time = t;
      el.textContent = timeOf(new Date(t), el.dataset.tz);
      const before = Math.round((start - t) / 60e3);
      root.querySelector("[data-before]").textContent = before ? `За ${before >= 60 ? `${Math.floor(before / 60)} год ${before % 60 ? `${before % 60} хв ` : ""}` : `${before} хв `}до початку` : "На початку";
    }
  });
}

/** Стос сповіщень, як на екрані блокування: нагадування, дайджест вихідних, нове в закладі, за яким стежите. */
export function notifications({ next, weekend, city, fresh }) {
  const items = [
    next && ["зараз", "Через годину", `«${displayTitle(next.title)}» о ${timeOf(new Date(next.starts_at), next.time_zone || "Europe/Kyiv")}${next.place_name ? ` · ${next.place_name}` : ""}`],
    weekend.count && ["пт, 10:00", `Вихідні в ${city}: ${plural(weekend.count, EVENTS)}`, weekend.titles.map((t) => `«${displayTitle(t)}»`).join(", ") + " та інші"],
    fresh && ["вчора", `Нове в «${fresh.place_name}»`, `«${displayTitle(fresh.title)}» — ${overline(fresh)}`],
  ].filter(Boolean);
  return items.map(([time, title, body]) => `<div class="push"><img src="icon.png" alt=""><div><div class="push-head"><b>Поряд</b><small>${esc(time)}</small></div>
    <b>${esc(title)}</b><p>${esc(body)}</p></div></div>`).join("");
}

const SHELTER_KINDS = { metro: "Метро", underpass: "Підземний перехід", parking: "Підземний паркінг", basement: "Укриття" };

/** Блок «Безпека» з екрана події: комендантська й найближчі укриття (відкриті дані КМДА). */
export function safetyCard(safety) {
  const rows = [
    safety.curfew && `<div class="p-row">${ico("clock", 22)}<div><div class="p-row__sub">Комендантська в місті з ${esc(safety.curfew.starts)} до ${esc(safety.curfew.ends)}</div></div></div>`,
    ...(safety.shelters ?? []).slice(0, 2).map((s) => `<div class="p-row">${ico("shield", 22)}<div><div class="p-overline">${esc(SHELTER_KINDS[s.kind] || "Укриття")} · ${Number(s.distance_m)} м</div>
      <div class="p-row__title">${esc(s.address)}</div></div>${ico("chevron", 18).replace("<svg", '<svg style="transform:rotate(-90deg);opacity:.4"')}</div>`),
  ].filter(Boolean);
  return `<div class="p-rows">${rows.join("")}</div>`;
}

/** «Стежити»: заклади з афіші, дзвіночок перемикається. */
export function followRows(places) {
  return `<div class="p-rows">${places.map((p, i) => `<div class="p-row"><span class="f-avatar cat-${esc(p.category)}">${ico(p.category, 20)}</span>
    <div><div class="p-row__title">${esc(p.name)}</div><div class="p-row__sub">${esc(plural(p.count, EVENTS))} попереду</div></div>
    <button type="button" class="f-bell" aria-pressed="${i === 0}">${ico("bell", 18)}<span>${i === 0 ? "Стежу" : "Стежити"}</span></button></div>`).join("")}</div>`;
}

/** Екран малюється в 402 точки завширшки; рамка телефона може бути будь-якою — масштабуємо. */
export function fitScreens(root = document) {
  const ro = new ResizeObserver((entries) => entries.forEach((e) => e.target.style.setProperty("--s", (e.contentRect.width / 402).toFixed(4))));
  root.querySelectorAll(".iphone .screen").forEach((el) => ro.observe(el));
}
