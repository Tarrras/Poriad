// Лендинг: сторінка — квиток. Корінець героїні — доказ: що справді йде сьогодні ввечері в місті. Далі зустрічі від людей
// (порожній квиток, який відвідувач друкує сам), «Шукаю компанію» на справжній події з афіші, сама афіша жанрами — опорою.
// Активності не вигадуємо: лише справжні дані prod.
import { discover, fold, soonFirst, inWhen, CITIES, cityOf, CATEGORIES, displayTitle, overline, stubParts, timeOf, httpsOrNull, esc, PLAY_URL } from "./poriad.js?v=9";
import { ensureCards, remember, poster, bindCards, openEvent, openInstall, reveal, navLine, bindLocks, savedCity, qr, stubTile, photo, applyStores } from "./ui.js?v=9";

applyStores();
navLine();
bindLocks();
reveal();
document.querySelector("[data-qr]").innerHTML = qr(PLAY_URL ? "Наведіть камеру телефону, і відкриється App Store чи Google Play" : "Наведіть камеру iPhone, і відкриється App Store");

const $ = (selector) => document.querySelector(selector);
const calm = matchMedia("(prefers-reduced-motion: reduce)").matches;
const entries = new Map();
bindCards($("main"), (id) => entries.get(id));
const setCat = (el, category) => { el.className = el.className.replace(/\bcat-\w+/g, "").trim() + ` cat-${category}`; };
const cityQuery = (city, extra = "") => {
  const params = new URLSearchParams(extra);
  if (city.name !== "Київ") params.set("city", city.name);
  return params.toString() ? `?${params}` : "";
};

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
  company: ["Є квиток, нема з ким піти?", "На будь-якій події з афіші натисніть «Шукаю компанію» й зберіть невелику компанію. Хто хоче долучитися, надсилає запит, а ви вирішуєте, кого взяти. Лише 18+.", "Шукаю компанію", "Знайти компанію в застосунку"],
  follow: ["Улюблене не загубиться", "Стежте за закладом, артистом чи організатором, і Поряд скаже, щойно в них з’явиться нова подія.", "Ви стежите", "Стежити в застосунку"],
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
// Лендинг продає вечір 20–32-річним і не дейтинг (PRODUCT.md): у доказах нема дитячих ранків, побачень і подій «для 38–50 років».
// Афіша на сайті показує все; фільтр стоїть лише на вітрині лендингу.
const OFF_BRAND = /побачен|знайомств|dating|\b\d{2}\s*[-–]\s*\d{2}\s*(рок|р\.)/i;
const grown = (e) => e.category !== "kids" && !OFF_BRAND.test(e.title);
const evening = (e) => Number(timeOf(new Date(e.startsAt), e.tz).slice(0, 2)) >= 17;
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

// ---- Корінець героїні: до п'яти справжніх вечірніх квитків (на телефоні три). Сьогодні ввечері пусто — завтра, далі вихідні.
// Зустрічі від людей першими, далі різні жанри: п'ять вистав о 17:00 доводять менше, ніж вистава, концерт і стендап.
function tonightPick(folded) {
  const upcoming = folded.filter((e) => ahead(e.startsAt) && grown(e));
  const peopleFirst = (list) => {
    const sorted = [...list].sort((a, b) => (b.origin === "community") - (a.origin === "community"));
    const seen = new Set(), varied = sorted.filter((e) => e.origin === "community" || (!seen.has(e.category) && seen.add(e.category)));
    return [...varied, ...sorted.filter((e) => !varied.includes(e))];
  };
  for (const [label, test] of [
    ["Сьогодні ввечері", (e) => inWhen(e, "today") && evening(e)],
    ["Завтра ввечері", (e) => inWhen(e, "tomorrow") && evening(e)],
    ["На вихідних", (e) => inWhen(e, "weekend")],
  ]) {
    const got = peopleFirst(upcoming.filter(test));
    if (got.length >= 2) return { label, events: got.slice(0, 5) };
  }
  return { label: "Найближчим часом", events: peopleFirst(upcoming.slice(0, 12)).slice(0, 5) };
}
async function loadTonight(folded, city) {
  const { label, events } = tonightPick(folded);
  const list = $("[data-tonight-list]");
  $("[data-tonight-title]").textContent = label;
  $("[data-tonight-all]").textContent = `Уся афіша ${city.of}`;
  if (!events.length) { list.innerHTML = `<p class="tn-note">Цього тижня в афіші тихо. Зате свою зустріч можна зібрати будь-коли.</p>`; return; }
  const got = await ensureCards(events.map((e) => e.id));
  list.innerHTML = got.map((card) => `<a class="tn" href="afisha.html?e=${encodeURIComponent(card.id)}" data-id="${esc(card.id)}">${stubTile(card)}
    <div><b>${esc(displayTitle(card.title))}</b><span>${esc(card.place_name || card.address || city.name)}</span></div></a>`).join("");
}
const FAILED = "Афіша зараз не відповідає";
function tonightFailed() {
  $("[data-tonight-title]").textContent = "Афіша";
  $("[data-tonight-list]").innerHTML = `<p class="tn-note">Афіша зараз не відповідає.</p><button class="btn small" type="button" data-retry>Спробувати ще</button>`;
  $("[data-tonight-list] [data-retry]").onclick = load;
}

