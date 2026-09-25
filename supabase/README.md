# Поряд backend

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
- `tests/places.sql`: пошук місць за префіксом назви, адресою й рамкою; місце без майбутніх подій сховане; `place_events` віддає картки місця з `place_name`; порожній і задовгий запит. Виконано на dev 2026-09-25: **PASS**.
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

## Чат учасників і стрічка запитів

`20260915223806_contact_link_and_request_feed.sql` закриває дві прогалини спільнотних подій.

**Чат.** `events.contact_url` — посилання на чат учасників (Telegram, Instagram, Viber…), яке організатор кладе в подію. CHECK і `private.assert_contact_url` (помилка `INVALID_CONTACT_URL`) пропускають лише `https://` без пробілів до 500 символів; порожній рядок з редактора стає `null`. Проєкція `event_result` отримала атрибут `contact_url` через `alter type … add attribute`, тож функції на композиті не перестворювались, переписано лише `private.event_rows`: посилання віддається організатору й підтвердженим учасникам, решті — `null`. Запит без відповіді й черга ще не всередині. `create_event` / `update_event` мають новий останній параметр `p_contact_url text default null`; стару сигнатуру знято, щоб PostgREST не вибирав між двома. Клієнт надсилає параметр лише коли посилання є, тож сервер без цієї міграції далі приймає події без чату. Вміст за посиланням ніхто не перевіряє: обидва клієнти показують попередження з хостом перед виходом із застосунку.

**Стрічка запитів.** `public.my_join_requests(p_limit)` повертає `join_request_result` (`event_id, user_id, display_name, avatar_url, requested_at`) для всіх запитів до опублікованих і ще не завершених подій організатора, свіжіші першими, ліміт `[1,200]`. Invoker: `members_read` і `profiles_read` вже пускають організатора до цих рядків. Клієнт читає стрічку разом із `my_events` (при відкритті, поверненні на передній план і після кожної дії), показує її на головній і дзвонить локальним сповіщенням про ключі `event:user`, яких ще не бачив. Пуш-інфраструктури нема, тож поза застосунком сповіщення не прийде.

`tests/contact_and_requests.sql`: організатор і учасник читають посилання, сторонній і гість — `null`; `http://`, `javascript:` і задовгий рядок відхиляються з `INVALID_CONTACT_URL`; порожнє стає `null`; стрічка показує обидва запити свіжішим першим, поважає ліміт, порожніє після відповіді та після скасування; гість не має гранту.

## Чат події

`20260915225504_event_chat.sql` (застосовано 2026-09-16 через Supabase MCP `apply_migration`) додає `public.event_messages` і RPC чату. Хто читає й пише — те саме правило, що для ростера: `private.can_view_members`, тобто організатор і підтверджені учасники; запит без відповіді ростер бачить, а чат — ні (`NOT_MEMBER`). Читання під RLS (`messages_read`): свої люди події, крім заблокованих одне з одним і обмежених акаунтів; власні повідомлення видно завжди. Запис лише через `public.send_message` → `private.send_message`: 1–2000 символів після обрізання (`INVALID_MESSAGE`), лише опублікована подія (`EVENT_CANCELLED`), до тижня після кінця (`CHAT_CLOSED`), не більше 20 повідомлень на хвилину від одного акаунта (`TOO_MANY_MESSAGES`). `public.event_messages(p_event_id, p_after, p_limit)` віддає хвіст за часом (старіші вгорі, ліміт `[1,200]`); з `p_after` — лише пізніше за нього, так клієнт дозавантажує нове. `public.delete_message` — автор своє, організатор будь-яке у своїй події; чуже — тиша. `public.report_message` подає скаргу на автора з подією, id повідомлення (`reports.message_id`) і першими 500 символами тексту; оновлення `reports` робить definer `private.attach_report_message`, бо клієнти таблицю не пишуть.

