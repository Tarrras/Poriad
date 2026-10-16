// Лендинг: сторінка — квиток. Спершу зустрічі від людей (порожній квиток, який відвідувач друкує сам), далі «Шукаю
// компанію» на справжній події з афіші, сама афіша жанрами — опорою. Активності не вигадуємо: лише справжні дані prod.
import { discover, fold, soonFirst, CITIES, cityOf, CATEGORIES, displayTitle, overline, stubParts, httpsOrNull, esc } from "./poriad.js?v=6";
import { ensureCards, remember, poster, bindCards, openEvent, openInstall, reveal, navLine, bindLocks, savedCity, qr, stubTile, photo } from "./ui.js?v=6";

navLine();
bindLocks();
reveal();
document.querySelector("[data-qr]").innerHTML = qr("Наведіть камеру телефону — відкриється App Store");

const $ = (selector) => document.querySelector(selector);
const calm = matchMedia("(prefers-reduced-motion: reduce)").matches;
const entries = new Map();
bindCards($("main"), (id) => entries.get(id));
const setCat = (el, category) => { el.className = el.className.replace(/\bcat-\w+/g, "").trim() + ` cat-${category}`; };

// ---- Порожній квиток: відвідувач друкує свою зустріч — жанр фарбує корінець, місця рахуються на корінці й у квитанції.
const GENRES = ["games", "sport", "music", "food", "outdoors", "social"];
const blank = $("[data-blank]");
let capacity = 6;
$("[data-genres]").innerHTML = GENRES.map((g) =>
  `<button class="chip cat-${g}" type="button" data-genre="${g}" aria-pressed="${g === "games"}"><span class="dot"></span>${CATEGORIES[g]}</button>`).join("");
$("[data-genres]").addEventListener("click", (event) => {
  const chip = event.target.closest("[data-genre]");
  if (!chip) return;
  document.querySelectorAll("[data-genre]").forEach((c) => c.setAttribute("aria-pressed", c === chip));
  setCat(blank, chip.dataset.genre);
  $("[data-genre-name]").textContent = CATEGORIES[chip.dataset.genre];
});
blank.addEventListener("click", (event) => {
  const step = Number(event.target.closest("[data-seats]")?.dataset.seats);
  if (!step) return;
  capacity = Math.min(20, Math.max(2, capacity + step));
  $("[data-seats-text]").textContent = $("[data-slip-seats]").textContent = `1/${capacity}`;
});

// ---- «Шукаю компанію» і сусідні вкладки: той самий квиток, інший штамп.
const STORIES = {
  company: ["Є квиток, нема з ким піти?", "На будь-якій події з афіші натисніть «Шукаю компанію» й зберіть невелику компанію. Хто хоче долучитися, надсилає запит — ви вирішуєте, кого взяти. Лише 18+.", "Шукаю компанію", "Знайти компанію в застосунку"],
  follow: ["Улюблене не загубиться", "Стежте за закладом, артистом чи організатором — Поряд скаже, щойно в них з’явиться нова подія.", "Ви стежите", "Стежити в застосунку"],
  remind: ["Нічого не проґавите", "Нагадування за годину до початку, дайджест вихідних щоп’ятниці й новини від тих, за ким стежите.", "Нагадаємо за годину", "Увімкнути нагадування"],
};
$("[data-story-tabs]").addEventListener("click", (event) => {
  const tab = event.target.closest("[data-story]");
  if (!tab) return;
  document.querySelectorAll("[data-story]").forEach((t) => t.setAttribute("aria-pressed", t === tab));
  const [title, text, stamp, action] = STORIES[tab.dataset.story];
  $("[data-story-title]").textContent = title;
  $("[data-story-text]").textContent = text;
  $("[data-plate-stamp]").textContent = stamp;
  $("[data-story-action]").textContent = action;
  $("[data-story-action]").dataset.reason = tab.dataset.story;
});
$("[data-story-action]").addEventListener("click", (event) => { event.preventDefault(); openInstall(event.currentTarget.dataset.reason, plateCard()); });

// ---- Дані міста
const ahead = (startsAt) => Date.parse(startsAt) > Date.now();
const withinDays = (startsAt, days) => Date.parse(startsAt) < Date.now() + days * 864e5;
const indexes = new Map();
async function cityIndex(name) {
  if (!indexes.has(name)) {
    const { index, cards } = await discover(name, { cards: 24 });
    remember(cards);
    const folded = soonFirst(fold(index));
    folded.forEach((e) => entries.set(e.id, e));
    indexes.set(name, folded);
  }
  return indexes.get(name);
}

