# Аудит безпеки «Поряд» — 2026-10-22

Привід — рілс про п'ять способів, як навайбкоджений застосунок коштує $100 000 без жодного користувача
(трафік статичного сайту, позови за доступність, Supabase без RLS, SMS без згоди, функція, що викликає сама себе).
Попередні аудити — [release-audit-2026-09-16](release-audit-2026-09-16.md) і [audit-2026-09-23](audit-2026-09-23.md);
закритого там тут не повторюю, дивився насамперед те, що з'явилось після 23.09 (~38 міграцій, `offer-check`, worker, CI з self-hosted runner).

Що перевірено: жива база prod (і dev для порівняння) — RLS, гранти, політики, функції, Storage, cron, тригери;
edge-функції, worker, CI, `tools/`; секрети в репо й історії; клієнти iOS/Android. Лише читання: нічого не змінено й не задеплоєно.
У prod пішло кілька безпечних запитів із публічним ключем (які схеми відкриті, розмір відповіді мапи).

## Стан виправлень (2026-10-22)

Виправлено в коді. Сервер перевірено на dev; **на prod 22.10 викладено** міграцію `20261102120000`, `push` (v15),
`offer-check` (v2) і worker (CSP пропускає Cloudflare Web Analytics — `062226f`). `delete-account` на prod — після релізу 1.3.1 (крок 5).

| # | Що зроблено | Де | dev |
|---|---|---|---|
| M1 | ≤60 нових пристроїв на годину з адреси (`cf-connecting-ip`), стеля пʼятничного прогону 5000, `push` забуває пристрій на iOS `BadDeviceToken` | міграція `20261102120000`, `push/index.ts` | ✔ 60 з 65 записались; фальшивий токен прибрано |
| N1 | **Нове:** `service_role` не мав `USAGE` на `private`, тож `push` ніколи не прибирав мертві пристрої каналу (`forget_device` мовчки падав) — і на prod теж | та сама міграція | ✔ |
| M2 | Тригер `events_move_limit`: ≤5 переносів на добу від людини (update_event і move_companion), імпорт і R6–R7 без ліміту; клієнт показує `TooManyAttempts` | міграція, `ApiErrors.kt` | ✔ 6-й перенос — `TOO_MANY_MOVES`, системні 8 з 8 |
| M3 | `delete-account` сам перевіряє пароль (403 `password`); зміна пароля шле `current_password` | `delete-account/index.ts`, `SupabaseAuthRepository.kt`, `SessionUseCases.kt` | задеплоєно, живцем не перевірено (немає тестового акаунта) |
| L1 | `revoke insert/update/delete/…` на `artists`, `places` | міграція | ✔ REST: `permission denied` |
| L3, L4 | 404 кешується на 60 с, ключ кешу в нижньому регістрі; HSTS, CSP з хешем скрипта, X-Frame-Options, nosniff, Referrer-Policy | `worker/index.mjs`, `worker/test.mjs` | тести ✔, не викладено |
| L6 | Зламана адреса не валить пакет, тіло й robots.txt читаються з межею, лише https на доменне ім'я | `offer-check/index.ts` | ✔ задеплоєно |
| L7 | Тег `do $…$`, якого нема в даних | `tools/ingest/emit.py` + тест | 262 тести ✔ |
| L8 | Точні версії `supabase-js@2.118.0`, `jose@5.10.0` | `push`, `delete-account` | ✔ |
| L11 | Amplitude на Android без `DEEP_LINKS` | `PoruchApplication.kt` | збірка ✔ |
| L12 | `ampBlock` / `amp_setBlocked` на прев'ю фото | `ProfileScreen.kt`, `PersonCard.swift` | збірки ✔ |
| L13 | JWT більше не лежить у SQLite: незняте після виходу знімає анонімний `release_push_token(token, user_id)`; без строку й і після 401 | міграція, `PushSync.kt`, `LocalPendingUnregister.kt`, `SupabasePushTokens.kt` | RPC ✔ (204) |
| L15 | Extras у `MainActivity` лише з випадковим ключем установки, який кладуть наші сповіщення | `MainActivity.kt` | збірка ✔ |
| I1–I3 | `env:` замість підстановки, ширший `.gitignore`, без `Viewed Home Page` | `ingest.yml`, `.gitignore`, `PoruchApplication.kt`, `AppModel.swift` | — |

