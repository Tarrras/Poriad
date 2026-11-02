// Файли людини в Storage, які видаляє `delete-account`: фото й відео її подій та аватари в теці `<uid>/` обох бакетів
// (App Store 5.1.1(v), GDPR). Без імпортів Deno: клієнт Storage приходить параметром, перевірка — node files.test.mjs поруч.

export const BUCKETS = ["event-images", "event-videos"];
const PAGE = 1000;

type Entry = { name: string; id: string | null };
type Bucket = {
  list(prefix: string, options: { limit: number; offset: number; sortBy: { column: string; order: string } }): Promise<{ data: Entry[] | null; error: unknown }>;
  remove(paths: string[]): Promise<{ error: unknown }>;
};

/**
 * Шляхи — <uid>/<event_id або avatar>/<file>, але RLS пускає й глибше (<uid>/<event>/a/b.jpg), а list не рекурсивний:
 * обходимо кожну папку до дна. Збій — виняток, акаунт лишається.
 */
export async function removeUserFiles(from: (bucket: string) => Bucket, uid: string): Promise<number> {
  let removed = 0;
  for (const bucket of BUCKETS) {
    const storage = from(bucket);
    const paths = await filesUnder(storage, uid);
    for (let i = 0; i < paths.length; i += PAGE) {
      const { error } = await storage.remove(paths.slice(i, i + PAGE));
      if (error) throw error;
    }
    removed += paths.length;
  }
  return removed;
}

// Папка в list має id=null, файл — id.
async function filesUnder(storage: Bucket, prefix: string): Promise<string[]> {
  const paths: string[] = [];
  for (const entry of await listAll(storage, prefix)) {
    if (entry.id) paths.push(`${prefix}/${entry.name}`);
    else paths.push(...await filesUnder(storage, `${prefix}/${entry.name}`));
  }
  return paths;
}

async function listAll(storage: Bucket, prefix: string) {
  const all: Entry[] = [];
  for (let offset = 0; ; offset += PAGE) {
    const { data, error } = await storage.list(prefix, { limit: PAGE, offset, sortBy: { column: "name", order: "asc" } });
    if (error) throw error;
    all.push(...(data ?? []));
    if (!data || data.length < PAGE) return all;
  }
}
