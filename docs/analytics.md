# Продуктова аналітика «Поряд»

Дата: 2026-09-19. Теорія — [marketing-101.md](marketing-101.md), уроки 2–3. Тут — що саме міряємо і де дивитись.

## Два джерела правди

| Питання | Де відповідь | Чому там |
|---|---|---|
| Скільки людей приєдналось, прийшло, повернулось, створило подію | **Supabase** (SQL нижче) | Це факти в базі: точні, без втрат, без блокувальників реклами |
| Що людина робила **до** дії: відкрила, подивилась, вперлась у порожню мапу чи в реєстрацію | **Firebase Analytics** | У базі цих кроків нема — вони не залишають рядків |

Правило: не логуй у Firebase те, що точно рахується з бази, *для звіту*. `event_join` і `event_create` там є лише для того, щоб зібрати воронку в одному інструменті.

## Словник подій

Логуються зі спільного коду (`PoruchAnalytics.track`), тож однакові на Android та iOS. Жодних id, імен, email, текстів.

| Подія | Коли | Параметри | Стадія AARRR |
|---|---|---|---|
| `first_open`, `session_start`, `user_engagement` | автоматично (Firebase) | — | Acquisition |
| `empty_map` | місто без фільтрів, 0 подій; раз на місто за запуск | `city` | ризик №1 |
| `event_view` | відкрито картку події | `from`: `home_hero`, `home_poster`, `home_people` (рейка «Від людей»), `home_your`, `home_search`; нема — відкрито з іншого екрана (мапа, «Мої події», посилання) | Activation (крок) |
| `auth_wall` | гість спробував дію, що потребує акаунта | — | Activation (втрата) |
| `sign_up` / `login` | успішна реєстрація / вхід | `confirmed` (сесія одразу чи чекає лист) | Activation (крок) |
| `event_join` | успішне приєднання | `by_request` | **Activation** |
| `waitlist_join` | місць нема, став у чергу | — | Activation (провал пропозиції) |
| `event_create` | опубліковано подію | `category`, `approval` | пропозиція |
| `create_start` | тап по «Створити»: гостя після нього чекає реєстрація, тож це попит, а не редактор; публікація — окремо, `event_create` | `from`: `fab` (плюс у таббарі), `home_top` (плашка «Організувати подію» під шапкою головної), `home_footer` (підвал головної), `map`, `mine`; `guest`: `true` — тапнув гість | пропозиція (крок) |
| `digest_prompt` | відповідь на мʼяке питання про пʼятничний дайджест (другий запуск, раз) | `granted` | Retention (згода) |
| `digest_open` | тап по дайджесту «Що поруч на вихідних» | — | **Retention**: чи дайджест повертає людей |
| `share` | відкрито «Поділитися» подією (посилання `poriad.app/e/…` у тексті) | `kind` | **Referral**: чи люди взагалі діляться |
| `link_open` | подію відкрито з посилання на неї | `kind` | **Referral**: чи поширення повертається людьми |
| `companion_create` | створено супутник «Шукаю компанію» на афішу | `category`, `capacity` | **Activation** без організатора: чи бар'єр «нема з ким» знімається |
| `companion_join` | запит у супутник (з картки на афіші чи з його сторінки); іде разом з `event_join` | — | **Activation**: чи на пошук хтось відгукується |
| `follow` | успішна підписка «Стежити» (кнопка на закладі, організаторі чи артисті, перемикач у шторці оцінки) | `target`: `place` / `organizer` / `artist` | **Retention**: чи є на що повертати людей |
| `push_open` | тап по сповіщенню (серверний пуш чи локальне); дайджест окремо — `digest_open` | `reason`: `chat`, `request`, `joined`, `moved`, `cancelled`, `place`, `artist`, `organizer`, `reminder` | **Retention**: який тригер повертає людей, а який лише дратує |

`from` у `event_view` і `create_start` відповідає на два питання про головну: які її частини (велика картка, постер, «Ваше», пошук) справді ведуть до подій і яка з точок входу веде людей до створення: плашка вгорі (`home_top`), плюс у таббарі (`fab`) чи підвал (`home_footer`). Якщо `home_top` не б'є `fab` за кількістю тапів на сесію, плашка не виправдовує місця вгорі.

Воронка створення для гостя (Explore → Funnel exploration): `create_start` (`guest = true`) → `sign_up` → `event_create`. Гостя після тапу чекає екран входу з вкладкою «Реєстрація» й підписом про створення, а після реєстрації — редактор без зайвого тапу; тож розрив між першим і другим кроком показує, скільки людей губить сама реєстрація, а між другим і третім — скільки губить редактор. `guest = false` — ті, хто вже увійшов: їхня частка `create_start → event_create` міряє лише редактор. Порівнюй з попередньою збіркою: `event_view` на людину за сесію й `create_start` до `event_create`.