**H1** — скрипт `tools/ingest/runner_user.sh` готовий, запускає власник (потрібен пароль адміністратора). Він закриває дім
(`chmod 700 ~`: зараз група `staff`, тобто кожен локальний користувач, читає `.env`), переносить runner у користувача
`poriad-runner` під LaunchDaemon. Секрети самого runner-а схвалений PR однаково бачить — тому PR від сторонніх не схвалювати.
Не виправлено: **L2** (`config.toml` свідомо не додано: випадковий
`supabase config push` з неповним файлом перезаписав би налаштування Auth на prod; прапорці деплою — у `docs/follows.md`,
`docs/event-offers.md`), **L9**, **L10**, **L14** (разом з App Links), ручні кроки розділу 6.
Лишається свідомо: акаунт лише з Google/Apple видаляється без повторного входу (токен Apple відкликається, але не вимагається);
`offer-check` не ловить доменне ім'я, що резолвиться в приватну IP (`ponytail:` у коді).

**Порядок на prod — важливий:**
1. Міграція `20261102120000` (старим клієнтам нічого не ламає; 6-й перенос за добу дасть їм загальну помилку).
2. `push` і `offer-check` (`--no-verify-jwt --use-api`) — після міграції: `push` покладається на новий `USAGE`.
3. Worker — `cd worker && npx wrangler deploy`, незалежно.
4. Нові збірки iOS і Android — лише після міграції: без `release_push_token` незняті токени просто забудуться.
5. **Після релізу 1.3.1**, коли люди оновились: `delete-account` на prod (стара версія клієнта не шле пароль — видалення
   акаунта з паролем у ній зламається) і **Auth → Require current password when updating** (стара не шле `current_password`).
   `supabase functions deploy delete-account --use-api --project-ref tzdogzdvctlumsqlqskr` — з перевіркою JWT, без `--no-verify-jwt`.

## Підсумок

Діри з відео (відкрита база) немає: RLS на всіх таблицях, `private` назовні закрита, модерація перевіряє роль,
дії з пушами мають ліміти. Серйозне одне — **публічний репозиторій із self-hosted runner на вашому Mac**.

