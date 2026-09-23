# Пуші: що вже є і що треба донести

Код, схема, функція й спільний секрет на місці. Без ключів провайдерів функція мовчить, а
застосунки працюють на локальних сповіщеннях, як і раніше. Щоб пуші пішли, треба чотири речі.

## 1. Секрет функції

У Vault проєкту вже лежить `push_function_secret`. Той самий рядок треба покласти в секрети
Edge Function під іменем `PUSH_SECRET` (значення — у Dashboard → Integrations → Vault, або
у людини, яка налаштовувала):

```bash
supabase secrets set PUSH_SECRET='<push_function_secret з Vault>' --project-ref tzdogzdvctlumsqlqskr
```

Поки його нема, функція відповідає 403, а тригери в базі просто не доставляють.

## 2. Android: Firebase Cloud Messaging

1. Firebase Console → проєкт `poruchapp-1e5c4` → Add app → Android, package `app.poriad.android` (вже додано).
2. Завантажити `google-services.json` і покласти в `androidApp/google-services.json`. Плагін `com.google.gms.google-services` сам генерує ресурси й ініціалізує Firebase на старті процесу; ніяких значень у `local.properties` не треба. Файл комітиться: у ньому лише публічні ідентифікатори.

3. Project settings → Service accounts → Generate new private key. JSON цілком — у секрет функції:

```bash
supabase secrets set FCM_SERVICE_ACCOUNT="$(cat service-account.json)" --project-ref tzdogzdvctlumsqlqskr
```

Сервісний акаунт має роль **Firebase Cloud Messaging API Admin** (за замовчуванням є). Емулятор Android з Google Play services отримує FCM, звичайний без Play — ні.

## 3. iOS: APNs

Два середовища — два ключі й два App ID. Team ID: `QTYQMJ94D2`.

| | Dev | Prod |
|---|---|---|
| Supabase | `ojadoyxeahepycpmjuvf` | `tzdogzdvctlumsqlqskr` |
| Bundle / App ID | `app.poriad.ios.dev` | `app.poriad.ios` |
| APNs-ключ | `Poriad APNs Dev`, Sandbox | `Poriad APNs Prod`, Production |
| `APNS_SANDBOX` | `true` | `false` (або не задано: за замовчуванням production) |

Функція йде в sandbox лише при `APNS_SANDBOX=true`, будь-яке інше значення — production. Токен стирається з `push_tokens` лише на 410 / `Unregistered`; `BadDeviceToken` (розбіжність sandbox ↔ production) лише логується — це помилка конфігурації, а не мертвий пристрій.

1. Identifiers → обидва App ID з capability **Push Notifications** (ентайтлмент `aps-environment` у проєкті вже є, підпис автоматичний).
2. Keys → два ключі з **Apple Push Notifications service (APNs)**, Team Scoped. Завантажити `.p8` (один раз), запамʼятати Key ID. Файли тримати поза репозиторієм. Apple дає максимум два APNs-ключі на команду, тож ротація = відкликати й перевипустити.
3. Секрети функції `push` у кожному проєкті:

```bash
supabase secrets set APNS_KEY="$(cat ~/.keys/AuthKey_D476H38CX8.p8)" APNS_KEY_ID=D476H38CX8 APNS_TEAM_ID=QTYQMJ94D2 APNS_BUNDLE_ID=app.poriad.ios.dev APNS_SANDBOX=true --project-ref ojadoyxeahepycpmjuvf
```

```bash
supabase secrets set APNS_KEY="$(cat ~/.keys/AuthKey_85C6JXDXN2.p8)" APNS_KEY_ID=85C6JXDXN2 APNS_TEAM_ID=QTYQMJ94D2 APNS_BUNDLE_ID=app.poriad.ios APNS_SANDBOX=false --project-ref tzdogzdvctlumsqlqskr
```

Середовище APNs визначає підпис збірки, а не bundle id: запуск з Xcode дає sandbox-токен, TestFlight і App Store — production. Тому пуші приходять у Dev-збірку з Xcode і в Prod-збірку з TestFlight/App Store; Prod з Xcode і Dev через TestFlight пушів не отримають.
Симулятор на Apple silicon (Xcode 14+) отримує справжні токени APNs і приймає пуші з sandbox.

## 3a. Analytics і Crashlytics

Обидві платформи, той самий проєкт Firebase `poruchapp-1e5c4`.

- **Android:** плагін `com.google.firebase.crashlytics` і `firebase-analytics`/`firebase-crashlytics` з BOM. Advertising ID вимкнено в маніфесті (`google_analytics_adid_collection_enabled=false`, дозволи `AD_ID` вирізано), бо політика обіцяє «без рекламних ідентифікаторів». Mapping для релізу плагін вивантажує сам.
- **iOS:** Swift Package `firebase-ios-sdk`, продукти `FirebaseAnalyticsCore` (без IDFA) і `FirebaseCrashlytics`. Firebase Console → Add app → iOS, bundle `app.poriad.ios` → завантажити `GoogleService-Info.plist` у `iosApp/Poruch/` і додати в таргет як ресурс (Xcode: перетягнути у групу Poruch, галочка Poruch у Target Membership). Без plist застосунок збирається й працює, просто `FirebaseApp.configure()` не викликається, а фаза «Crashlytics dSYM» пропускає вивантаження.

## 4. Перевірка

- Після входу в застосунок з дозволом на сповіщення в `public.push_tokens` має зʼявитись рядок пристрою.
- Написати в чат з іншого акаунта: у Dashboard → Edge Functions → push → Logs має бути виклик зі `sent: 1`.
- Без секретів провайдера в логах буде `FCM_SERVICE_ACCOUNT is not set` або `APNS_* are not set`, і це очікувано.

## Як це працює

- Пристрій реєструє токен через `register_push_token` при кожному вході; при виході знімає через `unregister_push_token`. Токен переходить до нового акаунта на тому ж телефоні.
- Тригери `event_messages_push` і `event_members_push` кличуть функцію через `pg_net` асинхронно; адресу й секрет читають з Vault.
- Функція вирішує, кому слати: повідомлення — організатору й підтвердженим, крім автора й заблокованих; запит — організатору. Android отримує data-пуш і малює сповіщення сам своїм каналом; iOS — alert-пуш з `thread-id` події. Токени, які провайдер відкинув, видаляються.
- Коли пристрій зареєстровано, локальні сповіщення при перечитуванні мовчать, щоб не дублювати; бейджі й секції на головній працюють як раніше. Тап по пушу відкриває подію.
