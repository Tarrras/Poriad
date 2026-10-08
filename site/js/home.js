// Лендинг: живі числа й афіші з prod, стрічка тижня, афіша-тизер, історія з телефоном, категорії.
import { discover, fold, soonFirst, inWhen, CITIES, cityOf, CATEGORIES, WHEN, plural, EVENTS, displayTitle, overline, timeOf, httpsOrNull, esc } from "./poriad.js";
import { cards, ensureCards, remember, poster, skeletons, art, bindCards, reveal, navGlass, bindLocks, countUp, savedCity, icon, qr } from "./ui.js";

navGlass();
bindLocks();
reveal();
document.querySelector("[data-qr]").innerHTML = qr("Наведіть камеру телефону — відкриється потрібний стор");

const $ = (selector) => document.querySelector(selector);
const state = { city: CITIES.some((c) => c.name === savedCity.get()) ? savedCity.get() : "Київ", when: null, folded: [], byId: new Map() };
bindCards(document.querySelector("main"), (id) => state.byId.get(id));

// ---- Сцена: телефони розгортаються з прокруткою й нахиляються за курсором.
const stage = $(".stage"), inner = $(".stage-inner");
const unfold = () => stage.style.setProperty("--p", Math.min(1, Math.max(0, scrollY / 520)).toFixed(3));
addEventListener("scroll", () => requestAnimationFrame(unfold), { passive: true });
unfold();
if (matchMedia("(pointer: fine)").matches && !matchMedia("(prefers-reduced-motion: reduce)").matches) {
  $(".hero").addEventListener("pointermove", (event) => {
    inner.style.setProperty("--tx", (event.clientX / innerWidth - 0.5).toFixed(3));
    inner.style.setProperty("--ty", (event.clientY / innerHeight - 0.5).toFixed(3));
  });
}

// ---- Історія: крок у центрі екрана показує свій екран на телефоні, що стоїть на місці.
const steps = [...document.querySelectorAll(".step")];
const screens = $(".story-phone .screens"), dots = $(".story-phone .dots"), phone = $(".story-phone");
screens.innerHTML = steps.map((s) => `<img src="${s.dataset.shot}" alt="" loading="lazy">`).join("");
dots.innerHTML = steps.map(() => "<i></i>").join("");
function activate(i) {
  steps.forEach((s, k) => s.classList.toggle("active", k === i));
  [...screens.children].forEach((img, k) => img.classList.toggle("on", k === i));
  [...dots.children].forEach((d, k) => d.classList.toggle("on", k === i));
  phone.style.setProperty("--hue", getComputedStyle(steps[i]).getPropertyValue("--hue"));
}
const storyObserver = new IntersectionObserver((entries) => entries.forEach((e) => { if (e.isIntersecting) activate(steps.indexOf(e.target)); }),
  { rootMargin: "-45% 0px -45% 0px" });
steps.forEach((s) => storyObserver.observe(s));
activate(0);

// ---- Перемикачі тизера
$("[data-cities]").innerHTML = CITIES.map((c) => `<button type="button" data-city="${c.name}">${c.name}</button>`).join("");
$("[data-cities]").addEventListener("click", (event) => {
  const city = event.target.closest("[data-city]")?.dataset.city;
  if (city && city !== state.city) { state.city = city; savedCity.set(city); load(); }
});
$("[data-when]").addEventListener("click", (event) => {
  const chip = event.target.closest("[data-w]");
  if (chip) { state.when = chip.dataset.w || null; renderTeaser(); }
});

async function load() {
  const city = cityOf(state.city);
  document.querySelectorAll("[data-city-in]").forEach((el) => { el.textContent = city.in; });
  document.querySelectorAll("[data-city]").forEach((b) => b.setAttribute("aria-pressed", b.dataset.city === city.name));
  $("[data-teaser]").innerHTML = skeletons(8);
  try {
    const { index, cards: first } = await discover(city.name, { cards: 24 });
    remember(first);
    state.folded = soonFirst(fold(index));
    state.byId = new Map(state.folded.map((e) => [e.id, e]));
  } catch {
    $("[data-teaser]").innerHTML = `<div class="empty"><b>Афіша не завантажилась</b><span>Перевірте з’єднання й спробуйте ще раз.</span>
      <button class="btn secondary" type="button" onclick="location.reload()">Оновити</button></div>`;
    return;
  }
  const all = state.folded;
  countUp($("[data-total]"), all.length);
  $("[data-total-word]").textContent = plural(all.length, EVENTS).split(" ").pop();
  const links = `afisha.html?city=${encodeURIComponent(city.name)}`;
  $("[data-live]").href = links;
  $("[data-all]").href = links;
  $("[data-all]").firstChild.textContent = `Уся афіша ${city.of} · ${all.length.toLocaleString("uk-UA")} `;

  // Чипи дат з кількостями; за замовчуванням — перше, де є що показати.
  const counts = Object.fromEntries(Object.keys(WHEN).map((w) => [w, all.filter((e) => inWhen(e, w)).length]));
  if (state.when === null || !counts[state.when]) state.when = ["today", "weekend", "tomorrow"].find((w) => counts[w] >= 4) ?? "";
  $("[data-when]").innerHTML = [...Object.entries(WHEN), ["", "Усе"]].map(([w, label]) =>
    `<button class="chip" type="button" data-w="${w}">${label}${w ? ` <span class="count">${counts[w]}</span>` : ""}</button>`).join("");

  renderCategories(all, links);
  await Promise.all([renderTeaser(), renderWeek(all)]);
}

