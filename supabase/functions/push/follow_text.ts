// Тексти пушів про підписки (docs/follows.md). Окремо від index.ts: чиста логіка без Deno й мережі,
// тож її перевіряє `node supabase/functions/push/follow_text.test.mjs`.

export type PlaceLine = { id: string; name: string; n: number };
export type ArtistLine = { id: string; name: string; n: number };
export type EventLine = { id: string; title: string; when: string };

export type FollowText = { title: string; body: string; placeId?: string; artistId?: string; eventId?: string };

const BODY_MAX = 180;

/** Українські форми числівника: 1 подія, 2–4 події, 5+ подій; 11–14 — завжди «подій». */
export function plural(n: number, one: string, few: string, many: string): string {
  const last = n % 10, tens = n % 100;
  if (last === 1 && tens !== 11) return one;
  if (last >= 2 && last <= 4 && !(tens >= 12 && tens <= 14)) return few;
  return many;
}

const newEvents = (n: number) => `${n} ${plural(n, "нова подія", "нові події", "нових подій")}`;

function clip(text: string): string {
  return text.length <= BODY_MAX ? text : `${text.slice(0, BODY_MAX - 1).trimEnd()}…`;
}

/**
 * Один пуш про нові події закладів, за якими стежить людина. [places] — найзавантаженіший першим (з
 * `notify_place_follows`), [events] — найближчі події за часом, до трьох; [total] і [placeCount] — скільки
 * їх усього. Одна подія — її назва; кілька в одному закладі — «У «…» 3 нові події»; у кількох — підсумок.
 * Тап: одна подія веде на неї, решта — на стос найзавантаженішого закладу на мапі.
 */
export function placeText(total: number, placeCount: number, places: PlaceLine[], events: EventLine[]): FollowText | null {
  const lead = places[0];
  if (!lead || total < 1) return null;
  if (total === 1 && events[0]) {
    return { title: events[0].title, body: clip(`Нова подія у «${lead.name}» · ${events[0].when}`), placeId: lead.id, eventId: events[0].id };
  }
  if (placeCount <= 1) {
    const rest = total - events.length;
    const titles = events.map((e) => e.title).join(", ") + (rest > 0 ? ` та ще ${rest}` : "");
    return { title: `У «${lead.name}» ${newEvents(total)}`, body: clip(titles), placeId: lead.id };
  }
  const shown = places.slice(0, 3);
  const more = placeCount - shown.length;
  const names = shown.map((p) => `«${p.name}»`).join(", ") + (more > 0 ? ` та ще ${more}` : "");
  return { title: `${newEvents(total)} у місцях, за якими ви стежите`, body: clip(names), placeId: lead.id };
}

/** Нова спільнотна подія організатора: назва події й від кого. */
export function organizerText(eventTitle: string, organizerName: string, when: string): FollowText {
  return { title: eventTitle, body: clip(organizerName ? `Нова подія від ${organizerName} · ${when}` : `Нова подія · ${when}`) };
}

/**
 * Один пуш про нові події артистів, за якими стежить людина (docs/artists-discovery-2026-10.md).
 * [artists] — найзавантаженіший першим, [events] — найближчі, до трьох; [total] і [artistCount] — скільки
 * їх усього. Заголовок — ім'я артиста: людина стежила за ним, а не за назвою вистави. Одна подія — її назва
 * й час (назву пропускаємо, коли вона збігається з іменем: «Jerry Heil» двічі не кажемо). Тап: одна подія
 * веде на неї, решта — на сторінку найзавантаженішого артиста.
 */
export function artistText(total: number, artistCount: number, artists: ArtistLine[], events: EventLine[]): FollowText | null {
  const lead = artists[0];
  if (!lead || total < 1) return null;
  if (total === 1 && events[0]) {
    const e = events[0];
    const same = e.title.trim().toLowerCase() === lead.name.trim().toLowerCase();
    return { title: lead.name, body: clip(same ? `Нова подія · ${e.when}` : `Нова подія: ${e.title} · ${e.when}`), artistId: lead.id, eventId: e.id };
  }
  if (artistCount <= 1) {
    const rest = total - events.length;
    const times = events.map((e) => e.when).join(" · ") + (rest > 0 ? ` та ще ${rest}` : "");
    return { title: `${lead.name}: ${newEvents(total)}`, body: clip(times), artistId: lead.id };
  }
  const shown = artists.slice(0, 3);
  const more = artistCount - shown.length;
  const names = shown.map((a) => a.name).join(", ") + (more > 0 ? ` та ще ${more}` : "");
  return { title: `${newEvents(total)} в артистів, за якими ви стежите`, body: clip(names), artistId: lead.id };
}
