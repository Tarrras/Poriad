// Лендинг: спершу продукт — живий телефон зі справжньою афішею, вітрина функцій на живих екранах; афіша міста — бонусом нижче.
import { discover, fold, soonFirst, inWhen, eventSafety, CITIES, cityOf, WHEN, plural, EVENTS, displayTitle, httpsOrNull } from "./poriad.js";
import { ensureCards, remember, poster, skeletons, bindCards, reveal, navGlass, bindLocks, countUp, savedCity, qr } from "./ui.js";
import { homeScreen, detailScreen, companionsScreen, bindCompanions, notifications, safetyCard, followRows, fitScreens } from "./screens.js";

navGlass();
bindLocks();
reveal();
fitScreens();
document.querySelector("[data-qr]").innerHTML = qr("Наведіть камеру телефону — відкриється потрібний стор");

const $ = (selector) => document.querySelector(selector);
const calm = matchMedia("(prefers-reduced-motion: reduce)").matches;
const state = { city: CITIES.some((c) => c.name === savedCity.get()) ? savedCity.get() : "Київ", when: null, folded: [] };
const entries = new Map();
bindCards(document.querySelector("main"), (id) => entries.get(id));

const indexes = new Map();
async function cityIndex(name) {
  if (!indexes.has(name)) {
    const { index, cards } = await discover(name, { cards: 24 });
    remember(cards);
    const folded = soonFirst(fold(index));
    folded.forEach((e) => entries.set(e.id, e));
    indexes.set(name, { index, folded });
  }
  return indexes.get(name);
}

const ahead = (startsAt, hours = 0) => Date.parse(startsAt) > Date.now() + hours * 36e5;
const withinDays = (startsAt, days) => Date.parse(startsAt) < Date.now() + days * 864e5;
const show = (selector, delay) => setTimeout(() => { $(selector).hidden = false; }, calm ? 0 : delay);

// ---- Демо застосунку: завжди Київ — там є все, зокрема укриття.
async function demo() {
  const { index, folded } = await cityIndex("Київ");
  const soon = folded.filter((e) => ahead(e.startsAt) && withinDays(e.startsAt, 7)).slice(0, 48);
  const got = await ensureCards(soon.map((e) => e.id));
  const vivid = got.filter((c) => httpsOrNull(c.image_url));
  if (vivid.length < 6) return;

  // Телефон у героїні: «Головна» з гортанням великих карток і сіткою постерів.
  const home = $("[data-home]");
  home.innerHTML = homeScreen({ city: "Київ", total: folded.length, heroes: vivid.slice(0, 6), posters: vivid.slice(6, 10) });
  autoPager(home);

  // Подія для вітрини: з афіші, з ціною, не раніше ніж за дві години — і з укриттями поруч.
  let featured = null, safety = null;
  const candidates = vivid.filter((c) => c.origin === "import" && (c.is_free || c.price_min > 0) && ahead(c.starts_at, 2)).slice(0, 5);
  for (const card of candidates) {
    const s = await eventSafety(card.id).catch(() => null);
    if (s?.shelters?.length) { featured = card; safety = s; break; }
  }
  featured ??= candidates[0] ?? vivid[0];
  $("[data-detail]").innerHTML = detailScreen(featured);
  $("[data-companions]").innerHTML = companionsScreen(featured);
  bindCompanions($("[data-companions]"), featured);
  if (safety) $("[data-safety]").innerHTML = safetyCard(safety);

  const weekend = folded.filter((e) => inWhen(e, "weekend"));
  const next = got.find((c) => ahead(c.starts_at, 0.5));
  const fresh = vivid.find((c) => c.place_name && c.place_name !== next?.place_name);
  $("[data-push]").innerHTML = notifications({ next, fresh, city: "Києві", weekend: { count: weekend.length, titles: weekend.slice(0, 2).map((e) => e.title) } });

  // «Стежити»: три заклади з найбільшою афішею серед найближчих подій; лічильник — по всьому індексу.
  const at = (lat, lng) => `${Number(lat).toFixed(4)},${Number(lng).toFixed(4)}`;
  const perPlace = new Map();
  for (const e of index) perPlace.set(at(e.lat, e.lng), (perPlace.get(at(e.lat, e.lng)) ?? 0) + 1);
  const places = [...new Map(got.filter((c) => c.place_name).map((c) =>
    [c.place_name, { name: c.place_name, category: c.category, count: perPlace.get(at(c.latitude, c.longitude)) ?? 1 }])).values()]
    .sort((a, b) => (a.name.length > 24) - (b.name.length > 24) || b.count - a.count).slice(0, 3);
  $("[data-follow]").innerHTML = followRows(places);
  $("[data-follow]").addEventListener("click", (event) => {
    const bell = event.target.closest(".f-bell");
    if (!bell) return;
    const on = bell.getAttribute("aria-pressed") !== "true";
    bell.setAttribute("aria-pressed", on);
    bell.querySelector("span").textContent = on ? "Стежу" : "Стежити";
  });

  // Скляні картки біля телефона — з тих самих даних.
  if (next) {
    $("[data-notif] p").textContent = `Через годину: «${displayTitle(next.title)}»${next.place_name ? ` · ${next.place_name}` : ""}`;
    show("[data-notif]", 500);
  }
  $("[data-company] small").textContent = `на «${displayTitle(featured.title)}»`;
  show("[data-company]", 1300);
  if (safety) {
    const s = safety.shelters[0];
    $("[data-shelter] b").textContent = `Укриття · ${s.distance_m} м`;
    $("[data-shelter] small").textContent = s.address;
    show("[data-shelter]", 1700);
  }
}

