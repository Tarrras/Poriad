// Edge Function `offer-check` (docs/event-offers.md, фаза 2, R5): адресна перевірка сторінок пропозицій.
// pg_cron кожні 15 хв кличе private.kick_offer_check(); якщо є що перевіряти, база шле сюди POST через pg_net.
// Функція бере пакет у private.offer_checks_due, читає сторінки й віддає вердикти в private.record_offer_checks,
// а стан події (R4) рахує база. Фаза 2 — тінь: нічого, що бачать клієнти, тут не змінюється.
//
// Правила ввічливості — як у tools/ingest/fetch.py: свій User-Agent, robots.txt (недоступний — нічого не читаємо),
// пауза не менша за crawl_delay_seconds джерела й Crawl-delay з robots.txt. Хости — паралельно, у хості — по черзі.
// Секрет — той самий PUSH_SECRET, що в `push` (у Vault — push_function_secret). SUPABASE_DB_URL середовище дає саме.

import postgres from "npm:postgres@3.4.5";
import robotsParser from "npm:robots-parser@3.0.1";
import { eventsFromHtml, type Node, verdict } from "./verdict.ts";

const UA = "PoriadBot/0.1 (+https://poriad.app/bot; hello@poriad.app)";
const BATCH = 60;
const BUDGET_MS = 100_000;      // нових запитів не починаємо: решту візьме наступний запуск
const MAX_BYTES = 10 * 1024 * 1024;
const MAX_HOPS = 5;

type Due = { offer_id: string; url: string; expected: Date; why: string; tz_policy: string; time_zone: string;
  crawl_delay: number };
type Page = { status: number; finalUrl: string | null; redirected: boolean; nodes: Node[]; error?: string };

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method" }, 405);
  const secret = Deno.env.get("PUSH_SECRET");
  if (!secret || !sameSecret(req.headers.get("x-push-secret") ?? "", secret)) return json({ error: "forbidden" }, 403);

  const sql = postgres(Deno.env.get("SUPABASE_DB_URL")!, { max: 1, prepare: false });
  try {
    const due = await sql<Due[]>`select * from private.offer_checks_due(${BATCH})`;
    const byUrl = new Map<string, Due[]>();
    for (const d of due) byUrl.set(d.url, [...(byUrl.get(d.url) ?? []), d]);
    const byHost = new Map<string, string[]>();
    for (const url of byUrl.keys()) {
      const host = new URL(url).host;
      byHost.set(host, [...(byHost.get(host) ?? []), url]);
    }

    const started = Date.now();
    const rows: Record<string, unknown>[] = [];
    await Promise.all([...byHost.values()].map(async (urls) => {
      for (const [i, url] of urls.entries()) {
        if (Date.now() - started > BUDGET_MS) return;
        const offers = byUrl.get(url)!;
        if (i > 0) await sleep(Math.max(offers[0].crawl_delay, await robotsDelay(url)) * 1000);
        const page = await read(url);
        for (const o of offers) {
          const [kind, detail] = verdict(page.status, page.redirected, page.nodes, o.expected.getTime(),
            o.tz_policy, o.time_zone);
          rows.push({ offer_id: o.offer_id, why: o.why, expected: o.expected, url, http: page.status,
            final_url: page.finalUrl, redirected: page.redirected, verdict: kind,
            detail: page.error ? { ...detail, error: page.error.slice(0, 200) } : detail });
        }
      }
    }));
    // sql.json, а не JSON.stringify: параметр типу jsonb драйвер серіалізує сам, рядок став би JSON-рядком.
    const [{ changed }] = await sql`select private.record_offer_checks(${sql.json(rows)}) as changed`;
    return json({ due: due.length, checked: rows.length, pages: new Set(rows.map((r) => r.url)).size, changed });
  } catch (e) {
    console.error("offer-check failed", String(e));
    return json({ error: "failed" }, 500);
  } finally {
    await sql.end();
  }
});

// Сторінка з переадресаціями вручну: кожна адреса проходить robots.txt свого хоста, як у fetch.py.
async function read(url: string): Promise<Page> {
  let current = url;
  for (let hop = 0; hop <= MAX_HOPS; hop++) {
    if (!(await allowed(current))) return fail(-1, "robots.txt забороняє");
    let r: Response;
    try {
      r = await fetch(current, { redirect: "manual", signal: AbortSignal.timeout(30_000), headers: {
        "User-Agent": UA, "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "uk,en;q=0.8" } });
    } catch (e) {
      return fail(0, String(e));
    }
    const location = r.headers.get("location");
    if (r.status >= 300 && r.status < 400 && location) {
      await r.body?.cancel();
      try { current = new URL(location, current).href; } catch { return fail(0, `зламана переадресація: ${location}`); }
      continue;
    }
    if (r.status !== 200) {
      await r.body?.cancel();
      return fail(r.status);
    }
    const body = await r.text();
    if (body.length > MAX_BYTES) return fail(413, `відповідь понад ${MAX_BYTES} байтів`);
    return { status: 200, finalUrl: current, redirected: bare(current) !== bare(url), nodes: eventsFromHtml(body) };
  }
  return fail(0, "забагато переадресацій");
}

const fail = (status: number, error?: string): Page => ({ status, finalUrl: null, redirected: false, nodes: [], error });

// Як _bare у shadow_checks.py: хост без www і шлях без кінцевого слеша.
function bare(url: string): string {
  const u = new URL(url);
  return u.host.replace(/^www\./, "") + u.pathname.replace(/\/+$/, "");
}

type Robots = ReturnType<typeof robotsParser> | null;
const robots = new Map<string, Promise<Robots>>();

function robotsFor(url: string): Promise<Robots> {
  const root = new URL(url).origin;
  if (!robots.has(root)) {
    robots.set(root, fetch(`${root}/robots.txt`, { headers: { "User-Agent": UA }, signal: AbortSignal.timeout(20_000) })
      .then(async (r) => (r.ok ? robotsParser(`${root}/robots.txt`, await r.text()) : null))
      // Недоступний robots.txt — не привід вважати, що все дозволено.
      .catch(() => null));
  }
  return robots.get(root)!;
}

async function allowed(url: string): Promise<boolean> {
  return (await robotsFor(url))?.isAllowed(url, UA) === true;
}

async function robotsDelay(url: string): Promise<number> {
  return (await robotsFor(url))?.getCrawlDelay(UA) ?? 0;
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

function sameSecret(given: string, expected: string): boolean {
  const a = new TextEncoder().encode(given), b = new TextEncoder().encode(expected);
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