Реального часу нема: клієнт перечитує хвіст кожні 5 с, поки екран чату відкритий, після відправлення — одразу, а кожне шосте опитування читає весь хвіст, щоб видалені зникали й у інших. Схема цього не знає, тож Realtime можна додати пізніше без міграції. Поза застосунком сповіщень про повідомлення нема.

`tests/chat.sql`: організатор і учасник пишуть, порожнє й задовге відхиляються, `p_after` і ліміт, сторонній і запит без відповіді не читають і не пишуть, скарга несе автора, подію й текст (своє — `CANNOT_REPORT_SELF`, невидиме — `MESSAGE_NOT_FOUND`), видалення за ролями, 20 на хвилину, блокування ховає повідомлення, скасована подія закриває запис і лишає читання, гість без гранту. Прогнано на проєкті перед застосуванням у транзакції з відкатом: **PASS**. Радник безпеки після міграції — без нових зауважень.

## Непрочитане в чатах

`20260916092710_chat_unread.sql` (застосовано 2026-09-16 через Supabase MCP `apply_migration`) додає `public.chat_reads` (акаунт × подія → `read_at`, читати лише своє) і два RPC. `public.mark_chat_read(p_event_id)` → definer `private.mark_chat_read`: «прочитано до зараз» для своїх людей події (`NOT_MEMBER` іншим). `public.my_chat_unread()` віддає `chat_unread_result` (`event_id, event_title, unread, last_message_id, last_author_name, last_body, last_at`) для опублікованих подій до тижня після кінця, де є чужі повідомлення пізніші за позначку; свої не рахуються; invoker, тож заблоковані автори не рахуються, як і в чаті; свіжіші першими.

Клієнт читає зведення разом із «моїми подіями», показує секцію «Нові повідомлення» на головній і бейдж на вкладці «Мої події» (кількість чатів, не повідомлень), дзвонить локальним сповіщенням про події, чиє останнє повідомлення ще не бачив, і позначає прочитаним при відкритті чату та щоразу, коли туди приїжджає чуже нове. Відкритий чат не дзвонить.

`tests/chat_unread.sql`: порожній чат — нічого; своє не рахується; лічильник і превʼю найновішого; позначка обнуляє, новіше рахується знову; сторонній нічого не бачить і не позначає; скасована подія випадає; гість без гранту. Прогнано на проєкті в транзакції з відкатом: **PASS**.

## Пуші

`20260916115335_push_notifications.sql` (застосовано 2026-09-16 через Supabase MCP `apply_migration`) вмикає `pg_net`, додає `public.push_tokens` (без політик: клієнт лише через `register_push_token` / `unregister_push_token`, токен переходить до акаунта, що ввійшов на цьому телефоні; знімати можна лише своє) і тригери `event_messages_push` та `event_members_push` (лише `requested`), які через `private.notify_push` асинхронно кличуть Edge Function `push`. Адреса й спільний секрет читаються з Vault (`push_function_url`, `push_function_secret`); без них тригери мовчать, а збій доставки ніколи не ламає запис. Функція `supabase/functions/push/index.ts` (задеплоєна, `verify_jwt=false`, автентифікація заголовком `x-push-secret`) вирішує отримувачів і шле у FCM HTTP v1 та APNs; ключі провайдерів — у секретах функції, див. `docs/push-setup.md`.

`tests/push.sql`: валідація токена й платформи, таблиця недоступна клієнту, токен переходить між акаунтами, зняття лише свого, тригери увімкнені й не заважають запису без адреси у Vault. Прогнано в транзакції з відкатом: **PASS**.

## Застосування SQL із коду

`tools/apply_sql.py` застосовує міграції й дампи конвеєра прямим зʼєднанням з Postgres, без SQL Editor і без MCP. Потрібен `psycopg[binary]`; рядок — Dashboard → Connect → Session pooler (transaction pooler не годиться для довгих транзакцій).

