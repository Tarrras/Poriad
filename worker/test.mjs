// Перевірка рендеру без Cloudflare: node worker/test.mjs
import assert from "node:assert/strict";
import { eventPage, esc } from "./index.mjs";

const now = new Date("2026-09-28T12:00:00Z");
const base = {
  id: "a1000000-0000-4000-8000-000000000005", title: "Настолки <script>alert(1)</script>", description: "Рядок 1\nРядок 2",
  city: "Київ", address: "Хрещатик, 22", latitude: 50.45, longitude: 30.52, starts_at: "2026-10-04T16:00:00Z",
  ends_at: "2026-10-04T19:00:00Z", time_zone: "Europe/Kyiv", status: "published", origin: "community",
  capacity: 8, attendee_count: 5, organizer_name: "Олена", image_url: "javascript:alert(1)", approval_required: true,
};

const community = eventPage(base, now);
assert.ok(!community.includes("<script>alert"), "назва екранується");
assert.ok(community.includes("Учасників: 5 з 8"));
assert.ok(community.includes("19:00"), "час у зоні події, а не UTC");
assert.ok(!community.includes('src="javascript:'), "лише https-зображення");
assert.ok(community.includes('content="https://poriad.app/img/og.png"'), "запасне прев'ю");
assert.ok(community.includes("poriad://event/a1000000-0000-4000-8000-000000000005"));
assert.ok(community.includes('name="robots" content="noindex"'));

const imported = eventPage({ ...base, origin: "import", canonical_url: "https://concert.ua/x", source_name: "Concert.ua", price_min: 450.4, organizer_name: "Concert.ua" }, now);
assert.ok(imported.includes('rel="canonical" href="https://concert.ua/x"'));
assert.ok(imported.includes("від 450 грн"));
assert.ok(!imported.includes("Учасників"), "в імпорті місць нема");

const shelters = [{ kind: "metro", address: "ст. м. «Контрактова <b>»", distance_m: 66, accessible: true, hours: null, latitude: 50.46, longitude: 30.51 }];
const withShelters = eventPage(base, now, shelters);
assert.ok(withShelters.includes("Укриття поруч") && withShelters.includes("Метро · 66 м · Є пандус"));
assert.ok(!withShelters.includes("<b>»"), "адреса укриття екранується");
assert.ok(!eventPage(base, now).includes("Укриття поруч"), "без даних секції нема");
assert.ok(!eventPage({ ...base, status: "cancelled" }, now, shelters).includes("Укриття поруч"), "скасованій — ні");
assert.ok(eventPage({ ...base, status: "cancelled" }, now).includes("Подію скасовано."));
assert.ok(eventPage(base, new Date("2026-10-05T00:00:00Z")).includes("вже минула"));
const companion = eventPage({ ...base, title: "Йдемо разом: Концерт", companion_of: "b2000000-0000-4000-8000-000000000001", companion_of_title: "Концерт <b>" }, now);
assert.ok(companion.includes('Разом на: <a href="/e/b2000000-0000-4000-8000-000000000001">Концерт &lt;b&gt;</a>'), "супутник веде на афішу");
assert.ok(!eventPage({ ...base, companion_of: "javascript:alert(1)" }, now).includes("Разом на"), "лише uuid у href");
assert.ok(!community.includes("Разом на"), "звичайна подія без рядка");
assert.equal(esc(`"'<&>`), "&quot;&#39;&lt;&amp;&gt;");
console.log("ok");
