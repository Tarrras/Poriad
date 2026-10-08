// Веб-афіша — режим перегляду: місто, дати, категорії, пошук, сітка з довантаженням і мапа.
// Стан — у адресі (?city=&when=&cat=&q=&view=&e=), тож будь-який вигляд можна надіслати посиланням.
import { discover, fold, soonFirst, inWhen, CITIES, cityOf, CATEGORIES, CATEGORY_COLORS, WHEN, plural, EVENTS, httpsOrNull, mapStyle, displayTitle, overline, esc } from "./poriad.js?v=3";
import { ensureCards, remember, poster, heroCard, skeletons, bindCards, openEvent, reveal, navGlass, bindLocks, savedCity, icon, art } from "./ui.js?v=3";

navGlass();
bindLocks();

const $ = (selector) => document.querySelector(selector);
const params = new URLSearchParams(location.search);
const PAGE = 24;
const state = {
  city: [params.get("city"), savedCity.get()].find((c) => CITIES.some((x) => x.name === c)) ?? "Київ",
  when: params.get("when") in WHEN ? params.get("when") : null,
  cat: params.get("cat") in CATEGORIES ? params.get("cat") : null,
  q: (params.get("q") || "").slice(0, 120),
  view: params.get("view") === "map" ? "map" : "list",
  index: [], list: [], byId: new Map(), shown: PAGE,
};
let renderToken = 0, firstRender = true;

bindCards($("main"), (id) => state.byId.get(id));
$("[data-city]").innerHTML = CITIES.map((c) => `<option value="${c.name}">${c.name}</option>`).join("");
$("[data-city]").value = state.city;
$("[data-q]").value = state.q;

// ---- Керування
$("[data-city]").addEventListener("change", (event) => { state.city = event.target.value; savedCity.set(state.city); load(); });
let typing;
$("[data-q]").addEventListener("input", (event) => {
  clearTimeout(typing);
  typing = setTimeout(() => { state.q = event.target.value.trim().slice(0, 120); load(); }, 350);
});
$("[data-filters]").addEventListener("click", (event) => {
  const chip = event.target.closest("[data-f]");
  if (!chip) return;
  const [kind, value] = chip.dataset.f.split(":");
  state[kind] = state[kind] === value ? null : value;
  state.shown = PAGE;
  render();
});
$("[data-view]").addEventListener("click", (event) => {
  const view = event.target.closest("[data-v]")?.dataset.v;
  if (view && view !== state.view) { state.view = view; render(); }
});
$("[data-more]").addEventListener("click", () => { state.shown += PAGE; renderGrid(true); });
// Довантаження, щойно кнопка «Показати ще» з’являється на екрані.
new IntersectionObserver((entries) => {
  if (entries[0].isIntersecting && !$("[data-more]").hidden && !$("[data-more]").disabled) $("[data-more]").click();
}, { rootMargin: "600px 0px" }).observe($("[data-more]"));

const toolbar = $("[data-toolbar]");
addEventListener("scroll", () => toolbar.classList.toggle("stuck", toolbar.getBoundingClientRect().top <= 80), { passive: true });

// Плашка застосунку: після першої прокрутки; хрестик ховає до кінця сеансу.
const appBar = $("[data-app-bar]");
const dismissed = () => { try { return sessionStorage.getItem("poriad.appbar") === "0"; } catch { return false; } };
addEventListener("scroll", () => { if (scrollY > 500 && !dismissed()) appBar.classList.remove("gone"); }, { passive: true });
$("[data-dismiss]").addEventListener("click", () => { appBar.classList.add("gone"); try { sessionStorage.setItem("poriad.appbar", "0"); } catch { /* приватне вікно */ } });