// ---- Пластина «Шукаю компанію»: вечірні події найближчого тижня з фото, у вибраному місті. Повільно змінюють одна одну;
// курсор, фокус чи дотик зупиняють зміну.
let plate = [], shown = 0, plateTimer = null, hold = false;
const plateCard = () => plate[shown] ?? null;
const plateEl = $("[data-plate]");
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
  setCat(plateEl, card.category);
  plateEl.dataset.id = card.id;
  $("[data-plate-link]").href = `afisha.html?e=${encodeURIComponent(card.id)}`;
}
$("[data-plate-link]").addEventListener("click", (event) => {
  if (!plateCard()) return;
  event.preventDefault();
  openEvent(plateCard().id, entries.get(plateCard().id));
});
$("[data-plate-queue]").addEventListener("click", (event) => {
  const button = event.target.closest("button");
  if (button) { hold = true; showPlate([...button.parentNode.children].indexOf(button)); }
});
plateEl.addEventListener("pointerenter", () => { if (!hold) hold = "hover"; });
plateEl.addEventListener("pointerleave", () => { if (hold === "hover") hold = false; });
plateEl.closest(".plate-col").addEventListener("focusin", () => { hold = true; });
plateEl.closest(".plate-col").addEventListener("touchstart", () => { hold = true; }, { passive: true });

function plateIdle(title, where) {
  plateEl.closest(".plate-row").classList.toggle("bare", title === FAILED);
  plateEl.classList.add("idle");
  plateEl.removeAttribute("data-id");
  $("[data-plate-title]").textContent = title;
  $("[data-plate-where]").textContent = where;
  $("[data-plate-queue]").innerHTML = "";
}
async function loadPlate(folded, city) {
  const pool = folded.filter((e) => e.origin === "import" && ahead(e.startsAt) && withinDays(e.startsAt, 7) && grown(e));
  const best = [...pool].sort((a, b) => evening(b) - evening(a)).slice(0, 40);
  const next = (await ensureCards(best.map((e) => e.id))).filter((c) => httpsOrNull(c.image_url)).slice(0, 6);
  clearInterval(plateTimer);
  $("[data-plate-cover]").querySelectorAll("img").forEach((img) => img.remove());
  if (!next.length) { plate = []; plateIdle(`Цього тижня в ${city.in} тихо`, "Подивіться всю афішу й мапу"); fillTiles([]); return; }
  plateEl.classList.remove("idle");
  plateEl.closest(".plate-row").classList.remove("bare");
  plate = next.slice(0, 4);
  $("[data-plate-cover]").insertAdjacentHTML("afterbegin", plate.map((c, k) => photo(c, k > 0)).join(""));
  // Черга під пластиною — ті самі події маленькими фото: видно, що далі, і можна вибрати самому.
  $("[data-plate-queue]").innerHTML = plate.map((c, k) => `<button type="button" class="cat-${esc(c.category)}" aria-pressed="${k === 0}" aria-label="${esc(displayTitle(c.title))}">${photo(c)}</button>`).join("");
  showPlate(0);
  fillTiles([...next.slice(4), ...plate.slice(-2)].slice(0, 2));
  if (calm || plate.length < 2) return;
  plateTimer = setInterval(() => { if (!hold && !document.hidden) showPlate((shown + 1) % plate.length); }, 5600);
}

// Плитки фіналу — ще дві справжні афіші міста. Нема фото — лишається одна чорнильна плитка.
function fillTiles(cards) {
  const sides = document.querySelectorAll("[data-tile-photo]");
  sides.forEach((side, k) => { side.innerHTML = cards[k] ? photo(cards[k]) : ""; if (cards[k]) setCat(side, cards[k].category); });
  $(".tiles").classList.toggle("solo", cards.length < 2);
}

// «Уже збирають»: справжні зустрічі від людей у місті, якщо вони є. Нема — секцію веде порожній квиток вище.
async function loadPeople(folded, city) {
  const people = folded.filter((e) => e.origin === "community" && ahead(e.startsAt)).slice(0, 8);
  $("[data-found]").hidden = !people.length;
  if (!people.length) return;
  $("[data-found-title]").textContent = `Уже збирають у ${city.in}`;
  $("[data-found-rail]").innerHTML = (await ensureCards(people.map((e) => e.id))).map((card) => poster(card, entries.get(card.id))).join("");
}

