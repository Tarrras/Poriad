# Build brief: A1–A3 «Одна мапа» і «Міста» (9:16 premium)

Scripts (Ukrainian copy, binding): `marketing/scripts/aggregation-cities.md`.

Template to clone: `marketing/hyperframes/c2-standup-list/` — the approved premium film:
- `index.html` plus `compositions/{hook,proof,turn,card,mark,cta}.html` and `film.json`;
- night ground with violet glow;
- Unbounded 300/900 and Inter only;
- glass pills;
- words assembling;
- badges stepping into chips;
- a match cut into a phone with real screenshots;
- a card carried out of the phone;
- the coral «Поряд» lockup;
- an end card with «твоє місто. нарешті видно.», «безкоштовно», the official App Store badge as a hard cut, and the Apple trademark line.

## Rules (all three)

- **Canvas and length:** 1080×1920, 30 fps, 12–15 s.
- **Safe zone:** all text inside x 60–920 / y 250–1450.
- **Coral `#E0582F`:** only on the «Поряд» wordmark.
- **Name reveal:** the name appears as the resolution in the turn, not from the first frame. This is the user's preference.
- **Copy:**
  - no gendered verb forms for «ти»;
  - no «уся афіша» or «збирає все»;
  - no numbers presented as data (the pill counters in A1 are an illustration of noise);
  - nothing that claims the app finds people or plans for you.
- **Screenshots:** they are real prod screenshots and already blurred where needed. Do not edit them.
- **Camera:** pushes and crossfades only. The «Знайдено подій: N» pill inside screenshots is fine to show, but never zoom into it as a claim.
- **App Store badge:** untouched, hard cut.
- **Ending:** the last 10 frames are static.
- **Audio:** retime the SFX (`ui_tick` / `whoosh` / `pin_pop_1`) and the music volume lane to the new beats.
- **Verify:**
  - `npx hyperframes lint` and `npx hyperframes check .` must reach 0 errors;
  - snapshot `--frames 14` into `snapshots/`;
  - inspect every contact sheet and fix what you find.

## Screens: `assets/ui/*.png`

All screens are 1206×2622 px, status bar 9:41. Coordinates below are in screenshot px.

| file | what | useful points |
|---|---|---|
| `map-kyiv.png` | Kyiv map, «Будь-коли», clusters all over the city, «Знайдено подій: 950», bottom card (stand-up, thumb blurred) | city chip «Київ ⌄» (203, 462) · gold stand-up pin (436, 838) · card y 1910–2240 |
| `map-kyiv-card.png` | zoomed onto a stand-up pin, selected card «СТЕНДАП на А… · ЧТ, 22 ЖОВТ. · 19:00 · АФІША · CONCERT.UA» | pin (603, 985) · card y 1910–2240 |
| `picker-map.png` | «Знайти місто» sheet over the Kyiv map | rows: Київ y 1919 · Харків 2050 · Одеса 2182 · Дніпро 2313 · Львів (150, 2447) · sheet top y ≈ 1228 |
| `map-lviv.png` | Lviv map, «Львів ⌄», 359 events, card «Василь Байдак» (thumb blurred) | chip «Будь-коли» (1000, 462) · card y 1910–2240 |
| `map-lviv-weekend.png` | Lviv with «Вихідні» selected, 38 events, card «Вечір джазу · У НЕДІЛЮ · 18:00 · АФІША · CONCERT.UA» | chip «Вихідні» (1028, 462) · card y 1910–2240 |
| `map-kyiv-weekend.png` | Kyiv with the weekend filter (badge 1), clusters around the centre, 123 events, card «Вистава «Будьте як вдома»» (thumb blurred) | card y 1910–2240 |

## Per film

- **A1 `a1-channels`.** Music `assets/audio/music-electronic.wav` (offset 0.06 s, like C1/C2).
  - Hook: the messenger folder of «афіші» as glass pills with unread badges, then the verdict «20 каналів. 0 планів.».
  - Bridge: «давай простіше:», then «одна мапа».
  - Phone: `map-kyiv` with the camera pulling back over the clusters → tap the gold pin (436, 838) → crossfade `map-kyiv-card` → push onto the card.
  - Turn: the card is carried out, then «Поряд збирає їх на одну мапу.» with «Поряд» as the coral wordmark lockup.
- **A2 `a2-weekend-trip`.** Music `assets/audio/music.m4a` (uplifting brand track) **from media offset 16.0 s**.
  - Hook: a travel checklist of pills with ticks, then the verdict «а що там робити?», then «давай подивимось», then the chip «Львів · вихідні».
  - Phone: `map-kyiv` → tap «Київ ⌄» → `picker-map` (the sheet slides up) → tap Львів → `map-lviv` → tap (1000, 462) → crossfade `map-lviv-weekend` → push onto the «Вечір джазу» card.
  - Captions: «перемикаєш місто» · «обираєш «вихідні»» · «і субота вже з планом».
  - Turn line: «5 міст — один застосунок».
- **A3 `a3-new-city`.** Music `assets/audio/music.m4a` (calm, even track).
  - Hook: two motion-design dots «дім» and «робота» with a route line bouncing between them, plus pills «знайомих у місті: 0» · «улюблених місць: 0» · «планів на пʼятницю: 0».
  - Then «щойно переїхали?», the verdict «дім → робота → дім», then «а місто — поруч».
  - Phone: `map-kyiv-weekend`, with the camera pulling back from a district to the whole city with pins → push onto its card.
  - Captions: «відкриваєш мапу» · «бачиш, що відбувається довкола» · «і місто стає твоїм».
  - Turn: «твоє нове місто. нарешті видно.».

The bait question for each film is in the script's table.
