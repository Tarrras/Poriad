# Тексти й графіка для сторів

Графіка в цій теці згенерована 2026-09-16 з реальних екранів debug-збірок (iPhone 17 Pro, Pixel 9a) через `tools`-скрипт у сесії аудиту; перегенерувати після зміни UI. Перезнято 2026-09-17 після появи видалення акаунту, юридичних посилань і реалістичних спільнотних подій у Києві.

## Файли

| Файл | Розмір | Куди |
| --- | --- | --- |
| `play/icon_512.png` | 512×512 | Play Console → Store listing → App icon |
| `play/feature_graphic_1024x500.png` | 1024×500 | Play Console → Feature graphic |
| `play/phone_01..06.png` | 1080×1920 | Play Console → Phone screenshots (порядок = нумерація) |
| `appstore/iphone69_01..05.png` | 1320×2868 | App Store Connect → iPhone 6.9" |
| `appstore/iphone67_01..05.png` | 1290×2796 | App Store Connect → iPhone 6.7" |
| `../iosApp/Poruch/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` | 1024×1024 | іконка App Store (уже в проєкті) |

iPad-скріншотів немає: у pbxproj `TARGETED_DEVICE_FAMILY = "1,2"`. Або зняти iPad 13" (2064×2752), або перейти на iPhone-only (`TARGETED_DEVICE_FAMILY = 1`), що безпечніше для першого релізу.

## Google Play

**Назва (30):** Поруч — події поруч з вами

**Короткий опис (80):** Події міста на мапі: концерти, настолки, пробіжки, зустрічі. Створюйте свої.

**Повний опис (4000):**

Поруч — застосунок про те, що відбувається поруч із вами просто зараз. Замість стрічки — мапа міста з подіями: концерти й вистави з афіш, настільні ігри, ранкові пробіжки, розмовні клуби, лекції та зустрічі, які створюють такі самі люди, як ви.

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
• Без реклами й стеження. Геолокація — лише за вашим запитом.

Афішні події беруться з відкритих джерел із зазначенням джерела; квитки купуються на сайті організатора.

Мапа: MapLibre, дані © учасники OpenStreetMap, тайли OpenFreeMap.

**Категорія:** Events. **Теги:** events, meetups, map, місто.
**Контакт:** hello@poruch.app (замінити). **Політика:** https://poruch.app/privacy.html (замінити на реальний URL).

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
| Device or other IDs (FCM token, Firebase Installation ID) | ні | пуші | Google |

Crash logs, diagnostics, реклама, фінанси, контакти, здоров'я — не збираються.

### Content rating (IARC)

UGC: так. Спілкування між користувачами: так (чат). Обмін контентом: так (фото, посилання). Поділ геолокації користувача: ні (публікується адреса події, не позиція людини). Цільова аудиторія: 18+, не Families.

### App access

Дати тестовий акаунт з підтвердженим email і датою народження 18+, місто за замовчуванням Київ. Опис англійською: sign in → Map tab → tap a pin → Join; Profile → notifications toggle; «+» → create event.

## App Store

**Name (30):** Поруч — події поруч
**Subtitle (30):** Мапа подій і зустрічей міста
**Promotional text (170):** Концерти, настолки, пробіжки й зустрічі за 15 хвилин ходьби від вас. Знаходьте на мапі, приєднуйтесь, створюйте власні.
**Keywords (100):** події,афіша,мапа,зустрічі,концерти,настолки,пробіжка,київ,львів,meetup,events,куди піти
**Description:** той самий текст, що для Play, без заголовків капсом за бажанням.
**Primary language:** Ukrainian. **Category:** Social Networking (secondary: Lifestyle). **Age rating:** 18+ (UGC, повідомлення між користувачами, чат зі стоп-словником і модерацією; «unrestricted web access» — ні, WebView немає).
**Support URL:** лендинг. **Privacy Policy URL:** privacy-en.html або privacy.html.

### App Privacy (Data linked to you)

Contact Info: Email, Name. Identifiers: User ID, Device ID. Location: Coarse Location (not linked). Photos or Videos. User Content: Other User Content, Messages (push через APNs). Other Data: дата народження. Tracking: none.

### App Review Notes (англійською)

> Poruch is a Ukrainian-language event discovery app (map + community meetups). Sign-up requires age 18+ (birth date is validated server-side). Test account: <email> / <password> (already 18+ and confirmed). The default city is Kyiv, which has imported public listings; tap any pin on the Map tab to open an event. "Buy ticket" opens the organizer's website in Safari (physical events, no IAP). User-generated events, chat, report and block are available from the event screen after sign-in. Account deletion: Profile → Delete account. Location is requested only when tapping "Near me".