Будь-який запис (`--apply`, `--mark-applied`) вимагає `--env dev|prod`. Рядок зʼєднання: dev — `SUPABASE_DB_URL_DEV`, prod — `SUPABASE_DB_URL` (середовище чи `.env`) або `--db-url`. Скрипт дістає ref з рядка й звіряє з очікуваним для `--env` (dev `ojadoyxeahepycpmjuvf`, prod `tzdogzdvctlumsqlqskr`); розбіжність — відмова. Перед записом друкується ціль, а prod просить ввести ref (`--yes` — для неінтерактивного запуску). Без `--env` і без запису скрипт лише читає базу з `SUPABASE_DB_URL` / `DATABASE_URL`; тихого переходу на `TEST_DATABASE_URL` більше немає.

```bash
python3 tools/apply_sql.py migrations --env dev           # що не застосовано; --apply виконує й записує в реєстр CLI
python3 tools/apply_sql.py dump out/ --env dev --apply    # SQL від tools.ingest; маніфест задає порядок частин і звіряє sha256
python3 tools/apply_sql.py all ~/sql-2026-09-15 --env prod --apply   # день змін: нові міграції, потім poruch-events-1…N.sql
```

Міграція і її запис у реєстр — одна транзакція. `--only` застосовує вибрані міграції лише тоді, коли раніших незастосованих немає.

`all` сортує файли даних як числа (`-2` перед `-10`) і веде журнал `.applied_sql.json` поруч із ними: після збою на девʼятому файлі повторний запуск пропускає перші вісім, а змінений файл застосовує знову. `--force` ігнорує журнал.

`run` робить повний цикл сам: створює теку `out/sql-<дата>`, генерує дамп конвеєром `tools.ingest` (аргументи конвеєра після `--`), застосовує дані й за успіху видаляє теку. Міграції `run` застосовує лише з `--with-migrations` (тоді кладе їхні копії в теку й застосовує перед даними); без прапорця лише попереджає про незастосовані. Після збою тека лишається з журналом і `report.json`; дозастосувати її можна через `all <тека> --apply`. Джерело, що не обійшлось, лише згадується в попередженні: конвеєр і так не знімає його події; `--strict` натомість зупиняє запис.

