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
  `media-src`; міста — лише свій домен; сторінки Pages — ще MapLibre (`site/vendor/`, тайли OpenFreeMap, `blob:`),
  сховище й `blob:` у `media-src` (відео в кабінеті). Inline-скриптів нема ніде, крім «Поділитися» з хешем;
  inline-стилів і `on…=` — теж (`tools/site_test.mjs` це перевіряє).
- Маршрут саме `poriad.app/*`: шаблон без `*` у Cloudflare збігається лише з адресою без рядка запиту, а шаблон з `?`
  недійсний, тож `https://poriad.app/?fbclid=…` (так Threads та Instagram відкривають кожне посилання) інакше пройшов би
  повз воркер без CSP. `worker/routes.test.mjs` перевіряє, що кожна `site/*.html` з запитом і без має маршрут.
- Кожен запит до сайту рахується як запит воркера (безкоштовно — 100 тис. на добу). Щоб js, css, шрифти й картинки
  йшли з Pages напряму, у панелі: Workers Routes → Add route **без воркера** (None) для `poriad.app/js/*`,
  `poriad.app/fonts/*`, `poriad.app/img/*`, `poriad.app/vendor/*`, `poriad.app/web.css*`, `poriad.app/tokens.css*`,
  `poriad.app/style.css*`, `poriad.app/icon.png*`: точніший шаблон перемагає `poriad.app/*`, а файлам CSP не потрібна.

Дані — публічний RPC `event_details` prod-проєкту з publishable-ключем, тобто рівно те, що бачить гість у
застосунку. Приховані, приватні й заблоковані події він не віддає → сторінка «Подію не знайдено». Відповідь
кешується на краю на 5 хвилин. Усі сторінки `noindex`: події доступні лише за посиланням, доки політика
конфіденційності не скаже інакше. Імпортовані — з `canonical` на джерело.

## Кабінет організатора

`poriad.app/kabinet` (`site/kabinet.html`, `site/js/kabinet.js`) воркер бере з Pages, як решту сайту, але зі своєю
політикою `CSP.kabinet`: там лежить токен організатора, тож картинки — лише свої й зі сховища Supabase (а не будь-який
https), плюс мапа й `blob:` для прев'ю фото й перевірки відео; заголовок `x-robots-tag: noindex`. Підказки адрес
редактора — `/api/geocode?q=&city=` (`worker/kabinet.mjs`): Photon з User-Agent PoriadBot і центром міста форми, кеш
на краю на добу, запит від 3 до 100 символів і лише п'ять міст сайту. Тести — `worker/kabinet.test.mjs`.

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
на `localhost` сам ходить у dev (`SUPABASE` у `site/js/poriad.js`), як і з емулятора Android (`http://10.0.2.2:8787`) і
з телефона в тій самій мережі (`--ip 0.0.0.0`, адреса Mac у 10.*, 192.168.* чи 172.16–31.*). Вхід через Google локально —
лише якщо ця адреса з `/**` є в Redirect URLs dev-проєкту. Assets у dev перенаправляє `/x.html` → `/x` і `@` → `%40`;
на Pages такого нема.

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
