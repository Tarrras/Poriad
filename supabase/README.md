# Poruch backend

Applied to the explicitly selected hosted project `tzdogzdvctlumsqlqskr` (`EventOrganiztor`) on 2026-09-05. The initial migration was created with the Supabase CLI, applied using the Supabase MCP `apply_migration` operation, then its local timestamp was aligned with the server-returned migration version `20260905101755`.

The public RPC contract matches `../docs/implementation-plan.md`. `events_in_view` returns at most 300 future published events; category, dates and spatial filtering run before this bound. Longitude bounds with west > east cross the antimeridian. Times are `timestamptz`; date filters are `[from,to)`. `my_events` includes organized, joined and saved events, including cancelled history. Guests can read public event details and aggregates but cannot read member identities or mutate data.

All five public tables have RLS and explicit grants. Clients cannot write events or memberships directly. Public mutation RPCs are invokers calling privileged implementations in unexposed `private`. Every mutation derives its user from `auth.uid()`. Search paths are empty and relations fully qualified. Do not add `private` or `gis` to the Data API exposed schemas. `private` schema usage and narrow execute grants are necessary for invoker wrappers and policies, and do not expose REST endpoints.

Joining, leaving, cancellation and editing lock the same event row. Duplicate joins are idempotent, hosts do not consume guest capacity, and capacity cannot be reduced below attendance. Creating uses the client-generated UUID plus a transaction advisory lock so uncertain-response retries return the same event. A retry with an existing UUID returns the original event ID without overwriting its fields; editing is a separate RPC.

The `event-images` public bucket allows JPEG, PNG and WebP up to 5 MiB. Write paths must be `<authenticated-user-id>/<owned-event-id>/<filename>`. Create the event first, upload the image, then update `image_url`. Insert, update/upsert and delete all enforce event ownership. Image reads are public; do not upload private material. Both native clients include system photo-picker upload on an existing owned event; iOS converts to JPEG. Transport and physical-device upload QA remain separate from SQL policy tests.

`profiles` contains only display name/avatar and is populated by an Auth trigger; signup metadata is used only for the display name. `user_preferences` stores private categories and reminder opt-in. Profile email is never copied into public tables. Configure email confirmation and native redirect URLs in Auth before production use; this migration does not change project-wide Auth settings.

## Attendee roster

`migrations/20260905203918_event_attendees.sql` adds `public.attendee_result` and `public.event_attendees(uuid,integer)`, applied to the same hosted project on 2026-09-05 through the Supabase MCP `apply_migration` operation; the local file name carries the server-returned version.

The function is an invoker, so `members_read` on `event_members` and `profiles_read` on `profiles` govern it unchanged: the organizer and confirmed members read identities, a signed-in stranger gets an empty set, and `anon` holds no execute grant. The aggregate `attendee_count` in `event_result` is untouched and stays visible to everyone, so this adds no new exposure of who attends what. `p_limit` is clamped to `[1,100]` rather than trusted. Both clients treat the roster as best-effort: a failure leaves the count-only view instead of an error.

## Waiting list

`migrations/20260905221357_event_waitlist.sql` adds `public.event_waitlist`, the queue RPCs and the promotion helper; `migrations/20260905221547_event_waitlist_grants.sql` adds the execute grants the invoker wrappers need on their private implementations. Both applied on 2026-09-05; local file names carry the server-returned versions.

A full event is no longer a dead end. `join_waitlist` accepts a position only when the event is published, future, and actually full; the organizer and existing members are refused. Positions are private — `waitlist_read` restricts `event_waitlist` to its own holder, and `my_waitlist` returns only the caller's rows, so waiting for an event never becomes a public signal. There is no aggregate queue length in any projection.

Places free up in two ways and both advance the queue inside the transaction that already holds the event row lock: `leave_event` and a capacity increase in `update_event` both call `private.promote_waitlist`, which fills places from the head of the queue by `created_at`. Joining outright drops any position the same person held. `promote_waitlist` carries no execute grant: it is reached only from inside definer functions, which run as the owner.

## Безпека, вік і скарги

`migrations/20260906195750_safety_age_and_reports.sql` (застосовано до того самого проєкту 2026-09-06 через Supabase MCP `apply_migration`; локальне імʼя файлу несе версію, яку повернув сервер) додає: `public.account_facts` (задекларована дата народження і статус модерації — окремо від world-readable `profiles`), `public.user_blocks`, `public.reports`, вікові межі та підтвердження участі на `public.events`, стан рядка в `public.event_members`, і переписує проєкцію `public.event_result` разом із функціями, що її повертають.