```bash
python3 tools/apply_sql.py run --env prod --apply -- --city Київ
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

## Аудит перед релізом (2026-09-17)

Чотири міграції за звітом `docs/release-audit-2026-09-16.md`, застосовані до того самого проєкту (перші дві через Supabase MCP, решта — `tools/apply_sql.py migrations --apply`; локальні файли `20260917100000…100300`, у реєстрі перші дві під штампами сервера).

**`organizer_null_guard`.** Імпортовані події мають `organizer_id = null`, а перевірка власника `v.organizer_id <> v_user` з NULL не піднімала виняток: будь-хто з акаунтом міг редагувати й скасовувати всю афішу. Тепер `private.assert_organizer(event, user)` — `is distinct from` плюс нарешті задіяний `assert_event_editable` — стоїть у `cancel_event`, `update_event`, `decide_member`; retry-гілка `create_event` теж через `is distinct from`. Перевірено на проді під `authenticated`: обидва виклики на імпортовану подію → `NOT_ORGANIZER`.

**`delete_my_account`.** `public.delete_my_account()` (invoker → definer `private.delete_my_account`) прибирає фото з `event-images/<uid>/…` і видаляє `auth.users`; каскади FK роблять решту, власні події зникають разом із членствами й чатом. `public.export_my_data()` віддає JSON з усім, що належить акаунту (definer, кожен підзапит по `auth.uid()`). Клієнт перед викликом повторно підтверджує пароль (`AuthRepository.verifyPassword`) і після — чистить локальний стан як при виході.

**`ugc_moderation`.** Три шари, яких вимагають App Store 1.2 і Play UGC policy:

1. Стоп-словник `private.banned_terms` і `private.assert_clean_text(text)` (`OBJECTIONABLE_CONTENT`, 22023) у `send_message`, `create_event`, `update_event`. Збіг по межах слова для коротких термінів і як підрядок для ≥4 символів. Поповнювати: `insert into private.banned_terms(term) values ('…')`.
2. Автоприховування: тригер `reports_auto_hide` ховає подію (`status='hidden'`) або повідомлення (`hidden_at`) після трьох відкритих скарг від різних людей. Прихована подія для клієнта — «скасована» (`EventStatus.HIDDEN`), з мапи зникає, приєднатись не можна. Повідомлення тепер не видаляються фізично (`deleted_at`), тож ліміт 20/хв рахує все надіслане.
3. Модератори — `private.moderators(user_id)`; додавати лише з SQL-консолі. RPC для авторизованого модератора (решті — `NOT_MODERATOR`): `moderation_queue(p_limit)`, `moderate_event(id, 'hide'|'unhide'|'cancel')`, `moderate_message(id, 'hide'|'unhide'|'delete')`, `moderate_user(id, 'active'|'limited'|'banned', note)`, `resolve_report(id, 'reviewing'|'actioned'|'dismissed')`. Радник безпеки позначає їх як definer, доступні `authenticated` — це навмисно, доступ перевіряє `private.assert_moderator()`.

Runbook (реакція ≤ 24 год, як обіцяно в умовах): раз на день `select * from moderation_queue()` під токеном модератора (curl до `/rest/v1/rpc/moderation_queue`, або SQL Editor), рішення через `moderate_*`, закрити `resolve_report`. Зняття прихованого — окреме `moderate_event(id,'unhide')`: закриття скарги само нічого не повертає.

**`read_exposure`.** Грант на `events` звужено до колонок, які потрібні invoker-функціям (без `contact_url`, `content_hash`, `dedupe_key`, `source_uid`, `ingest_run_id`; `location` і `quality` лишились, бо їх фільтрують `events_in_view`/`search_events_in_view`). `profiles` більше не читає anon; `members_read` показує запити лише організатору й самому прохачу; `event_sources` — лише `id, slug, name, base_url`; з `private.age_of` та інших помічників знято зайвий execute.

**PKCE.** Не міграція, а клієнт (`SupabaseAuthRepository`): реєстрація і відновлення шлють `code_challenge`, лист несе лише одноразовий `code`, колбек з токенами у фрагменті відхиляється. Налаштувань Auth це не потребує; посилання з листа треба відкривати на тому самому пристрої (інакше `LinkOnAnotherDevice`).

Лишилось із аудиту (не блокує реліз): антиспам join→leave→join (V3), розбір `errorCode` у Edge Function замість `includes("INVALID_ARGUMENT")` (V7), дедуп `report_message` по `message_id`, стеля на кількість push-токенів, leaked password protection у Auth (вмикається в Dashboard), App Links / Universal Links замість custom scheme, коли зʼявиться домен.

### Друга хвиля (2026-09-17, `20260917110000_abuse_limits`)

- **V3.** `private.join_attempts` + `private.assert_join_rate`: понад 20 приєднань (або нових позицій у черзі) за годину з одного акаунта → `TOO_MANY_JOINS`. Перевірено: цикл join→leave зупиняється на 21-й спробі.
- **V6.** `private.assert_image_url`: обкладинка спільнотної події — лише `…/storage/v1/object/public/event-images/<uid>/<event-id>/…` з нашого проєкту, інакше `INVALID_IMAGE_URL`; `profiles.avatar_url` — лише `https://`. Імпорт це не зачіпає.
- **S3.** `report_message` дедуплікує по `message_id`; друга скарга на інше повідомлення того ж автора йде окремим рядком (`private.file_report_message`); `details` обрізається до 2000.
- **N3.** `register_push_token` лишає не більше десяти найсвіжіших токенів на акаунт.
- **V7 (Edge Function `push`, задеплоєно CLI).** «Мертвим» вважається лише токен з `errorCode=UNREGISTERED` або `INVALID_ARGUMENT` про сам registration token; тіло запиту валідується (uuid, тип) до звернення в базу; секрет порівнюється за постійний час.

