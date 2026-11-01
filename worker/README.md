# Worker сторінок подій

`poriad.app/e/{id}` — сторінка події з прев'ю для Telegram і месенджерів (Open Graph), Smart App Banner на iOS
і кнопками «Відкрити в «Поряд»» / App Store. Той самий Worker віддає `/.well-known/apple-app-site-association`
і `/.well-known/assetlinks.json`, за якими iOS і Android відкривають такі посилання одразу в застосунку.

## Весь домен і CSP

З 1.5 воркер стоїть на `poriad.app/*`: сайт тримає токен входу в `localStorage`, а його бачить кожна сторінка домену.
Решту сайту він бере з GitHub Pages тим самим запитом (запит воркера у власну зону Cloudflare йде на origin з DNS, а
не знову у воркер) і додає до HTML заголовки безпеки; js, css, шрифти й картинки віддає як є.

- Маршрути — таблиця `ROUTES` у `index.mjs`: перший збіг шляху. Нова сторінка чи API — один рядок там.
- CSP кожен маршрут збирає з частин (`CSP` в `index.mjs`): сторінка події — Supabase у `connect-src` і сховище в
  `media-src`; міста — лише свій домен; сторінки Pages — ще MapLibre (`site/vendor/`, тайли OpenFreeMap, `blob:`).
  Inline-скриптів нема ніде, крім «Поділитися» з хешем; inline-стилів і `on…=` — теж.
- Кожен запит до сайту тепер рахується як запит воркера (безкоштовно — 100 тис. на добу). Якщо впремося, у панелі
  Cloudflare можна зняти воркер з `/js/*`, `/fonts/*`, `/img/*`, `/vendor/*`: заголовки там не потрібні.

Дані — публічний RPC `event_details` prod-проєкту з publishable-ключем, тобто рівно те, що бачить гість у
застосунку. Приховані, приватні й заблоковані події він не віддає → сторінка «Подію не знайдено». Відповідь
кешується на краю на 5 хвилин. Усі сторінки `noindex`: події доступні лише за посиланням, доки політика
конфіденційності не скаже інакше. Імпортовані — з `canonical` на джерело.

## Сторінки міст для пошуковиків

`poriad.app/afisha/{kyiv|lviv|odesa|dnipro|kharkiv}` і розділи `/sohodni`, `/vykhidni`, `/kontserty`, `/teatr`,
`/standup`, `/dityam`, разом 35 сторінок. Веб-афіша (`afisha.html`) малює події в браузері, і пошуковик її майже
не бачить, тому той самий індекс тут віддається готовим HTML з розміткою schema.org (ItemList з Event).

- Дані: `discover_events` (індекс без карток) + `event_cards_by_ids` для показаних, тобто два запити на сторінку
  й кеш на 5 хвилин.
- Лише афіша квиткових сервісів і лише те, що ще попереду. Зустрічі людей лишаються за посиланням, як і їхні
  сторінки (`noindex`).
- Менше трьох подій — сторінка `noindex, follow`, щоб не підсовувати пошуковику тонку сторінку.
- Адреси перелічено в `site/sitemap.xml`. Новий розділ чи місто додавай і туди.

## Перевірка без Cloudflare

```bash
node --test worker/*.test.mjs
```

`--test` запускає кожен файл окремо (`node worker/*.test.mjs` прогнав би лише перший); те саме робить CI.

## Локально з dev-базою

```bash
cd worker && npx wrangler dev --env dev
```

http://localhost:8787 — увесь сайт: сторінки з теки `site/` (assets замість Pages), дані — dev-проєкт Supabase. Сайт
на `localhost` сам ходить у dev (`SUPABASE` у `site/js/poriad.js`). Вхід через Google локально — лише якщо
`http://localhost:8787/**` є в Redirect URLs dev-проєкту.

## Перший деплой (один раз)

1. Cloudflare → poriad.app → DNS: чотири A-записи `@` перевести з **DNS only** на **Proxied**.
   SSL/TLS → Overview → режим **Full**. Без проксі маршрути Worker-а не спрацюють.
   Caching → Configuration → Browser Cache TTL: **Respect Existing Headers**. Інакше Cloudflare
   підміняє наші 5 хвилин на свої 4 години, і людина довго бачить старий стан події.
2. У терміналі:
   ```bash
   cd worker && npx wrangler login && npx wrangler deploy
   ```
3. Перевірити: `curl -sI https://poriad.app/e/<id-події>` → `200`, `content-type: text/html`;
   `curl -s https://poriad.app/.well-known/apple-app-site-association` → JSON з `QTYQMJ94D2.app.poriad.ios`.
   Прев'ю в Telegram — надіслати посилання собі в «Збережене» (Telegram кешує прев'ю; для повтору — @WebpageBot).

## Коли щось змінюється

- **Вихід у Google Play:** у `index.mjs` вписати `PLAY_URL` і відбиток з Play Console → App integrity →
  App signing (SHA-256) у `ANDROID_CERT_FINGERPRINTS`, потім `npx wrangler deploy`. До того Android відкриває
  посилання в браузері, на цій же сторінці, — це запасний шлях, а не помилка.
- **iOS:** Associated Domains (`applinks:poriad.app`) уже в `Poruch.entitlements`; Xcode з автоматичним підписом
  сам увімкне можливість в App ID при наступному архіві. Працює лише в prod-збірці: AASA називає тільки
  `app.poriad.ios`. Dev-збірки ділять тим самим посиланням, але dev-подій у prod нема → «Подію не знайдено».

## Вигляд сторінки

Сторінка події зверстана тими самими класами, що шторка події на сайті: стилі `/web.css`, значки `/img/icons.svg`,
назви й дати — `site/js/poriad.js` (wrangler збирає цей імпорт у воркер). Тому порядок викладки: спершу пуш сайту
(GitHub Pages), потім `npx wrangler deploy` — інакше нова сторінка якийсь час шукатиме ще не викладений `web.css`.
