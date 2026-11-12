// Лендинг: один об'ємний квиток летить сторінкою від секції до секції й на кожній стає іншим. Далі зустрічі від людей
// (порожній квиток, який відвідувач друкує сам), «Шукаю компанію» на справжній події з афіші, сама афіша жанрами — опорою.
// Активності не вигадуємо: лише справжні дані prod.
import { discover, fold, soonFirst, inWhen, CITIES, cityOf, CATEGORIES, displayTitle, cardTitle, overline, stubParts, timeOf, httpsOrNull, sourceNote, esc, PLAY_URL } from "./poriad.js?v=22";
import { ensureCards, remember, poster, bindCards, openEvent, openInstall, reveal, navLine, bindLocks, savedCity, qr, stubTile, photo, icon, applyStores, seatsOf } from "./ui.js?v=22";

applyStores();
navLine();
bindLocks();
reveal();

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

// ---- Свій квиток: відвідувач вибирає жанр, назву й місця — мандрівник на причалі «Від людей» друкує їх на собі.
const GENRES = ["games", "sport", "music", "food", "outdoors", "social"];
const mine = { genre: "games", title: $("#blank-title").value, capacity: 6 };
$("[data-genres]").innerHTML = GENRES.map((g) =>
  `<button class="chip cat-${g}" type="button" data-genre="${g}" aria-pressed="${g === "games"}"><span class="dot"></span>${CATEGORIES[g]}</button>`).join("");
$("[data-genres]").addEventListener("click", (event) => {
  const chip = event.target.closest("[data-genre]");
  if (!chip) return;
  document.querySelectorAll("[data-genre]").forEach((c) => c.setAttribute("aria-pressed", c === chip));
  mine.genre = chip.dataset.genre;
  paint();
});
$("#blank-title").addEventListener("input", (event) => { mine.title = event.target.value; paint(); });
$(".print-form").addEventListener("click", (event) => {
  const step = Number(event.target.closest("[data-seats]")?.dataset.seats);
  if (!step) return;
  mine.capacity = Math.min(20, Math.max(2, mine.capacity + step));
  $("[data-seats-text]").textContent = `1/${mine.capacity}`;
  paint();
});

