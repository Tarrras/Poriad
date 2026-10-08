// Edge Function `push`: тригери бази кличуть її на нове повідомлення в чаті, новий запит на
// участь чи приєднання до відкритої події, на скасування й перенесення події (docs/event-change-push.md),
// на нову подію організатора й зведення нових подій закладів та артистів (docs/follows.md).
// Вона вирішує, кому слати, бере токени й шле у FCM (Android) і APNs (iOS).
//
// Секрети функції (`supabase secrets set …`):
//   PUSH_SECRET           — той самий рядок, що у Vault як push_function_secret
//   FCM_SERVICE_ACCOUNT   — JSON сервісного акаунта Firebase (роль Firebase Cloud Messaging API Admin)
//   APNS_KEY              — вміст .p8 ключа APNs (PEM)
//   APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID
//   APNS_SANDBOX          — "true" лише для dev-збірок з Xcode; будь-що інше — production
// SUPABASE_URL і SUPABASE_SERVICE_ROLE_KEY середовище дає саме.

import { createClient } from "npm:@supabase/supabase-js@2";
import * as jose from "npm:jose@5";
import { artistText, organizerText, placeText, type ArtistLine, type EventLine, type PlaceLine } from "./follow_text.ts";

type Payload =
  | { type: "message"; message_id: string; event_id: string }
  | { type: "request" | "joined"; event_id: string; user_id: string }
  | { type: "event"; kind: EventKind; event_id: string }
  | { type: "follow"; kind: "organizer"; event_id: string }
  // Зведення `notify_place_follows`: одна людина, скільки нового, у скількох закладах і найближчі події.
  | { type: "follow"; kind: "place"; user_id: string; total: number; place_count: number; places: { id: string; n: number }[]; event_ids: string[] }
  // Те саме для артистів: `notify_artist_follows`.
  | { type: "follow"; kind: "artist"; user_id: string; total: number; artist_count: number; artists: { id: string; n: number }[]; event_ids: string[] };

type EventKind = "moved" | "cancelled";
const EVENT_KINDS: readonly string[] = ["moved", "cancelled"];

type Push = { kind: "chat" | "request" | "joined" | "organizer" | "place" | "artist" | EventKind; eventId?: string; placeId?: string; artistId?: string; title: string; body: string; key: string };
type Token = { token: string; platform: "android" | "ios" };

const PREVIEW = 120;
// Скільки запитів до провайдерів водночас і скільки чекати кожен: тригер кличе функцію
// через pg_net, і одна зависла відповідь APNs не має тримати розсилку решті.
const CONCURRENCY = 10;
const TIMEOUT_MS = 10_000;
// Скільки людей у одному запиті за токенами: id ідуть у рядок адреси, а їх може бути сотні.
const TOKEN_CHUNK = 100;

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method" }, 405);
  const secret = Deno.env.get("PUSH_SECRET");
  if (!secret || !sameSecret(req.headers.get("x-push-secret") ?? "", secret)) return json({ error: "forbidden" }, 403);

  let payload: Payload;
  try { payload = (await req.json()) as Payload; } catch { return json({ error: "bad json" }, 400); }
  if (!isPayload(payload)) return json({ error: "bad payload" }, 400);
  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  const { push, recipients } = payload.type === "message" ? await forMessage(db, payload)
    : payload.type === "event" ? await forEvent(db, payload)
    : payload.type === "follow" ? await forFollow(db, payload) : await forRequest(db, payload);
  if (!push || recipients.length === 0) return json({ sent: 0, reason: "no recipients" });

  const list: Token[] = [];
  for (let i = 0; i < recipients.length; i += TOKEN_CHUNK) {
    const { data: tokens } = await db.from("push_tokens").select("token,platform").in("user_id", recipients.slice(i, i + TOKEN_CHUNK));
    list.push(...((tokens ?? []) as Token[]));
  }
  if (list.length === 0) return json({ sent: 0, reason: "no tokens" });

  const stale: string[] = [];
  let sent = 0;
  // Пул з CONCURRENCY воркерів: беруть наступний токен зі спільного індексу.
  let next = 0;
  const worker = async () => {
    while (next < list.length) {
      const t = list[next++];
      try {
        const ok = t.platform === "android" ? await sendFcm(t.token, push) : await sendApns(t.token, push);
        if (ok === "stale") stale.push(t.token);
        else if (ok) sent++;
      } catch (e) {
        console.error("push failed", t.platform, String(e));
      }
    }
  };
  await Promise.all(Array.from({ length: Math.min(CONCURRENCY, list.length) }, worker));
  // Токени, які провайдер уже не знає, прибираємо: інакше вони лишаються назавжди.
  if (stale.length > 0) await db.from("push_tokens").delete().in("token", stale);
  return json({ sent, stale: stale.length, recipients: recipients.length });
});