Платформний мінімум віку — `private.min_signup_age()` (18). Він перевіряється тригером `private.handle_new_user` у транзакції, що створює акаунт (метадані `birth_date`), і `public.set_birth_date` для акаунтів, створених раніше — один раз, далі це дія модерації. `private.assert_can_join` — єдине місце, де зібрані всі причини відмови: обмежений акаунт, блокування, невказаний вік, замолодий, застарий. Його викликають і `join_event`, і `join_waitlist`, і `promote_waitlist` (просування черги — це приєднання, на якому людини немає поруч), і `decide_member` (правила перевіряються ще раз у момент прийняття).

Підтвердження участі: `event_members.status` — `requested` або `approved`. Усе, що рахувало учасників, рахує лише підтверджених, тож запит не займає місця; ростер і `attendee_count` теж показують тільки підтверджених. Організатор читає запити через `public.event_requests` і відповідає через `public.approve_member` / `public.decline_member`.

Блокування симетричне й діє в проєкції: `private.event_rows` ховає події заблокованих і заблокувавших, а також обмежених акаунтів — окрім власних для самого власника. Скарги приватні для автора (`reports_reporter`), дедуплікуються на рівні RPC і обмежені 10 на годину; створення подій — 6 на добу.

`migrations/20260906200401_event_requests_invoker.sql` знімає `security definer` з `public.event_requests`: організатор і так проходить `can_view_members` для власної події, а `where e.organizer_id=auth.uid()` лишається на місці. Це прибрало єдине попередження лінтера після міграції.

Клієнти терплять сервер без цієї міграції: нові поля мають значення за замовчуванням, а виклики безпекових RPC — best-effort.

## Verification

Executed successfully on the selected project:

- `tests/access_and_transactions.sql`: profile/preferences triggers; idempotent create and join; direct event/member writes denied; owner-only edits/cancellation; saved/profile/preferences/roster isolation; full capacity and capacity reduction; cancelled history and exclusion; idempotent leave; guest mutation rejection; owner image path checks; past time, coordinate, timezone, end time and capacity validation.
- `tests/discovery.sql`: both sides of antimeridian, ordinary bounds, category/date filters, 300-result bound, guest aggregate projection and invalid bounds.
- `tests/attendees.sql`: roster readable by a member and by the organizer, ordered by join time; a signed-in stranger reads no identities but still reads `attendee_count`; guests are refused by the missing execute grant; `p_limit` clamped up from `0`, down from `10000`, and defaulted from `null`. Executed on the selected project on 2026-09-05: **PASS**, with 0 events, 0 profiles, 0 members and 0 synthetic test users remaining. Because `now()` is the transaction timestamp, both joins in a single transaction share one `joined_at`; the suite spreads them apart so the ordering guarantee is genuinely exercised rather than decided by the uuid tiebreak.
- `tests/waitlist.sql`: a full event refuses `join_event` with `EVENT_FULL` but accepts a queue position; queueing twice is idempotent; members get `ALREADY_MEMBER` and the organizer `ORGANIZER_CANNOT_JOIN`; positions stay private between two queued accounts; leaving promotes the head of the queue and clears its position while capacity holds; raising capacity promotes the next one; an event with room refuses queueing with `EVENT_HAS_SPACE`; leaving a queue you are not in is a no-op; guests are refused by the missing execute grant. Executed on the selected project on 2026-09-05: **PASS**, 0 rows left behind. As in the roster suite, queue rows created in one transaction share `created_at`, so the suite spreads them apart before asserting promotion order.
- `tests/safety.sql`: вікова межа при реєстрації; одноразове `set_birth_date`; `TOO_YOUNG` / `AGE_REQUIRED`; межі `INVALID_AGE_LIMIT`; запит не займає місця й невидимий у ростері; чужий не бачить і не приймає запити; блокування ховає подію та зачиняє двері в обидва боки; заблокований акаунт бачить лише власні події й не може створювати чи приєднуватись; скарга приватна, дедуплікується й обмежена 10 на годину. Виконано на проєкті 2026-09-06: **PASS**, 0 синтетичних користувачів лишилось.
- Регресія після міграції: `tests/access_and_transactions.sql`, `tests/waitlist.sql`, `tests/attendees.sql`, `tests/discovery.sql`, `tests/map_search.sql` — усі **PASS**. Фікстури цих наборів тепер створюють користувачів із `birth_date` у метаданих: без задекларованого віку приєднання відмовляє, і без цієї правки набори перевіряли б не те, для чого написані. `tests/discovery.sql` додатково рахує лише власні фікстури (`title like 'Geo %'`), бо в проєкті вже є справжні події в тому самому Києві.
- Радник безпеки після міграції: єдине попередження — `auth_leaked_password_protection` (налаштування Auth рівня проєкту, не змінювалося цією роботою). Рекомендую увімкнути перевірку паролів за HaveIBeenPwned.
- `tests/access_and_transactions.sql` re-run after the waiting list replaced `join_event`, `leave_event` and `update_event`: **PASS**, no regression.
- The `my_waitlist` response shape was confirmed over PostgREST — a scalar `setof uuid` returns a flat JSON array of strings, which is what the client parses.
- Advisors after this migration: security **zero findings**; performance one informational unused-index notice on the empty database (`events_category_starts_idx`), retained for the same reason as before.
- All SQL suites use `BEGIN` / `ROLLBACK`, including synthetic Auth users. After tests: **0 events, 0 profiles, 0 synthetic test users** remained.
- Security advisor: **zero findings**. No public SECURITY DEFINER functions.
- Performance advisor: two informational unused-index notices on a fresh empty database (`events_category_starts_idx`, `saved_events_event_idx`). Retained because these support expected category queries and cascading foreign keys. [Advisor explanation](https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index).
- Live concurrent capacity test: **PASS**. Two parallel database transactions called `join_event` for the last place, with a three-second lock hold. Exactly one succeeded and the other returned `EVENT_FULL`; stored membership count was 1. A single bounded orchestration used `try/finally` cleanup; final checks showed **0 remaining test users and 0 remaining test events**. The earlier isolated setup was rejected by automatic review; the complete cleanup-scoped run was accepted.
- `tests/concurrent_capacity.py`: Python syntax checked; reusable two-connection runner with a `finally` cleanup that verifies deletion. Requires `psycopg[binary]==3.2.9` and `TEST_DATABASE_URL` pointed at an authorized test database. The live run above used the Supabase SQL tool concurrently, not this Python transport.

