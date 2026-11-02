// Кабінет організатора (docs/organizers-1.5.md, 1.2): сторінка `poriad.app/kabinet` з Pages і підказки адрес
// `/api/geocode` для її редактора. Політику CSP кабінету index.mjs збирає з тих самих частин, що й решту (CSP.kabinet).
import { CITIES, cityOf } from "../site/js/poriad.js";

/** Сторінка з Pages: заголовки безпеки вже стоять, кабінет ще й не індексуємо — там лише вхід і чужі події. */
export function kabinetPage(response) {
  if (!response.headers.get("content-type")?.startsWith("text/html")) return response;
  response.headers.set("x-robots-tag", "noindex, nofollow");
  return response;
}

// Photon — той самий геокодер, що в застосунку й імпорті (публічний komoot): чесний User-Agent і кеш на добу, щоб
// організатор, який набирає адресу по літері, не впирався в його ліміти. User-Agent свій, не імпорту (PoriadBot,
// tools/ingest/fetch.py): якщо komoot заблокує кабінет за зловживання, геокодинг імпорту працюватиме далі.
const PHOTON = "https://photon.komoot.io/api/";
const USER_AGENT = "PoriadKabinet/1.0 (+https://poriad.app; hello@poriad.app)";
const DAY = 86400;
// Як `PhotonGeoSearchRepository`: коротший запит нічого не звужує; просимо із запасом, бо частину відкидаємо.
const MIN_QUERY = 3;
const MAX_QUERY = 100;
const LIMIT = 6;
const EXCLUDED = new Set(["RU"]);

/** `GET /api/geocode?q=&city=` → `[{label, detail, city, lat, lon}]`; місто форми — першим, як у застосунку. */
export async function geocode(request, env, ctx) {
  const url = new URL(request.url);
  const q = (url.searchParams.get("q") ?? "").trim().replace(/\s+/g, " ").toLowerCase();
  const name = url.searchParams.get("city") ?? "";
  if (q.length < MIN_QUERY || q.length > MAX_QUERY || !CITIES.some((c) => c.name === name)) return answer({ error: "query" }, 400);
  // Ключ — нормалізований запит: «Хрещатик 22» і « хрещатик  22» — одна відповідь з кешу.
  const key = new Request(`${url.origin}/api/geocode?${new URLSearchParams({ city: name, q })}`);
  const cached = await caches.default.match(key);
  if (cached) return cached;
  // Кожен новий запит іде в komoot, а той за зловживання блокує наш User-Agent для всіх. Тож повз кеш — ліміт на
  // адресу (GEOCODE_LIMIT) і загальна стеля (GEOCODE_GLOBAL) з wrangler.toml, обидва в межах локації Cloudflare.
  // Без binding-ів — без ліміту.
  const over = async (limiter, key) => limiter && !(await limiter.limit({ key })).success;
  if (await over(env.GEOCODE_LIMIT, clientKey(request.headers.get("cf-connecting-ip"))) || await over(env.GEOCODE_GLOBAL, "global")) {
    return answer({ error: "rate" }, 429);
  }
  const city = cityOf(name);
  let found;
  try {
    const response = await fetch(`${PHOTON}?${new URLSearchParams({ q, lat: city.lat, lon: city.lng, limit: LIMIT * 2 })}`, { headers: { "user-agent": USER_AGENT } });
    if (!response.ok) throw new Error(`photon ${response.status}`);
    found = places((await response.json()).features ?? [], name);
  } catch (e) {
    // Підказок нема — не біда: крапку ставлять на мапі. Збій не кешуємо.
    console.warn("geocode", e.message);
    return answer([], 200, "no-store");
  }
  const out = answer(found);
  ctx.waitUntil(caches.default.put(key, out.clone()));
  return out;
}

/**
 * Ключ ліміту на людину: IPv4 як є, IPv6 — мережа /64. Провайдер видає абоненту цілу /64, і нова адреса в ній нічого
 * не коштує, тож ліміт на окрему IPv6 обходився б перебором адрес.
 */
export function clientKey(ip) {
  if (!ip) return "local";
  if (!ip.includes(":") || ip.includes(".")) return ip;
  const [head, tail] = ip.split("::");
  const left = head ? head.split(":") : [];
  const right = tail ? tail.split(":") : [];
  const groups = tail === undefined ? left : [...left, ...Array(Math.max(0, 8 - left.length - right.length)).fill("0"), ...right];
  return `${groups.slice(0, 4).map((g) => parseInt(g || "0", 16).toString(16)).join(":")}::/64`;
}

/** Рядки Photon → підказки: вулиця з будинком, інакше назва; без виключених країн і повторів. */
export function places(features, city) {
  const seen = new Set();
  const out = [];
  for (const { properties: p = {}, geometry } of features) {
    const [lon, lat] = geometry?.coordinates ?? [];
    if (EXCLUDED.has(String(p.countrycode).toUpperCase()) || !Number.isFinite(lat) || !Number.isFinite(lon)) continue;
    const label = p.street && p.housenumber ? `${p.street}, ${p.housenumber}` : p.street || p.name;
    if (!label) continue;
    const detail = [...new Set([p.name, p.district, p.city])].filter((part) => part && part !== label).join(", ");
    if (seen.has(label + detail)) continue;
    seen.add(label + detail);
    out.push({ label, detail, city: p.city ?? "", lat, lon });
  }
  // Стабільне сортування: місто форми — першим, решта в порядку Photon.
  return out.sort((a, b) => (b.city === city) - (a.city === city)).slice(0, LIMIT);
}

function answer(body, status = 200, cache = `public, max-age=${DAY}`) {
  return new Response(JSON.stringify(body), {
    status, headers: { "content-type": "application/json; charset=utf-8", "cache-control": status === 200 ? cache : "no-store", "x-content-type-options": "nosniff" },
  });
}
