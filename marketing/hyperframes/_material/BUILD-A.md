# Build brief: A1–A3 «Одна мапа» і «Міста» (9:16 premium)

Scripts (Ukrainian copy, binding): `marketing/scripts/aggregation-cities.md`.

> 26.10: the wordmark is no longer coral. «Поряд» is paper `#F3F3F0` in A2–A3 and ink `#141417` in A1 (the «Корінець» world, `marketing/scripts/README.md`). Read every «coral» below as that.

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

---

# v2: each film has its own visual language. Do NOT clone C1/C2.

User feedback 12.10: «А1–А3 виглядають як копії С1–С4, просто з іншим контентом. Я не хочу копіпаст».

So none of the C-series look:
- no violet glow ground;
- no glass pills circling an orbit;
- no badges stepping into chips;
- no centred «давай …» line assembling;
- no «card carried out of the phone» turn.

Only these brand constants stay:
- Unbounded (300/900) + Inter;
- coral `#E0582F` only on the «Поряд» wordmark;
- the end-card rules: «Поряд» wordmark, «безкоштовно», the official badge untouched by hard cut, the Apple trademark line, static last 10 frames;
- the safe zone x 60–920 / y 250–1450;
- real prod screenshots (`assets/ui`, already blurred).

Build each film from scratch, with its own ground, motion vocabulary, transitions, phone treatment and end-card entrance. Reuse registry items (`npx hyperframes add <name>`, customise in place) where named below. Read `/hyperframes-animation` and `/hyperframes-registry` first. Each film keeps its v1 copy and story beats from `marketing/scripts/aggregation-cities.md`.

## A1 «20 каналів з афішами»: noise → signal

- **Ground:** paper `#F5F5F7` and ink `#0B0B0F`, high contrast and monochrome. It starts light (the opposite of the C-series night).
- **Hook:** a phone lock-screen fills the frame edge to edge with no bezel, and the `notification-cascade` block buries it. Banners carry channel names and unread counts from the script (no foreign logos: neutral round avatars with letters). They stack faster and faster and overlap, the frame shakes slightly, and `rgb-glitch-text` hits the verdict «20 каналів. 0 планів.» (Unbounded 900, ink on paper, huge, tight).
- **Turn to signal:** the `glitch` shader transition or a hard RGB-split cut, then silence. All the banners collapse (scale and blur) into ONE ink dot in the middle. The dot drops and becomes a map pin with a small bounce. «давай простіше: одна мапа» types out in mono-weight lines next to it.
- **Phone:** NOT a framed phone. The pin pushes in, and the real `map-kyiv.png` screen opens full-bleed from the pin outwards as a circular mask (`transitions-radial` style). The camera drifts over the clusters, then taps the gold pin → `map-kyiv-card.png`.
- **Captions:** small Inter 600 labels in ink on paper strips, left-aligned, like UI annotations with a thin leader line pointing at the thing on screen.
- **Name:** «Поряд збирає їх на одну мапу.» Use `wordmark-tiles` (noise → glyph tiles) to resolve the coral «Поряд», continuing the noise → signal idea.
- **End card:** on paper, a light end card (ink text, coral name). The badge is a hard cut. This is the only light end card of the series.
- **Music:** `music-electronic.wav`. Cut the hook on its beats and let the music drop out at the «silence» moment.

## A2 «Вихідні в іншому місті»: the night train

- **Ground:** deep navy `#0E1626` with warm amber `#F2B544` and paper. The feel is a night train or a station.
- **Hook:** the `split-flap-board` (Solari departure board) carries the checklist as board rows: «КВИТКИ НА ПОТЯГ ✓» · «ЖИТЛО ✓» · «ПАВЕРБАНК ✓» · «ПЛАН НА СУБОТУ —» with the last cell flapping without resolving. Then the board flips to the verdict «А ЩО ТАМ РОБИТИ?».
- **Bridge:** a horizontal `whip-pan-cut` to a stylised outline of Ukraine in thin amber line (simple hand-made SVG path, approximate) with 5 city dots. A route line draws from Київ to Львів with a travelling dot (the train). Then «давай подивимось» rides along the route as a ticket stub with a perforated edge.
- **Phone:** a 3D-tilted phone (perspective rotateY about 18° → 0°, like a ticket sliding out of a pocket) with the real screens: `map-kyiv` → tap «Київ ⌄» → `picker-map` sheet → tap Львів → `map-lviv` → «Вихідні» → `map-lviv-weekend` → card «Вечір джазу».
  - The city switch is the signature: on the Львів tap, a split-flap tile row over the phone flips «КИЇВ» → «ЛЬВІВ».
  - Captions sit as amber split-flap labels above the phone: «перемикаєш місто» · «обираєш «вихідні»» · «і вихідні вже з планом».
- **Name:** «5 міст — один застосунок». The five city dots from the map light up in sequence, then converge into the coral «Поряд» wordmark.
- **End card:** navy ground with amber hairlines; «Поряд» lands like the last flap settling.
- **Music:** `music.m4a` from 16.0 s (already measured: about 7 dB loud, so keep the volume around 0.45). Use whip-pans on its hits.

## A3 «Переїзд у нове місто»: a city drawn in lines that lights up

- **Ground:** dusk gradient (indigo `#1A1C3A` → plum `#3A2346` at the bottom) with warm window light `#FFD27A`. Calm, soft, no slams.
- **Hook:** thin white line art drawn with `svg-stroke-trace` / `svg-line-draw-loader`:
  - two small house outlines, «дім» and «робота», with a dashed route between them;
  - a tiny figure-dot shuttles back and forth, with the trail drawing over itself (`hw-path-text` may write «дім → робота → дім» along the route instead of a big verdict);
  - the zero facts appear as handwritten annotations next to the drawing: «знайомих у місті: 0» · «улюблених місць: 0» · «планів на пʼятницю: 0»;
  - «щойно переїхали?» is set quietly at the top.
- **Reveal:** «а місто — поруч». From the «дім» house, a warm radial light expands (`transitions-light` / radial reveal). As it spreads, more line-drawn buildings appear all around and their windows light up one by one in amber, in a parallax layered skyline (`camera-rig-depth-stack` or hand-made layers).
- **Phone:** the light reaches a window, which becomes the phone screen. The real `map-kyiv-weekend.png` fades in inside a soft rounded frame that floats with a slow parallax drift (no hard device bezel). The camera eases from district to city and then onto the card.
  - Captions are handwriting-style lines in Inter 400 italic-feel (or `hw-path-text`) next to the phone: «відкриваєш мапу» · «бачиш, що відбувається довкола» · «і місто стає твоїм».
- **Name:** «твоє нове місто. нарешті видно.» The skyline windows all switch on at once, and the coral «Поряд» is drawn as a line (stroke trace), then filled.
- **End card:** on the dusk gradient, the icon fades up softly.
- **Music:** `music.m4a` (calm).
