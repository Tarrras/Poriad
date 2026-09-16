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

1. Firebase Console → створити проєкт (або взяти наявний) → Add app → Android, package `app.poruch.android`.
2. Project settings → General → у картці застосунку взяти `App ID`, `API key`, `Project ID`, `Sender ID` (Cloud Messaging → Sender ID). `google-services.json` не потрібен: значення йдуть у `local.properties`:

```properties
FIREBASE_PROJECT_ID=poruch-xxxxx
FIREBASE_APP_ID=1:1234567890:android:abcdef123456
FIREBASE_API_KEY=AIza...
FIREBASE_SENDER_ID=1234567890
```

3. Project settings → Service accounts → Generate new private key. JSON цілком — у секрет функції:

```bash
supabase secrets set FCM_SERVICE_ACCOUNT="$(cat service-account.json)" --project-ref tzdogzdvctlumsqlqskr
```

Сервісний акаунт має роль **Firebase Cloud Messaging API Admin** (за замовчуванням є). Емулятор Android з Google Play services отримує FCM, звичайний без Play — ні.

## 3. iOS: APNs

1. Apple Developer → Certificates, Identifiers & Profiles → Keys → новий ключ з увімкненим **Apple Push Notifications service (APNs)**. Завантажити `.p8` (один раз), запамʼятати Key ID. Team ID: `QTYQMJ94D2`.
2. Identifiers → `app.poruch.ios` → увімкнути capability **Push Notifications** (ентайтлмент `aps-environment` у проєкті вже є, підпис автоматичний).
3. Секрети функції:

```bash
supabase secrets set APNS_KEY="$(cat AuthKey_XXXXXXXXXX.p8)" APNS_KEY_ID=XXXXXXXXXX APNS_TEAM_ID=QTYQMJ94D2 APNS_BUNDLE_ID=app.poruch.ios APNS_SANDBOX=true --project-ref tzdogzdvctlumsqlqskr
```

`APNS_SANDBOX=true` для dev-збірок (Xcode, симулятор, TestFlight-development). Для App Store — `false`.
Симулятор на Apple silicon (Xcode 14+) отримує справжні токени APNs і приймає пуші з sandbox.

## 4. Перевірка

- Після входу в застосунок з дозволом на сповіщення в `public.push_tokens` має зʼявитись рядок пристрою.
- Написати в чат з іншого акаунта: у Dashboard → Edge Functions → push → Logs має бути виклик зі `sent: 1`.
- Без секретів провайдера в логах буде `FCM_SERVICE_ACCOUNT is not set` або `APNS_* are not set`, і це очікувано.

## Як це працює

- Пристрій реєструє токен через `register_push_token` при кожному вході; при виході знімає через `unregister_push_token`. Токен переходить до нового акаунта на тому ж телефоні.
- Тригери `event_messages_push` і `event_members_push` кличуть функцію через `pg_net` асинхронно; адресу й секрет читають з Vault.
- Функція вирішує, кому слати: повідомлення — організатору й підтвердженим, крім автора й заблокованих; запит — організатору. Android отримує data-пуш і малює сповіщення сам своїм каналом; iOS — alert-пуш з `thread-id` події. Токени, які провайдер відкинув, видаляються.
- Коли пристрій зареєстровано, локальні сповіщення при перечитуванні мовчать, щоб не дублювати; бейджі й секції на головній працюють як раніше. Тап по пушу відкриває подію.
