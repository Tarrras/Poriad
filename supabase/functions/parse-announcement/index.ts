// Edge Function `parse-announcement` (docs/organizers-1.5.md, 1.4): «Вставити анонс» у кабінеті й редакторі.
// POST {text ≤ 3000, city, today: YYYY-MM-DD, tz} → поля форми (announce.ts) або {error}; понад 20 викликів на годину з
// однієї адреси (IPv6 — мережі /64) чи 300 на годину на всіх — 429 (private.announce_calls). Текст і адреси не
// зберігаємо в журналі: там лише лічильники.
//
// Кличе й гість з публікованим ключем, а він не JWT, тож деплой без перевірки JWT:
//   supabase functions deploy parse-announcement --no-verify-jwt
// Секрет функції: ANTHROPIC_API_KEY. SUPABASE_URL і SUPABASE_SERVICE_ROLE_KEY середовище дає саме.

import { createClient } from "npm:@supabase/supabase-js@2.118.0";
import { announce, clientIp, readInput, TEXT_MAX } from "./announce.ts";

// Сайт і локальна розробка (`wrangler dev`, статичний сервер); застосунки ходять без Origin.
const ORIGIN = /^(https:\/\/poriad\.app|http:\/\/(localhost|127\.0\.0\.1)(:\d+)?)$/;

Deno.serve(async (req) => {
  const origin = req.headers.get("origin") ?? "";
  const cors: Record<string, string> = ORIGIN.test(origin) ? { "Access-Control-Allow-Origin": origin, Vary: "Origin" } : { Vary: "Origin" };
  const reply = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: { ...cors, "Access-Control-Allow-Methods": "POST",
      "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info", "Access-Control-Max-Age": "86400" } });
  }
  if (req.method !== "POST") return reply({ error: "method" }, 405);

  // Тіло — лише текст анонсу й три короткі поля: більше — не наш клієнт.
  const raw = await req.text();
  if (raw.length > TEXT_MAX * 4) return reply({ error: "too long" }, 413);
  let body: unknown;
  try { body = JSON.parse(raw); } catch { return reply({ error: "bad json" }, 400); }
  const input = readInput(body);
  if ("error" in input) return reply(input, 400);

  const ip = clientIp(req.headers.get("x-forwarded-for"));
  if (!ip) return reply({ error: "no ip" }, 400);
  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: allowed, error } = await db.rpc("announce_call", { p_ip: ip });
  // Повідомлення помилки бази може містити адресу (невдале приведення до inet), тож лише код.
  if (error) { console.error("announce_call failed", error.code); return reply({ error: "failed" }, 500); }
  if (!allowed) { console.warn("announce rate limited"); return reply({ error: "rate limited" }, 429); }

  const key = Deno.env.get("ANTHROPIC_API_KEY");
  if (!key) { console.warn("ANTHROPIC_API_KEY is not set"); return reply({ error: "not configured" }, 503); }
  const fields = await announce(input, key);
  return fields ? reply(fields) : reply({ error: "failed" }, 502);
});