## Завершені імпортовані події

`20260915120000_stale_finished_imports.sql` додає `private.retire_finished_imports(p_grace)`: імпортовані події, що закінчились понад тиждень тому, отримують `import_status='stale'`. Не `delete`: збережена подія лишається з чесною позначкою. Тиждень запасу потрібен, бо перенесений сеанс джерело часто публікує під тим самим ключем, і наступний дамп повертає рядок у `live` через upsert. Викликається останньою командою кожного дампу `tools.ingest` (`emit.retire_finished_sql`), тож окремого планувальника немає: очищення їде разом зі щоденним `apply_sql.py run --apply`. Спільнотні події не чіпаються. Застосовано 2026-09-15: 15 рядків стали `stale`.

## Застосування SQL із коду

`tools/apply_sql.py` застосовує міграції й дампи конвеєра прямим зʼєднанням з Postgres, без SQL Editor і без MCP. Рядок зʼєднання — `SUPABASE_DB_URL` у середовищі чи в `.env` (Dashboard → Connect → Session pooler; transaction pooler не годиться для довгих транзакцій). Потрібен `psycopg[binary]`.

```bash
python3 tools/apply_sql.py migrations          # що не застосовано; --apply виконує й записує в реєстр CLI
python3 tools/apply_sql.py dump out/ --apply     # SQL від tools.ingest; маніфест задає порядок частин і звіряє sha256
python3 tools/apply_sql.py all ~/sql-2026-09-15 --apply   # день змін: нові міграції, потім poruch-events-1…N.sql по черзі
```

`all` сортує файли даних як числа (`-2` перед `-10`) і веде журнал `.applied_sql.json` поруч із ними: після збою на девʼятому файлі повторний запуск пропускає перші вісім, а змінений файл застосовує знову. `--force` ігнорує журнал.

