# Build brief: C1–C4 «Шукаю компанію» (TikTok/Reels 9:16)

Scripts with copy and timing: `marketing/scripts/companions-tiktok.md` (Ukrainian, binding — copy text exactly).
Projects: `marketing/hyperframes/{c1-standup-chat,c2-standup-list,c3-anime-multiki,c4-anime-pov}/` (each already `hyperframes init`-ed; assets copied into its `assets/`).

> 26.10: the series was rebuilt in the «Корінець» world (`marketing/scripts/README.md` → Бренд-біблія; `companions-tiktok.md` → 26.10). Read the look, fonts, coral, chips and end card below as history: night `#0F0F13` without glow, Sofia Sans instead of Unbounded, ticket-face pills with stub-tile avatars, «Корінець» tickets instead of glass chips, «Поряд» in paper, the end card from `END-CARD.md`. The UI is the new app (screens from 26.10, dev); its points are in each `compositions/proof.html`.

## Canvas and safe zones
- 1080×1920, 30 fps, ~11 s (C3 11.5 s). Root composition id `main`.
- TikTok/Reels UI covers: top 0–250 and bottom 1450–1920 → background only there; right 940–1080 → no text. All text and the key UI moments live inside x 60–920, y 250–1450.

## Look (TikTok-native, NOT the premium track)
- Background: night `#0B0B0F` with a soft radial glow `#1B1A36`; subtle film grain (opacity ~0.08).
- Text «carriers» we draw ourselves (no foreign app logos):
  - **White plate:** Inter 600, 46–54 px, ink `#1D1D1F` on `#FFFFFF`, radius 16, padding 14×22, lowercase as written; plates pop in (scale 0.9→1, y 12→0, 0.18 s, back.out).
  - **Chat** (C1, C4): dark chat sheet `#17171C`, header with group name + three avatar circles with a letter (no faces; colours violet `#6D4AC9`, blue `#2F63C4`, amber `#E8A33D`), bubbles Inter 600 40 px: friends' bubbles `#2A2A33` left, my bubble `#6D4AC9` right. Each bubble pops with `assets/audio/ui_tick.wav`.
  - **Notes** (C2): iOS-notes-like paper `#FDFBF4`, title Inter 600 56 px, rows Inter 400/600 44 px with hollow circles; typing caret.
  - **Stamp:** Unbounded 900, 150–190 px, paper `#F5F5F7`, slight rotation (−4°), slams in (scale 1.4→1, 0.15 s) — used for «0 з 3», «таких не буває?».
- **Coral `#E0582F` belongs ONLY to the app name «Поряд».** No other coral anywhere.
- Fonts (local, `assets/fonts/`): Inter 400/600 (cyrillic + latin woff2 with unicode-range), Unbounded variable (cyrillic + latin, weights 300–900). Emoji in copy render with the system emoji font — fine.

## The name «Поряд»
- **Lockup from frame 0:** small app icon (`assets/icon.png`, 64 px, radius 16) + «Поряд» Unbounded 900 40 px coral, placed directly above the first caption/carrier (inside the safe zone, e.g. top ≈ 270, left 70). It stays until the big name appears with the UI, then fades.
- **Big name with the UI (~4.3–4.6 s):** caption plate «[icon 56 px] **Поряд** → шукаю компанію» where «Поряд» is Unbounded 900 coral 54 px inside a white plate (the rest Inter 600 ink).
- **End card:** see below.

## The phone (real app UI — screenshots, animated)
- All UI images are real screenshots from the dev build, 1206×2622 px, already blurred where posters showed faces or anime characters (do not blur again, do not edit).
- Phone: screen 470×1022 (scale 0.38972 of the screenshot), bezel 12 px `#000`, outer radius 64, subtle shadow; centred x=540, top ≈ 410 so the bottom stays ≤ 1450. Captions go in the band 270–395 above the phone (and may overlap the phone's top edge slightly).
- Sequence per video (screenshot names in `assets/ui/`, prefix cN = c1…c4):
  1. `cN-1-detail.png` slides/fades in (0.25 s). Hold ~0.6 s.
  2. **Tap «Шукаю компанію»:** tap dot (white 40 px circle, 0.5 opacity, scale 0.6→1.4 fade out, 0.3 s) at screenshot px (603, 2405) + `ui_tick.wav`.
  3. **Sheet:** `cN-2-sheet.png` — animate like an iOS sheet: dim the detail (black 0.35) and slide the sheet screenshot up from the bottom (translateY 100%→0, 0.35 s, power3.out). (Showing the full sheet screenshot sliding is fine — its top sliver already contains the dimmed detail.)
  4. **Change a value:** tap dot on the control, then crossfade (0.12 s) to `cN-3-*.png` (the number/time changes). Controls in px: C1 capacity «−» (876, 1432) → 3; C2 time «−» (876, 878) → 18:15; C3 capacity «−» (876, 1432) twice (two taps 0.25 s apart; only one target screenshot `c3-3-sheet-2.png` = 2); C4 capacity «+» (1043, 1501) → 5.
  5. **Publish:** tap dot on «Опублікувати й поділитися» — px (603, 1660) for C1–C3, (603, 1729) for C4 — then the share sheet `cN-4-share.png` slides up (0.3 s). Its preview line reads «Шукаю компанію на …» — let it be readable ≥ 0.6 s (macro zoom helps).
  6. Optional last UI beat (if time allows, ~0.6 s): cut to `cN-5-mine.png` zoomed onto the «Шукають компанію / ВАШ ПОШУК» card (px y-ranges: c1 1100–1442, c2 1638–1992, c3 1965–2306, c4 1350–1697).
- **Macro zoom:** on steps 2–5 the phone group may scale 1→1.3 toward the tap point (power2.inOut, ~0.4 s) so the tapped control is legible; keep the zoomed content of interest inside y 250–1450 (overflowing phone edges are fine — background).

## End card (~2.3–2.5 s)
- Night background + glow. Above everything: the bait line (white plate, from the script).
- Icon 200 px (radius 46, shadow `0 30px 80px rgba(224,88,47,.35)`) springs in; «Поряд» Unbounded 900 120 px coral under it.
- «безкоштовно» Inter 600 34 px `#A1A1A8`, then the **official badge** `assets/appstore-badge-uk.svg` at height 104 px, **hard cut, no animation, untouched**, ≥ 26 px clear space; under it «Apple, логотип Apple і App Store є торговельними марками Apple Inc.» Inter 400 22 px `#8A8A93`, max-width 860, centred.
- The whole end card sits inside y 250–1450. Last 10 frames fully static.

## Audio
- `assets/audio/music.m4a` from 0 s: C1/C2 = phonk-house 130.4 BPM (beat 0.46 s, first beat ≈ 0.1 s; a drop ≈ 7 s), C3/C4 = calm even track. Volume 0.8, fade out over the last 0.6 s (volume lane, as in the earlier promo projects).
- SFX: `ui_tick.wav` (chat bubbles, plates, taps, volume 0.35), `whoosh.wav` (carrier → phone, phone → end card, volume 0.3), `pin_pop_1.wav` (stamp slam / icon landing, volume 0.35).

## Deliverables (do not render — the orchestrator renders)
- `index.html` at the project root, HF contract (single paused timeline, `window.__timelines["main"]`, deterministic, `class="clip"` on timed elements).
- Reference implementation for lockup/end card/badge/fonts/volume lane: `marketing/hyperframes/poriad-10s-9x16/index.html` (premium track — reuse mechanics, not its look).
