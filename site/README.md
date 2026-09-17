# Сайт «Поряд»

Статичні сторінки, які потрібні магазинам і застосунку: лендинг, політика конфіденційності, умови користування, видалення акаунту. Без збірки: HTML + один CSS, кольори з `docs/design-system.md`.

| Файл | Навіщо |
| --- | --- |
| `index.html` | Лендинг: скріншоти, що вміє, підтримка, кнопки сторів |
| `privacy.html`, `privacy-en.html` | Privacy Policy URL для Play Console / App Store Connect і посилання в застосунку |
| `terms.html`, `terms-en.html` | Terms / EULA з правилами UGC (Apple 1.2, Play UGC policy) |
| `delete-account.html` | Обов'язковий веб-URL для Play «Account deletion» |
| `img/` | Скріншоти для лендингу |

## Перед публікацією

Усе, що позначено класом `.todo` (помаранчева підсвітка), треба замінити:

- назва контролера даних (ФОП / юрособа), код, адреса — у `privacy*.html`, `terms*.html`;
- `privacy@poriad.app`, `hello@poriad.app` — на реальні скриньки (або одну);
- регіон проєкту Supabase (Dashboard → Settings → General → Region);
- посилання на App Store / Google Play у `index.html` після публікації.

Перевірити, що нічого не лишилось:

```bash
grep -n 'class="todo"' site/*.html
```

## Хостинг

GitHub Pages, безкоштовно. Воркфлоу `.github/workflows/site.yml` викладає теку `site/` після кожного пушу в `main`; у репозиторії один раз увімкнути Settings → Pages → Source: **GitHub Actions**. Файл `site/CNAME` прив'язує домен `poriad.app`; у DNS домену додати:

| Тип | Ім'я | Значення |
| --- | --- | --- |
| A | @ | 185.199.108.153, 185.199.109.153, 185.199.110.153, 185.199.111.153 |
| CNAME | www | `<github-user>.github.io` |

Потім Settings → Pages → Custom domain: `poriad.app`, поставити «Enforce HTTPS» (для зони `.app` HTTPS обов'язковий, сертифікат GitHub видає сам за кілька хвилин). Якщо домен інший, замінити в `CNAME`, у `mailto:` і в App Links / Universal Links, коли вони з'являться.

Після публікації вписати URL:

- Play Console → App content → Privacy policy; Data safety → Account deletion URL.
- App Store Connect → App Information → Privacy Policy URL; Support URL = лендинг.
- У застосунку: Профіль → «Про застосунок» (політика, умови, підтримка) і екран реєстрації («Реєструючись, ви погоджуєтесь…»).
