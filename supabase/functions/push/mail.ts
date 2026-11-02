// Кому пуш на пристрій, кому лист, і що в листі — тим, у кого нема застосунку (docs/organizers-1.5.md, 1.1 «Листи» і
// 1.2 «Сповіщення організатору без застосунку»). Текст — той самий, що в пуші (крім питання); лист додає кнопку й підвал
// «чому ви це отримали». Окремо від index.ts: чиста логіка без Deno й мережі, тож її перевіряє
// `node supabase/functions/push/mail.test.mjs`.

export type MailKind = "request" | "question" | "approved" | "declined" | "promoted" | "moved" | "cancelled" | "organizer";
export const MAIL_KINDS: readonly string[] = ["request", "question", "approved", "declined", "promoted", "moved", "cancelled", "organizer"];
// Пуші, які випущені клієнти не покажуть (Android невідомий kind мовчки відкидає): лише на токени з прапорцем
// `push_tokens.features`, який реєструє застосунок, що їх знає.
const FEATURE: Record<string, string> = { companion: "companion", company: "company", approved: "decision", declined: "decision", promoted: "decision" };

export type TokenRow = { token: string; platform: "android" | "ios"; user_id: string; features: string[] };
type Routed = { kind: string; threadId?: string; change?: string };

/**
 * [tokens] — усі токени [recipients]. Людина з будь-яким пристроєм листа не отримує, навіть якщо її застосунок цього
 * виду ще не знає. Питання листом — лише організатору: відповідь організатора учаснику (threadId — це він) лишається
 * в застосунку. Зміна афіші (change) — тим, хто її зберіг у застосунку, а листом — лише спільнотна подія, куди записались.
 */
export function route(push: Routed, recipients: string[], tokens: TokenRow[]) {
  const feature = FEATURE[push.kind];
  const withDevice = new Set(tokens.map((t) => t.user_id));
  const devices = tokens.filter((t) => !feature || t.features.includes(feature)).map(({ token, platform }) => ({ token, platform }));
  const mailTo = MAIL_KINDS.includes(push.kind) && !push.change
    ? recipients.filter((id) => !withDevice.has(id) && !(push.kind === "question" && id === push.threadId))
    : [];
  return { devices, mailTo };
}

export type Mail = { subject: string; html: string; text: string };

const SITE = "https://poriad.app";
const SUBJECT_MAX = 150;

// Word joiner (U+2060) після кожної крапки: «Run.Club» чи «evil.com» у назві або імені поштовий клієнт інакше робить
// посиланням у листі з нашої адреси. Людина бачить той самий текст.
export function unlink(s: string): string {
  return s.replace(/\./g, ".\u2060");
}

export function esc(s: string): string {
  return s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);
}

/**
 * [title] і [body] — заголовок і текст пуша (заголовок — назва події), [who] — імʼя організатора для «Стежити».
 * Організатору (запит, питання) — кнопка в кабінет; учаснику — на сторінку події, де можна скасувати запис.
 * Організатору — фіксованим текстом, без імені й слів запитувача: лист іде з нашої адреси, і чужий текст у ньому —
 * готовий фішинг. Ім'я він побачить у кабінеті. Рядки від людей (назва, імена в тексті пуша) у тілі листа —
 * без посилань ([unlink]); тема лишається як є: її поштові клієнти посиланнями не роблять.
 */
export function mailText(kind: MailKind, eventId: string, title: string, body: string, who = ""): Mail {
  const page = `${SITE}/e/${eventId}`;
  const organizer = kind === "request" || kind === "question";
  const lineOf = (t: string, b: string) => kind === "question" ? `Вам поставили питання про «${t}»` : kind === "request" ? `Нова заявка на «${t}»` : b;
  const oneLine = (organizer ? lineOf(title, body) : `«${title}»: ${body}`).replace(/\s+/g, " ").trim();
  const subject = oneLine.length <= SUBJECT_MAX ? oneLine : `${oneLine.slice(0, SUBJECT_MAX - 1).trimEnd()}…`;
  [title, body, who] = [unlink(title), unlink(body), unlink(who)];
  const button = organizer ? { label: "Переглянути", url: `${SITE}/kabinet#/e/${eventId}` } : { label: "Відкрити подію", url: page };
  // Відповісти з вебу в першій версії не можна (1.2).
  const note = kind === "question" ? "Відповісти можна в застосунку «Поряд»." : "";
  const line = lineOf(title, body);
  const why = organizer ? `Ви отримали цей лист, бо організовуєте «${title}».`
    : kind === "organizer" ? `Ви отримали цей лист, бо стежите за ${who || "організатором"}.`
    : kind === "declined" ? `Ви отримали цей лист, бо надіслали запит на «${title}».`
    : `Ви отримали цей лист, бо записались на «${title}».`;
  // Скасовувати нема чого, коли запит не прийняли чи подію скасовано.
  const link = kind === "organizer" ? { label: "Не стежити", url: `${page}?unfollow` }
    : kind === "approved" || kind === "promoted" || kind === "moved" ? { label: "Скасувати запис", url: page } : null;

  const text = [title, line, ...(note ? [note] : []), `${button.label}: ${button.url}`, "", "—", why,
    ...(link ? [`${link.label}: ${link.url}`] : [])].join("\n");
  const p = (s: string, style = "") => `<p style="margin:0 0 16px;${style}">${esc(s)}</p>`;
  const html = `<!doctype html><html lang="uk"><body style="margin:0;padding:24px;background:#ffffff;color:#1a1a1a;font:16px/1.5 -apple-system,Segoe UI,Roboto,sans-serif">
<div style="max-width:520px">
${p(title, "font-size:20px;font-weight:600")}
${p(line)}
${note ? p(note) : ""}<p style="margin:0 0 32px"><a href="${esc(button.url)}" style="display:inline-block;padding:12px 20px;background:#1a1a1a;color:#ffffff;border-radius:8px;text-decoration:none">${esc(button.label)}</a></p>
<p style="margin:0;color:#666666;font-size:13px">${esc(why)}${link ? ` <a href="${esc(link.url)}" style="color:#666666">${esc(link.label)}</a>` : ""}</p>
</div>
</body></html>`;
  return { subject, html, text };
}