// ---- Дані
const indexCache = new Map();
async function load() {
  const city = cityOf(state.city);
  $("[data-title]").textContent = `Афіша ${city.of}`;
  document.title = `Афіша ${city.of} — Поряд`;
  $("[data-grid]").innerHTML = skeletons(8);
  $("[data-count]").textContent = "Завантажуємо…";
  const key = `${city.name}|${state.q}`;
  const token = ++renderToken;
  try {
    if (!indexCache.has(key)) {
      const { index, cards: first } = await discover(city.name, { text: state.q, cards: 24 });
      remember(first);
      indexCache.set(key, index);
    }
    if (token !== renderToken) return;
    state.index = indexCache.get(key);
    state.shown = PAGE;
    await render();
  } catch {
    if (token !== renderToken) return;
    $("[data-count]").textContent = "Немає з’єднання";
    $("[data-grid]").innerHTML = `<div class="empty"><b>Афіша не завантажилась</b><span>Перевірте з’єднання й спробуйте ще раз.</span>
      <button class="btn secondary" type="button" data-retry>Спробувати ще</button></div>`;
    $("[data-retry]").onclick = load;
  }
}

async function render() {
  syncUrl();
  const { index, when, cat } = state;
  const byDate = index.filter((e) => inWhen(e, when));
  const byCat = index.filter((e) => !cat || e.category === cat);
  state.list = soonFirst(fold(byDate.filter((e) => !cat || e.category === cat)));
  state.byId = new Map(state.list.map((e) => [e.id, e]));

  const total = fold(index).length;
  $("[data-count]").textContent = state.q ? `Знайдено: ${plural(total, EVENTS)}` : `${plural(total, EVENTS)} з квиткових сервісів і від людей`;

  // Чипи: кількість дат — у вибраній категорії, кількість категорій — у вибраних датах.
  const dateCounts = Object.fromEntries(Object.keys(WHEN).map((w) => [w, fold(byCat.filter((e) => inWhen(e, w))).length]));
  const catCounts = {};
  for (const e of fold(byDate)) catCounts[e.category] = (catCounts[e.category] ?? 0) + 1;
  const chip = (f, label, count, extra = "") =>
    `<button class="chip ${extra}" type="button" data-f="${f}" aria-pressed="${state[f.split(":")[0]] === f.split(":")[1]}">${label}${count != null ? ` <span class="count">${count}</span>` : ""}</button>`;
  $("[data-filters]").innerHTML = Object.entries(WHEN).map(([w, label]) => chip(`when:${w}`, label, dateCounts[w])).join("") + `<span class="sep"></span>` +
    Object.entries(CATEGORIES).filter(([k]) => catCounts[k] || k === cat)
      .sort(([a], [b]) => (catCounts[b] ?? 0) - (catCounts[a] ?? 0))
      .map(([k, label]) => chip(`cat:${k}`, `<span class="dot"></span>${label}`, catCounts[k] ?? 0, `cat-${k}`)).join("");

  // Посилання на категорію: її чип може бути за краєм ряду — показуємо його один раз, при відкритті.
  const active = firstRender && $('[data-f^="cat:"][aria-pressed="true"]');
  if (active) $("[data-filters]").scrollLeft = active.offsetLeft - $("[data-filters]").offsetLeft - 16;
  firstRender = false;
  document.querySelectorAll("[data-v]").forEach((b) => b.setAttribute("aria-pressed", b.dataset.v === state.view));
  $("[data-map-wrap]").hidden = state.view !== "map";
  $("[data-list-wrap]").hidden = state.view === "map";
  const title = [when && WHEN[when], cat && CATEGORIES[cat]].filter(Boolean).join(" · ");
  $("[data-list-title]").textContent = state.q ? `«${state.q}»` : title || "Усі події";
  $("[data-list-count]").textContent = plural(state.list.length, EVENTS);

  if (state.view === "map") { $("[data-rail-wrap]").hidden = true; return renderMap(); }
  await Promise.all([renderRail(), renderGrid()]);
}

/** «Не пропустіть»: найближчі з фото — лише на чистій афіші, без фільтрів і пошуку. */
async function renderRail() {
  const wrap = $("[data-rail-wrap]");
  if (state.when || state.cat || state.q) { wrap.hidden = true; return; }
  const soon = state.list.filter((e) => (inWhen(e, "today") || inWhen(e, "tomorrow")) && new Date(e.startsAt) > Date.now()).slice(0, 30);
  const got = (await ensureCards(soon.map((e) => e.id))).filter((c) => httpsOrNull(c.image_url)).slice(0, 10);
  wrap.hidden = got.length < 3;
  $("[data-rail]").innerHTML = got.map(heroCard).join("");
}

