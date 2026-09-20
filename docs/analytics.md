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
| `event_view` | відкрито картку події | — | Activation (крок) |
| `auth_wall` | гість спробував дію, що потребує акаунта | — | Activation (втрата) |
| `sign_up` / `login` | успішна реєстрація / вхід | `confirmed` (сесія одразу чи чекає лист) | Activation (крок) |
| `event_join` | успішне приєднання | `by_request` | **Activation** |
| `waitlist_join` | місць нема, став у чергу | — | Activation (провал пропозиції) |
| `event_create` | опубліковано подію | `category`, `approval` | пропозиція |

Нову подію додавай лише тоді, коли можеш назвати рішення, яке зміниться від її числа. Подія «про всяк випадок» — шум, який потім ніхто не читає.

## Воронка у Firebase

Console → Analytics → **Explore** → Funnel exploration, кроки:

```
first_open → event_view → event_join
```

Друга воронка — для гостя: `event_view → auth_wall → sign_up → event_join`. Вона показує, скільки людей губить реєстрація.

Налаштування один раз: Admin → Custom definitions → зареєструвати `city` і `category` як event-scoped dimensions, інакше по них не можна ділити звіти. Нові події зʼявляються у звітах із затримкою до доби; щоб бачити їх одразу при розробці — DebugView (Android: `adb shell setprop debug.firebase.analytics.app app.poriad.android.dev`, iOS: аргумент запуску `-FIRDebugEnabled` у схемі). Dev-збірки шлють у свій Firebase-проєкт і прод не засмічують.

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

## Щотижневий ритуал (15 хвилин, понеділок)

1. **Нові люди** — `first_open` за тиждень, з якого каналу (див. marketing-101, Install Referrer і campaign links).
2. **Конверсія `event_view → event_join`** — найдешевший важіль, це продукт, а не реклама.
3. **Частка сесій з `empty_map`** і в яких містах — де бракує пропозиції.
4. **Ретеншн тижня 1** для когорти двотижневої давнини.

Записуй чотири числа в таблицю й одне речення «що я змінив». Без запису через місяць не згадаєш, від чого число зрушило.

До ~50 людей на кожному кроці воронки цифри — шум. На старті важливіше говорити з людьми.

## Свідомо не зроблено

- **`screen_view`** — SwiftUI і Compose їх не шлють самі; воронці вистачає подій вище.
- **`share`** — поширення живе в UI кожної платформи; додати, коли почнемо міряти Referral.
- **Факт відвідування** — у застосунку нема відмітки «я прийшов», тож «відвідано» = приєднався + подія минула. Це верхня межа.
- **`setUserId`** — політика обіцяє, що аналітика не повʼязана з акаунтом. Не вмикати без правки [privacy](../site/privacy.html).
- **Згода на аналітику** — для ЄС знадобиться (GDPR); поки аудиторія — Україна, не робимо.
