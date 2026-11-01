// Спільні дані тестів воркера (worker/*.test.mjs).
export const now = new Date("2026-09-28T12:00:00Z");
export const base = {
  id: "a1000000-0000-4000-8000-000000000005", title: "Настолки <script>alert(1)</script>", description: "Рядок 1\nРядок 2",
  city: "Київ", address: "Хрещатик, 22", latitude: 50.45, longitude: 30.52, starts_at: "2026-10-04T16:00:00Z",
  ends_at: "2026-10-04T19:00:00Z", time_zone: "Europe/Kyiv", status: "published", origin: "community",
  capacity: 8, attendee_count: 5, organizer_name: "Олена", image_url: "javascript:alert(1)", approval_required: true,
};
export const shelters = [{ kind: "metro", address: "ст. м. «Контрактова <b>»", distance_m: 66, accessible: true, hours: null, latitude: 50.46, longitude: 30.51 }];
export const env = { SUPABASE_URL: "https://db.invalid", SUPABASE_KEY: "k" };
export const ctx = { waitUntil: (p) => p };
/** fetch, що на event_details віддає [base], а на решту — порожній об'єкт. */
export const detailsOk = async (url) => new Response(url.endsWith("/event_details") ? JSON.stringify([base]) : "{}", { status: 200 });