/** Сітка: заново після зміни фільтрів, або `append` — наступна порція до вже показаних. */
async function renderGrid(append = false) {
  const token = renderToken;
  const grid = $("[data-grid]"), more = $("[data-more]");
  if (!state.list.length) {
    grid.innerHTML = `<div class="empty"><b>Нічого не знайшли</b><span>${state.q ? "Спробуйте інше слово або приберіть фільтри." : "На ці дні в цій категорії подій поки нема."}</span>
      <button class="btn secondary" type="button" data-reset>Скинути фільтри</button></div>`;
    $("[data-reset]").onclick = () => { Object.assign(state, { when: null, cat: null, shown: PAGE }); if (state.q) { state.q = ""; $("[data-q]").value = ""; load(); } else render(); };
    more.hidden = true;
    return;
  }
  const from = append ? state.shown - PAGE : 0;
  const slice = state.list.slice(from, state.shown);
  more.disabled = true;
  if (!append) grid.innerHTML = skeletons(Math.min(8, slice.length));
  try {
    const got = await ensureCards(slice.map((e) => e.id));
    if (token !== renderToken) return;
    const html = got.map((card) => poster(card, state.byId.get(card.id))).join("");
    if (append) grid.insertAdjacentHTML("beforeend", html);
    else grid.innerHTML = html;
    grid.querySelectorAll(".poster:not(.reveal)").forEach((el, i) => { el.classList.add("reveal"); el.style.setProperty("--d", `${(i % 4) * 0.05}s`); });
    reveal(grid);
  } finally {
    more.disabled = false;
  }
  more.hidden = state.shown >= state.list.length;
}

function syncUrl() {
  const url = new URL(location.href);
  const set = (k, v) => (v ? url.searchParams.set(k, v) : url.searchParams.delete(k));
  set("city", state.city === "Київ" ? null : state.city);
  set("when", state.when); set("cat", state.cat); set("q", state.q); set("view", state.view === "map" ? "map" : null);
  history.replaceState(history.state, "", url);
}

// ---- Мапа: MapLibre з CDN, лише коли людина її відкрила. Стиль — порт стилю застосунку, тайли OpenFreeMap.
let mapReady;
function loadMap() {
  return mapReady ??= new Promise((resolve, reject) => {
    const css = Object.assign(document.createElement("link"), { rel: "stylesheet", href: "https://unpkg.com/maplibre-gl@4.7.1/dist/maplibre-gl.css" });
    const js = Object.assign(document.createElement("script"), { src: "https://unpkg.com/maplibre-gl@4.7.1/dist/maplibre-gl.js" });
    js.onload = () => {
      const city = cityOf(state.city);
      const map = new maplibregl.Map({ container: $("[data-map]"), style: mapStyle(), center: [city.lng, city.lat], zoom: 11.3, attributionControl: { compact: true }, dragRotate: false });
      map.addControl(new maplibregl.NavigationControl({ showCompass: false }), "bottom-right");
      map.on("load", () => { setupLayers(map); resolve(map); });
      map.on("error", (e) => console.warn("map", e.error?.message));
    };
    js.onerror = () => { mapReady = null; reject(new Error("maplibre")); };
    document.head.append(css, js);
  });
}

