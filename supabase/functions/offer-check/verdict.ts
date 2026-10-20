// Що сторінка продавця каже про сеанс — двійник tools/ingest/shadow_checks.verdict (і того, на що він спирається:
// extract.events_from_html, normalize.parse_datetime). Обидва ганяють спільні кейси tools/ingest/verdict_cases.json,
// тож правку роблять в обох місцях разом з кейсом.

export type Node = Record<string, unknown>;
export type Verdict = [string, Record<string, unknown>];
type Moment = { ms: number; off: number };          // мить і зсув у хвилинах, з яким її показувати

const EVENT_TYPES = new Set(["Event", "MusicEvent", "TheaterEvent", "ComedyEvent", "ScreeningEvent",
  "ExhibitionEvent", "LiteraryEvent", "ChildrensEvent", "SportsEvent", "DanceEvent", "FoodEvent",
  "EducationEvent", "SocialEvent", "Festival", "BusinessEvent", "VisualArtsEvent"]);
// Сеанс на цю дату живий: EventRescheduled тут означає «перенесено сюди», а не «звідси».
const ON = new Set(["EventScheduled", "EventRescheduled", "EventMovedOnline", ""]);
const SAME_MINUTE = 60_000;
const SCRIPT = /<script[^>]*type\s*=\s*["']application\/ld\+json["'][^>]*>(.*?)<\/script>/gis;
const ISO = /(\d{4}-\d{2}-\d{2})[T ](\d{2}:\d{2}(?::\d{2})?)(Z|[+-]\d{2}:?\d{2})?/;

const isObj = (x: unknown): x is Node => typeof x === "object" && x !== null && !Array.isArray(x);
const str = (x: unknown) => (x ? String(x) : "");

function walk(node: unknown, out: Node[]): void {
  if (isObj(node)) {
    const t = node["@type"];
    const types = typeof t === "string" ? [t] : Array.isArray(t) ? t.filter((x) => typeof x === "string") : [];
    if (types.some((x) => EVENT_TYPES.has(x))) out.push(node);
    for (const key of ["@graph", "itemListElement", "subEvent", "item"]) if (key in node) walk(node[key], out);
  } else if (Array.isArray(node)) {
    for (const item of node) walk(item, out);
  }
}

export function eventsFromHtml(html: string): Node[] {
  const found: Node[] = [];
  for (const m of html.matchAll(SCRIPT)) {
    const raw = m[1].trim();
    let data: unknown;
    try { data = JSON.parse(raw); } catch {
      try { data = JSON.parse(raw.replace(/[\x00-\x1f]/g, " ")); } catch { continue; }
    }
    walk(data, found);
  }
  const seen = new Set<string>();
  return found.filter((e) => {
    const key = JSON.stringify([str(e.url || e["@id"] || e.name), str(e.startDate), str(e.eventStatus)]);
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function offersOf(e: Node): Node[] {
  const off = e.offers;
  return isObj(off) ? [off] : Array.isArray(off) ? off.filter(isObj) : [];
}

// Зсув поясу `tz` у мить `ms`, хвилини.
function zoneOffset(ms: number, tz: string): number {
  const p = Object.fromEntries(new Intl.DateTimeFormat("en-US", { timeZone: tz, hourCycle: "h23", year: "numeric",
    month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit" })
    .formatToParts(ms).map((x) => [x.type, Number(x.value)]));
  return Math.round((Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second) - ms) / 60_000);
}

// Стінний час у поясі `tz`. Неоднозначна година переходу на зимовий час тут бере зимовий зсув, Python — літній:
// 03:00–04:00 однієї ночі на рік, сеансів тоді нема.
function zoned(wall: number, tz: string): Moment {
  let off = zoneOffset(wall, tz);
  const again = zoneOffset(wall - off * 60_000, tz);
  if (again !== off) off = again;
  return { ms: wall - off * 60_000, off };
}

export function parseDatetime(raw: unknown, policy: string, tz: string): Moment | null {
  const m = raw ? ISO.exec(String(raw)) : null;
  if (!m) return null;
  const [y, mo, d] = m[1].split("-").map(Number);
  const [h, mi, s = 0] = m[2].split(":").map(Number);
  const wall = Date.UTC(y, mo - 1, d, h, mi, s);
  const back = new Date(wall);
  if (h > 23 || mi > 59 || s > 59 || back.getUTCMonth() !== mo - 1 || back.getUTCDate() !== d) return null;
  const off = m[3];
  if (policy === "force_local" || !off) return zoned(wall, tz);
  let delta = 0;
  if (off !== "Z") {
    const digits = off.slice(1).replace(":", "");
    const hh = Number(digits.slice(0, 2)), mm = Number(digits.slice(2, 4));
    if (hh > 23 || mm > 59) return null;
    delta = (off[0] === "+" ? 1 : -1) * (hh * 60 + mm);
  }
  const ms = wall - delta * 60_000;
  // karabas: UTC-момент несе правильний стінний час — читаємо його як локальний час міста.
  return policy === "utc_is_local" ? zoned(ms, tz) : { ms, off: delta };
}

// Як Python datetime.isoformat(): 2026-11-07T19:00:00+02:00.
export function isoformat(t: Moment): string {
  const w = new Date(t.ms + t.off * 60_000).toISOString().slice(0, 19);
  const a = Math.abs(t.off);
  return `${w}${t.off < 0 ? "-" : "+"}${String(Math.floor(a / 60)).padStart(2, "0")}:${String(a % 60).padStart(2, "0")}`;
}

const cmp = (a: string, b: string) => (a < b ? -1 : a > b ? 1 : 0);   // як sorted() у Python: за кодами символів

/** Що сторінка каже про сеанс `expected` (мить, мс). Розпродаж — лише позначка: стан він не змінює. */
export function verdict(status: number, redirected: boolean, nodes: Node[], expected: number,
  policy: string, tz: string): Verdict {
  if (status === 404 || status === 410) return ["gone", {}];
  if (status !== 200) return ["error", {}];
  if (nodes.length === 0) return [redirected ? "redirect_away" : "no_jsonld", {}];
  const dates: string[] = [], statuses = new Set<string>(), names = new Map<string, string>();
  for (const n of nodes) {
    const start = parseDatetime(n.startDate, policy, tz);
    const prev = parseDatetime(n.previousStartDate, policy, tz);
    const raw = str(n.eventStatus).split("/").pop()!;
    statuses.add(raw);
    const here = start !== null && Math.abs(start.ms - expected) < SAME_MINUTE;
    if (prev && Math.abs(prev.ms - expected) < SAME_MINUTE && !here) {
      return ["rescheduled_away", { new_start: start ? isoformat(start) : null }];
    }
    if (here) {
      const sold = offersOf(n).some((o) => String(o.availability).includes("SoldOut"));
      const kind = ON.has(raw) ? "scheduled"
        : ({ EventCancelled: "cancelled", EventPostponed: "postponed" } as Record<string, string>)[raw] ?? "other";
      return [kind, { raw, sold_out: sold }];
    }
    if (start) {
      const iso = isoformat(start);
      dates.push(iso);
      if (!names.has(iso)) names.set(iso, str(n.name));
    }
  }
  const sortedStatuses = [...statuses].sort(cmp);
  if (dates.length === 0) return ["no_dates", { statuses: sortedStatuses }];
  if (new Set(dates).size === 1) {
    return ["moved_silent", { new_start: dates[0], name: names.get(dates[0]), statuses: sortedStatuses }];
  }
  return ["date_missing", { dates: [...dates].sort(cmp).slice(0, 5), statuses: sortedStatuses }];
}