| # | Рівень | Що | Де |
|---|---|---|---|
| H1 | Високий | PR із форка може виконати код на вашому Mac і забрати ключі prod | `.github/workflows/ci.yml:4-6`, `ingest.yml:27,34` |
| M1 | Середній | Будь-хто без входу забиває реєстр гостьових пристроїв і вмикає пʼятничний сплеск пушів | `touch_device`, `send_winbacks`, `push/index.ts:407` |
| M2 | Середній | Організатор може розіслати учасникам необмежено пушів «подію перенесено» | `private.on_event_changed`, `update_event`, `move_companion` |
| M3 | Середній | Зміну пароля й видалення акаунта захищає пароль лише в клієнті: з чужим токеном можна і те, і те | `SessionUseCases.kt:93-128`, `delete-account/index.ts:25-41` |
| L1 | Низький | `anon`/`authenticated` мають гранти на запис у `artists` і `places` (тримає лише RLS) | міграції `20260925120000`, `20261002120000` |
| L2 | Низький | `push` і `offer-check` з `verify_jwt=false`: кожен чужий виклик — оплачене викликання; у репо немає `config.toml` | `docs/follows.md:166` |
| L3 | Низький | Worker не кешує 404, ключ кешу чутливий до регістру | `worker/index.mjs:35-55,267` |
| L4 | Низький | На poriad.app немає HSTS/CSP/X-Frame-Options/nosniff | worker `html()`/`json()` |
| L6 | Низький | `offer-check`: битий URL зупиняє пакет назавжди, тіло читається без межі, редиректи на будь-який хост | `offer-check/index.ts:36,91-92,112` |
| L7 | Низький | `$tag$` у зібраних даних ламає весь денний дамп | `tools/ingest/emit.py:477-498,542-554` |
| L8 | Низький | Залежності edge-функцій без точних версій | `push/index.ts:17-18`, `delete-account/index.ts:16` |
| L9 | Низький | Захист від злитих паролів вимкнений (відомо з 16.09) | Dashboard → Auth |
| L10 | Низький | Найбільша анонімна відповідь мапи — 433 КБ і ~2,7 с | `discover_events` |
| L11 | Низький | Amplitude на Android пише повну URL колбека входу (`AutocaptureOption.ALL` → Deep Links) | `PoruchApplication.kt:53` |
| L12 | Низький | Щойно вибране фото профілю потрапляє в запис сесії до завантаження | `ProfileScreen.kt:259`, `PersonCard.swift:193` |
| L13 | Низький | Токен доступу лежить у звичайному SQLite після виходу офлайн | `LocalPendingUnregister.kt:23-30`, `PushSync.kt:182` |
| L14 | Низький | Колбек входу на власній схемі `poriad://` — чужа апка може перехопити скидання пароля | `AndroidManifest.xml:19`, `Info.plist:25-31` |
| L15 | Низький | Експортована `MainActivity` виконує extras від будь-якої апки | `MainActivity.kt:120-163` |
| I1 | Інфо | Вхід workflow підставляється прямо в shell | `ingest.yml:43` |
| I2 | Інфо | `.gitignore` не покриває `*.p8`, `*.p12`, `*.pem`, `.dev.vars`, `*service-account*.json` | `.gitignore` |
| I3 | Інфо | Лишилась подія налаштування Amplitude `Viewed Home Page` | `PoruchApplication.kt:55`, `AppModel.swift:143` |

Секретів у коді й історії git немає: у клієнтах лише публічні ключі (`sb_publishable_`, ключ Amplitude для збору подій).

## 1. П'ять ризиків із відео — де ми

1. **Трафік статичного сайту.** Сайт і `/e/{id}` на Cloudflare, а він не бере плату за трафік; на безкоштовному плані Workers
   при 100 000 запитів/добу сайт просто зупиняється, рахунку немає. Платити за трафік можемо в Supabase: публічний бакет
   `event-images` і анонімні RPC. Мільйон максимальних запитів мапи — ~430 ГБ, тобто десятки доларів понад ліміт Pro, якщо
   Spend Cap вимкнений, і нуль, якщо ввімкнений. Див. L3, L10, розділ 5.
2. **Доступність (ADA).** Закон США, нас прямо не стосується. Доступність варто робити заради людей, а не через позови.
3. **Supabase без RLS.** Не наш випадок: RLS увімкнено на всіх 22 таблицях `public`, клієнт пише лише через RPC з `auth.uid()`.
4. **SMS без згоди.** SMS ми не надсилаємо. Пуші — лише після дозволу системи, гостьові — з тихими годинами.
5. **Функція, що викликає сама себе.** Петель не знайдено (розділ 3). Найближче до цього — M1 і M2: вони не зациклюються самі,
   але дають чужій людині запускати пуші скільки завгодно.

## 2. База prod (Supabase)

**У порядку.**
- RLS на всіх таблицях `public`; таблиці без політик (`push_tokens`, `event_offers`, `event_ratings`, `venues`, `shelters`,
  `city_curfews`, `event_artists`) клієнтам закриті повністю, доступ лише через функції.
