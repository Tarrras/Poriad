# Тексти й графіка для сторів

Графіку в цій теці збирає `python3 tools/store_shots.py` (HTML + headless Chrome) із сирих екранів у `screens/`. Скріни перезняті 2026-09-18 після редизайну з prod-збірок Debug-Prod (iPhone 17 Pro, Android-емулятор) місто Київ; слайди 1, 3, 4 без входу в акаунт, слайди 2 («Мої події») і 5 (створення події) з тестовим акаунтом, форму не опубліковано. На Android поля форми порожні: кирилицю в емулятор через adb не ввести. Після зміни UI треба перезняти `screens/*.png` з тими самими іменами, за потреби поправити координати винесених шматків у `SLIDES` і запустити скрипт.

## Файли

| Файл | Розмір | Куди |
| --- | --- | --- |
| `play/icon_512.png` | 512×512 | Play Console → Store listing → App icon |
| `play/feature_graphic_1024x500.png` | 1024×500 | Play Console → Feature graphic |
| `play/phone_01..05.png` | 1080×1920 | Play Console → Phone screenshots (порядок = нумерація) |
| `appstore/iphone69_01..05.png` | 1320×2868 | App Store Connect → iPhone 6.9" |
| `appstore/iphone67_01..05.png` | 1290×2796 | App Store Connect → iPhone 6.7" |
| `appstore/iphone65_01..05.png` | 1242×2688 | App Store Connect → iPhone 6.5" |
| `../iosApp/Poruch/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` | 1024×1024 | іконка App Store (уже в проєкті) |

iPad-скріншоти не потрібні: застосунок iPhone-only (`TARGETED_DEVICE_FAMILY = 1`, рішення 2026-09-18). Додати iPad можна пізніше, прибрати після релізу — ні.

## Google Play

**Назва (30):** Поряд — події поряд з вами

**Короткий опис (80):** Події міста на мапі: концерти, настолки, пробіжки, зустрічі. Створюйте свої.

**Повний опис (4000):**

Поряд — застосунок про те, що відбувається поруч із вами просто зараз. Замість стрічки — мапа міста з подіями: концерти й вистави з афіш, настільні ігри, ранкові пробіжки, розмовні клуби, лекції та зустрічі, які створюють такі самі люди, як ви.

ЗНАХОДЬТЕ
• Мапа з кластерами за категоріями: музика, спорт, мистецтво, їжа, ігри, природа, стендап, екскурсії, конференції, зустрічі.
• Фільтри «сьогодні», «вихідні», «є вільні місця», пошук за назвою, місцем або темою.
• Будь-яке місто: оберіть вручну або натисніть «поруч зі мною».
• Головна збирає план тижня: ваші події, підбірка за інтересами, сьогодні в місті.

ПРИЄДНУЙТЕСЬ
• Одна кнопка: приєднатися, стати в чергу, зберегти на потім.
• Місце, що звільнилось, автоматично дістається першому в черзі.
• Чат події для організатора й учасників.
• Нагадування за годину до початку, експорт у календар, маршрут у мапах.

СТВОРЮЙТЕ
• Своя зустріч за три кроки: опис, точка на мапі, час і місткість.
• Підтвердження учасників, вікові межі, обкладинка, посилання на чат.
• Ви бачите, хто йде; сторонні бачать лише кількість.

БЕЗПЕКА
• Тільки для дорослих: реєстрація з 18 років.
• Скарга й блокування з екрана кожної події.
• Імена учасників — лише організатору й тим, хто вже приєднався.
• Без реклами й рекламних ідентифікаторів. Геолокація — лише за вашим запитом.

Афішні події беруться з відкритих джерел із зазначенням джерела; квитки купуються на сайті організатора.

Мапа: MapLibre, дані © учасники OpenStreetMap, тайли OpenFreeMap.

**Категорія:** Events. **Теги:** events, meetups, map, місто.
**Контакт:** hello@poriad.app (замінити). **Політика:** https://poriad.app/privacy.html.

### Data safety (як заповнювати)

Збирається / шифрується в дорозі: так / можна запросити видалення: так (`delete_my_account`, кнопка в профілі).

| Тип | Обов'язково | Мета | Передається |
| --- | --- | --- | --- |
| Email | так | акаунт | ні |
| Ім'я | так | акаунт, показ учасникам | ні |
| Інша особиста інформація (дата народження) | так | вікова перевірка | ні |
| User ID | так | акаунт | ні |
| Приблизна геолокація | ні | функціональність, ефемерно | ні |
| Фото | ні | обкладинка події (публічна) | ні |
| Повідомлення в застосунку | ні | чат події | Google (FCM) для доставки пушів |
| Інший контент користувача | ні | події, скарги, блокування | ні |
| Device or other IDs (FCM token, Firebase Installation ID) | ні | пуші, аналітика | Google |
| App interactions (Analytics) | ні | аналітика | Google |
| Crash logs, Diagnostics | ні | стабільність | Google |

Реклама, фінанси, контакти, здоров'я — не збираються. Advertising ID вимкнено в маніфесті, тож у Data safety його не вказувати.

### Content rating (IARC)

UGC: так. Спілкування між користувачами: так (чат). Обмін контентом: так (фото, посилання). Поділ геолокації користувача: ні (публікується адреса події, не позиція людини). Цільова аудиторія: 18+, не Families.

### App access

Дати тестовий акаунт з підтвердженим email і датою народження 18+, місто за замовчуванням Київ. Опис англійською: sign in → Map tab → tap a pin → Join; Profile → notifications toggle; «+» → create event.

## App Store

**Name (30):** Поряд — події поряд
**Subtitle (30):** Мапа подій і зустрічей міста
**Promotional text (170):** Концерти, настолки, пробіжки й зустрічі за 15 хвилин ходьби від вас. Знаходьте на мапі, приєднуйтесь, створюйте власні.
**Keywords (100):** події,афіша,мапа,зустрічі,концерти,настолки,пробіжка,київ,львів,meetup,events,куди піти
**Description:** той самий текст, що для Play, без заголовків капсом за бажанням.
**Primary language:** Ukrainian. **Category:** Social Networking (secondary: Lifestyle). **Age rating:** 18+ (UGC, повідомлення між користувачами, чат зі стоп-словником і модерацією; «unrestricted web access» — ні, WebView немає).
**Support URL:** https://poriad.app. **Privacy Policy URL:** https://poriad.app/privacy-en.html (українська: privacy.html). **Account deletion URL для Play:** https://poriad.app/delete-account.html.

### App Privacy (Data linked to you)

Contact Info: Email, Name. Identifiers: User ID, Device ID. Location: Coarse Location (not linked). Photos or Videos. User Content: Other User Content, Messages (push через APNs). Other Data: дата народження. **Not linked to you:** Diagnostics (Crash Data, Performance Data), Usage Data (Product Interaction). Tracking: none (Analytics без IDFA).

### App Review Notes (англійською)

> Poriad is a Ukrainian-language event discovery app (map + community meetups). Sign-up requires age 18+ (birth date is validated server-side). Test account: <email> / <password> (already 18+ and confirmed). The default city is Kyiv, which has imported public listings; tap any pin on the Map tab to open an event. "Buy ticket" opens the organizer's website in Safari (physical events, no IAP). User-generated events, chat, report and block are available from the event screen after sign-in. Account deletion: Profile → Delete account. Location is requested only when tapping "Near me".
