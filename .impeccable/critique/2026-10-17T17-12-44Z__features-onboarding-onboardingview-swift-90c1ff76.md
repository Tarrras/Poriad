---
target: флоу онбордингу (iOS + Android)
total_score: 23
max_score: 36
na_heuristics: 9
p0_count: 0
p1_count: 3
target_identity: "file:/Users/tarasvovcenko/StudioProjects/Poruch/iosApp/Poruch/Features/Onboarding/OnboardingView.swift"
target_fingerprint: "sha256:1c546d85f717a769d554345cb207a20b7beb6375ce5b911f6c0c85257ffa1b3e"
target_path: /Users/tarasvovcenko/StudioProjects/Poruch/iosApp/Poruch/Features/Onboarding/OnboardingView.swift
timestamp: 2026-10-17T17-12-44Z
slug: features-onboarding-onboardingview-swift-90c1ff76
closed: true
---
Method: design review only (detector not applicable, native platform)

# Критика: онбординг «Поряд» (вітання → 3 питання → тур по головній → геолокація)

Знято: iPhone SE 3 (iOS 18, 375 pt) з чистої установки, Android Small Phone (360 dp), ніч. Скріни: `.impeccable/review/onboarding/before/`.

## Design Health Score
| # | Heuristic | Score | Key Issue |
|---|---|---|---|
| 1 | Visibility of System Status | 3 | точки кроків туру вночі невидимі |
| 2 | Match System / Real World | 2 | «Яка компанія?» vs «Шукаю компанію»; «Конфе-ренції» |
| 3 | User Control and Freedom | 3 | повтор із профілю знову вітає «Знайомимось» |
| 4 | Consistency and Standards | 2 | кнопка підказки — пігулка; вітання не в мові квитка |
| 5 | Error Prevention | 3 | дві категорії можна не побачити |
| 6 | Recognition Rather Than Recall | 2 | невибрані прапорці/радіо вночі ~1,2:1; категорії під згином |
| 7 | Flexibility and Efficiency | 3 | — |
| 8 | Aesthetic and Minimalist Design | 2 | мозаїка ширша за екран, з'їдає поля |
| 9 | Error Recovery | n/a | помилок у потоці нема (локальне збереження) |
| 10 | Help and Documentation | 3 | — |
| Total | | 23/36 | Acceptable (64%) |

## Design Specificity Verdict
Питання — у мові дому (display-питання, GroupedRows, чорнильна дія), як редактор. Вітання — мозаїка плиток категорій, взаємозамінна з будь-яким застосунком подій; єдиний екран потоку без квитка й без слогана «Є куди. Буде з ким.».

## Priority Issues
- [P1] Мозаїка вітання 368 pt у 343 (SE): розпирає поля екрана до 4 pt; на Android 360 dp остання плитка — смужка. Fix: масштаб від ширини або 3 плитки. /impeccable layout
- [P1] Interests: 4-й ряд (Екскурсії, Конференції) повністю під згином на Android 640 dp, край збігається з краєм — виглядає повним; на SE обрізано й «Конфе-ренції». Fix: нижча плитка ~72, відступ кінця прокрутки, край-градієнт. /impeccable layout
- [P1] Невибрані прапорці/радіо (surfaceMuted на surface ~1,2:1) і кружок плитки вночі невидимі, WCAG 1.4.11. Fix: контур 1,5 ink-tertiary. /impeccable polish
- [P2] Кнопка «Далі»/«Зрозуміло» в турі — Capsule, всупереч «Правилу кута квитка»; коментар «засічками». Fix: Corner.md. /impeccable polish
- [P2] «Яка компанія?» колізія з «Шукаю компанію», підказка-застереження. /impeccable clarify

## Persona Red Flags
- Jordan: бачить 9 категорій; не бачить прапорців уночі; «компанія» = з ким.
- Casey: відповіді в пам'яті до «Готово», закриття — втрата.
- Оля (нова у Львові, SE): вітання лише про ранжування, не про «з ким»; тур «Ваше місто» над «Київ» до питання геолокації.

## Minor Observations
- Порядок слотів не тижневий, хоча коментар каже так.
- Вітання вгорі над порожнечею ~200 pt, а не по центру.
- Повтор із профілю починається з вітання.
- Картка туру на кроці «+» зсувається на 3 pt (ширина 340 vs край 16).
- «Усе місто на мапі» — межує з «повноти не стверджуємо».
- iOS rate_skip/apply vs Android onboarding_skip/onboarding_finish.

## Questions to Consider
- Вітання як перший порожній квиток зі слоганом і корінцями жанрів?
- Чи потрібне окреме вітання для 3 питань?
- Місто як питання нуль?
