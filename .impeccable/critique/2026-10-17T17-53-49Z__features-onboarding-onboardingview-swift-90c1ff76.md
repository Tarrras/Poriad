---
target: флоу онбордингу (iOS + Android), після layout + polish
total_score: 27
max_score: 36
na_heuristics: 9
p0_count: 0
p1_count: 0
target_identity: "file:/Users/tarasvovcenko/StudioProjects/Poruch/iosApp/Poruch/Features/Onboarding/OnboardingView.swift"
target_fingerprint: "sha256:93008afa8ad2ac40cfb1d37183febe19cf10c561a1e0f32711747b24af6be01c"
target_path: /Users/tarasvovcenko/StudioProjects/Poruch/iosApp/Poruch/Features/Onboarding/OnboardingView.swift
timestamp: 2026-10-17T17-53-49Z
slug: features-onboarding-onboardingview-swift-90c1ff76
---
Method: design review only (detector not applicable, native platform)

# Повторна критика після layout + polish: онбординг «Поряд»

Знято: iPhone SE 3 (iOS 18) світла/темна/AX-large, Android Small Phone 360 dp і 1080×2400. Скріни: `.impeccable/review/onboarding/after/`.

| # | Heuristic | Score | Key Issue |
|---|---|---|---|
| 1 | Visibility of System Status | 3 | прогрес і точки туру видно; лічильника вибраних нема |
| 2 | Match System / Real World | 3 | «Який формат?», слоти за тижнем |
| 3 | User Control and Freedom | 3 | повтор із профілю — одразу з питань |
| 4 | Consistency and Standards | 3 | CategoryTile як у шторці; кнопка туру з кутом 14; вітання — квиток |
| 5 | Error Prevention | 3 | — |
| 6 | Recognition Rather Than Recall | 3 | усі 11 категорій без прокрутки; контури позначок |
| 7 | Flexibility and Efficiency | 3 | — |
| 8 | Aesthetic and Minimalist Design | 3 | вітання по центру, поля 16 на SE |
| 9 | Error Recovery | n/a | помилок у потоці нема |
| 10 | Help and Documentation | 3 | — |
| Total | | 27/36 | Good (75%) |

## Лишилось
- [P3] Місто: тур каже «Ваше місто» над типовим «Київ» до питання про геолокацію (порядок — рішення 16.10).
- [P3] «Усе місто на мапі» межує з «повноти не стверджуємо».
- [P3] Відповіді живуть у пам'яті до «Готово».
