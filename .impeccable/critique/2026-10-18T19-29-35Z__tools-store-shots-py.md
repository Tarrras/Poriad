---
target: store screenshots
total_score: 16
max_score: 20
na_heuristics: 3,5,7,9,10
p0_count: 0
p1_count: 0
target_identity: "file:/Users/tarasvovcenko/StudioProjects/Poruch/tools/store_shots.py"
target_fingerprint: "sha256:e15268c415205d1a320b203fab6eca1c9efcf2861b45dfb9dee9d5a03dd2de63"
target_path: /Users/tarasvovcenko/StudioProjects/Poruch/tools/store_shots.py
timestamp: 2026-10-18T19-29-35Z
slug: tools-store-shots-py
---
Method: design review only (detector not applicable, generated raster store graphics, native platform)

Target: store screenshots (store/appstore/iphone69_01..05, store/play/phone_01..05, feature_graphic) from tools/store_shots.py, world «Корінець».

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 3 | Кожен слайд показує одну фічу наживо, винесений шматок тримає фокус |
| 2 | Match System / Real World | 4 | Слоган дослівно, «сотні» замість числа, укриття «поки що для Києва» |
| 3 | User Control and Freedom | n/a | статичні слайди стору |
| 4 | Consistency and Standards | 3 | Штамп як підпис розділу суперечить правилу «штамп лише для стану» |
| 5 | Error Prevention | n/a | статичні слайди стору |
| 6 | Recognition Rather Than Recall | 3 | Одна й та сама подія на слайдах 1 і 4; штамп нечитабельний на мініатюрі |
| 7 | Flexibility and Efficiency | n/a | Persuade |
| 8 | Aesthetic and Minimalist Design | 3 | Сильний квитковий шаблон; дрібні накладки UI під винесеним квитком |
| 9 | Error Recovery | n/a | статичні слайди стору |
| 10 | Help and Documentation | n/a | Persuade |
| **Total** | | **16/20** | **Good (80%)** |

Design specificity: authored. Слайд — квиток із корінцем кольору жанру, перфорація на одній лінії по всьому набору, Sofia Sans Condensed, нічне полотно — це «Корінець», а не шаблон стору.

Fixed in this run: P1 напівпрозорий двійник під піднятим шматком (слайди 1, 2, 5) → суцільний слід; P2 порожнеча під короткими заголовками → текст по центру квитка; P2 «Збирає Taras» латиницею на iOS → «Тарас»; P2 банер Play: тире на початку рядка, обрізаний телефон.

Priority issues (open):
- [P2] Повтор події на слайдах 1 і 4 (iOS «СТЕНДАП в Дороті Паб», Android «Екскурсія „З краси Японії“»). Fix: перезняти карусель мапи з іншою подією.
- [P2] Штамп-контур як підпис розділу («АФІША НА МАПІ») суперечить DESIGN.md: штамп — лише стан квитка. Fix: друкований overline або записати маркетинговий виняток.
- [P3] «Крок 4 з 4» частково під винесеним квитком на слайді 3.
- [P3] Підпис-штамп на мініатюрі пошуку ≈7 px — не читається (несе заголовок, тож не критично).

Personas: Casey (гортає пошук App Store) — перші три слайди читаються з мініатюри: слоган, «Не хочете йти самі?», «Зберіть своїх». Jordan — підзаголовки пояснюють, що таке «компанія» і «від людей». Riley — обіцянок без покриття нема: укриття чесно «поки що для Києва», без чисел подій.