// ---- Хто отримує

// Повідомлення: організатор і підтверджені учасники, крім автора й тих, хто заблокований з автором в будь-який бік.
async function forMessage(db: ReturnType<typeof createClient>, p: Extract<Payload, { type: "message" }>) {
  const { data: m } = await db.from("event_messages").select("id,event_id,author_id,body").eq("id", p.message_id).maybeSingle();
  if (!m) return { push: null, recipients: [] };
  const { data: e } = await db.from("events").select("id,title,organizer_id,status").eq("id", m.event_id).maybeSingle();
  if (!e || e.status !== "published") return { push: null, recipients: [] };
  const { data: author } = await db.from("profiles").select("display_name").eq("id", m.author_id).maybeSingle();
  const { data: members } = await db.from("event_members").select("user_id").eq("event_id", e.id).eq("status", "approved");
  const people = new Set<string>((members ?? []).map((r) => r.user_id as string));
  if (e.organizer_id) people.add(e.organizer_id as string);
  people.delete(m.author_id as string);
  const recipients = await withoutBlocked(db, [...people], m.author_id as string);
  const name = (author?.display_name as string | undefined)?.trim() || "Учасник";
  return {
    push: {
      kind: "chat" as const, eventId: e.id as string, title: e.title as string,
      body: `${name}: ${String(m.body).slice(0, PREVIEW)}`, key: m.id as string,
    },
    recipients,
  };
}

// Запит або приєднання до відкритої події: лише організатор.
async function forRequest(db: ReturnType<typeof createClient>, p: Extract<Payload, { type: "request" | "joined" }>) {
  const { data: e } = await db.from("events").select("id,title,organizer_id,status").eq("id", p.event_id).maybeSingle();
  if (!e || e.status !== "published" || !e.organizer_id || e.organizer_id === p.user_id) return { push: null, recipients: [] };
  const { data: who } = await db.from("profiles").select("display_name").eq("id", p.user_id).maybeSingle();
  const recipients = await withoutBlocked(db, [e.organizer_id as string], p.user_id);
  const name = (who?.display_name as string | undefined)?.trim() || "Хтось";
  return {
    push: {
      kind: p.type, eventId: e.id as string, title: e.title as string,
      body: p.type === "request" ? `${name} просить приєднатися` : `${name} приєднується до події`, key: `${e.id}:${p.user_id}`,
    },
    recipients,
  };
}