- REST відкриває тільки `public` і `graphql_public` (перевірено запитом: `Invalid schema: private`), `pg_graphql` не встановлено.
- Шість `SECURITY DEFINER`, доступних без входу (`artist_events`, `place_events`, `search_artists`, `search_places`,
  `companions`, `event_safety`), лише читають, обмежують ліміт (≤100/≤50/20), довжину пошуку (≤120) і віддають тільки
  опубліковане й доступне (`has_event_access`, `is_discoverable`). `companions` не віддає персональних даних.
- Усі сім RPC модерації починаються з `private.assert_moderator()`.
- Ліміти частоти: `TOO_MANY_EVENTS` (події й «Шукаю компанію»), `TOO_MANY_MESSAGES`, `TOO_MANY_FOLLOWS`, `assert_join_rate`,
  скарги й оцінки з вікном часу. Колонкові гранти на `events` (без `contact_url`) і `event_sources` на місці.
- Storage: один бакет `event-images`, jpeg/png/webp до 5 МБ, запис лише в `<uid>/<своя подія>/`.
- `statement_timeout` 3 с для `anon` і 8 с для `authenticated`.
- dev збігається з prod за всіма порадами безпеки Supabase.

**M1. Реєстр гостьових пристроїв можна забити без входу.** `touch_device` доступна `anon`, перевіряє формат токена, але нових
пристроїв не приймає після 100 000 рядків. 100 000 викликів із випадковими 64-hex токенами iOS — і справжні нові гості мовчки
не зберігаються; оновлення тих самих рядків раз на <120 днів тримає місця зайнятими. Через 4–5 тижнів `send_winbacks` у пʼятницю
о 17:12 шле ~80 тис. запитів `pg_net` → ~80 тис. викликів `push` → ~80 тис. звернень до APNs із prod-ключем на фальшиві токени,
і повторює на кроці 2, бо `BadDeviceToken` для iOS не вважається мертвим токеном (`push/index.ts:407`).
Зараз у `private.devices` 0 рядків: клієнт із гостьовим каналом ще не в сторах — виправити до релізу.
Фікс: на межі витісняти найстаріший `last_seen` замість відмови (краще — анонімний вхід Supabase з лімітом на IP і прив'язка до
користувача); у `push` для `kind = winback` на `BadDeviceToken` викликати `forget_device`; слати пакетами й обмежити пʼятничний прогін (`limit 5000`).

**M2. Пуші «подію перенесено» без ліміту.** `on_event_changed` шле пуш на кожну зміну `starts_at`, а `update_event` і
`move_companion` не мають обмежувача; ключ пушу `${id}:${kind}:${Date.now()}` щоразу новий, тож телефони не склеюють їх в одне.
Один акаунт, одна подія й цикл T1↔T2 — і всі учасники отримують сотні сповіщень, а ми — сотні викликів функції.
Фікс: не слати `moved`, якщо для цієї події пуш ішов за останні ~30 хв (маленька `private.event_push_log`), або ліміт на `update_event` (наприклад, 20/год).

**L1. Зайві гранти на запис.** Міграції дали `grant select` на `artists` і `places`, але не прибрали стандартних прав Supabase
(`insert/update/delete/truncate`). Зараз запис блокує RLS (лише політика `select`), REST не вміє `truncate` — експлуатувати нічим.
Але одна майбутня політика `for all` відкриє запис. Фікс — одна міграція:
`revoke insert, update, delete, truncate, references, trigger on public.artists, public.places from anon, authenticated;`

**L10. Важкий анонімний запит мапи.** `discover_events` з максимальними параметрами по Києву віддає 433 КБ (128 КБ стиснено) за ~2,7 с —
майже впритул до `statement_timeout` 3 с. Рахунку це не загрожує (розділ 5), але кілька паралельних циклів таких запитів можуть
навантажити базу. Фікс: стеля `p_limit` ближча до потреб клієнта, rate limit на рівні Cloudflare або кеш перед RPC.

## 3. Edge-функції, worker, CI

