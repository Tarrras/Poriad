# Поруч

Нативний Android/iOS застосунок для міських подій: інтерактивна мапа, пошук міста, створення події та приєднання. Спільна бізнес-логіка — Kotlin Multiplatform; Android — Jetpack Compose + Navigation 3; iOS — SwiftUI + NavigationStack.

## Запуск Android

Відкрийте цю папку в Android Studio. Потрібні JDK 21 та Android SDK 36. У `local.properties` задайте власний шлях до SDK:

```properties
sdk.dir=/absolute/path/to/Android/sdk
```

```sh
./gradlew :androidApp:assembleDebug
./gradlew :androidApp:installDebug
```

APK: `androidApp/build/outputs/apk/debug/androidApp-debug.apk`. Мінімальна версія — Android 8 / API 26. Це debug-збірка для перевірки, не реліз для Google Play.

## Запуск iOS

Потрібні macOS, Xcode та Java 21. Мінімальна версія iOS — 17.

```sh
./gradlew :shared:linkDebugFrameworkIosSimulatorArm64
open iosApp/Poruch.xcodeproj
```

Оберіть схему Poruch та arm64 iPhone Simulator. Або зберіть із командного рядка:

```sh
xcodebuild -project iosApp/Poruch.xcodeproj -scheme Poruch \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath iosApp/.build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

Для фізичного iPhone виконайте `./gradlew :shared:linkDebugFrameworkIosArm64` та оберіть власну signing team в Xcode. Для публікації потрібно налаштувати release framework, підпис і app icons; поточний Xcode-проєкт посилається на debug framework. Деталі — [iosApp/README.md](iosApp/README.md).

## Логи

Трасування живе в [PoruchLog.kt](core/domain/src/commonMain/kotlin/app/poruch/domain/PoruchLog.kt) — спільне для обох платформ, з `expect/actual` сінками: `android.util.Log`, `NSLog` та `println` для JVM. Вмикається лише в debug-збірках (`BuildConfig.DEBUG` на Android, `#if DEBUG` на iOS); у релізі сінк мовчить, а повідомлення-лямбди навіть не форматуються.

Що **ніколи** не потрапляє в лог: паролі, токени, email і тіла запитів. Ідентифікатори пишуться першими 8 символами — достатньо, щоб простежити одну подію крізь трейс, і замало, щоб зібрати список користувачів. Пошуковий запит і назва міста логуються довжиною й кількістю результатів, не текстом.

Теги: `app`, `session`, `auth`, `discovery`, `geo`, `detail`, `mine`, `action`, `http`, `map`. Типовий трейс запуску:

```
Poruch/app        graph created
Poruch/discovery  search 50.3,30.25..50.6,30.8 category=all from=now text=- available=false
Poruch/http       POST /rest/v1/rpc/search_events_in_view → 200 in 513ms
Poruch/discovery  0 events
```

Читати: `adb logcat | grep Poruch/` на Android і `xcrun simctl spawn booted log stream --predicate 'eventMessage CONTAINS "Poruch/"'` на iOS.

## Дизайн-система

Функціональний орієнтир — Meetup, візуальна мова — Corner; обидва референси й причини вибору описані в [docs/design-system.md](docs/design-system.md) і реалізовані двічі з однаковим API: [Tokens.kt](androidApp/src/main/java/app/poruch/android/ui/Tokens.kt) + [Components.kt](androidApp/src/main/java/app/poruch/android/ui/Components.kt) для Compose та [DesignSystem.swift](iosApp/Poruch/DesignSystem.swift) + [Components.swift](iosApp/Poruch/Components.swift) для SwiftUI. Екрани не задають кольори, радіуси чи відступи напряму — лише через токени.

## Що реалізовано