// Скасування й перенесення: підтверджені учасники, крім організатора й тих, хто заблокований з ним
// у будь-який бік.
async function forEvent(db: ReturnType<typeof createClient>, p: Extract<Payload, { type: "event" }>) {
  const { data: e } = await db.from("events").select("id,title,organizer_id,status,starts_at,time_zone").eq("id", p.event_id).maybeSingle();
  if (!e || !e.organizer_id || e.status !== (p.kind === "cancelled" ? "cancelled" : "published")) return { push: null, recipients: [] };
  const { data: members } = await db.from("event_members").select("user_id").eq("event_id", e.id).eq("status", "approved");
  const people = (members ?? []).map((r) => r.user_id as string).filter((id) => id !== e.organizer_id);
  const recipients = await withoutBlocked(db, people, e.organizer_id as string);
  const body = {
    moved: `Перенесено на ${when(e.starts_at as string, e.time_zone as string)}`,
    cancelled: "Подію скасовано",
  }[p.kind];
  // Ключ з часом: друге перенесення — нове сповіщення, а не тиха заміна першого.
  return { push: { kind: p.kind, eventId: e.id as string, title: e.title as string, body, key: `${e.id}:${p.kind}:${Date.now()}` }, recipients };
}

// Підписки. Організатор: його підписники, крім заблокованих з ним у будь-який бік. Заклади: одна людина,
// яку вже вибрала база (нове, ліміт на добу) — тут лише текст.
async function forFollow(db: ReturnType<typeof createClient>, p: Extract<Payload, { type: "follow" }>) {
  return p.kind === "organizer" ? forOrganizer(db, p) : p.kind === "artist" ? forArtists(db, p) : forPlaces(db, p);
}

// ponytail: підписників не більше 1000 — стільки віддає PostgREST за раз; більше — сторінками.
async function forOrganizer(db: ReturnType<typeof createClient>, p: Extract<Payload, { type: "follow"; kind: "organizer" }>) {
  const { data: e } = await db.from("events").select("id,title,organizer_id,status,origin,companion_of,starts_at,time_zone").eq("id", p.event_id).maybeSingle();
  // Супутник — не оголошення організатора, тригер його й не кличе; тут друга перевірка на випадок ручного виклику.
  if (!e || e.origin !== "community" || e.status !== "published" || !e.organizer_id || e.companion_of) return { push: null, recipients: [] };
  const { data: follows } = await db.from("follows").select("user_id").eq("target_kind", "organizer").eq("target_id", e.organizer_id);
  const people = (follows ?? []).map((r) => r.user_id as string).filter((id) => id !== e.organizer_id);
  const recipients = await withoutBlocked(db, people, e.organizer_id as string);
  const { data: who } = await db.from("profiles").select("display_name").eq("id", e.organizer_id).maybeSingle();
  const text = organizerText(e.title as string, ((who?.display_name as string | undefined) ?? "").trim(), when(e.starts_at as string, e.time_zone as string));
  return { push: { kind: "organizer" as const, eventId: e.id as string, title: text.title, body: text.body, key: `organizer:${e.id}` }, recipients };
}

async function forPlaces(db: ReturnType<typeof createClient>, p: Extract<Payload, { type: "follow"; kind: "place" }>) {
  const { data: rows } = await db.from("places").select("id,name").in("id", p.places.map((x) => x.id));
  const names = new Map((rows ?? []).map((r) => [r.id as string, r.name as string]));
  const places: PlaceLine[] = p.places.filter((x) => names.has(x.id)).map((x) => ({ id: x.id, name: names.get(x.id)!, n: x.n }));
  const { data: found } = await db.from("events").select("id,title,status,import_status,ends_at,starts_at,time_zone").in("id", p.event_ids);
  // Між прогоном бази й доставкою міг минути час: скасовану чи вже минулу подію не рекламуємо.
  const live = new Map((found ?? []).filter((e) => e.status === "published" && e.import_status !== "withdrawn" && new Date(e.ends_at as string).getTime() > Date.now()).map((e) => [e.id as string, e]));
  const events: EventLine[] = p.event_ids.filter((id) => live.has(id)).map((id) => {
    const e = live.get(id)!;
    return { id, title: e.title as string, when: when(e.starts_at as string, e.time_zone as string) };
  });
  const text = events.length > 0 ? placeText(p.total, p.place_count, places, events) : null;
  if (!text) return { push: null, recipients: [] };
  return {
    push: { kind: "place" as const, eventId: text.eventId, placeId: text.placeId, title: text.title, body: text.body, key: `place:${text.placeId}:${Date.now()}` },
    recipients: [p.user_id],
  };
}