// ---- «Шукаю компанію» і сусідні вкладки: той самий квиток, інший штамп.
const STORIES = {
  company: ["Є квиток, нема з ким піти?", "На будь-якій події з афіші натисніть «Шукаю компанію» й зберіть невелику компанію. Хто хоче долучитися, надсилає запит, а ви вирішуєте, кого взяти. Лише 18+.", "Шукаю компанію", "Знайти компанію в застосунку"],
  follow: ["Улюблене не загубиться", "Стежте за закладом, артистом чи організатором, і Поряд скаже, щойно в них з’явиться нова подія.", "Ви стежите", "Стежити в застосунку"],
  remind: ["Нічого не проґавите", "Нагадування за годину до початку, дайджест вихідних щоп’ятниці й новини від тих, за ким стежите.", "Нагадаємо за годину", "Увімкнути нагадування"],
};
let stampText = STORIES.company[2];
$("[data-story-tabs]").addEventListener("click", (event) => {
  const tab = event.target.closest("[data-story]");
  if (!tab) return;
  document.querySelectorAll("[data-story]").forEach((t) => t.setAttribute("aria-pressed", t === tab));
  const [title, text, stamp, action] = STORIES[tab.dataset.story];
  $("[data-story-title]").textContent = title;
  $("[data-story-text]").textContent = text;
  stampText = stamp;
  paint();
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

// ---- Зупинки героїні: до п'яти справжніх вечірніх квитків. Сьогодні ввечері пусто — завтра, далі вихідні.
// Зустрічі від людей першими, далі різні жанри: п'ять вистав о 17:00 доводять менше, ніж вистава, концерт і стендап.
function tonightPick(folded) {
  const upcoming = folded.filter((e) => ahead(e.startsAt) && grown(e));
  // Першими — зустрічі, куди вже хтось записався: порожня «0/6» на першому екрані доводить протилежне.
  const joined = (e) => e.origin === "community" && e.count > 0;
  const peopleFirst = (list) => {
    const sorted = [...list].sort((a, b) => joined(b) - joined(a));
    const seen = new Set(), varied = sorted.filter((e) => joined(e) || (!seen.has(e.category) && seen.add(e.category)));
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

// ---- Квиток-мандрівник. Один об'ємний квиток живе на всій сторінці: прокрутка веде його від причалу до причалу
// ([data-dock] у секціях), у польоті він робить півоберта й сідає вже іншим боком — у стані цієї секції.
// Місце рахуємо в координатах сторінки, тож на причалі квиток гортається разом із нею, без скрипта й без тремтіння;
// рахунок кадрів іде лише в польоті й під час оберту. theta — оберт рукою (пружина до кратного 180°), fly — політ
// (0 — перший причал, 1 — другий…). Бік, що дивиться від глядача, заздалегідь друкує те, що покаже наступним.
// Посеред шляху він стискається до значка в правому нижньому куті екрана, а сідаючи — розгортається (власник, 12.11):
// у польоті він не закриває ні текст, ні кнопки. Зі «зменшити рух» квиток не літає, а одразу стоїть на причалі секції.
const TOKEN = 110; // ширина значка в польоті, px
const t3 = $("[data-t3]"), body3 = $("[data-t3-body]"), hingeEl = $("[data-t3-hinge]"), stopsEl = $("[data-hero-stops]");
const faces = [...document.querySelectorAll("[data-t3-face]")], stubs = [...document.querySelectorAll("[data-t3-stub]")];
const mod = (k, n) => ((k % n) + n) % n;
const clamp01 = (x) => Math.min(1, Math.max(0, x));
const smooth = (x) => { const t = clamp01(x); return t * t * (3 - 2 * t); };
let stops = [], keys = [null, null], theta = -90, goal = -90, omega = 0, hinge = 0, tiltX = 0, tiltY = 0, wantX = 0, wantY = 0;
let grip = null, dragged = false, hovering = false, running = false, last = 0, touchedAt = 0;
let docks = [], base = { w: 340, h: 490 }, fly = 0, wantFly = 0, front = -1, at = "";

// --- Стани квитка: що надруковано на боці й корінці.
function eventSheet(card, mark = "") {
  const image = httpsOrNull(card.image_url), [time, day] = stubParts(card), genre = CATEGORIES[card.category] || "Подія";
  const seats = seatsOf(card);
  return { key: `${card.id}|${mark}`, cat: card.category, id: card.id,
    face: `<a class="t3-face" href="afisha.html?e=${encodeURIComponent(card.id)}" draggable="false">
      <div class="shot">${icon(card.category, "glyph")}${image ? photo(card, false) : ""}${mark ? `<span class="stamp photo">${esc(mark)}</span>` : ""}</div>
      <div class="txt"><b>${esc(cardTitle(card))}</b><span>${esc(card.place_name || card.address || card.city || "")}</span><span class="why">${esc(sourceNote(card))}</span></div></a>`,
    label: `${genre}, ${overline(card, new Date(), true)}${seats ? `, учасників ${seats}` : ""}`,
    stub: `<div class="l"><span class="kind">${esc(genre)}</span><b class="t">${esc(time)}</b></div>
      <div class="r"><small>${esc(day)}</small>${seats ? `<span class="seats">${icon("people")}${esc(seats)}</span>` : ""}</div>` };
}
function mineSheet() {
  const title = mine.title.trim(), genre = CATEGORIES[mine.genre];
  return { key: `mine|${mine.genre}|${mine.capacity}|${state.city}|${title}`, cat: mine.genre, lock: "create",
    face: `<div class="t3-face mine"><div class="shot"><span class="stamp">Від людей</span><b${title ? "" : ' class="ghost"'}>${esc(title || "Що збираєте?")}</b></div>
      <div class="txt"><span class="genre"><i class="dot cat"></i>${esc(genre)}</span><span>${esc(state.city)} · точка на мапі</span></div></div>`,
    label: `${genre}, сьогодні о 19:00, учасників 1/${mine.capacity}`,
    stub: `<div class="l"><span class="kind">${esc(genre)}</span><b class="t">19:00</b></div>
      <div class="r"><small>Сьогодні</small><span class="seats">${icon("people")}1/${mine.capacity}</span></div>` };
}
// Організаторам: подія клубу, яку ведуть у кабінеті, — вже надрукована (без пунктиру) і зі списком; тап — «Організаторам».
const orgSheet = () => ({ key: "org", cat: "games",
  face: `<a class="t3-face mine org" href="organizatoram" draggable="false"><div class="shot"><span class="stamp">Від людей</span><b>Настолки щочетверга</b></div>
    <div class="txt"><span class="genre"><i class="dot cat"></i>Ігри</span><span>Київ · Поділ</span><span class="why">Запис за посиланням, без застосунку</span></div></a>`,
  // Зразок, а не справжня подія: без вигаданого «12/20» (власник, 12.11).
  label: "Ігри, щочетверга о 19:00",
  stub: `<div class="l"><span class="kind">Щочетверга</span><b class="t">19:00</b></div>
    <div class="r"><small>Четвер</small></div>` });
const rulesSheet = () => ({ key: "rules", ink: true,
  face: `<div class="t3-face rules"><div class="shot">${icon("shield", "glyph")}</div>
    <div class="txt"><b>Правила тримає база</b><span>Вікові межі, підтвердження, черга</span><span class="why">Імена бачать лише свої</span></div></div>`,
  label: "Профіль з 18 років", stub: `<div class="l"><span class="kind">Профіль</span><b class="t">18+</b></div><div class="r"><small>Лише своїм</small></div>` });
const passSheet = () => ({ key: "pass", ink: true, lock: "app",
  face: `<div class="t3-face pass3"><div class="shot">${qr("")}<img class="appicon" src="icon.png" alt=""></div>
    <div class="txt"><b>Поряд у телефоні</b><span>${PLAY_URL ? "iPhone і Android" : "iPhone з iOS 17"}</span><span class="why">poriad.app/app</span></div></div>`,
  label: "Перепустка в застосунок", stub: `<div class="l"><span class="kind">Застосунок</span><b class="t">Поряд</b></div>` });
function sheetFor(i, k) {
  const name = docks[i].name, card = stops.length ? stops[mod(k - i, stops.length)] : null;
  if (name === "people") return mineSheet();
  if (name === "org") return orgSheet();
  if (name === "company") return plateCard() ? eventSheet(plateCard(), stampText) : card && eventSheet(card, stampText);
  if (name === "safety") return rulesSheet();
  if (name === "download") return passSheet();
  return card && eventSheet(card);
}
function print(side, sheet) {
  if (!sheet || keys[side] === sheet.key) return;
  keys[side] = sheet.key;
  for (const el of [faces[side], stubs[side]]) {
    el.className = `t3-side ${side ? "b" : "a"}${sheet.cat ? ` cat-${sheet.cat}` : ""}${sheet.ink ? " ink" : ""}`;
    if (sheet.id) el.dataset.id = sheet.id; else delete el.dataset.id;
    if (sheet.lock) el.dataset.lock = sheet.lock; else delete el.dataset.lock;
  }
  faces[side].innerHTML = sheet.face;
  stubs[side].setAttribute("role", "img");
  stubs[side].setAttribute("aria-label", sheet.label);
  stubs[side].innerHTML = sheet.stub;
}

// --- Причали: центр і ширина кожного в координатах сторінки та прокрутка, на якій він стоїть посеред екрана.
function measure() {
  const max = document.documentElement.scrollHeight - innerHeight;
  base = { w: t3.offsetWidth || base.w, h: t3.offsetHeight || base.h };
  docks = [...document.querySelectorAll("[data-dock]")].filter((el) => el.offsetParent).map((el) => {
    let x = 0, y = 0;
    for (let node = el; node; node = node.offsetParent) { x += node.offsetLeft; y += node.offsetTop; }
    return { name: el.dataset.dock, x: x + el.offsetWidth / 2, y: y + el.offsetHeight / 2, w: el.offsetWidth };
  });
  docks.forEach((dock, i) => {
    dock.at = Math.min(max, Math.max(0, dock.y - innerHeight / 2));
    if (i) dock.at = Math.max(dock.at, docks[i - 1].at + 1);
  });
  wantFly = flightAt(scrollY);
}
// Між причалами квиток спершу тримається свого, летить посередині шляху й сідає заздалегідь.
function flightAt(y) {
  for (let i = 0; i < docks.length - 1; i += 1) {
    const from = docks[i].at, gap = docks[i + 1].at - from;
    if (y >= docks[i + 1].at) continue;
    const pad = Math.min(gap * .25, innerHeight * .28);
    return i + smooth((y - from - pad) / Math.max(1, gap - 2 * pad));
  }
  return Math.max(0, docks.length - 1);
}
function paint() {
  if (!docks.length || t3.hidden) return;
  const end = docks.length - 1, here = Math.max(0, Math.min(end, Math.round(fly)));
  const next = fly > here + .02 ? Math.min(end, here + 1) : fly < here - .02 ? Math.max(0, here - 1) : here;
  const turn = theta + tiltY + fly * 180, rad = turn * Math.PI / 180, c = Math.cos(rad), s = Math.sin(rad), sign = s < 0 ? -1 : 1;
  const spin = theta / 180 + fly, k = [2 * Math.round(spin / 2), 2 * Math.round((spin - 1) / 2) + 1], vis = c >= 0 ? 0 : 1;
  const sheet = sheetFor(here, k[vis]);
  print(vis, sheet);
  print(1 - vis, sheetFor(next, k[1 - vis]));
  // Бік, що стоїть спиною, недосяжний і для клавіатури та читача екрана.
  if (vis !== front) { front = vis; faces.forEach((el, side) => { el.inert = side !== vis; }); }
  if (docks[here].name !== at) { at = docks[here].name; t3.dataset.at = at; }
  const hingeClass = `t3-panel stub${sheet?.cat ? ` cat-${sheet.cat}` : ""}${sheet?.ink ? " ink" : ""}`;
  if (hingeEl.className !== hingeClass) hingeEl.className = hingeClass;
  // Поза в польоті: від причалу до причалу по прямій, з набором «висоти» (масштаб) і креном у бік руху.
  const i = Math.max(0, Math.min(end - 1, Math.floor(fly))), from = docks[i], to = docks[Math.min(end, i + 1)];
  const f = clamp01(fly - i), arc = Math.sin(Math.PI * f), mix = (a, b) => a + (b - a) * f;
  const pose = (name, value) => t3.style.setProperty(name, value);
  // cruise — наскільки квиток зараз значок: 0 біля причалів, 1 на середніх двох третинах шляху. Кут рахуємо від видимої
  // частини вікна (clientWidth — без смуги прокрутки), тож у польоті значок тримається кута й під час прокрутки.
  const cruise = smooth(clamp01(arc * 2));
  const docked = mix(from.w, to.w) / base.w, scale = docked + (Math.min(docked, TOKEN / base.w) - docked) * cruise;
  const line = mix(from.x, to.x), x = line + (document.documentElement.clientWidth - 12 - base.w * scale / 2 - line) * cruise;
  const path = mix(from.y, to.y), y = path + (scrollY + innerHeight - 12 - base.h * scale / 2 - path) * cruise;
  pose("--x", `${(x - base.w / 2).toFixed(1)}px`);
  pose("--y", `${(y - base.h / 2).toFixed(1)}px`);
  // Значок у куті може лягти на край колонки — тоді натискання проходять крізь нього до кнопок під ним.
  t3.classList.toggle("cruising", cruise > .5);
  pose("--s", scale.toFixed(4));
  pose("--bank", `${(arc * (to.x >= from.x ? 7 : -7)).toFixed(2)}deg`);
  pose("--sx", Math.max(.14, Math.abs(c)).toFixed(3));
  t3.classList.add("placed");
  const set = (name, value) => body3.style.setProperty(name, value);
  set("--ry", `${turn.toFixed(2)}deg`);
  set("--tx", `${(tiltX + arc * 10).toFixed(2)}deg`);
  set("--sa", ((1 - Math.max(0, c)) * .38).toFixed(3));
  set("--sb", ((1 - Math.max(0, -c)) * .38).toFixed(3));
  set("--ga", `${(sign * (60 - Math.abs(s) * 85)).toFixed(1)}%`);
  set("--gb", `${(-sign * (60 - Math.abs(s) * 85)).toFixed(1)}%`);
  hingeEl.style.setProperty("--hinge", `${hinge.toFixed(2)}deg`);
}
function step(now) {
  const dt = Math.min(.034, (now - last) / 1000 || .016);
  last = now;
  const held = grip && dragged, was = fly;
  if (held) omega *= .9;
  else { omega += ((goal - theta) * 90 - omega * 13) * dt; theta += omega * dt; }
  fly += (wantFly - fly) * .2;
  tiltX += (wantX - tiltX) * .12; tiltY += (wantY - tiltY) * .12;
  // Корінець відстає від оберту — і від руки, і від польоту.
  hinge += (Math.max(-34, Math.min(34, -(omega + (fly - was) / dt * 180) * .05)) - hinge) * .18;
  const still = !held && Math.abs(goal - theta) < .05 && Math.abs(omega) < .5 && Math.abs(hinge) < .1 && Math.abs(wantX - tiltX) < .05 && Math.abs(wantY - tiltY) < .05 && Math.abs(wantFly - fly) < .001;
  if (still) { theta = goal; fly = wantFly; omega = hinge = 0; running = false; }
  paint();
  if (!still) requestAnimationFrame(step);
}
function kick() {
  if (calm && !(grip && dragged)) { theta = goal; fly = Math.round(wantFly); omega = hinge = 0; paint(); return; }
  if (!running) { running = true; last = performance.now(); requestAnimationFrame(step); }
}
const shownStop = () => stops.length ? mod(Math.round(goal / 180), stops.length) : -1;
function markStop() {
  const i = shownStop();
  stopsEl.querySelectorAll("button").forEach((b, k) => b.setAttribute("aria-pressed", k === i));
}
const turnTo = (k) => { goal = 180 * k; markStop(); kick(); };

t3.addEventListener("pointerdown", (event) => {
  if (event.button) return;
  grip = { id: event.pointerId, x: event.clientX, theta, at: performance.now() };
  dragged = false;
  touchedAt = Date.now();
});
t3.addEventListener("pointermove", (event) => {
  if (!grip || event.pointerId !== grip.id) {
    if (calm || event.pointerType !== "mouse") return;
    const box = t3.getBoundingClientRect();
    wantY = Math.max(-1, Math.min(1, (event.clientX - box.left) / box.width * 2 - 1)) * 14;
    wantX = -Math.max(-1, Math.min(1, (event.clientY - box.top) / box.height * 2 - 1)) * 9;
    return kick();
  }
  const dx = event.clientX - grip.x;
  if (!dragged && Math.abs(dx) < 6) return;
  if (!dragged) { dragged = true; try { t3.setPointerCapture(event.pointerId); } catch { /* вказівник уже відпущено */ } t3.classList.add("grab"); wantX = wantY = 0; }
  const now = performance.now(), next = grip.theta + dx * .55;
  omega = omega * .6 + (next - theta) / Math.max(.008, (now - grip.at) / 1000) * .4;
  theta = next; grip.at = now;
  kick();
});
function letGo() {
  if (!grip) return;
  grip = null;
  t3.classList.remove("grab");
  if (dragged) turnTo(Math.round((theta + omega * .22) / 180));
}
t3.addEventListener("pointerup", letGo);
t3.addEventListener("pointercancel", letGo);
t3.addEventListener("pointerenter", (event) => { hovering = event.pointerType === "mouse"; });
t3.addEventListener("pointerleave", () => { hovering = false; wantX = wantY = 0; kick(); });
// Після потягу клік нічого не відкриває: квиток крутили, а не натискали.
t3.addEventListener("click", (event) => { if (dragged) { dragged = false; event.preventDefault(); event.stopPropagation(); } }, true);
// Квиток події відкриває подію (bindCards); свій квиток і перепустка ведуть у застосунок.
t3.addEventListener("click", (event) => {
  const lock = event.target.closest("[data-lock]")?.dataset.lock;
  if (lock) openInstall(lock);
});
t3.addEventListener("dragstart", (event) => event.preventDefault());
stopsEl.addEventListener("click", (event) => {
  const button = event.target.closest("button");
  if (!button) return;
  const i = [...stopsEl.children].indexOf(button), k = Math.round(goal / 180);
  touchedAt = Date.now();
  turnTo(k + mod(i - k, stops.length));
});
addEventListener("scroll", () => { wantFly = flightAt(scrollY); kick(); }, { passive: true });
addEventListener("resize", () => { measure(); kick(); });
// Афіша приходить порціями й зсуває секції — причали перемірюємо щоразу, коли сторінка змінює висоту.
new ResizeObserver(() => { measure(); kick(); }).observe($("main"));
// На першому причалі квиток сам перегортається раз на кілька секунд, поки його не чіпають. Фокус клавіатури на квитку
// чи зупинках — пауза (перемальоване лице скидало фокус на body), а перший дотик зупиняє гортання зовсім (WCAG 2.2.2).
const focusedIn = (...els) => els.some((el) => el?.matches(":focus-within"));
setInterval(() => {
  if (calm || stops.length < 2 || at !== "hero" || running || document.hidden || grip || hovering || touchedAt || focusedIn(t3, stopsEl)) return;
  turnTo(Math.round(goal / 180) + 1);
}, 5200);

function heroNote(text, retry = null) {
  stops = [];
  t3.hidden = true; $("[data-hero-hint]").hidden = true;
  stopsEl.innerHTML = "";
  const note = $("[data-hero-note]");
  note.hidden = false;
  note.innerHTML = `<p>${esc(text)}</p>${retry ? `<button class="btn small" type="button" data-retry>Спробувати ще</button>` : ""}`;
  if (retry) note.querySelector("[data-retry]").onclick = retry;
}
async function loadHero(folded, city) {
  const { label, events } = tonightPick(folded);
  $("[data-tonight-title]").textContent = label;
  $("[data-tonight-all]").textContent = `Афіша ${city.of}`;
  if (!events.length) return heroNote("Цього тижня в афіші тихо. Зате свою зустріч можна зібрати будь-коли.");
  stops = await ensureCards(events.map((e) => e.id));
  t3.hidden = false; $("[data-hero-note]").hidden = true; $("[data-hero-hint]").hidden = stops.length < 2;
  stopsEl.innerHTML = stops.map((card) => `<button type="button" aria-pressed="false" aria-label="${esc(`${displayTitle(card.title)}, ${overline(card, new Date(), true)}`)}">${stubTile(card)}</button>`).join("");
  // Нове місто — нові події на обох боках; квиток виходить ребром і розвертається лицем.
  keys = [null, null];
  theta = -90; omega = 0;
  measure();
  fly = wantFly;
  turnTo(0);
}
const FAILED = "Афіша зараз не відповідає";
const heroFailed = () => heroNote(`${FAILED}.`, load);

// ---- «Шукаю компанію»: вечірні події найближчого тижня з фото, у вибраному місті. На причалі секції мандрівник несе
// одну з них зі штампом; черга під ним — ті самі події маленькими фото. Подія повільно змінюється, поки квиток тут.
let plate = [], shown = 0, plateTimer = null;
const plateCard = () => plate[shown] ?? null;
function showPlate(i) {
  shown = i;
  document.querySelectorAll("[data-plate-queue] button").forEach((b, k) => b.setAttribute("aria-pressed", k === i));
  $("[data-plate-link]").href = `afisha.html?e=${encodeURIComponent(plate[i].id)}`;
  paint();
}
$("[data-plate-link]").addEventListener("click", (event) => {
  if (!plateCard()) return;
  event.preventDefault();
  openEvent(plateCard().id, entries.get(plateCard().id));
});
$("[data-plate-queue]").addEventListener("click", (event) => {
  const button = event.target.closest("button");
  if (button) { touchedAt = Date.now(); showPlate([...button.parentNode.children].indexOf(button)); }
});
// Нема подій із фото чи афіша не відповіла — секція лишається текстом, причал зникає, і квиток його оминає.
function plateOff() {
  clearInterval(plateTimer);
  plate = [];
  $(".plate-row").classList.add("bare");
  $("[data-plate-queue]").innerHTML = "";
  fillTiles([]);
  measure(); kick();
}
async function loadPlate(folded, city) {
  const pool = folded.filter((e) => e.origin === "import" && ahead(e.startsAt) && withinDays(e.startsAt, 7) && grown(e));
  const best = [...pool].sort((a, b) => evening(b) - evening(a)).slice(0, 40);
  const next = (await ensureCards(best.map((e) => e.id))).filter((c) => httpsOrNull(c.image_url)).slice(0, 6);
  if (!next.length) return plateOff();
  clearInterval(plateTimer);
  $(".plate-row").classList.remove("bare");
  plate = next.slice(0, 4);
  $("[data-plate-queue]").innerHTML = plate.map((c, k) => `<button type="button" class="cat-${esc(c.category)}" aria-pressed="${k === 0}" aria-label="${esc(displayTitle(c.title))}">${photo(c)}</button>`).join("");
  showPlate(0);
  fillTiles([...next.slice(4), ...plate.slice(-2)].slice(0, 2));
  measure(); kick();
  if (calm || plate.length < 2) return;
  plateTimer = setInterval(() => {
    if (at === "company" && !running && !grip && !hovering && !document.hidden && !touchedAt && !focusedIn(t3, $(".plate-row"))) showPlate((shown + 1) % plate.length);
  }, 5600);
}

// Плитки фіналу — ще дві справжні афіші міста. Нема фото — лишається одна чорнильна плитка.
function fillTiles(cards) {
  const sides = document.querySelectorAll("[data-tile-photo]");
  sides.forEach((side, k) => { side.innerHTML = cards[k] ? photo(cards[k]) : ""; if (cards[k]) setCat(side, cards[k].category); });
  $(".tiles").classList.toggle("solo", cards.length < 2);
}

// «Уже збирають»: справжні зустрічі від людей у місті, якщо вони є. Нема — секцію веде порожній квиток вище.
async function loadPeople(folded, city) {
  // Ті, куди вже записались, — першими; місця на корінці друкуються лише з першого учасника (seatsOf).
  const people = folded.filter((e) => e.origin === "community" && ahead(e.startsAt)).sort((a, b) => (b.count > 0) - (a.count > 0)).slice(0, 8);
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
  if (!top.length) { list.innerHTML = `<div class="empty"><b>Цього тижня подій поки нема</b><span>Подивіться афішу й мапу.</span></div>`; return; }
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

// ---- Місто: з минулого візиту або Київ. Вкладки міняють квитки героїні, пластину, афішу й «уже збирають».
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
    heroFailed();
    plateOff();
    $("[data-genre-list]").innerHTML = `<div class="empty"><b>Афіша не завантажилась</b><span>Перевірте з’єднання й спробуйте ще раз.</span>
      <button class="btn secondary" type="button" data-retry>Спробувати ще</button></div>`;
    $("[data-genre-list] [data-retry]").onclick = load;
    return;
  }
  if (city.name !== state.city) return;
  await Promise.all([
    loadHero(folded, city).catch(heroFailed),
    loadPlate(folded, city).catch(plateOff),
    loadBoard(folded, city),
    loadPeople(folded, city),
  ]);
}

load();