/** Великі картки гортаються самі; за телефоном світиться обкладинка поточної. Курсор на телефоні — пауза. */
function autoPager(screen) {
  const track = screen.querySelector(".pager-track");
  const glows = [...document.querySelectorAll(".ambient i")];
  let i = 0, layer = 0, paused = false;
  const glow = () => {
    const card = track.children[i];
    const img = card.querySelector("img");
    layer ^= 1;
    glows[layer].style.backgroundImage = img ? `url("${img.src}")` : "";
    glows[layer].style.backgroundColor = getComputedStyle(card).getPropertyValue("--hue");
    glows.forEach((g, k) => g.classList.toggle("on", k === layer));
  };
  glow();
  if (calm) return;
  const phone = screen.closest(".iphone");
  phone.addEventListener("pointerenter", () => { paused = true; phone.classList.add("paused"); });
  phone.addEventListener("pointerleave", () => { paused = false; phone.classList.remove("paused"); });
  setInterval(() => {
    if (paused || document.hidden) return;
    i = (i + 1) % track.children.length;
    track.style.transform = `translateX(${-i * 330}px)`;
    glow();
  }, 3400);
}

// ---- Лічильник і бонус-афіша — у місті людини.
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
  $("[data-teaser]").innerHTML = skeletons(6);
  try {
    state.folded = (await cityIndex(city.name)).folded;
  } catch {
    $("[data-teaser]").innerHTML = `<div class="empty"><b>Афіша не завантажилась</b><span>Перевірте з’єднання й спробуйте ще раз.</span></div>`;
    return;
  }
  const all = state.folded;
  countUp($("[data-total]"), all.length);
  $("[data-total-word]").textContent = plural(all.length, EVENTS).split(" ").pop();
  const link = `afisha.html?city=${encodeURIComponent(city.name)}`;
  $("[data-live]").href = link;
  $("[data-all]").href = link;
  $("[data-all]").firstChild.textContent = `Уся афіша ${city.of} `;

  const counts = Object.fromEntries(Object.keys(WHEN).map((w) => [w, all.filter((e) => inWhen(e, w)).length]));
  if (state.when === null || !counts[state.when]) state.when = ["today", "weekend", "tomorrow"].find((w) => counts[w] >= 4) ?? "";
  $("[data-when]").innerHTML = [...Object.entries(WHEN), ["", "Усе"]].map(([w, label]) =>
    `<button class="chip" type="button" data-w="${w}">${label}${w ? ` <span class="count">${counts[w]}</span>` : ""}</button>`).join("");

  const weekend = all.filter((e) => inWhen(e, "weekend"));
  const box = $("[data-weekend]");
  if (weekend.length) {
    box.querySelector(".big").textContent = plural(weekend.length, EVENTS);
    const faces = (await ensureCards(weekend.slice(0, 12).map((e) => e.id))).filter((c) => httpsOrNull(c.image_url)).slice(0, 4);
    box.querySelector(".mini").innerHTML = faces.map((c) => `<span style="background-image:url('${encodeURI(c.image_url)}')"></span>`).join("");
    show("[data-weekend]", 900);
  } else box.hidden = true;
  await renderTeaser();
}

async function renderTeaser() {
  document.querySelectorAll("[data-w]").forEach((c) => c.setAttribute("aria-pressed", c.dataset.w === (state.when || "")));
  const list = state.folded.filter((e) => inWhen(e, state.when)).slice(0, 10);
  const rail = $("[data-teaser]");
  if (!list.length) { rail.innerHTML = `<div class="empty"><b>На ці дні подій поки нема</b><span>Подивіться інші дні або всю афішу.</span></div>`; return; }
  rail.innerHTML = (await ensureCards(list.map((e) => e.id))).map((card) => poster(card, entries.get(card.id))).join("");
}

load().then(demo).catch(() => { /* статичні скріни в рамках лишаються запасним варіантом */ });