**H1. PR із форка може виконати код на вашому Mac.** Репозиторій `Tarrras/Poriad` публічний, runner `MacBook-Pro-Taras` онлайн і
працює від вашого користувача `tarasvovcenko`. `ci.yml` запускається на `pull_request`, а для PR із форка GitHub бере workflow
з самого PR — тобто атакувальник міняє `runs-on: ubuntu-latest` на `[self-hosted, macOS]` і отримує shell на Mac.
Звідти досяжні `.env` (`SUPABASE_DB_URL` prod, `OPENAI_API_KEY`), `~/.keys/AuthKey_*.p8` (APNs), `~/.ssh`, токени `gh` і `supabase`,
а також `~/actions-runner/.credentials` — з ними можна видати себе за runner і отримати наступний нічний імпорт разом із секретами
`SUPABASE_DB_URL` і `CLAUDE_CODE_OAUTH_TOKEN`. Ще один шлях закріпитися: `clean: false` лишає невідстежені файли в робочій теці
між запусками (підкладений `sitecustomize.py` чи `.claude/`-хук виконається в наступному prod-імпорті).
Запобіжник зараз один — політика `all_external_contributors`: кожен запуск від стороннього автора чекає вашого «Approve and run».
Один клік на PR «typo fix» — і все. GitHub прямо радить не ставити self-hosted runner на публічні репо.
Фікс (на вибір):
- **Окремий користувач macOS для runner** без доступу до вашого дому (без `.env`, `.keys`, `.ssh`, токенів CLI); URL бази — лише з
  секретів Actions; кеш імпорту — поза робочою текою (`~/.poruch/cache`), `clean: true`.
- **Або приватний репо** — прибирає шлях через форки, але GitHub Pages для `site.yml` тоді потребує GitHub Pro (або перенести сайт на Cloudflare, куди вже йде worker).
- До того — **не схвалювати жодного PR від сторонніх**, особливо з правками в `.github/`.

**L2. `push` і `offer-check` відкриті для викликів.** Обидві з `verify_jwt=false` (pg_net не шле `Authorization`), секрет порівнюється
за сталий час, тож зробити щось не можна — але кожна відповідь 403 все одно оплачене викликання. Тримати Spend Cap увімкненим.
Додати `supabase/config.toml` з `verify_jwt` для кожної функції (false для `push`/`offer-check`, true для `delete-account`), бо
повторний деплой без `--no-verify-jwt` мовчки зламає доставку пушів.

**L3. Worker не кешує промахи.** 404/503 віддаються з `no-store`, тож `/e/<випадковий-uuid>` щоразу коштує запит до Worker і два RPC;
UUID перевіряється без урахування регістру, а ключ кешу — сирий шлях, тож варіанти регістру справжнього id теж оминають кеш.
На безкоштовному плані Workers перевищення 100 тис./добу кладе й `/.well-known/apple-app-site-association` та `assetlinks.json`
(Universal/App Links). Фікс: id у нижньому регістрі в ключі кешу, кеш 404 на 60 с, безкоштовне правило rate limit Cloudflare на `/e/*`.

**L4. Заголовки безпеки.** На `/` і `/e/…` немає HSTS, CSP, X-Frame-Options, nosniff. XSS не знайдено (усі рядки з бази проходять `esc`),
тож це другий рубіж. Фікс: заголовки в `html()`/`json()` worker; для inline-скрипта поділитися — `script-src 'self' 'sha256-…'`;
сторінки GitHub Pages — через Transform Rule Cloudflare.

**L6. `offer-check`.** `new URL(url)` на битому `canonical_url` падає до циклу → 500 → той самий пакет кожні 15 хв назавжди;
`r.text()` читає все тіло до перевірки 10 МБ, robots.txt без межі; редиректи на будь-який хост, включно з приватними IP (сліпий SSRF,
стримує лише robots.txt). Фікс: try/catch на кожен URL, обмеження байтів у потоці, відмова від не-https, IP-літералів і приватних хостів.