- Черга очікування: повна подія пропонує стати в чергу замість глухого кута, а місце, що звільнилось (хтось вийшов або організатор підняв місткість), автоматично дістається першому в черзі. Позиція в черзі приватна.
- Головна вкладка збирає план тижня з уже завантажених даних: ваші майбутні події, категорії, «сьогодні в місті» та решта подій поруч.
- Поділитися подією через системний share sheet (Android Intent / iOS ShareLink), додати її в системний календар (Android `CalendarContract` / iOS EventKit) і прокласти маршрут у системних мапах.
- Сторінка події показує превʼю мапи з місцем зустрічі та список учасників з аватарами. Імена учасників бачать лише організатор і самі учасники — це та сама межа, що вже діє в RLS; решта бачить тільки лічильник. Міграцію застосовано до погодженого проєкту, SQL-набір `supabase/tests/attendees.sql` проходить.
- MapLibre Native з вуличною мапою OpenFreeMap (Positron у світлій темі, Dark у темній), власними пінами категорій, кластеризацією на рівні стилю та каруселлю подій, синхронізованою з мапою.
- Пошук довільного міста через Photon, ручна навігація й геолокація за запитом. Відмова у доступі не блокує застосунок.
- Фільтри дати, категорії й доступних місць, альтернативний список. «Сьогодні» та «Вихідні» рахуються в часовому поясі пристрою; час самої події — в її IANA timezone.
- Створення в три кроки, локальна чернетка, точка на мапі, редагування та скасування власних подій.
- Приєднання/вихід, збережені й власні події. Сервер контролює місткість навіть за одночасних запитів.
- Email/password Auth, підтвердження email, відновлення пароля та native callback. Токени зберігаються в Android Keystore/шифрованому сховищі та iOS Keychain.
- Фото через системний Photo Picker на сторінці вже створеної власної події. Storage перевіряє належність події; максимум 5 MiB, JPEG/PNG/WebP (iOS конвертує в JPEG).
- Збереження інтересів у Supabase, локальні нагадування за годину до події за згодою користувача.
- SQLDelight кеш останніх результатів, явний офлайн-стан. Створення та участь потребують серверного підтвердження. ID створення зберігається разом із відбитком чернетки для безпечного повтору після перезапуску.

Нагадування локальні. Кому й коли нагадувати вирішує `ReminderRules` у `core/domain` (власні й приєднані опубліковані події, за годину до початку), прапорець «нагадувати» живе в `AppState` і сторі пристрою, а `ReminderSync` у `shared` перераховує план на кожну зміну стану й віддає його платформному `ReminderScheduler` (AlarmManager на Android, UNUserNotificationCenter на iOS). Платформи лишають собі лише системний дозвіл і доставку; оновлення чи скасування події синхронізуються при відкритті/оновленні застосунку. Серверні push-сповіщення, чат, квитки й платежі не входять у цю версію.

## Supabase

Схему вже застосовано до погодженого проєкту **EventOrganiztor** (`tzdogzdvctlumsqlqskr`). Репозиторій містить лише публічний client key. Service-role key не використовується клієнтами.

