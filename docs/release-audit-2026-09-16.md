# Аудит перед релізом «Поруч» — 2026-09-16

> **Стан на 2026-09-17.** Закрито: K1 (міграція `organizer_null_guard`, перевірено на проді), K2 (PKCE у `SupabaseAuthRepository`, колбек з токенами відхиляється), K3 (`delete_my_account` + `export_my_data` + кнопка в профілі обох платформ), K4 (посилання на політику/умови/підтримку в профілі й згода при реєстрації; сторінки в `site/` ще треба опублікувати й замінити плейсхолдери), K5 (стоп-словник, автоприховування після 3 скарг, RPC модерації — див. `supabase/README.md`), K6 (release build type, R8, proguard, signing з `local.properties`), K7 (Release лінкує `releaseFramework`), K8 (перекодування фото без EXIF на Android). Також V1–V9 (V2 як soft delete повідомлень; V8 — лише COARSE; V9 — чернетки чистяться при виході, нагадування чистив `ReminderSync` і раніше), дедуп `report_message`, стеля push-токенів, таймаути Ktor, `https` для Apple Maps, одна версія kotlinx-serialization. Не зроблено й потребує рук: leaked password protection у Dashboard → Auth, App Links / Universal Links (потрібен домен), публікація `site/`, ключ підпису Android, `APNS_SANDBOX=false` перед прод-збіркою.

Гілка `feat/poruch-mvp`, коміт `0f6bcd6`. Перевірено: усі 22 міграції та Edge Function `push` (плюс живий стан проєкту `tzdogzdvctlumsqlqskr` через радників і read-only запити), клієнти Android/iOS/KMP з повною git-історією, вимоги Google Play і App Store. Нічого на сервері не змінювалось.

Що зроблено в цьому ж коміті (не потребує рішень): `site/` (політика, умови, видалення акаунту, лендинг — UK+EN), `store/` (графіка й тексти для сторів), `iosApp/Poruch/PrivacyInfo.xcprivacy` (зареєстрований у pbxproj і `generate_project.rb`), `ITSAppUsesNonExemptEncryption=false` і `CFBundleDevelopmentRegion=uk` в `Info.plist`, чернетки SQL у `supabase/drafts/` (не застосовані).

## 1. Блокери релізу

Порядок = пріоритет. Перші два — вразливості, решта — відхилення в сторах.

### K1. Будь-який користувач може редагувати й скасовувати всі імпортовані події

`private.update_event`, `private.cancel_event`, `private.decide_member` і retry-гілка `create_event` перевіряють власника як `v.organizer_id <> v_user`. З міграції `20260907130000` імпортовані події мають `organizer_id = null`; `null <> uuid` → `NULL`, `if NULL` у PL/pgSQL не піднімає виняток. Живий стан: 2028 опублікованих імпортованих подій без організатора. `private.assert_event_editable` існує, але ніде не викликається.

Експлойт: `POST /rest/v1/rpc/update_event` з id будь-якої афіші (id видно гостю через `discover_events`) → підміна назви, обкладинки, `contact_url` на фішинг; або `cancel_event` у циклі → зняття всієї афіші.

Фікс: `supabase/drafts/20260917090000_organizer_null_guard.sql` (`is distinct from` + виклик `assert_event_editable`), тест у `tests/access_and_transactions.sql`. Перед застосуванням — `supabase db pull`: репозиторій відстає від прода на три міграції `discovery_index_*`.

Файли: `supabase/migrations/20260915223806_contact_link_and_request_feed.sql:73,93`, `20260905101755_poruch_initial.sql:169`, `20260906195750_safety_age_and_reports.sql:345`.

### K2. Auth callback без PKCE: токени в custom-scheme URL

`SupabaseAuthRepository.kt:47,71,79-81` — `redirect_to=poruch://auth/callback`, `access_token`/`refresh_token` читаються з фрагмента URL. Схему `poruch://` може зареєструвати будь-який застосунок на пристрої й перехопити лист відновлення пароля → повний захоплення акаунту. Зворотний варіант (`MainActivity.kt:82`): сторонній застосунок шле `poruch://auth/callback#access_token=<свій>` і тихо логінить жертву в чужий акаунт (session fixation).

Фікс: PKCE flow у Supabase Auth (`flow_type = pkce`, обмін `code` + `code_verifier` через `/auth/v1/token?grant_type=pkce`), `token_hash` для recovery; App Links (`autoVerify`, `assetlinks.json`) і Universal Links (`applinks:` + AASA) замість custom scheme.

### K3. Немає видалення акаунту

Play «Account deletion» і App Store 5.1.1(v). Немає ні RPC, ні кнопки (`ProfileScreen.kt`, `ProfileView.swift` мають лише «Вийти»). Каскади FK майже готові; не каскадують `storage.objects` (фото лишаються публічними) і `events.organizer_id … on delete cascade` знищує чужі членства й чат.

