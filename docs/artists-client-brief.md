# Бриф для клієнтів: артисти (Android + iOS)

Для окремої сесії AI-агента. Бекенд готовий і лежить поруч: [artists-discovery-2026-10.md](artists-discovery-2026-10.md)
(рішення, метрики), [follows.md](follows.md) (розділ «Артисти»). Тут тільки те, що треба клієнту.

## Мета

Додати артистів у застосунок трьома місцями, **всі три в одному релізі**:

1. **Чип у картці й деталях події**: хто виступає (до трьох імен, ведучий окремо).
2. **Пошук**: секція «Артисти» поруч із «Місця» в пошуку на мапі й головній. Тап відкриває екран артиста.
3. **«Стежити»**: кнопка на екрані артиста, артисти в екрані «Підписки», їхні події на головній у блоці підписок,
   тап по пушу про нову подію артиста.

Зразок для всього: **заклади**. Усе, що зроблено для `place` (пошук `search_places`, `place_events`, чип «Стежити»,
`FollowsScreen`, пуш `kind=place`), повторюється для `artist`. Починай з читання цих місць, не вигадуй нових шаблонів.

## Що вже є на бекенді

Dev: усе розгорнуто, дані для Києва є (Львів, Харків, Одеса, Дніпро наповнюються). Prod: міграції й функція
`push` розгорнуті, **даних артистів на prod ще нема** (перший прогін чекає), тож перевіряти на **dev**
(схема iOS `Poruch-Dev`, Android `devDebug`). Не змінюй `supabase/`, `tools/ingest/`: це інша сесія.

### RPC (усі через `EventRpc`, як `search_places`)

| RPC | Параметри | Відповідь | Хто може |
|---|---|---|---|
| `search_artists` | `p_text`, `p_city` (null = усі), `p_limit` (≤50) | `[{id, name, kind?, upcoming}]`, за спаданням `upcoming` | anon + authenticated |
| `artist_events` | `p_artist_id`, `p_limit` (≤100) | масив **карток подій**, як `place_events` (найближчі першими) | anon + authenticated |
| `follow` / `unfollow` | `p_kind: "artist"`, `p_target: <artist id>` | void; `FOLLOW_UNAVAILABLE` якщо артиста нема | authenticated |
| `my_follows` | | елементи `{kind:"artist", id, name, artist_kind?, since, upcoming}` разом із place/organizer | authenticated |
| `follow_events` | `p_limit` | картки, **уже включають події артистів** (прокат одного артиста згорнуто в одну картку) | authenticated |

`search_artists` повертає лише артистів, у яких є майбутні видимі події. Порожній або задовгий (>120) текст:
`[]` / помилка `INVALID_SEARCH_TEXT` (як у `search_places`).

### Картка події: нове поле `artists`

```json
"artists": [
  {"id": "…", "name": "Андрій Бережко", "kind": "person", "role": "headliner"},
  {"id": "…", "name": "Дмитро Захарченко", "role": "host"}
]
```

- `role`: `headliner` | `support` | `host`. Порядок вже серверний, не пересортовуй.
- `kind`: `person` | `group` | `company` | `show`; **буває відсутнім** (сервер не знає виду). Не показуй вид як текст.
- Поле **відсутнє**, якщо артистів нема (серверний `jsonb_strip_nulls`). Старі відповіді й prod без даних теж без нього:
  `artists` у DTO з дефолтом `emptyList()`, нічого не падає.
- Складу може бути багато (фестиваль, 10+ імен): у картці показуй до трьох і «та ще N», повний список в деталях події.

### Пуш про нові події артистів

Один пуш на людину, спільний добовий ліміт із закладами (серверна логіка, клієнту нічого рахувати не треба).

- **FCM `data`** (Android): `kind="artist"`, `title`, `body`, `key`, `artistId`, і `eventId` **лише коли подія одна**.
- **APNs** (iOS): `kind="artist"`, `artistId`, `eventId` (опційно), `key`; `thread-id` = `eventId` або `artist:<id>`.
- **Тап**: є `eventId` → відкрий подію; інакше `artistId` → екран артиста. Так само працює `placeId` для закладів
  у [Push.kt](../androidApp/src/main/java/app/poruch/android/platform/Push.kt), `MainActivity.kt` (`EXTRA_PLACE_ID`,
  `openPlace`), `Reminders.notifyFollowed`, iOS [Push.swift](../iosApp/Poruch/Platform/Push.swift),
  `PoruchApp.swift` (`PushDelegate.openEvent`) і `Reminders.swift`. Додай `artistId` тим самим шляхом.
- Невідомий `kind` старий клієнт має ігнорувати, не падати. Перевір обидва `when`/`switch`.

## Що змінити (шари)

**Domain** (`core/domain`): `FollowKind.ARTIST("artist")`; `Follow` отримує вид артиста (`artistKind`); нова модель
`Artist(id, name, kind, role)` і `Event.artists: List<Artist>`; `ArtistHit(id, name, kind, upcoming)` для пошуку.
`EventAccess`: `searchArtists(text, city)` і `artistEvents(artistId)` поруч із `searchPlaces`/`placeEvents`.
`FollowRules`: `canFollowArtist` (артист існує, є акаунт). Серверні правила пуша (`placePush`, `isNew`) **не дублюй**:
вони виконуваний опис place-логіки, для артистів сервер сам, клієнту не потрібні.

