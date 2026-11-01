// Листи замість пушів тим, у кого нема застосунку (docs/organizers-1.5.md, 1.1 «Листи» і 1.2 «Сповіщення організатору
// без застосунку»). Текст — той самий, що в пуші; лист додає кнопку й підвал «чому ви це отримали». Окремо від
// index.ts: чиста логіка без Deno й мережі, тож її перевіряє `node supabase/functions/push/mail_text.test.mjs`.

export type MailKind = "request" | "question" | "approved" | "declined" | "promoted" | "moved" | "cancelled" | "organizer";
export const MAIL_KINDS: readonly string[] = ["request", "question", "approved", "declined", "promoted", "moved", "cancelled", "organizer"];

export type Mail = { subject: string; html: string; text: string };

const SITE = "https://poriad.app";
const SUBJECT_MAX = 150;

export function esc(s: string): string {
  return s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);
}

/**
 * [title] і [body] — заголовок і текст пуша (заголовок — назва події), [who] — імʼя організатора для «Стежити».
 * Організатору (запит, питання) — кнопка в кабінет; учаснику — на сторінку події, де можна скасувати запис.
 */
export function mailText(kind: MailKind, eventId: string, title: string, body: string, who = ""): Mail {
  const page = `${SITE}/e/${eventId}`;
  const organizer = kind === "request" || kind === "question";
  const button = organizer ? { label: "Переглянути", url: `${SITE}/kabinet#/e/${eventId}` } : { label: "Відкрити подію", url: page };
  // Відповісти з вебу в першій версії не можна (1.2).
  const note = kind === "question" ? "Відповісти можна в застосунку «Поряд»." : "";
  const why = organizer ? `Ви отримали цей лист, бо організовуєте «${title}».`
    : kind === "organizer" ? `Ви отримали цей лист, бо стежите за ${who || "організатором"}.`
    : kind === "declined" ? `Ви отримали цей лист, бо надіслали запит на «${title}».`
    : `Ви отримали цей лист, бо записались на «${title}».`;
  // Скасовувати нема чого, коли запит не прийняли чи подію скасовано.
  const link = kind === "organizer" ? { label: "Не стежити", url: `${page}?unfollow` }
    : kind === "approved" || kind === "promoted" || kind === "moved" ? { label: "Скасувати запис", url: page } : null;

  const oneLine = `«${title}»: ${body}`.replace(/\s+/g, " ").trim();
  const subject = oneLine.length <= SUBJECT_MAX ? oneLine : `${oneLine.slice(0, SUBJECT_MAX - 1).trimEnd()}…`;
  const text = [title, body, ...(note ? [note] : []), `${button.label}: ${button.url}`, "", "—", why,
    ...(link ? [`${link.label}: ${link.url}`] : [])].join("\n");
  const p = (s: string, style = "") => `<p style="margin:0 0 16px;${style}">${esc(s)}</p>`;
  const html = `<!doctype html><html lang="uk"><body style="margin:0;padding:24px;background:#ffffff;color:#1a1a1a;font:16px/1.5 -apple-system,Segoe UI,Roboto,sans-serif">
<div style="max-width:520px">
${p(title, "font-size:20px;font-weight:600")}
${p(body)}
${note ? p(note) : ""}<p style="margin:0 0 32px"><a href="${esc(button.url)}" style="display:inline-block;padding:12px 20px;background:#1a1a1a;color:#ffffff;border-radius:8px;text-decoration:none">${esc(button.label)}</a></p>
<p style="margin:0;color:#666666;font-size:13px">${esc(why)}${link ? ` <a href="${esc(link.url)}" style="color:#666666">${esc(link.label)}</a>` : ""}</p>
</div>
</body></html>`;
  return { subject, html, text };
}