Фікс: `supabase/drafts/20260917090100_delete_my_account.sql` (скасувати власні події → прибрати фото → `delete from auth.users`; плюс `export_my_data()`), кнопка «Видалити акаунт» із повторним паролем у профілі обох платформ, `site/delete-account.html` як веб-URL для Play.

### K4. Немає політики, умов, згоди при реєстрації, контактів підтримки

Play (Privacy policy, UGC policy) і Apple 1.2/5.1.1. Сторінки готові в `site/`; треба: опублікувати, вписати URL у консолі, додати посилання в «Про застосунок» і на екран реєстрації («Реєструючись, ви погоджуєтесь…»), email підтримки в `err_account_restricted` і в «Про застосунок». Замінити всі `class="todo"` (див. `site/README.md`).

### K5. Немає фільтрації UGC (Apple 1.2 вимагає прямо)

`chat_disclaimer` каже, що «Поруч» повідомлення не перевіряє; у `Chat.kt` лише trim і довжина. Мінімум: серверний стоп-словник у `private.send_message`/`create_event`, автоприховування після 3 скарг, runbook модерації з реакцією ≤24 год (`reports.status`, `account_facts.status`). Зараз модерувати можна лише SQL-ем під service role.

### K6. Android: немає release-конфігурації

`androidApp/build.gradle.kts` без `buildTypes.release`, R8, `proguard-rules.pro`, `signingConfigs`. Потрібно: upload keystore поза git (через `local.properties`/env), `isMinifyEnabled`, правила для kotlinx-serialization/Ktor/MapLibre/Koin, `bundleRelease`, перевірка 16 KB (`zipalign -c -P 16 -v 4`; MapLibre 11.11.0 arm64/x86_64 вирівняні на 2^14 — ок).

### K7. iOS: Release лінкує debug-фреймворк

`project.pbxproj:403-410` — `FRAMEWORK_SEARCH_PATHS` для Release вказує на `debugFramework`, а скрипт збирає `releaseFramework`. Замінити на `$(CONFIGURATION:lower)Framework` у pbxproj і `generate_project.rb:26-27`. Також `APNS_SANDBOX=false` у секретах функції для прод-збірки.

### K8. Android: EXIF з GPS не вирізається з фото → публічний бакет

`PhotoPicker.kt:57-73` шле байти з галереї як є в публічний `event-images`. JPEG з телефона містить координати зйомки — де живе організатор. iOS перекодовує через `UIImage.jpegData` і чистий. Фікс: перекодувати через `ImageDecoder` → `Bitmap.compress(JPEG, 85)`.

## 2. Високі

| # | Що | Де | Фікс |
| --- | --- | --- | --- |
| V1 | `contact_url` та службові колонки `events` читаються напряму через REST, включно з anon (`GET /rest/v1/events?select=contact_url`) | `20260905101755:89,95` | Колонкові гранти замість `grant select on public.events` |
| V2 | Ліміт 20 повідомлень/хв обходиться через `delete_message` (лічильник рахує лише живі рядки), пуш іде на кожен insert → необмежений пуш-спам | `20260915225504:65,76`, `20260916115335:73` | Soft delete (`deleted_at`), лічильник без фільтра |
| V3 | join → leave → join у циклі = необмежені пуші організатору на подіях з підтвердженням | `20260916115335:81`, `join_event`/`leave_event` | Журнал спроб + ліміт 20/год або статус `declined` без видалення рядка |
| V4 | Учасник бачить, хто лише подав запит (`event_members?status=eq.requested`) | політика `members_read`, `20260905101755:90` | Додати `status='approved'` у політику для не-організатора |
| V5 | Anon перелічує всіх користувачів (`GET /rest/v1/profiles`) | `20260905101755:86,95` | `revoke select … from anon`; імена гостю віддають definer-проєкції |
| V6 | `image_url`/`avatar_url` приймають будь-який https-URL → трекінг IP переглядачів, підміна після модерації | `20260905101755:34`, `update_event` | `assert_image_url` за префіксом бакета |
| V7 | Edge Function видаляє валідні Android-токени на будь-який `INVALID_ARGUMENT` (у т.ч. на помилку payload) | `push/index.ts:148` | Розбирати `error.details[].errorCode === "UNREGISTERED"` |
| V8 | `ACCESS_FINE_LOCATION` без потреби (iOS працює з `kCLLocationAccuracyKilometer`) | `AndroidManifest.xml:4`, `Routes.kt:92` | Лишити COARSE; спрощує Data safety |
| V9 | Чернетка події й нагадування в SharedPreferences/UserDefaults не чистяться при виході | `DraftStore.kt:29`, `Reminders.kt:84`, `EventEditorModel.swift:240` | Очищати в `signOut`/`synchronizeIdentity` |

## 3. Середні й низькі

