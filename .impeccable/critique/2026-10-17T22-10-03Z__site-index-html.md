---
target: poriad.app site (landing + afisha)
total_score: 25
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 4
target_identity: "file:/Users/tarasvovcenko/StudioProjects/Poruch/site/index.html"
target_fingerprint: "sha256:b6b100f62ec510c6d171cac52e9cf756f222e2c55ddf71b14f36e60ed9cea2bc"
target_path: /Users/tarasvovcenko/StudioProjects/Poruch/site/index.html
timestamp: 2026-10-17T22-10-03Z
slug: site-index-html
---
Method: dual-agent (A: design review · B: detector) + tasteskill lint/inspect/critique in parent.

## Design Health Score
| # | Heuristic | Score | Key issue |
|---|---|---|---|
| 1 | Visibility of system status | 3 | Landing company plate pulses forever on RPC failure |
| 2 | Match system / real world | 3 | "31.10 … ДО" stub reversed; "Компанія" vs "Шукаю компанію" |
| 3 | User control and freedom | 2 | "Подію не знайдено" sheet has no close; plate auto-rotates |
| 4 | Consistency and standards | 2 | Circle clusters vs DESIGN.md:446; .btn beats [hidden]; role=tab + aria-pressed |
| 5 | Error prevention | 2 | QR → non-public Google Play on Android; iPhone-only unstated |
| 6 | Recognition over recall | 3 | Desktop categories after "Спорт" unreachable by mouse |
| 7 | Flexibility and efficiency | 2 | Listing: no evening/near-me, no sort (n/a for landing) |
| 8 | Aesthetic and minimalist | 3 | Sheet repeats time ×3; 86svh footer void |
| 9 | Error recovery | 2 | "Показати ще" under error/empty; landing board error no retry |
| 10 | Help and documentation | 3 | Hints and install sheets adequate |
| Total | | 25/40 | Acceptable |

Taste ROUND 1 landing: design 6.5 · usability 7.5 · creativity 7 · content 7.5 → 7.0 (caps: two near-empty desktop screens; ticket idea passes for Karabas). Afisha: 2 inspector FAILs (14px body, 3-line title @390) → capped 6.0.

## Design specificity
Landing highly specific (page-ticket, receipt, price list, tear-off footer). Listing medium (poster grid). Map + install sheet generic.
Detector: mostly false positives (zigzag polygons, system font, spring easing). Real: genre stamps over photos 3.3–3.8:1; 12 em dashes. Taste lint FAILs mostly brand (perforation masks, overline per DESIGN.md); real resting shadow on poster save button web.css:129. Inspector: landing 13 type sizes; afisha side-cut rows, grey body 5.9:1, 126-char measure.

## Priority issues
- [P1] Broken states: .btn beats [hidden] (web.css:41) → "Показати ще" under error/empty; bad ?e= sheet no close (ui.js:131); landing plate skeleton forever; board error no retry. → harden
- [P1] Featured events undercut pitch: plate + "Не пропустіть" pick soonest → 11:00 kids show beside "нема з ким піти? Лише 18+" (home.js:95); plate ignores city tab. → clarify
- [P1] Install path: app.html → non-public Play + visible Google Play button; QR caption says App Store; smart banner + app bar double prompt; app bar title clipped "Поряд у телеф" @390 and covers tickets; iPhone-only stated last. → harden
- [P1] Map off-system (circle clusters, afisha.js:198), clipped zoom + scroll trap ≤640, no synced list; targets 36–40px < 44pt. → adapt
- [P2] Landing asks before it proves: no real tonight ticket until ~1700px on phone; hero stub empty, "Афіша" word screen, 380px accordion column, 86svh footer, blank purple tile, 13 sizes. → layout

## Persona red flags
Jordan: metaphor before meaning, no app screen, platform late. Casey: ~1/3 screen chrome, 36px saves, map traps scroll. Riley: retry + "Показати ще" together, stuck on bad link, "Інші дати" spans look tappable. Куди піти?: no "tonight near me" above fold, kids shows first, two install prompts.

## Minor observations
Raw genre hue text in light mode 3.77–4.15:1 (DESIGN.md:350 says darken 16%); focus ring clipped in chip rows; dark safety section merges; dark sheet secondary button 1.05:1; accordion repeats time; mixed-face h2 on afisha; overline + dotted leaders are DESIGN.md rules (keep).

## Questions
1. Hero sells tonight's afisha, "друкуєте самі" second? 2. Hand over *this* ticket in the install sheet? 3. Android visitor: "not for me" or "notify me"?