## Аудит 2026-09-23: видалення акаунта, UGC, витоки

Міграції `20260923100000`–`20260923100300` і Edge Function `delete-account`. Застосовано до dev (`ojadoyxeahepycpmjuvf`) 2026-09-23; prod — окремим кроком.

- **Видалення акаунта.** Основний шлях — `POST /functions/v1/delete-account` з токеном користувача: функція (service role) видаляє файли `event-images/<uid>/…` через Storage API, потім `auth.admin.deleteUser`; каскади FK прибирають решту. `public.delete_my_account` лишено для вже випущених збірок: тепер вона ставить `storage.allow_delete_query` у межах транзакції й не падає на `storage.protect_delete` (рядки файлів зникають, байти в S3 лишаються сиротами). CHECK `reports_subject` знято: скарга на видаленого користувача чи подію лишається з `subject_type` і null-посиланням. Текст повідомлення, видаленого автором чи організатором, стирається (`body = null`).
- **UGC.** Коментар до оцінки проходить стоп-словник, `rate_event` відмовляє при блокуванні з організатором (`BLOCKED`). Організатор скаржиться через `report_rating(event, created_at, reason)` (`subject_type='rating'`), модератор бачить коментар у `moderation_queue` і керує ним через `moderate_rating(event, user, hide|unhide|delete)`. Автоприховування рахує лише активні акаунти, старші за три дні; обмежений акаунт скаржитись не може. Ліміти (`send_message`, `create_event`, `file_report`, `assert_join_rate`) серіалізовані `pg_advisory_xact_lock` на користувача.
- **Витоки.** `profiles_read` — лише сам, заблоковані мною й люди зі спільних подій (`private.can_see_profile`). URL обкладинки й аватара — лише бакет власного проєкту (з `iss` токена). Ім'я, місто, адреса — через стоп-словник. Anon більше не перелічує бакет, `UPDATE`-політику знято (власник читає лише свої файли). Блокування організатором виганяє учасника з поточних і майбутніх подій. Індекси на FK `reports`, `event_waitlist`, `event_ratings`, `chat_reads`; `my_chat_unread` стартує від власних членств.
- Тести: `tests/account_deletion.sql`, `tests/ugc_and_limits.sql`; `tests/push.sql` рахує лише власні фікстури.

## Бекапи і відкат

- **PITR** (Point-in-Time Recovery) вмикається в Dashboard → Database → Backups; без нього є лише щоденні бекапи плану. Вмикає людина з доступом до білінгу — з коду це не робиться.
- Перед застосуванням дампу конвеєра чи міграції в prod — локальна копія подій:

```bash
pg_dump "$SUPABASE_DB_URL" -t public.events --data-only -Fc -f events-$(date +%F_%H%M).dump
# відкат: pg_restore у тимчасову базу, звідти вибірково назад (events має FK з members/messages — не TRUNCATE)
```

- Для міграцій, що змінюють функції, відкат — нова міграція з попереднім визначенням (воно лежить у попередньому файлі `migrations/`); старі файли міграцій не редагуються.

## Профіль

`20260924100000_profiles.sql` (dev 2026-09-24; prod — ще ні): `profiles.bio` (≤ 300, стоп-словник у тригері `profiles_validate`), `profiles.created_at` (заповнено з `auth.users`), `public.profile_card(uuid)` — картка людини з лічильниками «організував / відвідав»; пошта лише власна, з JWT. Видимість — `private.can_see_profile` плюс організатор опублікованої спільнотної події; блокування в будь-який бік і обмежений акаунт ховають картку. Фото профілю — `event-images/<uid>/avatar/<файл>`: `owns_image_path` пускає туди запис, тригер приймає `avatar_url` лише з цієї теки. `public.moderate_profile(uuid, 'clear_avatar'|'clear_bio'|'reset_name')` — для модераторів. `tests/profiles.sql` — **PASS** на dev; `tests/ugc_and_limits.sql` оновлено під теку `avatar`. Деталі — `docs/profile.md`.