async function renderTeaser() {
  document.querySelectorAll("[data-w]").forEach((c) => c.setAttribute("aria-pressed", c.dataset.w === (state.when || "")));
  const list = state.folded.filter((e) => inWhen(e, state.when)).slice(0, 8);
  const grid = $("[data-teaser]");
  if (!list.length) { grid.innerHTML = `<div class="empty"><b>На ці дні подій поки нема</b><span>Подивіться інші дні або всю афішу.</span></div>`; return; }
  const got = await ensureCards(list.map((e) => e.id));
  grid.innerHTML = got.map((card) => poster(card, state.byId.get(card.id))).join("");
  grid.querySelectorAll(".poster").forEach((el, i) => { el.classList.add("reveal"); el.style.setProperty("--d", `${(i % 4) * 0.06}s`); });
  reveal(grid);
}

/** Стрічка тижня й живі картки над телефонами: найближчі сім днів, спершу з фото. */
async function renderWeek(all) {
  // Спершу те, що ще не почалось: виставка «до 31 жовтня» — не найкращий приклад вечора.
  const now = Date.now();
  const ahead = (e) => new Date(e.startsAt) > now;
  const week = all.filter((e) => daysAhead(e) <= 7);
  const soon = [...week.filter(ahead), ...week.filter((e) => !ahead(e))].slice(0, 60);
  const got = await ensureCards(soon.map((e) => e.id));
  const withImage = got.filter((c) => httpsOrNull(c.image_url));
  const tiles = (withImage.length >= 12 ? withImage : got).slice(0, 28);
  const rows = [tiles.filter((_, i) => i % 2 === 0), tiles.filter((_, i) => i % 2 === 1)];
  document.querySelectorAll("[data-track]").forEach((track, k) => {
    const html = rows[k].map((card) => `<div class="tile" data-id="${esc(card.id)}" role="link" tabindex="0" aria-label="${esc(displayTitle(card.title))}">${art(card)}
      <div class="tip"><small>${esc(overline(card))}</small><b>${esc(displayTitle(card.title))}</b></div></div>`).join("");
    track.innerHTML = `<div class="track-inner" style="--dur:${rows[k].length * 5}s">${html}</div><div class="track-inner" style="--dur:${rows[k].length * 5}s" aria-hidden="true">${html}</div>`;
  });

  // Над телефонами — дві найближчі події з фото, «пуш» про найближчу й лічильник вихідних.
  const [a, b] = withImage;
  const floats = document.querySelectorAll("[data-float]");
  [a, b].forEach((card, i) => {
    if (!card) { floats[i].hidden = true; return; }
    floats[i].dataset.id = card.id;
    floats[i].innerHTML = `${art(card, "thumb")}
      <div><div class="when">${esc(overline(card))}</div><b>${esc(displayTitle(card.title))}</b></div>`;
    setTimeout(() => { floats[i].hidden = false; }, 500 + i * 300);
  });
  const next = got.find((c) => new Date(c.starts_at) > now);
  const notif = $("[data-notif]");
  if (next) {
    notif.dataset.id = next.id;
    notif.querySelector("p").textContent = `Нагадування: «${displayTitle(next.title)}» о ${timeOf(new Date(next.starts_at), next.time_zone || "Europe/Kyiv")}${next.place_name ? `, ${next.place_name}` : ""}`;
    setTimeout(() => { notif.hidden = false; }, 1200);
  }
  const weekend = all.filter((e) => inWhen(e, "weekend"));
  const box = $("[data-weekend]");
  if (weekend.length) {
    box.querySelector(".big").textContent = plural(weekend.length, EVENTS);
    box.querySelector(".mini").innerHTML = withImage.slice(2, 6).map((c) => `<span style="background-image:url('${encodeURI(c.image_url)}')"></span>`).join("");
    setTimeout(() => { box.hidden = false; }, 900);
  } else box.hidden = true;
}

const daysAhead = (e) => (new Date(e.startsAt) - Date.now()) / 864e5;

function renderCategories(all, links) {
  const counts = {};
  for (const e of all) counts[e.category] = (counts[e.category] ?? 0) + 1;
  // Найбільші дві — великими плитками, решта 3×3: місто саме каже, чим живе.
  const order = Object.entries(CATEGORIES).sort(([a], [b]) => (counts[b] ?? 0) - (counts[a] ?? 0));
  $("[data-cats]").innerHTML = order.map(([key, label], i) => `<a class="cat cat-${key} reveal${i < 2 ? " big" : ""}" style="--d:${(i % 3) * 0.05}s" href="${links}&cat=${key}">
    <div class="art">${icon(key, "glyph")}</div><b>${label}</b><small>${counts[key] ? plural(counts[key], EVENTS) : "Скоро"}</small>
    <span class="arrow">${icon("arrow")}</span></a>`).join("");
  reveal($("[data-cats]"));
}

// Клавіатура для плиток стрічки (role="link").
document.addEventListener("keydown", (event) => {
  if (event.key === "Enter" && event.target.matches?.(".tile, .float")) event.target.click();
});

load();
