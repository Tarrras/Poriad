// Edge Function `delete-account`: видалення акаунта з застосунку (Google Play Account deletion,
// App Store 5.1.1(v)). SQL-шлях не годиться: storage.protect_delete забороняє DELETE зі
// storage.objects напряму, а файли в S3 лишилися б сиротами. Тут — через Storage API.
//
// Контракт: POST /functions/v1/delete-account, Authorization: Bearer <access token користувача>,
// apikey: <publishable>, тіло {"password": "…"} для акаунта з поштою і/або {"apple_authorization_code": "…"} —
// свіжий код Sign in with Apple: з ним спершу відкликаємо токени Apple (5.1.1(v)), best effort — див. apple.ts.
// Акаунт з поштою без пароля (вхід кодом з пошти) замість пароля входить кодом ще раз: вхід не старший за 10 хв
// (claim `amr` токена, reauth.ts) теж підтверджує.
//   200 {"deleted":true} · 401 без/з недійсним токеном · 403 {"error":"password"} · 409 {"error":"paid_events"} — спершу
//   скасувати онлайн-події, на які записались · 500 {"error":…}
//
// Порядок: спершу фото й відео користувача в бакетах event-images і event-videos (<uid>/…, files.ts), потім
// auth.admin.deleteUser. Каскади FK у базі прибирають решту (профіль, участь, власні події з чатом, оцінки, токени,
// скарги). Якщо файли не видалились — акаунт не чіпаємо: повтор запиту доробить.
// SUPABASE_URL і SUPABASE_SERVICE_ROLE_KEY середовище дає саме; верифікація JWT на шлюзі увімкнена,
// а користувача все одно перевіряємо getUser — токен міг бути відкликаний.

import { createClient } from "npm:@supabase/supabase-js@2.118.0";
import { revokeApple } from "./apple.ts";
import { removeUserFiles } from "./files.ts";
import { freshLogin, needsReauth } from "./reauth.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204 });
  if (req.method !== "POST") return json({ error: "method" }, 405);
  const token = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "").trim();
  if (!token) return json({ error: "unauthorized" }, 401);

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: { user }, error: authError } = await admin.auth.getUser(token);
  if (authError || !user) return json({ error: "unauthorized" }, 401);
  const body = await req.json().catch(() => null);
  const appleCode = typeof body?.apple_authorization_code === "string" ? body.apple_authorization_code : null;
  // Пароль чи свіжий вхід перевіряємо тут, а не лише в застосунку: інакше чужий токен доступу (викрадений, з бекапу)
  // видаляє акаунт.
  if (needsReauth(user.app_metadata?.providers ?? []) && !freshLogin(token, Date.now() / 1000)) {
    const password = typeof body?.password === "string" ? body.password : "";
    if (!user.email || !password || !(await passwordOk(user.email, password))) return json({ error: "password" }, 403);
  }

  // Оплата онлайн: організатор спершу скасовує події, на які записались, а розмови про оплату лишаються доказом на 180
  // днів (prepare_account_deletion, 20261125170000_pay_online_safety). До Apple й файлів: відмова нічого не чіпає.
  const { error: held } = await admin.rpc("prepare_account_deletion", { p_user: user.id });
  if (held?.message?.includes("PAID_EVENTS_ACTIVE")) return json({ error: "paid_events" }, 409);
  // Сервер без міграції (PGRST202) — видаляємо як раніше.
  if (held && held.code !== "PGRST202") {
    console.error("delete-account prepare failed", user.id, held.message);
    return json({ error: "delete failed" }, 500);
  }

  try {
    if (appleCode && user.app_metadata?.providers?.includes("apple")) await revokeAppleTokens(user.id, appleCode);
    await removeUserFiles((bucket) => admin.storage.from(bucket), user.id);
    const { error } = await admin.auth.admin.deleteUser(user.id);
    if (error) throw error;
    return json({ deleted: true });
  } catch (e) {
    console.error("delete-account failed", user.id, String(e));
    return json({ error: "delete failed" }, 500);
  }
});

// Вхід паролем створює зайву сесію, але за мить її прибирає видалення користувача.
async function passwordOk(email: string, password: string): Promise<boolean> {
  const res = await fetch(`${Deno.env.get("SUPABASE_URL")}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, "Content-Type": "application/json" },
    body: JSON.stringify({ email, password }),
  });
  await res.body?.cancel();
  return res.ok;
}

// Відкликання не тримає людину в акаунті: прострочений код чи незаданий ключ — лише в лог.
// Клієнт Apple — bundle id середовища (APNS_BUNDLE_ID), команда — та сама, що для пушів.
async function revokeAppleTokens(uid: string, code: string) {
  const teamId = Deno.env.get("APNS_TEAM_ID"), clientId = Deno.env.get("APNS_BUNDLE_ID");
  const keyId = Deno.env.get("APPLE_SIWA_KEY_ID"), key = Deno.env.get("APPLE_SIWA_KEY");
  if (!teamId || !clientId || !keyId || !key) return console.error("apple revoke skipped: APPLE_SIWA_* or APNS_* not set", uid);
  try {
    await revokeApple(code, { teamId, clientId, keyId, key });
    console.log("apple tokens revoked", uid);
  } catch (e) {
    console.error("apple revoke failed", uid, String(e));
  }
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
