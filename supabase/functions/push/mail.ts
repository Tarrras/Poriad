// Кому пуш на пристрій, кому лист, і що в листі — тим, у кого нема застосунку (docs/organizers-1.5.md, 1.1 «Листи» і
// 1.2 «Сповіщення організатору без застосунку»). Текст — той самий, що в пуші (крім питання); лист додає кнопку й підвал
// «чому ви це отримали». Окремо від index.ts: чиста логіка без Deno й мережі, тож її перевіряє
// `node supabase/functions/push/mail.test.mjs`.

// `answer` і `proof` — лише листи: пуш про них має вид `question` (застосунки вже його знають), а вид листа — `mail`.
export type MailKind = "request" | "question" | "answer" | "proof" | "approved" | "declined" | "promoted" | "moved" | "cancelled" | "organizer";
export const MAIL_KINDS: readonly string[] = ["request", "question", "approved", "declined", "promoted", "moved", "cancelled", "organizer"];
// Пуші, які випущені клієнти не покажуть (Android невідомий kind мовчки відкидає): лише на токени з прапорцем
// `push_tokens.features`, який реєструє застосунок, що їх знає.
const FEATURE: Record<string, string> = { companion: "companion", company: "company", approved: "decision", declined: "decision", promoted: "decision" };

export type TokenRow = { token: string; platform: "android" | "ios"; user_id: string; features: string[] };
type Routed = { kind: string; change?: string };

/**
 * [tokens] — усі токени [recipients]. Людина з будь-яким пристроєм листа не отримує, навіть якщо її застосунок цього
 * виду ще не знає. Розмова на двох: адресат — завжди інша сторона (організатор чи той, хто питав, — відповісти він
 * може й на сторінці події). Зміна афіші (change) — тим, хто її зберіг у застосунку, а листом — лише спільнотна подія,
 * куди записались.
 */
export function route(push: Routed, recipients: string[], tokens: TokenRow[]) {
  const feature = FEATURE[push.kind];
  const withDevice = new Set(tokens.map((t) => t.user_id));
  const devices = tokens.filter((t) => !feature || t.features.includes(feature)).map(({ token, platform }) => ({ token, platform }));
  const mailTo = MAIL_KINDS.includes(push.kind) && !push.change
    ? recipients.filter((id) => !withDevice.has(id))
    : [];
  return { devices, mailTo };
}

export type Mail = { subject: string; html: string; text: string };

/** Листи організатору: кнопка в кабінет. */
const TO_ORGANIZER: readonly MailKind[] = ["request", "question", "proof"];
/** Листи з фіксованим рядком замість тексту пуша (див. [mailText]): `line` — з назви події, `note` — що робити далі. */
const FIXED: Partial<Record<MailKind, { line: (title: string) => string; note?: string }>> = {
  request: { line: (t) => `Нова заявка на «${t}»` },
  question: { line: (t) => `Вам поставили питання про «${t}»`, note: "Відповісти можна в кабінеті на poriad.app чи в застосунку «Поряд»." },
  proof: { line: (t) => `Вам надіслали скріншот оплати за «${t}»`, note: "Звірте надходження в банку й натисніть «Оплату отримано» в кабінеті." },
  answer: {
    line: (t) => `Організатор написав вам про «${t}»`,
    note: "«Поряд» не приймає оплату й не відповідає за неї. Не переказуйте гроші, якщо сумніваєтесь в організаторі.",
  },
};

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
 * готовий фішинг. Ім'я він побачить у кабінеті. Так само й тому, хто питав (`answer`): слова організатора, а з ними й
 * реквізити, лишаються в розмові на сторінці події, під застереженням. Рядки від людей (назва, імена в тексті пуша)
 * у тілі листа — без посилань ([unlink]); тема лишається як є: її поштові клієнти посиланнями не роблять.
 */
export function mailText(kind: MailKind, eventId: string, title: string, body: string, who = ""): Mail {
  const page = `${SITE}/e/${eventId}`;
  const fixed = FIXED[kind];
  const organizer = TO_ORGANIZER.includes(kind);
  const oneLine = (fixed ? fixed.line(title) : `«${title}»: ${body}`).replace(/\s+/g, " ").trim();
  const subject = oneLine.length <= SUBJECT_MAX ? oneLine : `${oneLine.slice(0, SUBJECT_MAX - 1).trimEnd()}…`;
  [title, body, who] = [unlink(title), unlink(body), unlink(who)];
  const button = organizer ? { label: "Переглянути", url: `${SITE}/kabinet#/e/${eventId}` }
    : kind === "answer" ? { label: "Відкрити розмову", url: `${page}?ask` } : { label: "Відкрити подію", url: page };
  const note = fixed?.note ?? "";
  const line = fixed ? fixed.line(title) : body;
  const why = organizer ? `Ви отримали цей лист, бо організовуєте «${title}».`
    : kind === "organizer" ? `Ви отримали цей лист, бо стежите за ${who || "організатором"}.`
    : kind === "declined" ? `Ви отримали цей лист, бо надіслали запит на «${title}».`
    : kind === "answer" ? `Ви отримали цей лист, бо листуєтесь з організатором «${title}» у «Поряд».`
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