Нову подію додавай лише тоді, коли можеш назвати рішення, яке зміниться від її числа. Подія «про всяк випадок» — шум, який потім ніхто не читає.

## Воронка у Firebase

Console → Analytics → **Explore** → Funnel exploration, кроки:

```
first_open → event_view → event_join
```

Друга воронка — для гостя: `event_view → auth_wall → sign_up → event_join`. Вона показує, скільки людей губить реєстрація.

Налаштування один раз: Admin → Custom definitions → зареєструвати `city`, `category` і `from` як event-scoped dimensions, інакше по них не можна ділити звіти. Нові події зʼявляються у звітах із затримкою до доби; щоб бачити їх одразу при розробці — DebugView (Android: `adb shell setprop debug.firebase.analytics.app app.poriad.android.dev`, iOS: аргумент запуску `-FIRDebugEnabled` у схемі). Dev-збірки шлють у свій Firebase-проєкт і прод не засмічують.

## SQL для Supabase

Відвідування = людина приєдналась (`approved`), подія не скасована й уже почалась, людина — не організатор.

**North Star — відвідані події на людину, помісячно:**

```sql
select date_trunc('month', e.starts_at)::date as month,
       count(*) as visits,
       count(distinct m.user_id) as people,
       round(count(*)::numeric / nullif(count(distinct m.user_id), 0), 2) as visits_per_person
from public.event_members m join public.events e on e.id = m.event_id
where m.status = 'approved' and e.status <> 'cancelled' and e.starts_at < now()
  and m.user_id is distinct from e.organizer_id
group by 1 order by 1;
```

Точний North Star ділить `visits` на MAU з Firebase, а не на `people`: людина, що відкрила застосунок і нікуди не пішла, теж у знаменнику.

**Тижневий ретеншн когорт** (когорта — тиждень першого відвідування):

```sql
with visits as (
  select m.user_id, date_trunc('week', e.starts_at) as week
  from public.event_members m join public.events e on e.id = m.event_id
  where m.status = 'approved' and e.status <> 'cancelled' and e.starts_at < now()
    and m.user_id is distinct from e.organizer_id
), first as (select user_id, min(week) as cohort from visits group by 1)
select f.cohort::date, count(distinct f.user_id) as people,
  count(distinct v.user_id) filter (where v.week = f.cohort + interval '1 week') as w1,
  count(distinct v.user_id) filter (where v.week = f.cohort + interval '2 week') as w2,
  count(distinct v.user_id) filter (where v.week between f.cohort + interval '3 week' and f.cohort + interval '4 week') as w3_4
from first f join visits v using (user_id) group by 1 order by 1;
```

Читай форму кривої, не рівень: плато — є ядро, падіння в нуль — продукту ще нема.

**Створення подій: нові акаунти й спільнотні події по тижнях** (з бази, без Firebase; читати до й після релізу з плашкою «Організувати подію»):

```sql
select w.week::date as week,
       (select count(*) from auth.users u where date_trunc('week', u.created_at) = w.week) as new_accounts,
       (select count(*) from public.events e where e.origin = 'community' and date_trunc('week', e.created_at) = w.week) as community_events,
       (select count(distinct e.organizer_id) from public.events e where e.origin = 'community' and date_trunc('week', e.created_at) = w.week) as organizers
from generate_series(date_trunc('week', now()) - interval '12 weeks', date_trunc('week', now()), interval '1 week') as w(week)
order by 1;
```

## Плашка «Організувати подію»: що міряти й коли вирішувати

Плашка вгорі головної повернула створенню місце, яке воно мало в старій версії, але чи виправдовує вона його, покаже лише трафік.

**Базова лінія на 2026-09-30 (prod).** Акаунтів усього 3: перший 05.09, останній **15.09**, тож після релізу в App Store 27.09 нових нема. Спільнотних подій 8 від 3 організаторів (перша 11.09, остання 24.09) і 10 підтверджених приєднань від 3 людей: тижні 07.09 / 14.09 / 21.09 дали 2 / 3 / 3 події, тиждень 28.09 — 0. Усе це зробили ті самі три акаунти. До появи плашки й `create_start` воронка створення від сторонніх людей нульова, і вузьке місце в ній не плашка, а те, що в застосунок ще ніхто не заходить: порівнювати `home_top` з `fab` нема на чому, поки не з'явиться хоч кілька десятків сесій. `create_start` з `from` іще не вийшов до людей: iOS 1.1.0 (9) без нього.