async function forArtists(db: ReturnType<typeof createClient>, p: Extract<Payload, { type: "follow"; kind: "artist" }>) {
  const { data: rows } = await db.from("artists").select("id,name").in("id", p.artists.map((x) => x.id));
  const names = new Map((rows ?? []).map((r) => [r.id as string, r.name as string]));
  const artists: ArtistLine[] = p.artists.filter((x) => names.has(x.id)).map((x) => ({ id: x.id, name: names.get(x.id)!, n: x.n }));
  const { data: found } = await db.from("events").select("id,title,status,import_status,ends_at,starts_at,time_zone").in("id", p.event_ids);
  // Як для закладів: скасовану чи вже минулу подію між прогоном бази й доставкою не рекламуємо.
  const live = new Map((found ?? []).filter((e) => e.status === "published" && e.import_status !== "withdrawn" && new Date(e.ends_at as string).getTime() > Date.now()).map((e) => [e.id as string, e]));
  const events: EventLine[] = p.event_ids.filter((id) => live.has(id)).map((id) => {
    const e = live.get(id)!;
    return { id, title: e.title as string, when: when(e.starts_at as string, e.time_zone as string) };
  });
  const text = events.length > 0 ? artistText(p.total, p.artist_count, artists, events) : null;
  if (!text) return { push: null, recipients: [] };
  return {
    push: { kind: "artist" as const, eventId: text.eventId, artistId: text.artistId, title: text.title, body: text.body, key: `artist:${text.artistId}:${Date.now()}` },
    recipients: [p.user_id],
  };
}

function when(iso: string, zone: string): string {
  const opts: Intl.DateTimeFormatOptions = { weekday: "short", day: "numeric", month: "long", hour: "2-digit", minute: "2-digit" };
  try { return new Date(iso).toLocaleString("uk-UA", { ...opts, timeZone: zone }); } catch { return new Date(iso).toLocaleString("uk-UA", opts); }
}

async function withoutBlocked(db: ReturnType<typeof createClient>, people: string[], other: string): Promise<string[]> {
  if (people.length === 0) return [];
  const { data: blocks } = await db.from("user_blocks").select("user_id,blocked_id")
    .or(`user_id.eq.${other},blocked_id.eq.${other}`);
  const excluded = new Set<string>();
  for (const b of blocks ?? []) {
    excluded.add(b.user_id as string);
    excluded.add(b.blocked_id as string);
  }
  return people.filter((id) => !excluded.has(id));
}

// ---- Вхід: секрет порівнюємо за постійний час, тіло перевіряємо до будь-якого запиту в базу.

