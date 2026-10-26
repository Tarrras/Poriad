// Пости для Telegram-каналів міст: node tools/telegram_post.mjs today|weekend [--dry-run] [--city Київ]
// today — події міста на сьогодні, що ще не почались (щодня о 12:00); weekend — субота й неділя (щоп'ятниці).
// Афіша та сама, що на сайті й у гостя в застосунку (site/js/poriad.js, публічні RPC з publishable-ключем): лише
// опубліковане, не злите (злиття — import_status withdrawn) і не сховане, сеанси прокату згорнуті.
// --dry-run друкує пости всіх міст. Без нього — надсилає через Bot API: TELEGRAM_BOT_TOKEN і
// TELEGRAM_CHANNEL_<KYIV|LVIV|ODESA|DNIPRO|KHARKIV> з env (у CI — secrets); місто без каналу пропускається.
// Канали, бот і розклад — tools/telegram.md.
import { pathToFileURL } from "node:url";
import { discover, cardsByIds, inWhen, fold, displayTitle, timeOf, price, esc, CITIES, cityOf, eventUrl } from "../site/js/poriad.js";

/** Латиницею: суфікс змінної з id каналу й мітка ?from= для /app (site/app.html приймає лише ^[a-z]{1,12}$). */
export const CHANNELS = { Київ: ["KYIV", "tgk"], Львів: ["LVIV", "tgl"], Одеса: ["ODESA", "tgo"], Дніпро: ["DNIPRO", "tgd"], Харків: ["KHARKIV", "tgh"] };
/** Скільки подій у пості, [мінімум, максимум]: понад мінімум — лише якщо є різні категорії, а не четверта вистава. */
const LIMIT = { today: [5, 7], weekend: [8, 10] };
/** Емодзі категорії замість сірого підпису: око чіпляється за рядок. */
const EMOJI = { music: "🎵", art: "🎭", comedy: "🎤", kids: "🧸", social: "🤝", games: "🎲", sport: "🏃", food: "🍷", outdoors: "🌿", tours: "🧭", conference: "💡" };
/** Що є в пості, для вступу: «вистави, концерти і стендап». */
const WHAT = { music: "концерти", art: "мистецтво", comedy: "стендап", kids: "щось для дітей", social: "зустрічі", games: "ігри", sport: "спорт", food: "дегустації", outdoors: "прогулянки", tours: "екскурсії", conference: "лекції" };
/**
 * «Безкоштовно» — лише від людей і з джерел, де нуль-заглушка вже не стає is_free (88e1047: Concert.ua без валюти,
 * Karabas OutOfStock). Решта is_free — без ціни: краще не сказати, ніж пообіцяти вхід вільний на платне.
 */
const FREE_TRUSTED = new Set(["concert_ua", "karabas"]);

const weekday = (date, tz, style = "long") => new Intl.DateTimeFormat("uk-UA", { weekday: style, timeZone: tz }).format(date);
const dayMonth = (date, tz) => new Intl.DateTimeFormat("uk-UA", { day: "numeric", month: "long", timeZone: tz }).format(date);
const upper = (s) => s.charAt(0).toUpperCase() + s.slice(1);
const dayOf = (e) => dayMonth(new Date(e.startsAt), e.tz);
const byStart = (a, b) => Date.parse(a.startsAt) - Date.parse(b.startsAt);

/**
 * До `n` подій, по одній з кожної категорії по колу — щоб день не був п'ятьма концертами, — і один заклад на день
 * (планетарій із шоу щогодини інакше займе пів поста). Третє коло — лише поки не набралось `min`: з трьох категорій
 * краще п'ять подій, ніж сім із чотирма виставами поспіль. ponytail: заклад — точка на мапі; place_id, якщо злипнуться.
 */
function roundRobin(list, n, min) {
  const places = new Set(), byCategory = new Map();
  for (const e of list) {
    const place = `${e.lat.toFixed(4)},${e.lng.toFixed(4)}`;
    if (places.has(place)) continue;
    places.add(place);
    byCategory.set(e.category, [...(byCategory.get(e.category) ?? []), e]);
  }
  const out = [];
  for (let round = 0; out.length < n && (round < 2 || out.length < min); round++) {
    const next = [...byCategory.values()].map((events) => events[round]).filter(Boolean);
    if (!next.length) break;
    out.push(...next.slice(0, n - out.length));
  }
  return out;
}

