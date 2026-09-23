// Edge Function `push`: тригери бази кличуть її на нове повідомлення в чаті й новий запит на
// участь. Вона вирішує, кому слати, бере токени й шле у FCM (Android) і APNs (iOS).
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

type Payload =
  | { type: "message"; message_id: string; event_id: string }
  | { type: "request"; event_id: string; user_id: string };

type Push = { kind: "chat" | "request"; eventId: string; title: string; body: string; key: string };
type Token = { token: string; platform: "android" | "ios" };

const PREVIEW = 120;
// Скільки запитів до провайдерів водночас і скільки чекати кожен: тригер кличе функцію
// через pg_net, і одна зависла відповідь APNs не має тримати розсилку решті.
const CONCURRENCY = 10;
const TIMEOUT_MS = 10_000;

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method" }, 405);
  const secret = Deno.env.get("PUSH_SECRET");
  if (!secret || !sameSecret(req.headers.get("x-push-secret") ?? "", secret)) return json({ error: "forbidden" }, 403);

  let payload: Payload;
  try { payload = (await req.json()) as Payload; } catch { return json({ error: "bad json" }, 400); }
  if (!isPayload(payload)) return json({ error: "bad payload" }, 400);
  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  const { push, recipients } = payload.type === "message" ? await forMessage(db, payload) : await forRequest(db, payload);
  if (!push || recipients.length === 0) return json({ sent: 0, reason: "no recipients" });

  const { data: tokens } = await db.from("push_tokens").select("token,platform").in("user_id", recipients);
  const list = (tokens ?? []) as Token[];
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

// Запит: лише організатор.
async function forRequest(db: ReturnType<typeof createClient>, p: Extract<Payload, { type: "request" }>) {
  const { data: e } = await db.from("events").select("id,title,organizer_id,status").eq("id", p.event_id).maybeSingle();
  if (!e || e.status !== "published" || !e.organizer_id) return { push: null, recipients: [] };
  const { data: who } = await db.from("profiles").select("display_name").eq("id", p.user_id).maybeSingle();
  const recipients = await withoutBlocked(db, [e.organizer_id as string], p.user_id);
  const name = (who?.display_name as string | undefined)?.trim() || "Хтось";
  return {
    push: { kind: "request" as const, eventId: e.id as string, title: e.title as string, body: `${name} просить приєднатися`, key: `${e.id}:${p.user_id}` },
    recipients,
  };
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

function isPayload(p: unknown): p is Payload {
  if (!p || typeof p !== "object") return false;
  const o = p as Record<string, unknown>;
  if (o.type === "message") return typeof o.message_id === "string" && UUID.test(o.message_id) && typeof o.event_id === "string" && UUID.test(o.event_id);
  if (o.type === "request") return typeof o.event_id === "string" && UUID.test(o.event_id) && typeof o.user_id === "string" && UUID.test(o.user_id);
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
        data: { kind: push.kind, eventId: push.eventId, title: push.title, body: push.body, key: push.key },
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
      "apns-collapse-id": push.eventId.slice(0, 64),
    },
    body: JSON.stringify({
      aps: { alert: { title: push.title, body: push.body }, sound: "default", "thread-id": push.eventId },
      kind: push.kind, eventId: push.eventId, key: push.key,
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