function sameSecret(given: string, expected: string): boolean {
  const a = new TextEncoder().encode(given), b = new TextEncoder().encode(expected);
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const isUuid = (v: unknown): v is string => typeof v === "string" && UUID.test(v);
const isCount = (v: unknown): v is number => Number.isInteger(v) && (v as number) >= 1 && (v as number) <= 100_000;

function isPayload(p: unknown): p is Payload {
  if (!p || typeof p !== "object") return false;
  const o = p as Record<string, unknown>;
  if (o.type === "message") return typeof o.message_id === "string" && UUID.test(o.message_id) && typeof o.event_id === "string" && UUID.test(o.event_id);
  if (o.type === "request" || o.type === "joined") return typeof o.event_id === "string" && UUID.test(o.event_id) && typeof o.user_id === "string" && UUID.test(o.user_id);
  if (o.type === "event") return typeof o.kind === "string" && EVENT_KINDS.includes(o.kind) && typeof o.event_id === "string" && UUID.test(o.event_id);
  if (o.type === "follow" && o.kind === "organizer") return isUuid(o.event_id);
  if (o.type === "follow" && o.kind === "place") {
    return isUuid(o.user_id) && isCount(o.total) && isCount(o.place_count)
      && Array.isArray(o.places) && o.places.length >= 1 && o.places.length <= 5
      && o.places.every((x) => !!x && typeof x === "object" && isUuid((x as Record<string, unknown>).id) && isCount((x as Record<string, unknown>).n))
      && Array.isArray(o.event_ids) && o.event_ids.length >= 1 && o.event_ids.length <= 3 && o.event_ids.every(isUuid);
  }
  if (o.type === "follow" && o.kind === "artist") {
    return isUuid(o.user_id) && isCount(o.total) && isCount(o.artist_count)
      && Array.isArray(o.artists) && o.artists.length >= 1 && o.artists.length <= 5
      && o.artists.every((x) => !!x && typeof x === "object" && isUuid((x as Record<string, unknown>).id) && isCount((x as Record<string, unknown>).n))
      && Array.isArray(o.event_ids) && o.event_ids.length >= 1 && o.event_ids.length <= 3 && o.event_ids.every(isUuid);
  }
  return false;
}

// ---- FCM HTTP v1 (Android). Лише data: застосунок сам малює сповіщення своїм каналом і веде на подію.

let fcmToken: { value: string; expires: number } | null = null;

async function fcmAccessToken(): Promise<{ token: string; project: string } | null> {
  const raw = Deno.env.get("FCM_SERVICE_ACCOUNT");
  if (!raw) return null;
  const account = JSON.parse(raw) as { client_email: string; private_key: string; project_id: string; token_uri?: string };
  if (fcmToken && fcmToken.expires > Date.now() + 60_000) return { token: fcmToken.value, project: account.project_id };
  const key = await jose.importPKCS8(account.private_key, "RS256");
  const assertion = await new jose.SignJWT({ scope: "https://www.googleapis.com/auth/firebase.messaging" })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(account.client_email)
    .setAudience(account.token_uri ?? "https://oauth2.googleapis.com/token")
    .setIssuedAt()
    .setExpirationTime("1h")
    .sign(key);
  const res = await fetch(account.token_uri ?? "https://oauth2.googleapis.com/token", {
    method: "POST",
    signal: AbortSignal.timeout(TIMEOUT_MS),
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
  });
  if (!res.ok) throw new Error(`fcm oauth ${res.status}: ${await res.text()}`);
  const body = await res.json() as { access_token: string; expires_in: number };
  fcmToken = { value: body.access_token, expires: Date.now() + body.expires_in * 1000 };
  return { token: body.access_token, project: account.project_id };
}

async function sendFcm(token: string, push: Push): Promise<boolean | "stale"> {
  const auth = await fcmAccessToken();
  if (!auth) { console.warn("FCM_SERVICE_ACCOUNT is not set; skipping android"); return false; }
  const res = await fetch(`https://fcm.googleapis.com/v1/projects/${auth.project}/messages:send`, {
    method: "POST",
    signal: AbortSignal.timeout(TIMEOUT_MS),
    headers: { Authorization: `Bearer ${auth.token}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      message: {
        token,
        // Лише задані поля: FCM приймає в data тільки рядки. Заклад — для пуша про кілька подій.
        data: {
          kind: push.kind, title: push.title, body: push.body, key: push.key,
          ...(push.eventId ? { eventId: push.eventId } : {}), ...(push.placeId ? { placeId: push.placeId } : {}),
          ...(push.artistId ? { artistId: push.artistId } : {}),
        },
        android: { priority: "high" },
      },
    }),
  });
  if (res.ok) return true;
  const text = await res.text();
  // «Мертвий» токен — лише UNREGISTERED або INVALID_ARGUMENT про сам токен. INVALID_ARGUMENT про
  // payload (задовге тіло, не-рядок у data) не привід стерти всі Android-токени за один прохід.
  let code = "", message = "";
  try { const err = JSON.parse(text)?.error; code = err?.details?.find((d: { errorCode?: string }) => d.errorCode)?.errorCode ?? ""; message = err?.message ?? ""; } catch { /* не JSON */ }
  if (res.status === 404 || code === "UNREGISTERED" || (code === "INVALID_ARGUMENT" && /registration token/i.test(message))) return "stale";
  throw new Error(`fcm ${res.status}: ${text}`);
}

// ---- APNs (iOS). Alert-пуш: систему малює сама, тап веде на подію через userInfo.

const APNS_TOKEN = /^[0-9a-f]{64,200}$/i;

let apnsJwt: { value: string; issued: number } | null = null;

async function apnsAuth(): Promise<{ jwt: string; topic: string; host: string } | null> {
  const key = Deno.env.get("APNS_KEY"), keyId = Deno.env.get("APNS_KEY_ID"), teamId = Deno.env.get("APNS_TEAM_ID"), topic = Deno.env.get("APNS_BUNDLE_ID");
  if (!key || !keyId || !teamId || !topic) return null;
  // Apple приймає токен до години; оновлюємо кожні 40 хвилин.
  if (!apnsJwt || Date.now() - apnsJwt.issued > 40 * 60_000) {
    const pk = await jose.importPKCS8(key.replace(/\\n/g, "\n"), "ES256");
    const jwt = await new jose.SignJWT({}).setProtectedHeader({ alg: "ES256", kid: keyId }).setIssuer(teamId).setIssuedAt().sign(pk);
    apnsJwt = { value: jwt, issued: Date.now() };
  }
  // Production за замовчуванням: забутий секрет на проді не має слати TestFlight/App Store-токени в sandbox.
  const sandbox = Deno.env.get("APNS_SANDBOX") === "true";
  return { jwt: apnsJwt.value, topic, host: sandbox ? "https://api.sandbox.push.apple.com" : "https://api.push.apple.com" };
}

async function sendApns(token: string, push: Push): Promise<boolean | "stale"> {
  const auth = await apnsAuth();
  if (!auth) { console.warn("APNS_* are not set; skipping ios"); return false; }
  // Токен іде в шлях URL: лише hex, інакше це не токен APNs, а спроба підмінити запит.
  if (!APNS_TOKEN.test(token)) { console.warn("invalid apns token format; skipping"); return false; }
  const res = await fetch(`${auth.host}/3/device/${token}`, {
    method: "POST",
    signal: AbortSignal.timeout(TIMEOUT_MS),
    headers: {
      authorization: `bearer ${auth.jwt}`,
      "apns-topic": auth.topic,
      "apns-push-type": "alert",
      "apns-priority": "10",
      // Зміна події — окрема група: повідомлення чату не має витіснити «подію скасовано». Новіший пуш про
      // ті самі заклади заміняє попередній.
      "apns-collapse-id": push.kind === "place" ? `place:${push.placeId}` : push.kind === "artist" ? `artist:${push.artistId}` : EVENT_KINDS.includes(push.kind) ? `${push.eventId}:state` : push.eventId!,
    },
    body: JSON.stringify({
      aps: { alert: { title: push.title, body: push.body }, sound: "default", "thread-id": push.eventId ?? (push.artistId ? `artist:${push.artistId}` : `place:${push.placeId}`) },
      kind: push.kind, eventId: push.eventId, placeId: push.placeId, artistId: push.artistId, key: push.key,
    }),
  });
  if (res.ok) return true;
  const text = await res.text();
  // Лише 410 / Unregistered — токен мертвий. BadDeviceToken означає розбіжність середовищ
  // (sandbox ↔ production): стерти токен тут — втратити справний пристрій через конфіг.
  if (res.status === 410 || text.includes("Unregistered")) return "stale";
  throw new Error(`apns ${res.status}: ${text}`);
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