/** Спершу «Від людей» (до двох), решта — порівну на кожен день. */
export function pick(entries, [min, max]) {
  const people = entries.filter((e) => e.origin === "community").slice(0, 2);
  const rest = entries.filter((e) => e.origin !== "community");
  const days = [...new Set(rest.map(dayOf))];
  const share = (n) => Math.ceil((n - people.length) / Math.max(days.length, 1));
  const picked = [];
  for (const day of days) picked.push(...roundRobin(rest.filter((e) => dayOf(e) === day), Math.min(share(max), max - people.length - picked.length), share(min)));
  return [...people, ...picked.sort(byStart)];
}

/** «24 і 25 жовтня», через межу місяця — «31 жовтня і 1 листопада». Без тире: тон каналів. */
function dateRange(picks) {
  const days = [...new Set([...picks].sort(byStart).map(dayOf))];
  if (days.length < 2) return days[0] ?? "";
  const [first, last] = [days[0], days.at(-1)];
  const month = (d) => d.split(" ").slice(1).join(" ");
  return month(first) === month(last) ? `${first.split(" ")[0]} і ${last}` : `${first} і ${last}`;
}

/** «мистецтво, концерти і стендап». */
const listing = (words) => words.length < 2 ? words.join("") : `${words.slice(0, -1).join(", ")} і ${words.at(-1)}`;
const isPeople = (e) => e.origin === "community";

/**
 * Рядок події: емодзі, час (з днем, коли блок не по днях), назва-посилання; під ним речення «що це» (events.blurb від
 * агента імпорту, коли є: назва продавця часто не каже, що це за подія) і хто збирає, заклад, ціна.
 */
function eventLines(e, cards, withDay) {
  const start = new Date(e.startsAt);
  const card = cards.get(e.id) ?? {};
  // Ще й жоден продавець не просить грошей: Concert.ua досі буває 0 ₴ поряд із 550 ₴ у Badseller (26.10.2026).
  const free = (isPeople(e) || FREE_TRUSTED.has(e.source)) && !(card.offers ?? []).some((o) => o.price_min > 0);
  const host = isPeople(e) && card.organizer_name ? `Збирає ${card.organizer_name}` : null;
  const meta = [host, card.place_name, price(free ? card : { ...card, is_free: false })].filter(Boolean).join(" · ");
  const time = `${withDay ? `${upper(weekday(start, e.tz, "short"))} ` : ""}${timeOf(start, e.tz)}`;
  return [`${EMOJI[e.category] ?? "📍"} <b>${time}</b> <a href="${eventUrl(e)}">${esc(displayTitle(e.title))}</a>`, card.blurb, meta].filter(Boolean).map((line, i) => i ? esc(line) : line);
}

/**
 * Текст поста в HTML-розмітці Bot API. `cards` — за id: заклад, ціна, хто збирає (в індексі їх нема). Спершу блок
 * «Від людей», як на головній (DESIGN.md, правило людей першими), далі афіша за часом, у вихідних — по днях.
 */
export function format(city, mode, picks, cards) {
  const c = cityOf(city);
  const sorted = [...picks].sort(byStart);
  const what = listing([...new Set(sorted.map((e) => WHAT[e.category]).filter(Boolean))].slice(0, 4));
  // Милозвучність: після голосного «в», крім в-, ф-, льв-, св-, тв- («Сьогодні в Києві», «Сьогодні у Львові»); після
  // приголосного «у», крім голосного далі («На вихідних у Києві», «На вихідних в Одесі»).
  const where = mode === "today"
    ? `Сьогодні ${/^(в|ф|льв|св|тв)/i.test(c.in) ? "у" : "в"} ${c.in}`
    : `На вихідних ${/^[аеєиіїоуюя]/i.test(c.in) ? "в" : "у"} ${c.in}`;
  const head = mode === "today" ? `${upper(weekday(new Date(sorted[0].startsAt), sorted[0].tz))}, ${dayOf(sorted[0])}` : `Вихідні, ${dateRange(picks)}`;
  const people = sorted.filter(isPeople), rest = sorted.filter((e) => !isPeople(e));
  const sections = [{ title: "Від людей", events: people, withDay: mode === "weekend" }];
  if (mode === "today") sections.push({ title: people.length ? "Афіша" : null, events: rest });
  else for (const day of new Set(rest.map(dayOf))) {
    const events = rest.filter((e) => dayOf(e) === day);
    sections.push({ title: upper(weekday(new Date(events[0].startsAt), events[0].tz)), events });
  }
  const lines = [`<b>${head}</b>`, `${where} є куди піти${what ? `: ${what}` : ""} 👇`];
  for (const { title, events, withDay } of sections.filter((section) => section.events.length)) {
    if (title) lines.push("", `<b>${title}</b>`);
    events.forEach((e, i) => lines.push(...(i || !title ? [""] : []), ...eventLines(e, cards, withDay)));
  }
  lines.push("", `Більше подій на мапі в <a href="https://poriad.app/app?from=${CHANNELS[c.name][1]}">«Поряд»</a>. Нема з ким піти? На кожній події є «Шукаю компанію».`);
  return lines.join("\n");
}

