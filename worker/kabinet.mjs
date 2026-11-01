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
// організатор, який набирає адресу по літері, не впирався в його ліміти.
const PHOTON = "https://photon.komoot.io/api/";
const USER_AGENT = "PoriadBot/0.1 (+https://poriad.app/bot; hello@poriad.app)";
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
  // Кожен новий запит іде в komoot, а той за зловживання блокує наш User-Agent для всіх. Тож повз кеш — не більше
  // ліміту на адресу (GEOCODE_LIMIT у wrangler.toml, у межах однієї локації Cloudflare). Без binding-а — без ліміту.
  const limited = env.GEOCODE_LIMIT && !(await env.GEOCODE_LIMIT.limit({ key: request.headers.get("cf-connecting-ip") ?? "local" })).success;
  if (limited) return answer({ error: "rate" }, 429);
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