**L7. `$tag$` у дампі.** `emit.py` загортає зібрані `source_uid` у `do $retire$ … $retire$`, а `_lit` екранує `'`, але не `$tag$`.
Ін'єкції немає (обрізане тіло PL/pgSQL падає, дамп — одна транзакція), але одна адреса з `$retire$` валить увесь денний імпорт.
Фікс: випадковий тег (`$r_<hex>$`) або відкидати значення з `$` у цих блоках.

**L8. Версії залежностей.** `npm:@supabase/supabase-js@2`, `npm:jose@5` без lockfile. Закріпити точні версії, як у `offer-check`.

**I1.** `ingest.yml:43` підставляє `${{ inputs.env || 'prod' }}` прямо в `run:`. Не експлуатується (вибір зі списку, запуск лише з правом запису); для гігієни — через `env:`.

**У порядку.**
- Петель немає: `push` пише лише в `push_tokens` і `forget_device` (без тригерів); `offer-check` → `apply_event_change` вмикає
  `poruch.follow_parent`, що глушить `events_push`; імпортовані події мають `organizer_id null`, тож пушевих тригерів не чіпають;
  `kick_offer_check` лише з cron і виходить, якщо нічого не настало; `pg_net` без повторів.
- Розсилки обмежені: підписники організатора ≤1000 на пуш при 6 подіях/добу; дайджести закладів і артистів — одній людині, ≤5/≤3;
  `user_ids` ≤10 000; конкурентність `push` 10 з тайм-аутом 10 с; `offer-check` — пакети по 60, ≤3 помилки на вікно.
- `push` валідує весь payload до звернень у базу, токен APNs перевіряється як hex перед URL, мертві токени — лише за
  UNREGISTERED/404/410. `delete-account` бере особу з `getUser(token)` і чистить лише свою теку.
- Worker використовує лише публічний ключ, усі рядки з бази через `esc`, URL через `httpsOrNull`, id перевіряються як UUID —
  відкритого редиректу немає; query string не входить у ключ кешу.
- CI: усі 5 дій закріплені за SHA (збігаються з тегами), мінімальні `permissions`, без `pull_request_target`, імпорт лише за розкладом
  або вручну; `claude -p` з `--tools ""` і `--strict-mcp-config`.
- `apply_sql.py` вимагає `--env`, звіряє ref і питає підтвердження для prod; `.mcp.json` тримає prod у `read_only`; `.env` і ключі в `.gitignore`.
- Firebase — лише Analytics, Crashlytics, Messaging: платних серверних сервісів немає.

## 4. Секрети й клієнти

**M3. Пароль перевіряє лише клієнт.** Перед видаленням акаунта й зміною пароля застосунок просить поточний пароль і перевіряє його
сам (`auth.verifyPassword`), а тоді робить справжній виклик із поточним токеном: `PUT /auth/v1/user {password}` без старого пароля
і `delete-account`, яка дивиться лише на `getUser(token)`. Хто має чинний токен доступу (викрадений, з L13, чи розблокований телефон
із пропатченим клієнтом), той може поставити свій пароль — постійне захоплення — або незворотно видалити акаунт.
Фікс: видалення — перевіряти пароль у самій функції (grant `password` на `user.email`), для входу через Google/Apple вимагати свіжий
`amr[].timestamp` у JWT (≤5–10 хв); зміна пароля — увімкнути «Secure password change» в Supabase Auth і йти через `/reauthenticate`,
або через edge-функцію, що перевіряє поточний пароль перед `admin.updateUserById`.

**L11. Amplitude пише URL колбека входу.** `AutocaptureOption.ALL` включає `DEEP_LINKS`, і SDK логує `intent.data` як
«[Amplitude] Deep Link Opened». На холодному старті з листа підтвердження чи скидання в Amplitude потрапляє `poriad://auth/callback?code=…`.
Сам PKCE-код без верифікатора марний, але якщо Supabase колись надішле лист у неявному потоці (запрошення з Dashboard, magic link,
зміна email), у URL будуть `#access_token=…&refresh_token=…` — доступ до проєкту Amplitude дасть захоплення акаунта.
Фікс: `autocapture = setOf(SESSIONS, APP_LIFECYCLES, SCREEN_VIEWS)`. На iOS автозбору deep links немає.

