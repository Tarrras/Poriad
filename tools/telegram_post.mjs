// Пост «Вихідні в місті» для Telegram-каналу: node tools/telegram_post.mjs [Місто] [кількість]
// Друкує готовий текст — скопіювати в канал. Афіша та сама, що на сайті й у гостя в застосунку (site/js/poriad.js):
// вихідні — як чип «Вихідні», сеанси прокату згорнуті. Посилання poriad.app/e/… відкривають застосунок, якщо він є
// (Universal Links), інакше — сторінку події з кнопкою в стор. Telegram сам розгортає перше посилання в прев'ю.
// ponytail: посилання без власної мітки — трафік з Telegram видно в Cloudflare Web Analytics за referrer t.me;
// окремий ct=tg для App Store — коли worker навчиться передавати ?from= далі.
import { pathToFileURL } from "node:url";
import { discover, cardsByIds, inWhen, fold, displayTitle, timeOf, price, plural, CATEGORIES, CITIES, EVENTS, cityOf, eventUrl } from "../site/js/poriad.js";

const weekday = (date, tz) => new Intl.DateTimeFormat("uk-UA", { weekday: "short", timeZone: tz }).format(date);
const dayMonth = (date, tz) => new Intl.DateTimeFormat("uk-UA", { day: "numeric", month: "long", timeZone: tz }).format(date);
const upper = (s) => s.charAt(0).toUpperCase() + s.slice(1);
const dayOf = (e) => dayMonth(new Date(e.startsAt), e.tz);
const byStart = (a, b) => Date.parse(a.startsAt) - Date.parse(b.startsAt);

/** До `n` подій, по одній з кожної категорії по колу — щоб день не був п'ятьма концертами. */
function roundRobin(list, n) {
  const byCategory = new Map();
  for (const e of list) byCategory.set(e.category, [...(byCategory.get(e.category) ?? []), e]);
  const out = [];
  for (let round = 0; out.length < n; round++) {
    const next = [...byCategory.values()].map((events) => events[round]).filter(Boolean);
    if (!next.length) break;
    out.push(...next.slice(0, n - out.length));
  }
  return out;
}

/** Спершу «Від людей» (до двох), решта ліміту — порівну на суботу й неділю, за часом. */
export function pick(entries, limit) {
  const people = entries.filter((e) => e.origin === "community").slice(0, 2);
  const rest = entries.filter((e) => e.origin !== "community");
  const days = [...new Set(rest.map(dayOf))];
  const perDay = Math.ceil((limit - people.length) / Math.max(days.length, 1));
  const picked = [];
  for (const day of days) picked.push(...roundRobin(rest.filter((e) => dayOf(e) === day), Math.min(perDay, limit - people.length - picked.length)));
  return [...people, ...picked.sort(byStart)];
}

/** «24–25 жовтня», через межу місяця — «31 жовтня – 1 листопада». */
function dateRange(picks) {
  const days = [...new Set([...picks].sort(byStart).map(dayOf))];
  if (days.length < 2) return days[0] ?? "";
  const [first, last] = [days[0], days.at(-1)];
  const month = (d) => d.split(" ").slice(1).join(" ");
  return month(first) === month(last) ? `${first.split(" ")[0]}–${last}` : `${first} – ${last}`;
}

/** Текст поста. `cards` — за id: заклад і ціна (в індексі їх нема). Розмітка — та, яку Telegram розбирає при надсиланні. */
export function format(city, picks, cards, total) {
  const c = cityOf(city);
  const range = dateRange(picks);
  // Милозвучність: «у Львові» (перед в-, ф-, льв-, св-, тв-), «в Києві».
  const prep = /^(в|ф|льв|св|тв)/i.test(c.in) ? "у" : "в";
  const lines = [`**Вихідні ${prep} ${c.in}**${range ? ` · ${range}` : ""}`, ""];
  for (const e of picks) {
    const start = new Date(e.startsAt);
    const card = cards.get(e.id) ?? {};
    const label = e.origin === "community" ? "Від людей" : CATEGORIES[e.category] ?? "Подія";
    lines.push(`${label} · ${upper(weekday(start, e.tz))} ${timeOf(start, e.tz)}`);
    lines.push(`**${displayTitle(e.title)}**`);
    const meta = [card.place_name, price(card)].filter(Boolean).join(" · ");
    if (meta) lines.push(meta);
    lines.push(eventUrl(e), "");
  }
  const cityQuery = c.name === "Київ" ? "" : `city=${c.name}&`;
  lines.push(`Усього на вихідних — ${plural(total, EVENTS)}: poriad.app/afisha.html?${cityQuery}when=weekend`);
  lines.push("Нема з ким піти — у застосунку є «Шукаю компанію».", "", "Є куди. Буде з ким.");
  return lines.join("\n");
}

async function main() {
  const [city = "Київ", limit = "8"] = process.argv.slice(2);
  if (!CITIES.some((c) => c.name === city)) { console.error(`Невідоме місто «${city}». Є: ${CITIES.map((c) => c.name).join(", ")}.`); process.exit(2); }
  const { index } = await discover(city, { cards: 0 });
  const weekend = fold(index.filter((e) => inWhen(e, "weekend")));
  if (!weekend.length) { console.error(`На вихідних у місті «${city}» подій нема.`); process.exit(1); }
  const picks = pick(weekend, Number(limit));
  const cards = new Map((await cardsByIds(picks.map((e) => e.id))).map((card) => [card.id, card]));
  console.log(format(city, picks, cards, weekend.length));
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) await main();