Для email callback у [Supabase Auth URL Configuration](https://supabase.com/dashboard/project/tzdogzdvctlumsqlqskr/auth/url-configuration) додайте:

```text
poruch://auth/callback
```

Перевірте email confirmation, поштовий провайдер і redirect allowlist. Ці глобальні Auth settings не були змінені або перевірені доступним MCP конектором. Логін/реєстрація та recovery реалізовані в коді; доставку листів і повний перехід із листа на фізичному пристрої ще потрібно перевірити.

Android: `SUPABASE_URL`, `SUPABASE_KEY`, `MAP_TILES_URL`, `MAP_GLYPHS_URL` можна перевизначити через `local.properties` або environment. iOS: `iosApp/Config.xcconfig`. Стандартні значення вже вказують на погоджений проєкт.

Не застосовуйте початкову міграцію повторно до цього проєкту. Для нового середовища використовуйте міграції з `supabase/migrations`. Політики RLS, RPC, тести й результати описані в [supabase/README.md](supabase/README.md).

## Архітектура

```text
androidApp (Compose / Navigation 3)    iosApp (SwiftUI / NavigationStack)
                 \                    /
                    shared / AppGraph
                  Koin + StateFlow facade
                    /              \
           feature/events      feature/account
                    \              /
                      core/domain
                    interfaces + rules
                           ↑
                       core/data
              Ktor / Supabase / SQLDelight
```

`core/domain` не залежить від UI чи Supabase. Feature use cases перевіряють бізнес-правила через інтерфейси репозиторіїв; data реалізує ці інтерфейси. `shared` збирає ізольований Koin container і керує станом, скасуванням запитів та Swift bridge. Кожен нативний UI має власні системні адаптери й навігацію.

**Помилки** — типізовані: `sealed interface AppError` у `core/domain`, який кидається єдиним `AppFailure`. Жодного тексту для користувача в бізнес-логіці: назву випадку перекладає презентація (`androidApp/ui/Wording.kt`, `iosApp/App/Wording.swift`). Межі й константи, які раніше були вписані в код, зібрані в `core/domain/Rules.kt`, а стартове місто — у `AppConfig.home`.

**Android** — один екран, один MVI-цикл:

```text
Composable ──Intent──▶ ViewModel ──▶ PoruchApp (спільне сховище)
    ▲                     │  │
    └────── State ────────┘  └── Effect ──▶ Route (навігація, системні виклики)
```

Екрани лежать у `androidApp/.../feature/<screen>/`: `…Contract.kt` (State/Intent/Effect), `…ViewModel.kt`, `…Screen.kt`. Composable не знає ані сховища, ані навігації — їх з'єднує `feature/Routes.kt`.

**iOS** — `iosApp/Poruch/{App,DesignSystem,Features/<screen>,Platform}`. Екран із власним станом має `ObservableObject` (`EventEditorModel`, `AuthFormModel`, `EventActionsModel`), екран без нього — `struct`-проєкцію спільного стану (`HomePresentation`, `EventDetailPresentation`).

Версії: Kotlin 2.4.0, Gradle 9.1.0, AGP 9.0.1, Ktor 3.2.3, Koin 4.2.2, SQLDelight 2.1.0, Navigation 3 1.0.1. MapLibre Android 11.11.0, iOS 6.28.0 (SPM resolved file включено).

## Перевірки

```sh
./gradlew :core:domain:jvmTest :core:data:jvmTest \
  :feature:account:jvmTest :shared:jvmTest
```

2026-09-05:

- **22 KMP/JVM тести — PASS:** валідація, Auth refresh/logout/callback, створення з idempotency ID, скасування застарілих запитів, стан recovery.
- **Android assembleDebug — PASS**, APK встановлено й застосунок запущено на Pixel 9a emulator. Перевірено рендер мапи.
- **iOS simulator build — PASS**, застосунок запущено на iPhone 17 Pro / iOS 26.3. Перевірено рендер мапи.
- **Supabase SQL suites — PASS:** RLS, права власності, пошук, повторне приєднання, місткість і скасування.
- **Конкурентне приєднання — PASS:** одне вільне місце, два запити, рівно один учасник. Тестові користувачі/події прибрані.
- **Supabase security advisor — 0 findings.** Публічний discovery API відповідає HTTP 200.

Не виконано повний UI-сценарій із кількома реальними акаунтами, перевірку доставки листів/фото через фізичні пристрої, VoiceOver/TalkBack та store-release QA. Не видаємо ці перевірки за пройдені.

OpenFreeMap і публічний Photon працюють без власних ключів у цій конфігурації; для виробничого навантаження потрібні перевірка умов, лімітів та відповідна конфігурація провайдера. Атрибуція мапи збережена.

## Екрани із запущених застосунків

База подій порожня після очищення тестових даних; скріншоти не містять вигаданих подій.

[Android](androidApp/android-map.png) · [iOS](iosApp/ios-map.png)