**Data** (`core/data`): `EventDto` читає `artists`; `SupabaseEventDiscovery` додає два методи (див. `searchPlaces`,
рядок ~94); `SupabaseFollows`/`FollowDto` знають `kind=artist`. `FollowKind.fromKey` вже повертає null для невідомого,
а `mine()` робить `mapNotNull`: це лишається.

**Shared** (`shared`): `DiscoveryEngine` (пошук артистів поруч із `searchPlaces`, ті самі debounce/скасування),
`FollowUseCases`, `AppState`/`UserLibrary` (підписки й їхній стан). Гість: «Стежити» веде на вхід, як для закладу.

**Android** (Compose, `androidApp/.../feature/*`, `ui/Components.kt`): чип у картці й деталях (`DetailViewModel`,
Explore/Home картки), секція «Артисти» в пошуку (`ExploreViewModel`), екран артиста (найближчі події + «Стежити»),
`FollowsScreen`/`FollowsViewModel`, пуш (`Push.kt`, `MainActivity.kt`, `Reminders.kt`).

**iOS** (SwiftUI, `iosApp/Poruch/Features/*`, `DesignSystem.swift`/`Components.swift`): те саме дзеркально:
`EventDetailView`, `DiscoveryView`/`HomeView`, `FollowsView`, `Push.swift`/`PoruchApp.swift`/`Reminders.swift`.

Екрани мають **однаковий API й поведінку** на обох платформах (це правило проєкту, див. README «Дизайн-система»).
Кольори, радіуси, відступи лише з токенів (`Tokens.kt`, `DesignSystem.swift`), без прямих значень.

## UX (рішення власника, не змінюй без питання)

- Артист це людина, гурт, **ґастролююча трупа** (МУР, «Леви на Джипах») або шоу-бренд («Бродячий Стендап»).
  Театр-майданчик не артист: сервер його вже відсіяв, клієнт нічого не фільтрує.
- Чип: ім'я артиста тапається (екран артиста). Ведучий підписаний («Ведучий»). Жодних фото/біографій: їх нема.
- Екран артиста: ім'я, вид словом лише якщо відомий (`group` → «Гурт», `show` → «Шоу», `company` → «Трупа»,
  `person` без підпису), «Стежити», список найближчих подій (`artist_events`), порожній стан «Поки нічого не заплановано».
- Пошук: секція «Артисти» нижче «Місця», не більше 5 рядків, тап відкриває екран артиста. Не шукай до 2 символів
  (дзеркаль поведінку `search_places`).
- «Підписки»: окрема група «Артисти» (як заклади й організатори), рядок: ім'я + «N подій» (`upcoming`).
- Українська мова в усіх текстах; множина через наявні хелпери (як `plural` для подій).

## Аналітика й приватність

[analytics.md](analytics.md): подія `follow` вже має `target`; додай значення `artist`. Нових подій не вигадуй без
потреби; якщо додаєш `artist_open`, опиши в analytics.md. Текст пошуку й імена не відправляй, лише кількості (як для
місць). `PoruchLog`: ідентифікатори першими 8 символами, без імен і пошукових рядків.

## Перевірка

- **Тести**: `FollowRules`/`Follows` у `core/domain`, `EventDtoTest` (нове поле + його відсутність), `PoruchAppTest`
  (фейк `searchArtists`), `PlaceLookupTest`-подібні для пошуку. Запуск (звір назви задач через `./gradlew tasks`, вони могли
  відрізнятись): `./gradlew :core:domain:allTests :core:data:allTests :shared:allTests` і
  `./gradlew :androidApp:testDevDebugUnitTest`.
- **Android**: `./gradlew :androidApp:installDevDebug`, пройди три місця вручну (картка, пошук «бережко», підписка).
- **iOS**: схема `Poruch-Dev`, симулятор, ті самі три сценарії + скріншоти. Зібрати можна й з командного рядка
  (README, «Запуск iOS»); якщо видно `MLNResourceNotFoundException` після перевстановлення, це відомий збій
  симулятора, не твій баг.
- Реальні дані на dev: артисти «Андрій Бережко» (23 події), «Kyiv Mozart Orchestra», «Театр Чорний квадрат».
- Підписку на dev перевіряй з акаунтом, що має токен; пуш про артиста відправляється лише з сервера
  (`select private.notify_artist_follows()` в SQL Editor, див. follows.md), клієнт його не провокує.

## Межі й обережність

- **Не комітити, не пушити, не розгортати.** У дереві є чужі незакомічені зміни (`tools/ingest/`, `supabase/`, docs).
  Працюй лише в клієнтських теках; коміт лише якщо попросять, і тільки своїх файлів.
- **Prod і релізи** (`iosApp/release.sh`, Play, версії) робить власник сам. Підняття версій не входить у завдання.
- Не міняй серверний контракт: якщо чогось бракує (поле, фільтр), опиши в підсумку, а не вигадуй обхід.
- Старі версії застосунку без цієї фічі мають і далі працювати з тим самим сервером (нових обов'язкових полів нема).

## Готово, коли

1. Три місця працюють на обох платформах проти dev, сценарії пройдені й описані у підсумку зі скріншотами.
2. Тести зелені, нові тести покривають парсинг `artists` (є/нема), пошук, підписку, `kind=artist` у `mine()`.
3. Пуш про артиста відкриває подію або екран артиста з холодного й теплого старту на обох платформах
   (перевір симульованим payload, реального пуша на dev не потрібно).
4. Оновлено `docs/follows.md` (клієнтська частина) і розділ «Що реалізовано» в README.
