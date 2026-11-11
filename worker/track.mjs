// Аналітика кабінету (docs/analytics.md, «Кабінет на сайті»): сторінка шле кроки воронки на свою адресу `/api/t`,
// а воркер пересилає їх в Amplitude HTTP API — туди ж, куди пишуть застосунки. У CSP кабінету не з'являється ні чужого
// скрипта, ні чужої адреси. Словник закритий: довільну подію чи текст цією адресою в наш проєкт не записати.
import { clientKey } from "./kabinet.mjs";

const AMPLITUDE = "https://api2.amplitude.com/2/httpapi";
const MAX_BODY = 2048;
const DEVICE = /^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/;
const WORD = /^[A-Za-z0-9_]{1,40}$/;

/** Подія → її параметри. Значення — слово (`WORD`), число чи прапорець; решту відкидаємо мовчки. */
export const TRACKED = {
  kab_open: ["guest", "from", "mobile"],
  kab_editor: ["mode", "draft", "mobile"],
  kab_submit: ["mode", "guest", "blocked", "mobile"],
  kab_publish: ["mode", "media", "mobile"],
  kab_failed: ["mode", "code", "mobile"],
};

/** Тіло запиту сторінки → подія Amplitude або null, якщо це не наша подія. */
export function tracked(body, now = Date.now()) {
  const allowed = TRACKED[body?.name];
  if (!allowed || !DEVICE.test(body.device ?? "")) return null;
  const props = {};
  for (const key of allowed) {
    const value = body.props?.[key];
    if (typeof value === "boolean" || Number.isFinite(value) || (typeof value === "string" && WORD.test(value))) props[key] = value;
  }
  return { event_type: body.name, device_id: body.device, platform: "Web", time: now, insert_id: crypto.randomUUID(), event_properties: props };
}

/** `POST /api/t {name, device, props}` → 204. Без ключа (dev) подію не шлемо, як і застосунки без ключа. */
export async function track(request, env, ctx) {
  if (request.method !== "POST") return new Response(null, { status: 405 });
  // Лише з наших сторінок: чужий сайт не накрутить воронку формою чи fetch без CORS.
  if (request.headers.get("origin") !== new URL(request.url).origin) return new Response(null, { status: 403 });
  if (env.TRACK_LIMIT && !(await env.TRACK_LIMIT.limit({ key: clientKey(request.headers.get("cf-connecting-ip")) })).success) {
    return new Response(null, { status: 429 });
  }
  const text = await request.text();
  let event = null;
  try { event = text.length <= MAX_BODY ? tracked(JSON.parse(text)) : null; } catch { /* не JSON */ }
  if (!event) return new Response(null, { status: 400 });
  if (env.AMPLITUDE_KEY) {
    // Адресу людини не передаємо: Amplitude бачить лише воркер. Країна — з Cloudflare.
    const body = JSON.stringify({ api_key: env.AMPLITUDE_KEY, events: [{ ...event, country: request.cf?.country }] });
    ctx.waitUntil(fetch(AMPLITUDE, { method: "POST", headers: { "content-type": "application/json" }, body })
      .then((r) => { if (!r.ok) console.warn("track", r.status); }, (e) => console.warn("track", e.message)));
  }
  return new Response(null, { status: 204 });
}
