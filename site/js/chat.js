// Розмова з організатором — спільне для сторінки події (join.js) і кабінету (kabinet.js, «Розмови з учасниками»):
// повідомлення, скріншоти оплати з приватного бакета, стрічка з опитуванням і JPEG з файлу (скріншот, фото події,
// аватар). Правила без DOM — експорти, перевірка — `node tools/join_test.mjs`.
import { rpc, upload, download } from "./auth.js?v=17";
import { esc } from "./poriad.js?v=17";

// ---- Повідомлення

const TIME = new Intl.DateTimeFormat("uk-UA", { timeZone: "Europe/Kyiv", hour: "2-digit", minute: "2-digit" });
const DAY_TIME = new Intl.DateTimeFormat("uk-UA", { timeZone: "Europe/Kyiv", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });

/**
 * Повідомлення розмови. Текст — лише текстом: посилання не клікаються, бо в розмові може писати будь-хто. Під
 * реквізитами від організатора — застереження й «Поскаржитись» (docs/organizer-events.md): воно для того, хто платить,
 * тож сам організатор його не бачить.
 */
export function bubble(m, me, organizer, now = new Date()) {
  const mine = m.author_id === me;
  const who = mine ? "Ви" : m.author_id === organizer ? "Організатор" : m.author_name || "Учасник";
  const at = new Date(m.created_at);
  const when = (at.toDateString() === now.toDateString() ? TIME : DAY_TIME).format(at);
  const note = m.payment_details && m.author_id === organizer && me !== organizer
    ? `<p class="pay-warn">Реквізити для оплати. «Поряд» не приймає оплату й не відповідає за неї — не переказуйте гроші, якщо сумніваєтесь в організаторі. <button class="link" type="button" data-report="${esc(m.id)}">Поскаржитись</button></p>`
    : "";
  // Скріншот оплати — з приватного бакета: `src` ставить hydrateProofs із токеном, тут лише шлях.
  const image = m.image ? `<button class="proof" type="button" data-proof-open><img alt="Скріншот оплати" data-proof-path="${esc(m.image)}"></button>` : "";
  return `<div class="msg${mine ? " mine" : ""}" data-id="${esc(m.id)}"><small>${esc(who)} · ${esc(when)}</small>${image}<p>${esc(m.body)}</p>${note}</div>`;
}

// ---- Скріншоти оплати. Шлях — `<uid>/<подія>/<uuid>.jpg` і не змінюється, тож кожен файл вантажимо раз за сторінку
// (blob: URL), а не на кожне відкриття розмови. Вихід з акаунта — `forgetProofs`.

const PROOFS = "payment-proofs";
const proofs = new Map(); // шлях → Promise<blob: URL>

function proofUrl(path) {
  if (!proofs.has(path)) {
    proofs.set(path, download(PROOFS, path).then((blob) => URL.createObjectURL(blob)).catch((e) => {
      proofs.delete(path); // збій мережі — наступне відкриття спробує ще раз
      throw e;
    }));
  }
  return proofs.get(path);
}
/** Щойно вивантажений скріншот: показати з памʼяті, без другого завантаження. */
function rememberProof(path, blob) {
  proofs.set(path, Promise.resolve(URL.createObjectURL(blob)));
}
export function forgetProofs() {
  for (const url of proofs.values()) url.then((u) => URL.revokeObjectURL(u), () => {});
  proofs.clear();
}

/** Скріншоти в `root`: `src` — blob: з токеном людини. Недоступний — підпис замість картинки. */
export function hydrateProofs(root) {
  for (const img of root.querySelectorAll("img[data-proof-path]:not([data-loading])")) {
    img.dataset.loading = "1";
    proofUrl(img.dataset.proofPath)
      .then((url) => { img.src = url; })
      .catch(() => { img.closest("[data-proof-open]")?.replaceWith(Object.assign(document.createElement("small"), { textContent: "Скріншот недоступний" })); });
  }
}
/** Тап на скріншот — повністю в новій вкладці: звірити суму й імʼя з банком. true — це був скріншот. */
export function openProof(event) {
  const src = event.target.closest("[data-proof-open]")?.querySelector("img")?.src;
  if (src) window.open(src, "_blank", "noopener");
  return Boolean(src);
}

/** Скріншот оплати: JPEG у приватний бакет, потім повідомлення з ним. Порожній текст — «Скріншот оплати» (`ChatRules.PROOF_BODY`). */
export async function sendProof({ event, me, file, body }) {
  if (!file.type.startsWith("image/")) throw Object.assign(new Error("not an image"), { code: "NOT_IMAGE" });
  const blob = await jpegFile(file);
  const path = `${me}/${event}/${crypto.randomUUID()}.jpg`;
  await upload(PROOFS, path, blob);
  rememberProof(path, blob);
  await rpc("send_message", { p_event_id: event, p_body: body || "Скріншот оплати", p_thread: me, p_image: path });
}