/** Скільки символів Telegram порахує: текст без тегів, сутність — один символ. */
const visible = (html) => html.replace(/<[^>]+>/g, "").replace(/&(?:amp|lt|gt|quot|#39);/g, "&").length;

/** Bot API приймає до 4096 символів: зайве знімаємо з кінця афіші, «Від людей» (на початку `picks`) лишаються. */
export function fit(city, mode, picks, cards, limit = 4096) {
  while (picks.length > 1 && visible(format(city, mode, picks, cards)) > limit) picks = picks.slice(0, -1);
  return picks;
}

/** Один повтор через 5 с: prod зрідка відповідає 500 (discover_events, 26.10.2026), і місто пропустило б день. */
async function retry(call) {
  try { return await call(); } catch { await new Promise((resolve) => setTimeout(resolve, 5000)); return call(); }
}

/**
 * Пост міста ({ text, cover }) або null, якщо радити нічого. Обкладинка — сторінка події з картинкою (Telegram бере її
 * og:image з worker/ і ставить великим прев'ю над текстом): спершу «Від людей», далі вечір, далі будь-яка.
 */
async function postFor(city, mode, now) {
  const { index } = await retry(() => discover(city, { cards: 0 }));
  const upcoming = fold(index.filter((e) => inWhen(e, mode, now) && Date.parse(e.startsAt) > now));
  const cards = new Map((await retry(() => cardsByIds(upcoming.map((e) => e.id)))).map((card) => [card.id, card]));
  // Скасоване чи зняте з продажу (state не scheduled) не радимо; у подій від людей стану нема.
  const live = upcoming.filter((e) => cards.has(e.id) && (cards.get(e.id).state ?? "scheduled") === "scheduled");
  if (!live.length) return null;
  const picks = fit(city, mode, pick(live, LIMIT[mode]), cards);
  const photos = picks.filter((e) => cards.get(e.id).image_url);
  const cover = photos.find(isPeople) ?? photos.find((e) => Number(timeOf(new Date(e.startsAt), e.tz).slice(0, 2)) >= 17) ?? photos[0];
  return { text: format(city, mode, picks, cards), cover: cover && eventUrl(cover) };
}

async function send(chat, { text, cover }) {
  const response = await fetch(`https://api.telegram.org/bot${process.env.TELEGRAM_BOT_TOKEN}/sendMessage`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      chat_id: chat, text, parse_mode: "HTML",
      link_preview_options: cover ? { url: cover, prefer_large_media: true, show_above_text: true } : { is_disabled: true },
    }),
  });
  const body = await response.json().catch(() => ({}));
  if (!body.ok) throw new Error(`Bot API ${response.status}: ${body.description ?? "без відповіді"}`);
}

async function main() {
  const args = process.argv.slice(2);
  const [mode] = args;
  const dryRun = args.includes("--dry-run");
  const only = args.includes("--city") ? args[args.indexOf("--city") + 1] : null;
  if (!LIMIT[mode]) { console.error("node tools/telegram_post.mjs today|weekend [--dry-run] [--city Київ]"); process.exit(2); }
  if (only && !CHANNELS[only]) { console.error(`Невідоме місто «${only}». Є: ${CITIES.map((c) => c.name).join(", ")}.`); process.exit(2); }
  if (!dryRun && !process.env.TELEGRAM_BOT_TOKEN) { console.error("Нема TELEGRAM_BOT_TOKEN. Подивитись пости: --dry-run."); process.exit(2); }
  const now = new Date();
  let failed = 0;
  for (const { name } of CITIES.filter((c) => !only || c.name === only)) {
    const variable = `TELEGRAM_CHANNEL_${CHANNELS[name][0]}`;
    const chat = process.env[variable];
    if (!dryRun && !chat) { console.error(`${name}: нема ${variable}, пропускаю.`); continue; }
    try {
      const post = await postFor(name, mode, now);
      if (!post) console.error(`${name}: подій нема, пропускаю.`);
      else if (dryRun) console.log(`==== ${name} → ${chat ?? variable}\nобкладинка: ${post.cover ?? "нема"}\n${post.text}\n`);
      else { await send(chat, post); console.error(`${name}: надіслано.`); }
    } catch (error) {
      failed++;
      console.error(`${name}: ${error.message}`);
    }
  }
  process.exit(failed ? 1 : 0);
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) await main();