**L12. Фото профілю в записі сесії.** Режим `CONSERVATIVE` маскує лише текст, тому `Avatar` має `ampBlock()`/`amp_setBlocked(true)`.
Але прев'ю щойно вибраного фото малюється окремо, повз `Avatar`, — і фото з галереї, яке людина потім скасувала, усе одно йде в Amplitude.
Фікс: `.ampBlock()` / `.amp_setBlocked(true)` на обох прев'ю.

**L13. Токен доступу в SQLite.** Якщо вийти з акаунта без мережі, `LocalPendingUnregister` кладе JWT (до години чинності; `/logout` його
не відкликає) у звичайний кеш `poruch.db`, щоб пізніше зняти пуш-токен. Це повертає назад висновок 16.09 «токени не в SQLite».
На Android бекап вимкнений, а на iOS база контейнера потрапляє в бекапи iTunes/iCloud. Фікс: зберігати цей запис через
`SecureSessionStore`, або тримати лише пуш-токен і знімати його на сервері (RPC на кшталт `forget_device` чи чистка при наступному вході).

**L14. Колбек входу на власній схемі.** PKCE захищає лише потоки, які почав справжній застосунок. Шкідлива апка, що зареєструвала
`poriad://`, запускає `/recover` для email жертви зі своїм `code_challenge`; жертва тисне на лист — і код обмінює чужа апка.
Це недороблена половина K2 з аудиту 16.09. Фікс: `https://poriad.app/auth/callback` — intent-filter з `autoVerify`, `/auth/*` в AASA і
`assetlinks.json`, адреса в списку редиректів Supabase.

**L15. Extras у `MainActivity`.** Явний intent від будь-якої апки може задати `reason`, `placeId`, `artistId`, `eventId`, `target=chat`
чи `ACTION_DIGEST`: підкинути значення в аналітику `push_open`/`digest_open` і змусити перехід. Даних це не відкриває (усе перевіряє сервер).
Фікс: читати extras лише з приватною дією, яку ставлять тільки наші `PendingIntent`, або з nonce в extras.

**I2.** `.gitignore` не покриває `*.p8`, `*.p12`, `*.pem`, `.dev.vars`, `*service-account*.json`; `.claude/settings.local.json`
ігнорується лише глобальним `~/.config/git/ignore`. Справжні ключі лежать у `~/.keys` і `~/.poriad`, тож нічого не витекло — це від випадковості.

**I3.** `track("Viewed Home Page")` лишився після налаштування Amplitude — шум у метриках.

**У порядку.**
- Секретів немає ні в дереві, ні в історії жодної гілки (pickaxe і regex: `service_role`, `sb_secret_`, Postgres URL із паролем,
  JWT, PEM-ключі, `service_account`, ключі FCM, `sk-ant`/`sk-proj`, `ghp_`, `xox`, `AKIA`, `GOCSPX-`); знайдено лише шаблони й заглушки тестів.
  `.env` (OpenAI, URL баз) і `local.properties` (паролі keystore) ніколи не комітились.
- Кожна збірка несе лише `sb_publishable_` свого середовища; prod більше не містить значень dev. Client ID Google не секретні.
- Вхід через Google/Apple: nonce з `SecureRandom`/`SecRandomCopyBytes`, провайдеру — SHA-256, сирий nonce одноразовий і стирається;
  код Apple для відкликання використовується лише на сервері після `getUser`. PKCE і відмова від токенів неявного потоку на місці.
- Сесія — Keystore AES-GCM і Keychain `AfterFirstUnlockThisDeviceOnly`.
- Посилання: `EventLinks` приймає лише строгий UUID, відкриття посилання лише переходить і нічого не виконує; зовнішні посилання
  лише https (на iOS `contactURL` перевіряє сервер — `assert_contact_url` і CHECK). AASA покриває лише `/e/*`.