`run` робить повний цикл сам: створює теку `out/sql-<дата>`, кладе туди копії ще не застосованих міграцій, генерує дамп конвеєром `tools.ingest` (аргументи конвеєра після `--`), застосовує спершу міграції, потім дані, і за успіху видаляє теку. Після збою тека лишається з журналом і `report.json`; дозастосувати її можна через `all <тека> --apply`. Джерело, що не обійшлось, лише згадується в попередженні: конвеєр і так не знімає його події; `--strict` натомість зупиняє запис.

```bash
python3 tools/apply_sql.py run --apply -- --city Київ
```

Реєстр — `supabase_migrations.schema_migrations`, спільний із Supabase CLI. Частину міграцій цього проєкту застосовано з Dashboard під іншими штампами часу, тому міграція вважається застосованою, якщо в реєстрі є її версія або її назва; скрипт показує обидва випадки окремо. Міграцію, яка вже виконана вручну, але в реєстрі відсутня, записують без виконання: `migrations --mark-applied <назва>` (так зроблено з `listing_has_no_capacity` 2026-09-15).

To repeat SQL tests, execute each whole file as a database administrator through the SQL editor or `psql -v ON_ERROR_STOP=1 "$TEST_DATABASE_URL" -f tests/access_and_transactions.sql`. Do not run partial fixture sections. This test uses database JWT claim emulation to test Postgres authorization; it does not replace device Auth, email callback, upload transport or end-to-end UI tests.

## Errors

Stable message strings: `AUTH_REQUIRED`, `EVENT_NOT_FOUND`, `NOT_ORGANIZER`, `ORGANIZER_CANNOT_JOIN`, `EVENT_FULL`, `EVENT_HAS_SPACE`, `ALREADY_MEMBER`, `EVENT_CANCELLED`, `EVENT_STARTED`, `START_MUST_BE_FUTURE`, `INVALID_TIME_ZONE`, `INVALID_BOUNDS`, `CAPACITY_BELOW_ATTENDANCE`. Constraint violations use standard Postgres SQLSTATEs. UI should translate messages, not expose raw SQL diagnostics.

## Імпорт подій із зовнішніх джерел

`migrations/20260907120000_event_ingestion.sql` і `migrations/20260907130000_import_without_organizer.sql` застосовано до того самого проєкту 2026-09-07 через Supabase MCP `apply_migration`. Обґрунтування джерел і виміряні числа — [../docs/event-discovery.md](../docs/event-discovery.md).

Міграція додає `public.event_sources` (реєстр джерел із правилами обходу), `public.venues` (кеш майданчиків), поля імпорту на `public.events` і приватні `private.ingest_runs` / `private.ingest_items`. Композитний тип `public.event_result` перестворюється разом із пʼятьма залежними функціями — тим самим порядком, що й у міграції безпеки, бо це єдиний чесний спосіб змінити тип.

**Межа тримається в базі, а не в клієнті.** `private.assert_can_join` тепер відмовляє з `IMPORTED_EVENT` раніше за всі інші перевірки: місткості чужого концерту ми не знаємо й не керуємо нею, тож «приєднатися» було б обіцянкою, яку нема кому виконати. Це та сама функція, яку викликають `join_event`, `join_waitlist`, `promote_waitlist` і `decide_member`, тож жоден шлях приєднання її не оминає. `private.assert_event_editable` так само закриває редагування.

`private.is_discoverable` — один вимикач видимості для мапи й пошуку: `community` видно завжди, імпорт — лише при `import_status='live'` і `quality >= 0.55`. Відкликана подія при цьому лишається доступною тому, хто її зберіг: порожній збережений запис гірший за позначку «більше не проводиться».


### Друга міграція: чому імпорт не має організатора

Перша версія вимагала для кожного джерела «синтетичний профіль». Це виявилось хибним ходом: `public.profiles.id` посилається на `auth.users.id`, тож ішлося про фантомні облікові записи в таблиці автентифікації — які довелося б виключати з пошуку людей, блокувань, скарг і відновлення пароля. `20260907130000_import_without_organizer.sql` знімає `not null` з `events.organizer_id` і переносить обов'язковість туди, де вона справді потрібна: `events_community_has_organizer_ck` вимагає організатора лише для подій, до яких можна приєднатися. Ім'я на картці імпортованої події бере `coalesce(profiles.display_name, event_sources.name)` — модель тепер збігається з тим, що показує UI.

### Перевірено після застосування

