---
target: poriad.app site (landing + afisha) after fixes
total_score: 28
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 2
target_identity: "file:/Users/tarasvovcenko/StudioProjects/Poruch/site/index.html"
target_fingerprint: "sha256:6646aa0a1c5a88ead782eb24b1ed297dc477122add395d06834119516c4e075c"
target_path: /Users/tarasvovcenko/StudioProjects/Poruch/site/index.html
timestamp: 2026-10-17T23-10-21Z
slug: site-index-html
---
Method: dual-agent (A: design review · B: detector), re-run after five fix passes (layout, clarify, harden, adapt, polish). A second round of fixes followed this run (focus rings on ink, off-brand showcase filter, sheet focus, failure state, search copy) — not yet re-scored.

## Design Health Score
| # | Heuristic | Score | Key issue |
|---|---|---|---|
| 1 | Visibility of system status | 3 | Header «973 події» vs list «2 події»; sheet focus fell to body (fixed in round 2) |
| 2 | Match system / real world | 3 | «31.10 … ДО» stub order (matches app); after midnight «Сьогодні ввечері» = new day |
| 3 | User control and freedom | 3 | No «Повернути» after «Скинути фільтри»; two-finger map pan (reverted in round 2) |
| 4 | Consistency and standards | 3 | Sheet primary «Купити квиток» vs DESIGN «Шукаю компанію»; 11 inline category chips; «Шукаю компанію» stamp on plate |
| 5 | Error prevention | 2 | Off-brand live events in showcase (dating 38–50 in Kharkiv — fixed in round 2); three install invitations on non-iOS |
| 6 | Recognition over recall | 3 | Mobile categories in a long horizontal row; icon-only view toggle (aria-label added in round 2) |
| 7 | Flexibility and efficiency | 2 | No «ввечері» filter, no near-me, no sort, no calendar export |
| 8 | Aesthetic and minimalist | 3 | Hero face gap; listing chrome ~32% of phone screen |
| 9 | Error recovery | 3 | Landing failure left grey plate (hidden in round 2); no «Створити подію» exit on empty |
| 10 | Help and documentation | 3 | Receipts explain meetups and safety |
| Total | | 28/40 | Good |

Taste ROUND 2 landing: design 7.5 · usability 8 · creativity 7 · content 8 → 7.6 (inspector 0 real FAIL; one false eyebrow from a collapsed accordion row). Afisha: 2 inspector FAILs (14px card meta; clamped title counted as 5 lines) → capped 6.0, rubric not built for listings.

## Detector
Same brand false positives: zigzag clip-path ×2, --spring easing, system font stack, genre colours. Real: em-dash density (12 in rendered landing text), brand icon 8px radius off-token.

## Remaining priority issues
- [P2] Listing on one thumb: chrome ~268/844px, filters at top, chronological grid starts with matinees, no «Сьогодні ввечері» chip, no category sheet.
- [P2] Web is all walls: every guest action opens the same install sheet without the event; Android/desktop dead end; no .ics for «Нагадати».
- [P2] No static proof when Supabase is down (worker snapshot fallback).
- [P3] Copy: «Готель «Portal'» quote nesting and leftover caps from displayTitle; «Усі 2» rows (dropped <3 in round 2).

## Questions
1. Guest-printable meetup ticket with a share link? 2. Honest proof of «з ким»? 3. Shelters/curfew line on every tonight ticket?
