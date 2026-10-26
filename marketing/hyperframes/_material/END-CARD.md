# End card v2: two stores, room to breathe (12.10)

User feedback on v1:
1. The videos ship after the Android release, so the end card needs Google Play as well.
2. The elements sat in one heap with lots of empty space around them. Use the room, but respect the 9:16 blind zones.
3. The bait question was centred in some videos and left-aligned in others, so it "hung" without a clear place.

This grid is a **brand constant**, the same in all videos. Each film styles it in its own language (ground, colour, entrance motion), but the positions, order, alignment and sizes below are fixed.

Type and colour follow the «Корінець» world ([DESIGN.md](../../../DESIGN.md), updated here 26.10): Sofia Sans from `korinets/fonts/` (baked Ukrainian д, л, п), Inter for small print, no coral on the wordmark — the same as the app splash. All finished 9:16 films were re-rendered with this on 26.10, and C1–C4 and `poriad-10s-9x16` were rebuilt in «Корінець» the same day: no film follows the previous version any more.

## Grid (1080×1920, centred column, axis x = 540)

Safe zone: text only inside x 160–920 (centred, max width 760) and y 250–1450. The right edge 940–1080 and the bottom 1450–1920 belong to TikTok/Reels UI and stay empty (ground only).

| Group | Element | Position | Type |
|---|---|---|---|
| 1. Question | the bait from the script (e.g. «скільки ти вже в новому місті? 👇») | **centred**, top of text y ≈ 300, max 2 lines, max width 760 | Sofia Sans Condensed 700, 58–60 px, line-height 1.1 |
| ↓ air ≥ 120 px | | | |
| 2. Brand | app icon | centred, 176×176, radius 40, top y ≈ 560 | official `icon.png` |
| | «Поряд» wordmark | centred, cap-top y ≈ 790 | Sofia Sans Condensed 800, 128 px, tracking −1 px, paper `#F3F3F0` on night (ink `#141417` on day). Never coral: coral is urgency stamp ink only |
| | **brand slogan «Є куди. Буде з ким.»** (every video, verbatim) | centred, y ≈ 950 | Sofia Sans Condensed 700, 44 px, second ink `#A6A5AD` night / `#5E5E66` day (never coral) |
| ↓ air ≥ 140 px | | | |
| 3. Stores | «безкоштовно» | centred, y ≈ 1110 | Inter 600, 34 px |
| | **two official badges side by side**: App Store on the left, Google Play on the right | row top y = 1176, both **height 104 px** (Google Play is never smaller than App Store), gap 32 px, centred as a pair (≈ x 196–884) | `appstore-badge-uk.svg` (≈306×104), `googleplay-badge-uk.svg` (≈351×104) |
| | legal lines, two lines | centred, y ≈ 1316 and 1344 | Inter 400, 20 px, muted (≥ 4.5:1 contrast) |
| | | «Apple, логотип Apple і App Store є торговельними марками Apple Inc.» | |
| | | «Google Play і логотип Google Play є торговельними марками Google LLC.» | |

Nothing below y 1450.

## Badge rules (Apple and Google)

- Use official files only. Do not recolour, outline, shadow, stretch or animate them.
- Both badges **appear together by a hard cut** (no fade, no scale) and stay still to the end.
- Clear space around each badge ≥ ¼ of its height (26 px). The 32 px gap between them satisfies this.
- Use them on a solid or calm ground: black badges sit fine on light paper (A1) and on dark grounds.
- The last 10 frames of the video are fully static.

## What each film may vary

- Ground and palette.
- Entrance motion of the icon and wordmark: flap / stroke-trace / glyph tiles etc.
- How the slogan enters (type-on, flap, fade), but never its wording.
- The colour of «безкоштовно» (any non-coral brand-safe tone).

Positions, alignment (always centred), sizes and order stay as above.