| Перевірка | Результат |
|---|---|
| Наявні спільнотні події в `events_in_view` | повертаються, регресії немає |
| `assert_can_join` на імпортованій події | `IMPORTED_EVENT` |
| `assert_event_editable` на імпортованій | `IMPORTED_EVENT` |
| `events_origin_source_ck` на імпорті без джерела | вставка відхилена |
| `is_discoverable('import','live',0.4)` | `false` — нижче порога якості |
| `is_discoverable('import','withdrawn',0.9)` | `false` — відкликана зникає з видачі |

`public.venues` навмисно має RLS без політик: це внутрішній кеш геокодування, клієнтам він не потрібен, бо координати приходять уже в проєкції події. Лінтер повідомляє про це на рівні INFO (`rls_enabled_no_policy`) — очікувано, не дефект.

### Стан даних і відкат

Засіяно три джерела (`karabas` і `concert_ua` увімкнені, `moemisto` вимкнене до перевірки його зсуву часу), 34 майданчики, перша партія імпортованих подій Києва. Повний набір генерується `python3 -m tools.ingest --city Київ --sql out.sql`.

```sql
update public.events set import_status='withdrawn' where ingest_run_id = '<run_id>';
delete from public.events where origin = 'import';   -- прибрати весь імпорт
```

### Третя міграція: часовий пояс karabas

`20260907140000_karabas_timezone_policy.sql` розширює `tz_policy` значенням `utc_is_local` і виправляє вже завантажені події. karabas віддає коректний зсув, але зсуває сам момент рівно на нього: сторінка показує «17 жовтня 2026, 18:00», JSON-LD каже `2026-10-17T21:00:00+03:00`. Виправлено 142 події; після цього всі сім пар, наявних одночасно в karabas і concert.ua, збігаються хвилина в хвилину.

Виявила ваду **дедуплікація**, а не перевірка розмітки: розбіжність між джерелами дорівнювала UTC-зсуву. Це аргумент за те, щоб дублікати між джерелами не приховувати автозлиттям, доки на них не подивилась людина.

## Четверта міграція: видача двома рівнями

`20260911070031_discovery_index_and_cards.sql` розділяє одну відповідь на дві: **індекс** і
**картки**. Причина — не швидкість сама по собі, а стеля: `search_events_in_view` брав
`order by starts_at limit 300`, і 163 київські події просто не існували для застосунку.

Стеля стояла там, бо одна відповідь несла і те, чим мапа ставить пін, і те, чим картка малює
обкладинку. Розділені, вони обидві дешевшають настільки, що обмеження стає непотрібним:

| Запит | Рядків | Розмір | Прогріте виконання |
|---|---|---|---|
| `search_events_in_view`, Київ | 300 із 432 | 306 КБ | 95 мс |
| `discover_events`, Київ | **432** + 24 картки | 103 КБ | **14 мс** |

`private.discover_index` — `security definer`, і це не зручність. Набір обмежений
`status='published'`, а `private.has_event_access` для опублікованої події повертає `true`
беззастережно, тож RLS на цьому шляху нічого не вирішує — лише виконується, по разу на кожен із
432 рядків. Прибрано виконання, не правило: блокування й неактивні акаунти перевіряються всередині,
інакше лічильник рахував би події, яких цей читач не побачить.

Індекс — масив масивів, а не масив обʼєктів: основною вагою старої відповіді були не значення, а
двадцять вісім разів повторені назви полів. Картки йдуть через `jsonb_strip_nulls`, тож із 1254
афіш зникає по вісім ключів (місткості й членства в них немає), а з подій спільноти — джерело й
ціна квитка. Клієнт це переживає без правок: у `EventDto` кожне таке поле має значення за
замовчуванням, а розбір іде з `ignoreUnknownKeys`.

Композит `public.event_result` **не** перестворювався: нові функції повертають `jsonb`, тож
пʼять залежних функцій лишились на місці разом зі своїми грантами. Усе, що змінює наявне, —
`create or replace` з тією самою сигнатурою.

### Дві пастки, на які пішло по заміру

**`matched` сканувався тричі.** Перша редакція рахувала `count(*) from matched` окремо від
`limit`, а CTE з трьома посиланнями Postgres матеріалізує й перечитує. 45 мс. `count(*) over ()`
дає повне число тим самим проходом вікна, яким нумеруються рядки: 15 мс.

