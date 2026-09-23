// Edge Function `delete-account`: видалення акаунта з застосунку (Google Play Account deletion,
// App Store 5.1.1(v)). SQL-шлях не годиться: storage.protect_delete забороняє DELETE зі
// storage.objects напряму, а файли в S3 лишилися б сиротами. Тут — через Storage API.
//
// Контракт: POST /functions/v1/delete-account, Authorization: Bearer <access token користувача>,
// apikey: <publishable>, тіло порожнє або {}.
//   200 {"deleted":true} · 401 без/з недійсним токеном · 500 {"error":…}
//
// Порядок: спершу фото користувача в бакеті event-images (<uid>/…), потім auth.admin.deleteUser.
// Каскади FK у базі прибирають решту (профіль, участь, власні події з чатом, оцінки, токени, скарги).
// Якщо фото не видалились — акаунт не чіпаємо: повтор запиту доробить.
// SUPABASE_URL і SUPABASE_SERVICE_ROLE_KEY середовище дає саме; верифікація JWT на шлюзі увімкнена,
// а користувача все одно перевіряємо getUser — токен міг бути відкликаний.

import { createClient } from "npm:@supabase/supabase-js@2";

const BUCKET = "event-images";
const PAGE = 1000;

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

  try {
    await removeFiles(admin, user.id);
    const { error } = await admin.auth.admin.deleteUser(user.id);
    if (error) throw error;
    return json({ deleted: true });
  } catch (e) {
    console.error("delete-account failed", user.id, String(e));
    return json({ error: "delete failed" }, 500);
  }
});

// Шляхи — <uid>/<event_id>/<file>: list не рекурсивний, тож обходимо папки подій.
async function removeFiles(admin: ReturnType<typeof createClient>, uid: string) {
  const storage = admin.storage.from(BUCKET);
  const paths: string[] = [];
  for (const folder of await listAll(storage, uid)) {
    // Папка в list має id=null; файл просто в <uid>/ теж можливий — видаляємо і його.
    if (folder.id) { paths.push(`${uid}/${folder.name}`); continue; }
    for (const file of await listAll(storage, `${uid}/${folder.name}`)) {
      if (file.id) paths.push(`${uid}/${folder.name}/${file.name}`);
    }
  }
  for (let i = 0; i < paths.length; i += PAGE) {
    const { error } = await storage.remove(paths.slice(i, i + PAGE));
    if (error) throw error;
  }
}

async function listAll(storage: ReturnType<ReturnType<typeof createClient>["storage"]["from"]>, prefix: string) {
  const all: { name: string; id: string | null }[] = [];
  for (let offset = 0; ; offset += PAGE) {
    const { data, error } = await storage.list(prefix, { limit: PAGE, offset, sortBy: { column: "name", order: "asc" } });
    if (error) throw error;
    all.push(...(data ?? []));
    if (!data || data.length < PAGE) return all;
  }
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