**Коли вирішувати.** Не раніше, ніж набереться 50 подій `create_start` (правило цього документа: до ~50 людей на кроці цифри — шум), і лише за збірку з `from`. Читати: Explore → Free form, рядки — параметр `from`, значення — кількість `create_start`; знаменник — `session_start` тієї ж версії.

**Правило.**
1. Частка `home_top` серед усіх `create_start`. Не менша за `fab` — плашка виправдовує місце, лишаємо. Менша за чверть — зменшуємо до рядка-посилання (як `home_footer`) і віддаємо екран контенту.
2. `create_start` (`guest = true`) → `sign_up`. Менше третини доходить — проблема в реєстрації (довжина форми, підтвердження пошти), а не в плашці: чіпати екран входу, не головну.
3. `sign_up` → `event_create`. Втрата тут — редактор (три кроки), а не вхід чи плашка.
4. Якщо `event_create` не росте, а `home_top` росте, — плашка тягне людей, яких редактор не тримає: чинити редактор.

Одне число нічого не вирішує; записуй три частки й одне речення «що я змінив», як у щотижневому ритуалі.

## Щотижневий ритуал (15 хвилин, понеділок)

1. **Нові люди** — `first_open` за тиждень, з якого каналу (див. marketing-101, Install Referrer і campaign links).
2. **Конверсія `event_view → event_join`** — найдешевший важіль, це продукт, а не реклама.
3. **Частка сесій з `empty_map`** і в яких містах — де бракує пропозиції.
4. **Ретеншн тижня 1** для когорти двотижневої давнини.

Записуй чотири числа в таблицю й одне речення «що я змінив». Без запису через місяць не згадаєш, від чого число зрушило.

До ~50 людей на кожному кроці воронки цифри — шум. На старті важливіше говорити з людьми.

## Звіти про помилки (Crashlytics non-fatal)

Аналітика відповідає «скільки людей дійшло», звіти — «що зламалось і де». Тому помилки йдуть не подіями
в Analytics (там нема стеку й контексту), а non-fatal у Crashlytics: зі стеком, моделлю пристрою, версією
і логом кроків перед збоєм. Вхід один — `PoruchLog.report`, сінк ставить платформа.

| Що | Де ловиться | Назва проблеми в консолі |
|---|---|---|
| Сервер відмовив, а ми не впізнали чому: нове `raise exception`, RLS (`42501`), 5xx, `PGRST*` | `apiFailure` | `http: POST /rest/v1/rpc/join_event 400 P0001 RATING_CLOSED` |
| Відповідь не розібрати | `ApiClient` | `http: GET /rest/v1/profiles unreadable body` |
| Будь-який чужий виняток у сценарії: розбір JSON, стан, платформа | `asAppError()` | `unexpected: MissingFieldException` (+ яке поле) |
| Не отримали пуш-токен | `Push.kt`, `Push.swift` | `push: token failed`, `push: apns registration failed …` |

**Не звітуємо** очікуване: нема мережі, 401, 429 і всі названі відмови (`EVENT_FULL`, `TOO_YOUNG`…) — їх
показуємо людині, код тут не лагодиться. Нова серверна відмова, якої клієнт ще не знає, якраз з'явиться
у звітах — сигнал додати її в `SERVER_ERRORS`.

**Кроки перед збоєм** — `PoruchLog.i/w/e` у будь-якій збірці йдуть у `Crashlytics.log` (`d` — лише в debug).
Правила ті самі, що для логу: без email, текстів і повних id.

**Як читати:** Firebase → Crashlytics → фільтр *Non-fatals*. Dev-збірка шле у dev-проєкт. Звіти приходять
після наступного запуску застосунку. Перемикач «Аналітика» в профілі вимикає і їх.

## Свідомо не зроблено

- **`screen_view`** — SwiftUI і Compose їх не шлють самі; воронці вистачає подій вище.
- **Факт відвідування** — у застосунку нема відмітки «я прийшов», тож «відвідано» = приєднався + подія минула. Це верхня межа.
- **`setUserId`** — політика обіцяє, що аналітика не повʼязана з акаунтом. Не вмикати без правки [privacy](../site/privacy.html).
- **Згода на аналітику** — не питаємо: підстава — законний інтерес, а відмова — перемикач «Аналітика» в профілі (`setAnalyticsCollectionEnabled`). Так описано в [privacy](../site/privacy.html) і в Data safety (`store/listing.md`): аналітика необов'язкова, дані псевдонімні (ідентифікатор екземпляра застосунку), без рекламних ідентифікаторів.
