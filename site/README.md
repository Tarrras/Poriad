# Сайт «Поряд»

Лендинг, веб-афіша в режимі перегляду і сторінки, які потрібні магазинам. Без збірки: HTML, CSS і ES-модулі. `tokens.css` — шрифти й кольори застосунку для всіх сторінок; `web.css` — лендинг, афіша й сторінка події `/e/{id}` (її рендерить `worker/`); `style.css` — правові сторінки.

Афіша на сайті — та сама, що бачить гість у застосунку: браузер сам звертається до публічних RPC prod (`discover_events`, `event_cards_by_ids`, `event_safety`) з publishable-ключем. Дивитися, ділитися, купувати квиток у джерела — на сайті; приєднатися, зберегти, нагадати, «Шукаю компанію», стежити — кнопки відкривають шторку «у застосунку» з QR (`poriad.app/app` → стор телефона).

| Файл | Навіщо |
| --- | --- |
| `index.html`, `js/home.js` | Лендинг: живі числа й афіші з prod, стрічка тижня, тизер афіші, «Можливості» з телефоном, категорії, сайт проти застосунку |
| `afisha.html`, `js/afisha.js` | Веб-афіша: місто, дати, категорії, пошук, сітка з довантаженням, мапа (MapLibre з unpkg, стиль — порт `shared/MapStyle.kt`, тайли OpenFreeMap). Стан у адресі: `?city=&when=&cat=&q=&view=map&e=` |
| `js/poriad.js` | Дані й правила, спільні з застосунком: назви (`TitleRules`), дати («Сьогодні · 19:00», «до 31 жовтня»), згортання прокатів, фільтр «вихідні». Імпортує й `worker/` |
| `js/ui.js` | Картки, шторка події, шторка «у застосунку», QR |
| `app.html` | Посилання для QR: iPhone → App Store, Android → Google Play, комп’ютер → лендинг |
| `web.css`, `fonts/`, `img/icons.svg` | Стилі; Inter і Source Serif 4 600 локально; значки застосунку (`ds-bundle/icons/sprite.svg`) + системні й логотипи сторів |
| `privacy.html`, `privacy-en.html` | Privacy Policy URL для Play Console / App Store Connect і посилання в застосунку |
| `terms.html`, `terms-en.html` | Terms / EULA з правилами UGC (Apple 1.2, Play UGC policy) |
| `delete-account.html` | Обов'язковий веб-URL для Play «Account deletion» |
| `bot.html` | Сторінка робота імпорту (`/bot` з User-Agent `PoriadBot`): що читає, як відмовитись |
| `img/` | Екрани для лендингу — знімки iOS prod-збірки (603×1311; `companions.jpg`, `safety.jpg` — з `store/screens/ios_*.png`). Без тестової «Демо для перевірки застосунку» в кадрі |
| `CNAME`, `robots.txt` | Домен для GitHub Pages і дозвіл на індексацію |

## Перевірка

```bash
node tools/site_test.mjs
python3 -m http.server 8766 --directory site
```

`tools/site_test.mjs` звіряє правила `js/poriad.js` із застосунком (назви, дати в поясі події, вихідні, згортання). Сервер — щоб відкрити `http://localhost:8766/` і `/afisha.html`: модулі з `file://` не завантажуються.

## Перед публікацією

Тимчасові місця позначаються класом `.todo` (підсвітка). Перевірити, що нічого не лишилось:

```bash
grep -n 'class="todo"' site/*.html
```

## Хостинг

GitHub Pages, безкоштовно. Воркфлоу `.github/workflows/site.yml` викладає теку `site/` після кожного пушу в `main`; у репозиторії один раз увімкнути Settings → Pages → Source: **GitHub Actions**. Файл `site/CNAME` прив'язує домен `poriad.app`; у DNS домену додати:

| Тип | Ім'я | Значення |
| --- | --- | --- |
| A | @ | 185.199.108.153, 185.199.109.153, 185.199.110.153, 185.199.111.153 |
| CNAME | www | `<github-user>.github.io` |

Потім Settings → Pages → Custom domain: `poriad.app`, поставити «Enforce HTTPS» (для зони `.app` HTTPS обов'язковий, сертифікат GitHub видає сам за кілька хвилин). Якщо домен інший, замінити в `CNAME`, у `mailto:` і в `worker/` (сторінки подій `/e/…`, App Links / Universal Links — див. [worker/README.md](../worker/README.md)).

Після публікації вписати URL:

- Play Console → App content → Privacy policy; Data safety → Account deletion URL.
- App Store Connect → App Information → Privacy Policy URL; Support URL = лендинг.
- У застосунку: Профіль → «Про застосунок» (політика, умови, підтримка) і екран реєстрації («Реєструючись, ви погоджуєтесь…»).