- `report_message`: друга скарга на інше повідомлення того ж автора губить `message_id` і текст (дедуп за парою event+user), можливий сирий `23514` при довгих details (`20260906195750:124`, `20260915225504:92`).
- Текст повідомлень іде у FCM/APNs і на екран блокування — не вада, але обов'язкове розкриття в Data safety / App Privacy («Messages»), уже враховано в `site/privacy.html` і `store/listing.md`.
- Зайві `execute` для `authenticated` на `private.age_of`, `assert_age_limits`, `assert_event_editable`, `assert_contact_url`, `assert_can_join` — оракул віку, якщо `private` колись потрапить у Data API.
- `push/index.ts:27` — порівняння секрету не constant-time, немає валідації `type`/uuid; `register_push_token` без стелі на кількість токенів; `event_sources` віддає anon службові поля (`etag`, `listing_urls`, `crawl_delay_seconds`).
- Leaked password protection вимкнено (єдине попередження радника безпеки) — увімкнути в Auth.
- `account_facts.status_note` читає власник — внутрішні нотатки модерації стануть видимі.
- Ktor без `HttpTimeout` (Darwin — 60 с) → `mutating=true` блокує UI до хвилини.
- `http://maps.apple.com` у `SystemActions.swift:16` → https.
- kotlinx-serialization 1.9.0 у `core/data` проти 1.10.0 в решті.
- Репозиторій ≠ прод: на сервері три міграції `discovery_index_*`, яких немає локально, шість файлів з іншими версіями. Зробити `supabase db pull` і закомітити.
- Photo `PhotosPicker`/`PickVisualMedia` — дозволів не треба, ок. Точні будильники не використовуються, ок. Sign in with Apple не потрібен (лише email/password), ок. ATT не потрібен (нема трекінг-SDK), ок.

## 4. Стор-чеклист

| Пункт | Play | App Store |
| --- | --- | --- |
| Target/min SDK, 16 KB, iOS 17 | ✅ | ✅ |
| Release-збірка й підпис | ❌ K6 | ❌ K7 |
| Privacy manifest / export compliance | — | ✅ додано (перевірити збірку) |
| Видалення акаунту | ❌ K3 | ❌ K3 |
| Privacy Policy URL + у застосунку | ❌ K4 (сторінка є) | ❌ K4 |
| Terms/EULA, згода при реєстрації, контакти | ❌ K4 | ❌ K4 |
| UGC: скарги, блокування | ✅ | ✅ |
| UGC: фільтрація, модерація ≤24 год | ❌ K5 | ❌ K5 |
| Purpose strings | — | ✅ |
| Age gate 18+ / рейтинг | ✅ / заповнити IARC як 18+, UGC+chat | ✅ / 18+ |
| Data safety / App Privacy | заповнити за `store/listing.md` | заповнити за `store/listing.md` |
| iPad | — | ⚠️ `TARGETED_DEVICE_FAMILY=1,2` без iPad-тестів → перейти на iPhone-only або зняти iPad-скріншоти |
| Імпортований контент | ⚠️ згоди джерел / takedown-адреса / дисклеймер «не пов'язано з <джерело>» | ⚠️ 5.2.2 |
| Тестовий акаунт для рецензентів | потрібен | потрібен |
| Версії | `0.1.0 (1)` | `1.0 (1)` — вирівняти |

## 5. Що підтверджено як добре

RLS на всіх 14 таблицях, `search_path=''` у всіх 41 функції, жодного public SECURITY DEFINER, `auth.uid()` у кожній мутації, клієнти без прямих INSERT/UPDATE/DELETE. `push_tokens`, Vault, `pg_net` недосяжні для клієнтів; Realtime publication порожня. Storage-політики перевіряють `<uid>/<own-event>/`. Ліміти створення (6/добу) і скарг (10/год) тримаються. Сесія в Android Keystore (AES-GCM) і iOS Keychain (`AfterFirstUnlockThisDeviceOnly`); токени не в SQLite/логах; `PoruchLog` мовчить у release. Секретів у коді й історії немає (pickaxe по `service_role`, `sb_secret`, `postgres://`, `sk-`, JWT, `AIza`). Лише HTTPS, без cleartext і WebView; зовнішні посилання лише `https://` з показом хоста. Компоненти Android з правильним `exported`, `allowBackup=false`, `FLAG_IMMUTABLE`. Sign-out знімає push-токен і чистить приватний кеш. Photo Picker без media-дозволів, локація лише foreground за натисканням, нотифікації з перемикача в профілі, пуші без маркетингу.

## 6. Артефакти

- `site/` — лендинг, політика (UK/EN), умови (UK/EN), видалення акаунту, README з інструкцією хостингу. Плейсхолдери: `grep -n 'class="todo"' site/*.html`.
- `store/play/` — іконка 512, feature graphic 1024×500, 6 скріншотів 1080×1920. `store/appstore/` — по 5 скріншотів 6.9" і 6.7". `store/listing.md` — назви, описи, keywords, Data safety / App Privacy, App Review Notes.
- `iosApp/Poruch/PrivacyInfo.xcprivacy`, `Info.plist` (encryption, development region).
- `supabase/drafts/` — SQL для K1 і K3, не застосовано.

Скріншоти перезнято 2026-09-17 з оновлених збірок.