- Android: експортована лише `MainActivity`, `allowBackup=false`, правила вивантаження даних виключають усе, FINE_LOCATION/AD_ID/ADSERVICES
  прибрано, `http://` немає. iOS: без винятків ATS, associated domains — лише `applinks:poriad.app`.
- Аналітика й звіти про збої: подій з персональними даними немає, `setUserId` ніде не викликається; Crashlytics отримує лише назву
  проблеми й `summary()`; логи в релізі вимкнені; на iOS автозбір мережі вимкнений, вміст текстових полів не записується.
- Те, на що покладається клієнт, сервер перевіряє: вік (`AGE_REQUIRED`) для входу через OAuth, ліміти «Шукаю компанію», тригер чистого
  тексту й префікс URL аватара, email у `profile_card` лише власнику.

## 5. Рахунки: де може вилізти чек

| Сервіс | Що може рости | Що зупиняє |
|---|---|---|
| Supabase | виклики функцій (M1, M2, L2), трафік бакета й RPC (L10) | Spend Cap (на Pro за замовчуванням увімкнений), на Free — жорсткі квоти без рахунку |
| Cloudflare Workers | запити (L3) | Free — 100 тис./добу, далі помилка, не рахунок; Paid — $0,30 за мільйон |
| Firebase | нічого платного | Analytics/Crashlytics/FCM безкоштовні |
| APNs / FCM | — | безкоштовні, але масові звернення з фальшивими токенами (M1) псують репутацію ключа |
| OpenAI / Claude (імпорт) | токени агента-аналітика | ліміти в кабінетах провайдерів; ключі на Mac — див. H1 |

Найгірший реалістичний сценарій для нас — не рахунок, а **недоступність**: забитий гостьовий канал (M1), лежачий сайт на Free-плані
Workers (L3) чи навантажена база (L10).

## 6. Що перевірити руками (з коду не видно)

- Supabase → Billing: план і **Spend Cap увімкнений**.
- Supabase → Edge Functions: фактичний `verify_jwt` і версії `push`, `offer-check`, `delete-account` на prod.
- Supabase → Auth: **Leaked password protection** (L9), **Secure password change** (M3), **Confirm email** увімкнений
  (інакше хтось зареєструє чужий email наперед і прив'яжеться, коли власник увійде через Google/Apple), точний список редиректів,
  перевірка nonce для Google/Apple не вимкнена, ліміти реєстрації й OTP, CAPTCHA, анонімний вхід вимкнений.
- Amplitude: чи справді Session Replay не знімає зображень, чи слухається `optOut` під час роботи; регіон і строк зберігання.
- Збірка iOS: в IPA `aps-environment=production` (у файлі entitlements стоїть `development`; при підписі для стору зазвичай підміняється).
- Supabase → Database: PITR / бекапи.
- Cloudflare: план Workers, правила WAF/rate limit для `/e/*`.
- Google Cloud: обмеження API-ключів Firebase за пакетом/bundle id.
- GitHub → Settings → Actions: після рішення щодо H1 — переглянути, хто може запускати workflow.

## 7. Порядок робіт

1. **Сьогодні:** не схвалювати PR від сторонніх; вирішити H1 — окремий користувач macOS для runner або приватний репо.
2. **До релізу гостьового каналу:** M1 (витіснення замість відмови, `forget_device` на `BadDeviceToken`, стеля пʼятничного прогону).
3. M2 — обмежувач пушів «перенесено»; M3 — перевірка пароля на сервері й «Secure password change».
4. Клієнт, у наступну збірку: L11 (одна стрічка), L12 (два модифікатори), L13, L15.
5. L1 — одна міграція `revoke`; L2 — `supabase/config.toml` з `verify_jwt`.
6. L3, L4 у worker одним комітом; L14 разом із Play App Links; L6–L8, I1–I3 за нагоди.
7. Ручні кроки з розділу 6.
