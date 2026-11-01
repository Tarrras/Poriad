# Lottie публікації події — джерела й ліцензії

Анімації для docs/organizers-1.5.md, розділ 1.6. Вибір власника 02.11 із семи кандидатів.

| Файл | Що | Джерело | Ліцензія |
|---|---|---|---|
| `publishing.json`, `publishing_dark.json` | «Поки публікується»: на квитку друкуються назва, рядок організатора, місце й час на корінці; петля 2,4 с, 30 fps, 240×160 | власна робота «Поряд», генератор `tools/generate_publish_lottie.py` | власна, без обмежень |
| `published.json`, `published_dark.json` | «Подію створено»: на квиток падає штамп «ОПУБЛІКОВАНО»; раз, 1,8 с, 30 fps, 240×160 | власна робота «Поряд», той самий генератор | власна, без обмежень; літери — контури шрифту нижче |

Файли не редагуємо вручну: правимо генератор і запускаємо його (`python3 tools/generate_publish_lottie.py`, потрібен
`fonttools`).

## Шрифт штампа

Літери «ОПУБЛІКОВАНО» в `published*.json` — векторні контури шрифту **Sofia Sans Condensed ExtraBold**
(`iosApp/Poruch/Fonts/SofiaSansCondensed-ExtraBold.ttf`, з українськими формами д, л, п).

- © 2019 The Sofia Sans Project Authors, https://github.com/lettersoup/Sofia-Sans
- SIL Open Font License 1.1, повний текст — `iosApp/Poruch/Fonts/SofiaSans-OFL.txt`

Самого файлу шрифту в анімації нема. OFL стосується поширення шрифту, а не графіки, зробленої ним; запис тут — для
повноти.

## Як клієнтам брати файли

Кольори запечені, тому день і ніч — окремі файли, як у наявних анімаціях із `tools/generate_lottie.py`:

- **Android:** `publishing.json` → `res/raw/publishing.json`, `publishing_dark.json` → `res/raw-night/publishing.json`
  (ім'я однакове, тему вибирає система); так само `published`.
- **iOS:** Data Set `PublishingLight` (`publishing.json` під іменем `publishing_light.json`) і `PublishingDark`
  (`publishing_dark.json`); `BrandAnimation(name: "Publishing")` бере варіант за `colorScheme`. Так само `Published`.
- **Сайт:** обидва в `site/vendor/lottie/`; тема — як у `site/tokens.css`: `data-theme` на `<html>`, якщо стоїть, інакше
  `prefers-color-scheme`. Зміна теми — перезавантажити анімацію з іншим файлом.
- **«Зменшити рух»:** `publishing` стоїть на кадрі 0 (надрукований квиток), `published` — на останньому кадрі (штамп
  уже стоїть). Наявний `BrandAnimation` для стоп-кадру бере кадр 0, тож для `published` потрібен останній кадр
  (iOS `.paused(at: .progress(1))`, Android `progress = 1f`) і програвання один раз.
- **Корінець** — шар `Stub`, запечений кольором музики `#6041B1`. Перефарбувати в жанр події: iOS `ColorValueProvider`
  на `**.Stub.**.Color`, Android `rememberLottieDynamicProperties` з `LottieProperty.COLOR` на `"Stub", "**"`, сайт —
  замінити цей колір у даних перед `loadAnimation`.