// ---- Стрічка

/**
 * Стрічка розмови в `box`: спершу останні 100, далі — лише нове (`p_after`), раз на 8 с, поки `alive()`. У прихованій
 * вкладці не опитуємо, а повернувшись — одразу дочитуємо. Нове — позначаємо прочитаним. `empty` — розмітка порожньої
 * розмови.
 */
export function threadFeed(box, { empty, alive }) {
  let at = null; // { event, thread, me, organizer }
  let last = null, ids = new Set(), timer = null;

  async function load() {
    const was = at;
    if (!was) return;
    const rows = (await rpc("event_messages", { p_event_id: was.event, p_after: last, p_limit: 100, p_thread: was.thread })) ?? [];
    if (at !== was) return; // поки чекали, відкрили іншу розмову чи вийшли
    const fresh = rows.filter((m) => !ids.has(m.id));
    if (!fresh.length) {
      if (!box.children.length) box.innerHTML = empty;
      return;
    }
    box.querySelector("[data-empty]")?.remove();
    for (const m of fresh) ids.add(m.id);
    const now = new Date();
    box.insertAdjacentHTML("beforeend", fresh.map((m) => bubble(m, was.me, was.organizer, now)).join(""));
    hydrateProofs(box);
    last = fresh.at(-1).created_at;
    box.scrollTop = box.scrollHeight;
    rpc("mark_chat_read", { p_event_id: was.event, p_thread: was.thread }).catch(() => {});
  }
  function stop() {
    clearTimeout(timer);
    timer = null;
  }
  /** Наступне читання — через 8 с після попереднього: на повільній мережі запити не накладаються. */
  function schedule() {
    stop();
    timer = setTimeout(async () => {
      if (!alive()) return void (timer = null);
      if (!document.hidden) await load().catch(() => {});
      if (timer) schedule();
    }, 8000);
  }
  globalThis.document?.addEventListener("visibilitychange", () => { if (!document.hidden && timer && alive()) load().catch(() => {}); });

  return {
    /** Відкрити розмову: та сама — дочитати нове, інша — з початку. */
    async show(next) {
      const same = at && at.event === next.event && at.thread === next.thread && at.me === next.me;
      if (!same) {
        at = next;
        last = null;
        ids = new Set();
        box.innerHTML = "";
      }
      await load();
      schedule();
    },
    load,
    stop,
    /** Вихід з акаунта: на спільному компʼютері розмова не лишається на сторінці. */
    clear() {
      stop();
      at = null;
      box.innerHTML = "";
    },
  };
}

// ---- JPEG з файлу: перекодування заодно прибирає метадані (EXIF з геолокацією теж), як `pickedJPEG` у застосунку.

/** Фото подій і скріншоти: довша сторона до 2048, до 5 МБ. */
export const PHOTO = { side: 2048, bytes: 5 * 1024 * 1024 };

/** Розмір кадру з довшою стороною до `max`. */
export function fit(width, height, max = PHOTO.side) {
  const k = Math.min(1, max / Math.max(width, height));
  return [Math.round(width * k), Math.round(height * k)];
}
export const jpeg = (source, [width, height], quality) => new Promise((resolve, reject) => {
  const canvas = Object.assign(document.createElement("canvas"), { width, height });
  canvas.getContext("2d").drawImage(source, 0, 0, width, height);
  canvas.toBlob((blob) => (blob ? resolve(blob) : reject(new Error("Не вдалося додати цей файл"))), "image/jpeg", quality);
});
/**
 * Файл → JPEG до `side` і `bytes`: якість знижуємо, поки не влізе. createImageBitmap, а не <img>.decode(): decode у
 * фоновій вкладці може не завершитись; поворот з EXIF — як у браузера.
 */
export async function jpegFile(file, { side = PHOTO.side, bytes = PHOTO.bytes, qualities = [0.86, 0.75, 0.6] } = {}) {
  const bitmap = await createImageBitmap(file).catch(() => { throw Object.assign(new Error("Не вдалося відкрити це фото"), { code: "NOT_IMAGE" }); });
  try {
    const size = fit(bitmap.width, bitmap.height, side);
    for (const quality of qualities) {
      const blob = await jpeg(bitmap, size, quality);
      if (blob.size <= bytes) return blob;
    }
    throw Object.assign(new Error("Фото завелике навіть після стиснення"), { code: "TOO_BIG" });
  } finally {
    bitmap.close();
  }
}
