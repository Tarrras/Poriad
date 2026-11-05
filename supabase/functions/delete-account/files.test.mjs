// Видалення файлів людини без Deno й мережі: node supabase/functions/delete-account/files.test.mjs
import assert from "node:assert/strict";
import { removeUserFiles } from "./files.ts";

// Підробний Storage: плоский список шляхів на бакет, list віддає один рівень, як справжній.
function fake(files, failRemove = null) {
  const removed = {};
  const from = (bucket) => ({
    async list(prefix, { limit, offset }) {
      const level = new Map();
      for (const path of files[bucket] ?? []) {
        if (!path.startsWith(`${prefix}/`)) continue;
        const [head, ...rest] = path.slice(prefix.length + 1).split("/");
        level.set(head, rest.length ? null : `id-${path}`);
      }
      const all = [...level].sort(([a], [b]) => a.localeCompare(b)).map(([name, id]) => ({ name, id }));
      return { data: all.slice(offset, offset + limit), error: null };
    },
    async remove(paths) {
      if (bucket === failRemove) return { error: new Error("storage down") };
      (removed[bucket] ??= []).push(...paths);
      return { error: null };
    },
  });
  return { from, removed };
}

const files = {
  "event-images": ["u1/e1/cover.jpg", "u1/e1/poster.jpg", "u1/e1/a/b/deep.jpg", "u1/avatar/a.jpg", "u1/loose.jpg", "u2/e9/other.jpg"],
  "event-videos": ["u1/e1/clip.mp4", "u1/e2/long.mp4", "u2/e9/other.mp4"],
  // Скріншоти оплати (20261125130000): теж у теці людини, у чужій події.
  "payment-proofs": ["u1/e9/proof.jpg", "u2/e1/their.jpg"],
};
const s = fake(files);
assert.equal(await removeUserFiles(s.from, "u1"), 8);
assert.deepEqual(s.removed["payment-proofs"], ["u1/e9/proof.jpg"], "payment screenshots go too, other people's stay");
assert.deepEqual(s.removed["event-images"].sort(), ["u1/avatar/a.jpg", "u1/e1/a/b/deep.jpg", "u1/e1/cover.jpg", "u1/e1/poster.jpg", "u1/loose.jpg"],
  "deeper folders too: RLS allows them");
assert.deepEqual(s.removed["event-videos"].sort(), ["u1/e1/clip.mp4", "u1/e2/long.mp4"], "videos go too");
assert.ok(![...s.removed["event-images"], ...s.removed["event-videos"]].some((p) => p.startsWith("u2/")), "someone else's files stay");

// Сторінки list по 1000: тека з 1500 відео — усі.
const many = fake({ "event-videos": Array.from({ length: 1500 }, (_, i) => `u1/e1/v${i}.mp4`) });
assert.equal(await removeUserFiles(many.from, "u1"), 1500);

// Збій видалення — виняток: функція не видаляє акаунт, повтор запиту доробить.
await assert.rejects(removeUserFiles(fake(files, "event-videos").from, "u1"), /storage down/);

console.log("files: ok");