// ---- Афіша жанрами: найближчі події кожного жанру на тиждень уперед. На широкому екрані — табло: жанр і три події
// в один рядок; на телефоні — рядки, що відкриваються на місці. Подія відкривається шторкою, «Усі N» — категорією афіші.
const wide = matchMedia("(min-width: 1101px)");
let board = null;
async function loadBoard(folded, city) {
  const week = folded.filter((e) => ahead(e.startsAt) && withinDays(e.startsAt, 7) && !OFF_BRAND.test(e.title));
  const groups = new Map();
  for (const e of week) if (CATEGORIES[e.category]) groups.set(e.category, [...(groups.get(e.category) ?? []), e]);
  // Усередині жанру — вечір першим; «Дітям» — останнім рядком; жанри з однією-двома подіями табло не показує.
  for (const [k, list] of groups) groups.set(k, [...list].sort((a, b) => evening(b) - evening(a)));
  const top = [...groups.entries()].filter(([, list]) => list.length >= 3)
    .sort((a, b) => (a[0] === "kids") - (b[0] === "kids") || b[1].length - a[1].length).slice(0, 7);
  board = { top, city, firsts: top.length ? await ensureCards(top.map(([, events]) => events[0].id)) : [] };
  renderBoard();
}
function renderBoard() {
  if (!board) return;
  const list = $("[data-genre-list]");
  const { top, firsts, city } = board;
  if (!top.length) { list.innerHTML = `<div class="empty"><b>Цього тижня подій поки нема</b><span>Подивіться всю афішу й мапу.</span></div>`; return; }
  const at = (e) => overline({ starts_at: e.startsAt, time_zone: e.tz });
  list.innerHTML = top.map(([category, events], k) => {
    const first = firsts.find((c) => c.id === events[0].id) ?? { ...events[0], starts_at: events[0].startsAt, time_zone: events[0].tz, category };
    const all = `<a class="all-cat" href="afisha.html${cityQuery(city, { cat: category })}">Усі ${events.length}</a>`;
    const items = (n) => events.slice(0, n).map((e) => `<li><button type="button" data-open="${esc(e.id)}"><span class="name">${esc(displayTitle(e.title))}</span><span class="at">${esc(at(e))}</span></button></li>`).join("");
    if (wide.matches) return `<div class="genre row cat-${category}"><div class="head">${stubTile(first)}<h3>${esc(CATEGORIES[category])}</h3></div><ul>${items(3)}</ul>${all}</div>`;
    return `<details class="genre cat-${category}"${k === 0 ? " open" : ""}>
      <summary>${stubTile(first)}<span>${esc(CATEGORIES[category])}</span><span class="plus" aria-hidden="true"></span></summary>
      <ul>${items(5)}</ul><div class="foot">${all}</div>
    </details>`;
  }).join("");
}
wide.addEventListener("change", renderBoard);
$("[data-genre-list]").addEventListener("click", (event) => {
  const id = event.target.closest("[data-open]")?.dataset.open;
  if (id) openEvent(id, entries.get(id));
});

// ---- Місто: з минулого візиту або Київ. Вкладки міняють корінець героїні, пластину, афішу й «уже збирають».
const state = { city: CITIES.some((c) => c.name === savedCity.get()) ? savedCity.get() : "Київ" };
$("[data-cities]").innerHTML = CITIES.map((c) => `<button type="button" data-city="${c.name}">${c.name}</button>`).join("");
$("[data-cities]").addEventListener("click", (event) => {
  const city = event.target.closest("[data-city]")?.dataset.city;
  if (city && city !== state.city) { state.city = city; savedCity.set(city); load(); }
});

async function load() {
  const city = cityOf(state.city);
  document.querySelectorAll("[data-city]").forEach((b) => b.setAttribute("aria-pressed", b.dataset.city === city.name));
  document.querySelectorAll("[data-all]").forEach((a) => { a.href = `afisha.html${cityQuery(city)}`; });
  let folded;
  try {
    folded = await cityIndex(city.name);
  } catch {
    tonightFailed();
    plateIdle(FAILED, "Спробуйте трохи згодом");
    $("[data-genre-list]").innerHTML = `<div class="empty"><b>Афіша не завантажилась</b><span>Перевірте з’єднання й спробуйте ще раз.</span>
      <button class="btn secondary" type="button" data-retry>Спробувати ще</button></div>`;
    $("[data-genre-list] [data-retry]").onclick = load;
    return;
  }
  if (city.name !== state.city) return;
  await Promise.all([
    loadTonight(folded, city).catch(tonightFailed),
    loadPlate(folded, city).catch(() => plateIdle(FAILED, "Спробуйте трохи згодом")),
    loadBoard(folded, city),
    loadPeople(folded, city),
  ]);
}

load();