**`plan_cache_mode='force_custom_plan'` робить гірше.** Здавалося, що узагальнений план не візьме
gist-індекс, бо межі приходять параметрами. Виміряно — бере. А планування цього запиту коштує
~50 мс (оператори PostGIS і схема `gis`), тож примусове перепланування перетворювало 14 мс на 45.
Перший виклик у зʼєднанні платить за план, решта — ні; у пулі PostgREST це одна відповідь на
процес, а не на запит.

### Фільтр «Є місця»

`private.event_has_space` тепер перевіряє `capacity is not null` до всього іншого. Семантика та
сама — порівняння з null і так давало «ні», — але тепер це видно планувальнику. Місткість
заповнена у 2 подій із 1295: підзапит виконується двічі замість 463 разів, 470 мс → 46 мс. Той
самий запобіжник додано і в `search_events_in_view`, щоб збірки, які ще не знають про
`discover_events`, теж перестали за це платити.

### Перевірка

| Перевірка | Результат |
|---|---|
| `discover_events` під `anon`, Київ | 432 події, `truncated=false`, 24 картки |
| `search_events_in_view` під `anon` | 300 рядків, 2 з місцями, 4 за текстом — без змін |
| `event_cards_by_ids` на неопублікованих | порожньо |
| Радник безпеки | нових попереджень немає (`venues` RLS-без-політик і `auth_leaked_password_protection` — обидва були раніше) |

Клієнти терплять сервер без цієї міграції: `search_events_in_view` лишається на місці, а виклик
`discover_events` на старому сервері відповідає `PGRST202`.

## Події, що вже тривають

`migrations/20260911120000_ongoing_events.sql`. Запит на зміну й виміряні числа —
[../docs/ongoing-events-change-request.md](../docs/ongoing-events-change-request.md).

Конвеєр давно імпортував виставки, ярмарки й фестивальні програми, але показати їх було нікому:
і `private.discover_index`, і `public.search_events_in_view` відсікали подію за часом **початку**.
На обході пʼяти міст під цю умову потрапляли 62 події, яких застосунок не показував жодного дня
їхнього прокату.

**Три класи, а не один.** Тих 62 не можна впустити разом. Менші за добу (46) — це концерт чи
вистава, що почались годину тому. 8–86 днів (6) — реальний прокат, заради якого все й робиться.
Понад 110 днів (10) — постійний атракціон, проданий квитком: «Київський океанаріум», «Музей
медуз», VR-екскурсія, майстер-клас із кінцем через 560 днів. У третього класу `endDate` — це не
кінець події, а дата, доки діє квиткова пропозиція.

**Межа стоїть при імпорті, а не при показі.** `tools/ingest/pipeline.py`, `PERMANENT_RUN` — 90
днів. Фільтр у базі сховав би рядок, але рядок лишився б, займав місце в індексі й спливав у
кожному новому запиті, який хтось напише пізніше. Межа евристична: у вибірці реальний прокат
укладався в 86 днів, найкоротша постійна пропозиція починалась зі 111. Підібрано на одній
вибірці, а не виміряно.

**Порядок ламається в іншому файлі, ніж умова.** `ends_at > now()` впускає виставку, що почалась
38 днів тому, а `order by starts_at` поставив би її першою й лишив там до кінця прокату. Обидві
функції сортують за `greatest(starts_at, now())`: усе, що вже йде, згортається в одну точку
«зараз» і далі розрізняється за `id`, а не за тим, хто почався давніше. Той самий ключ рахує
клієнт (`TasteRanking.interestingAt`) — розійтись їм не можна, бо вікно карток приїжджає під
серверний порядок.

Це не ставить прокат нижче за майбутні події: усе, що йде зараз, лишається попереду того, що
почнеться пізніше. Змінюється лише те, що найдовший прокат більше не пришпилений до першого
місця.

**Чого міграція не чіпає.** `p_from`/`p_to` лишаються на `starts_at`: «на вихідних» — це питання
про те, що **почнеться** на вихідних, а не про те, що тоді триватиме. `public.events_in_view` теж
лишається на `starts_at` — жоден клієнт її не викликає, і третє місце з цією умовою було б
зайвим.

### Перевірка

| Перевірка | Як |
|---|---|
| Постійні пропозиції зняті | `select count(*) from public.events where origin='import' and import_status='live' and ends_at-starts_at > interval '90 days'` → 0 |
| Прокат видно | `select count(*) from public.events where status='published' and ends_at>now() and starts_at<=now()` до і після зміни умови |
| Пошук «на вихідних» | не повертає виставку, що почалась місяць тому |