function setupLayers(map) {
  map.addSource("events", { type: "geojson", data: geojson(), cluster: true, clusterRadius: 40, clusterMaxZoom: 15 });
  map.addLayer({ id: "halo", type: "circle", source: "events", filter: ["has", "point_count"],
    paint: { "circle-color": "#1D1D1F", "circle-opacity": 0.14, "circle-radius": ["interpolate", ["linear"], ["get", "point_count"], 2, 26, 60, 40] } });
  map.addLayer({ id: "clusters", type: "circle", source: "events", filter: ["has", "point_count"],
    paint: { "circle-color": "#1D1D1F", "circle-stroke-width": 3, "circle-stroke-color": "#FFFFFF", "circle-radius": ["interpolate", ["linear"], ["get", "point_count"], 2, 18, 60, 30] } });
  map.addLayer({ id: "cluster-count", type: "symbol", source: "events", filter: ["has", "point_count"],
    layout: { "text-field": ["get", "point_count_abbreviated"], "text-font": ["Noto Sans Bold"], "text-size": 13 }, paint: { "text-color": "#FFFFFF" } });
  map.addLayer({ id: "points", type: "circle", source: "events", filter: ["!", ["has", "point_count"]],
    paint: { "circle-color": ["match", ["get", "category"], ...Object.entries(CATEGORY_COLORS).flat(), "#1D1D1F"],
      "circle-radius": ["interpolate", ["linear"], ["zoom"], 11, 7, 16, 10], "circle-stroke-width": 3, "circle-stroke-color": "#FFFFFF" } });

  map.on("click", "clusters", async (event) => {
    const feature = event.features[0], source = map.getSource("events"), id = feature.properties.cluster_id;
    const zoom = await source.getClusterExpansionZoom(id);
    // Усі події в одній точці (заклад з афішею) — одразу список, а не зум до даху будинку.
    const leaves = zoom > 15 ? await source.getClusterLeaves(id, 100, 0) : [];
    if (leaves.length && new Set(leaves.map((f) => f.geometry.coordinates.join())).size === 1) {
      map.easeTo({ center: feature.geometry.coordinates, zoom: Math.max(map.getZoom(), 14) });
      showStack(leaves.map((f) => f.properties.id));
    } else map.easeTo({ center: feature.geometry.coordinates, zoom: zoom + 0.3 });
  });
  map.on("click", "points", (event) => {
    const box = [[event.point.x - 6, event.point.y - 6], [event.point.x + 6, event.point.y + 6]];
    const ids = [...new Set(map.queryRenderedFeatures(box, { layers: ["points"] }).map((f) => f.properties.id))];
    if (ids.length === 1) openEvent(ids[0], state.byId.get(ids[0]));
    else showStack(ids);
  });
  for (const layer of ["clusters", "points"]) {
    map.on("mouseenter", layer, () => { map.getCanvas().style.cursor = "pointer"; });
    map.on("mouseleave", layer, () => { map.getCanvas().style.cursor = ""; });
  }
}

const geojson = () => ({ type: "FeatureCollection", features: state.list.map((e) => ({
  type: "Feature", geometry: { type: "Point", coordinates: [e.lng, e.lat] }, properties: { id: e.id, category: e.category } })) });

let mapCity = null;
async function renderMap() {
  try {
    const map = await loadMap();
    map.resize();
    map.getSource("events").setData(geojson());
    if (mapCity !== state.city) {
      const city = cityOf(state.city);
      if (mapCity) map.flyTo({ center: [city.lng, city.lat], zoom: 11.3, duration: 1200 });
      mapCity = state.city;
    }
  } catch {
    $("[data-map]").innerHTML = `<div class="empty" style="height:100%;justify-content:center"><b>Мапа не завантажилась</b><span>Список подій працює й без неї.</span></div>`;
  }
}

/** Кілька подій в одній точці (заклад з афішею) — список поруч із мапою. */
async function showStack(ids) {
  $(".stack")?.remove();
  const panel = document.createElement("div");
  panel.className = "stack";
  panel.innerHTML = `<header><span>Тут подій: ${ids.length}</span><button type="button" aria-label="Закрити">${icon("close")}</button></header>`;
  $("[data-map]").append(panel);
  panel.querySelector("button").onclick = () => panel.remove();
  const got = (await ensureCards(ids.slice(0, 100))).sort((a, b) => Date.parse(a.starts_at) - Date.parse(b.starts_at));
  panel.insertAdjacentHTML("beforeend", got.map((card) => `<div class="mini" data-id="${esc(card.id)}">${art(card)}
    <div><small>${esc(overline(card))}</small><b>${esc(displayTitle(card.title))}</b><span>${esc(card.place_name || card.address || "")}</span></div></div>`).join(""));
}

// Подія за посиланням `?e=` відкривається поверх афіші.
const deepLink = params.get("e");
load().then(() => { if (deepLink) openEvent(deepLink, state.byId.get(deepLink)); });
reveal();
