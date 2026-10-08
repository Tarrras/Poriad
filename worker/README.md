# Worker сторінок подій

`poriad.app/e/{id}` — сторінка події з прев'ю для Telegram і месенджерів (Open Graph), Smart App Banner на iOS
і кнопками «Відкрити в «Поряд»» / App Store. Той самий Worker віддає `/.well-known/apple-app-site-association`
і `/.well-known/assetlinks.json`, за якими iOS і Android відкривають такі посилання одразу в застосунку.
Решта сайту — як і раніше, GitHub Pages (`site/`): маршрути в `wrangler.toml` перехоплюють лише ці адреси.

Дані — публічний RPC `event_details` prod-проєкту з publishable-ключем, тобто рівно те, що бачить гість у
застосунку. Приховані, приватні й заблоковані події він не віддає → сторінка «Подію не знайдено». Відповідь
кешується на краю на 5 хвилин. Усі сторінки `noindex`: події доступні лише за посиланням, доки політика
конфіденційності не скаже інакше. Імпортовані — з `canonical` на джерело.

## Перевірка без Cloudflare

```bash
node worker/test.mjs
```

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