// Пластина: справжні події найближчих днів із фото, повільно змінюють одна одну. Курсор на пластині — пауза.
let plate = [], shown = 0, plateTimer = null;
const plateCard = () => plate[shown] ?? null;
function showPlate(i) {
  shown = i;
  const card = plate[i];
  document.querySelectorAll("[data-plate-cover] img").forEach((img, k) => img.classList.toggle("on", k === i));
  document.querySelectorAll("[data-plate-queue] button").forEach((b, k) => b.setAttribute("aria-pressed", k === i));
  $("[data-plate-title]").textContent = displayTitle(card.title);
  $("[data-plate-where]").textContent = [card.place_name, card.city].filter(Boolean).join(" · ");
  const [time, day] = stubParts(card);
  $("[data-plate-time]").textContent = time;
  $("[data-plate-day]").textContent = day;
  $("[data-plate-stub]").setAttribute("aria-label", overline(card, new Date(), true));
  setCat($("[data-plate]"), card.category);
  $("[data-plate]").dataset.id = card.id;
  $("[data-plate-link]").href = `afisha.html?e=${encodeURIComponent(card.id)}`;
}
$("[data-plate-link]").addEventListener("click", (event) => {
  if (!plateCard()) return;
  event.preventDefault();
  openEvent(plateCard().id, entries.get(plateCard().id));
});
async function loadPlate(folded) {
  const soon = folded.filter((e) => e.origin === "import" && ahead(e.startsAt) && withinDays(e.startsAt, 7)).slice(0, 40);
  plate = (await ensureCards(soon.map((e) => e.id))).filter((c) => httpsOrNull(c.image_url)).slice(0, 4);
  if (!plate.length) return;
  $("[data-plate-cover]").insertAdjacentHTML("afterbegin", plate.map((c, k) => photo(c, k > 0)).join(""));
  // Черга під пластиною — ті самі події маленькими фото: видно, що далі, і можна вибрати самому.
  $("[data-plate-queue]").innerHTML = plate.map((c, k) => `<button type="button" class="cat-${esc(c.category)}" aria-pressed="${k === 0}" aria-label="${esc(displayTitle(c.title))}">${photo(c)}</button>`).join("");
  $("[data-plate-queue]").addEventListener("click", (event) => {
    const button = event.target.closest("button");
    if (button) showPlate([...button.parentNode.children].indexOf(button));
  });
  showPlate(0);
  // Плитка фіналу — ще одна справжня афіша, інша, ніж на пластині.
  const extra = plate[plate.length - 1];
  $("[data-tile-photo]").innerHTML = photo(extra);
  setCat($("[data-tile-color]"), plate[0].category === "music" ? "games" : "music");
  clearInterval(plateTimer);
  if (calm || plate.length < 2) return;
  let paused = false;
  $("[data-plate]").addEventListener("pointerenter", () => { paused = true; });
  $("[data-plate]").addEventListener("pointerleave", () => { paused = false; });
  plateTimer = setInterval(() => { if (!paused && !document.hidden) showPlate((shown + 1) % plate.length); }, 5600);
}

// «Уже збирають»: справжні зустрічі від людей у місті, якщо вони є. Нема — секцію веде порожній квиток вище.
async function loadPeople(folded, city) {
  const people = folded.filter((e) => e.origin === "community" && ahead(e.startsAt)).slice(0, 8);
  $("[data-found]").hidden = !people.length;
  if (!people.length) return;
  $("[data-found-title]").textContent = `Уже збирають у ${city.in}`;
  $("[data-found-rail]").innerHTML = (await ensureCards(people.map((e) => e.id))).map((card) => poster(card, entries.get(card.id))).join("");
}

// Афіша жанрами: найближчі події кожного жанру на тиждень уперед; рядок відкривається на місці, подія — шторкою.
async function loadBoard(folded) {
  const week = folded.filter((e) => ahead(e.startsAt) && withinDays(e.startsAt, 7));
  const groups = new Map();
  for (const e of week) if (CATEGORIES[e.category]) groups.set(e.category, [...(groups.get(e.category) ?? []), e]);
  const top = [...groups.entries()].sort((a, b) => b[1].length - a[1].length).slice(0, 7);
  const list = $("[data-genre-list]");
  if (!top.length) { list.innerHTML = `<div class="empty"><b>Цього тижня подій поки нема</b><span>Подивіться всю афішу й мапу.</span></div>`; return; }
  const firsts = await ensureCards(top.map(([, events]) => events[0].id));
  list.innerHTML = top.map(([category, events], k) => {
    const first = firsts.find((c) => c.id === events[0].id) ?? { ...events[0], starts_at: events[0].startsAt, time_zone: events[0].tz, category };
    const at = (e) => overline({ starts_at: e.startsAt, time_zone: e.tz });
    return `<details class="genre cat-${category}"${k === 0 ? " open" : ""}>
      <summary>${stubTile(first)}<span>${esc(CATEGORIES[category])}</span><span class="when">найближча: ${esc(at(events[0]))}</span><span class="plus" aria-hidden="true"></span></summary>
      <ul>${events.slice(0, 5).map((e) => `<li><button type="button" data-open="${esc(e.id)}"><span class="name">${esc(displayTitle(e.title))}</span><span class="at">${esc(at(e))}</span></button></li>`).join("")}</ul>
    </details>`;
  }).join("");
}
$("[data-genre-list]").addEventListener("click", (event) => {
  const id = event.target.closest("[data-open]")?.dataset.open;
  if (id) openEvent(id, entries.get(id));
});

// ---- Місто: з минулого візиту або Київ. Вкладки міняють афішу й «уже збирають»; пластина лишається київською.
const state = { city: CITIES.some((c) => c.name === savedCity.get()) ? savedCity.get() : "Київ" };
$("[data-cities]").innerHTML = CITIES.map((c) => `<button type="button" data-city="${c.name}">${c.name}</button>`).join("");
$("[data-cities]").addEventListener("click", (event) => {
  const city = event.target.closest("[data-city]")?.dataset.city;
  if (city && city !== state.city) { state.city = city; savedCity.set(city); load(); }
});

async function load() {
  const city = cityOf(state.city);
  document.querySelectorAll("[data-city]").forEach((b) => b.setAttribute("aria-pressed", b.dataset.city === city.name));
  document.querySelectorAll("[data-all]").forEach((a) => { a.href = `afisha.html${city.name === "Київ" ? "" : `?city=${encodeURIComponent(city.name)}`}`; });
  try {
    const folded = await cityIndex(city.name);
    await Promise.all([loadBoard(folded), loadPeople(folded, city)]);
  } catch {
    $("[data-genre-list]").innerHTML = `<div class="empty"><b>Афіша не завантажилась</b><span>Перевірте з’єднання й спробуйте ще раз.</span></div>`;
  }
}

load();
cityIndex("Київ").then(loadPlate).catch(() => { /* пластина лишається з підписом без фото */ });
