// Пости для Telegram-каналів міст: node tools/telegram_post.mjs today|weekend [--dry-run] [--city Київ]
// today — події міста на сьогодні, що ще не почались (щодня о 12:00); weekend — субота й неділя (щоп'ятниці).
// Афіша та сама, що на сайті й у гостя в застосунку (site/js/poriad.js, публічні RPC з publishable-ключем): лише
// опубліковане, не злите (злиття — import_status withdrawn) і не сховане, сеанси прокату згорнуті.
// --dry-run друкує пости всіх міст. Без нього — надсилає через Bot API: TELEGRAM_BOT_TOKEN і
// TELEGRAM_CHANNEL_<KYIV|LVIV|ODESA|DNIPRO|KHARKIV> з env (у CI — secrets); місто без каналу пропускається.
// Канали, бот і розклад — tools/telegram.md.
import { pathToFileURL } from "node:url";
import { discover, cardsByIds, inWhen, fold, displayTitle, timeOf, price, esc, CATEGORIES, CITIES, cityOf, eventUrl } from "../site/js/poriad.js";

/** Латиницею: суфікс змінної з id каналу й мітка ?from= для /app (site/app.html приймає лише ^[a-z]{1,12}$). */
export const CHANNELS = { Київ: ["KYIV", "tgk"], Львів: ["LVIV", "tgl"], Одеса: ["ODESA", "tgo"], Дніпро: ["DNIPRO", "tgd"], Харків: ["KHARKIV", "tgh"] };
/** Скільки подій у пості. */
const LIMIT = { today: 7, weekend: 10 };
/**
 * «Безкоштовно» — лише від людей і з джерел, де нуль-заглушка вже не стає is_free (88e1047: Concert.ua без валюти,
 * Karabas OutOfStock). Решта is_free — без ціни: краще не сказати, ніж пообіцяти вхід вільний на платне.
 */
const FREE_TRUSTED = new Set(["concert_ua", "karabas"]);

const weekday = (date, tz) => new Intl.DateTimeFormat("uk-UA", { weekday: "short", timeZone: tz }).format(date);
const dayMonth = (date, tz) => new Intl.DateTimeFormat("uk-UA", { day: "numeric", month: "long", timeZone: tz }).format(date);
const upper = (s) => s.charAt(0).toUpperCase() + s.slice(1);
const dayOf = (e) => dayMonth(new Date(e.startsAt), e.tz);
const byStart = (a, b) => Date.parse(a.startsAt) - Date.parse(b.startsAt);

/**
 * До `n` подій, по одній з кожної категорії по колу — щоб день не був п'ятьма концертами, — і один заклад на день
 * (планетарій із шоу щогодини інакше займе пів поста). ponytail: заклад — точка на мапі; place_id, якщо точки злипнуться.
 */
function roundRobin(list, n) {
  const places = new Set(), byCategory = new Map();
  for (const e of list) {
    const place = `${e.lat.toFixed(4)},${e.lng.toFixed(4)}`;
    if (places.has(place)) continue;
    places.add(place);
    byCategory.set(e.category, [...(byCategory.get(e.category) ?? []), e]);
  }
  const out = [];
  for (let round = 0; out.length < n; round++) {
    const next = [...byCategory.values()].map((events) => events[round]).filter(Boolean);
    if (!next.length) break;
    out.push(...next.slice(0, n - out.length));
  }
  return out;
}

/** Спершу «Від людей» (до двох), решта ліміту — порівну на кожен день, за часом. */
export function pick(entries, limit) {
  const people = entries.filter((e) => e.origin === "community").slice(0, 2);
  const rest = entries.filter((e) => e.origin !== "community");
  const days = [...new Set(rest.map(dayOf))];
  const perDay = Math.ceil((limit - people.length) / Math.max(days.length, 1));
  const picked = [];
  for (const day of days) picked.push(...roundRobin(rest.filter((e) => dayOf(e) === day), Math.min(perDay, limit - people.length - picked.length)));
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

/** Текст поста в HTML-розмітці Bot API. `cards` — за id: заклад і ціна (в індексі їх нема). */
export function format(city, mode, picks, cards) {
  const c = cityOf(city);
  // Милозвучність: «у Львові» (перед в-, ф-, льв-, св-, тв-), «в Києві».
  const prep = /^(в|ф|льв|св|тв)/i.test(c.in) ? "у" : "в";
  const lines = [`<b>${mode === "today" ? "Сьогодні" : "Вихідні"} ${prep} ${c.in}</b>, ${dateRange(picks)}`, ""];
  for (const e of picks) {
    const start = new Date(e.startsAt);
    const card = cards.get(e.id) ?? {};
    const label = e.origin === "community" ? "Від людей" : CATEGORIES[e.category] ?? "Подія";
    const time = mode === "today" ? timeOf(start, e.tz) : `${upper(weekday(start, e.tz))} ${timeOf(start, e.tz)}`;
    // Ще й жоден продавець не просить грошей: Concert.ua досі буває 0 ₴ поряд із 550 ₴ у Badseller (26.10.2026).
    const free = (e.origin === "community" || FREE_TRUSTED.has(e.source)) && !(card.offers ?? []).some((o) => o.price_min > 0);
    const meta = [card.place_name, price(free ? card : { ...card, is_free: false })].filter(Boolean).join(" · ");
    lines.push(`${label} · ${time}`, `<a href="${eventUrl(e)}"><b>${esc(displayTitle(e.title))}</b></a>`);
    if (meta) lines.push(esc(meta));
    lines.push("");
  }
  lines.push(`Решта афіші міста на мапі в «Поряд», там же знайдеш компанію, якщо нема з ким піти: <a href="https://poriad.app/app?from=${CHANNELS[c.name][1]}">poriad.app/app</a>`);
  return lines.join("\n");
}

/** Пост міста або null, якщо радити нічого. */
async function postFor(city, mode, now) {
  const { index } = await discover(city, { cards: 0 });
  const upcoming = fold(index.filter((e) => inWhen(e, mode, now) && Date.parse(e.startsAt) > now));
  const cards = new Map((await cardsByIds(upcoming.map((e) => e.id))).map((card) => [card.id, card]));
  // Скасоване чи зняте з продажу (state не scheduled) не радимо; у подій від людей стану нема.
  const live = upcoming.filter((e) => cards.has(e.id) && (cards.get(e.id).state ?? "scheduled") === "scheduled");
  return live.length ? format(city, mode, pick(live, LIMIT[mode]), cards) : null;
}

async function send(chat, text) {
  const response = await fetch(`https://api.telegram.org/bot${process.env.TELEGRAM_BOT_TOKEN}/sendMessage`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    // Без прев'ю: інакше Telegram розгортає першу подію, і дайджест виглядає постом про неї одну.
    body: JSON.stringify({ chat_id: chat, text, parse_mode: "HTML", link_preview_options: { is_disabled: true } }),
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
      else if (dryRun) console.log(`==== ${name} → ${chat ?? variable}\n${post}\n`);
      else { await send(chat, post); console.error(`${name}: надіслано.`); }
    } catch (error) {
      failed++;
      console.error(`${name}: ${error.message}`);
    }
  }
  process.exit(failed ? 1 : 0);
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) await main();
