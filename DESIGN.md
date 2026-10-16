---
name: Поряд
description: Афіша міста на одній мапі — спокійний аркуш, на якому оживає місто.
colors:
  ink: "#1D1D1F"
  ink-secondary: "#6E6E73"
  ink-tertiary: "#6E6E78"
  on-brand: "#FFFFFF"
  brand-container: "#E8E8ED"
  evening-coral: "#E0582F"
  evening-coral-text: "#C2431F"
  evening-coral-on-photo: "#FF8A5B"
  evening-coral-container: "#FDE7DF"
  on-evening-coral-container: "#7A2E14"
  success: "#2E7D4F"
  success-container: "#DFF3E6"
  on-success-container: "#1B4C2F"
  danger: "#C0392B"
  danger-container: "#FBE3E0"
  canvas: "#F5F5F7"
  canvas-tint: "#EBEBF0"
  surface: "#FFFFFF"
  surface-muted: "#F2F2F7"
  hairline: "#E5E5EA"
  glow: "#E4E1F6"
  night-canvas: "#0B0B0F"
  night-canvas-tint: "#141419"
  night-surface: "#17171C"
  night-surface-raised: "#202027"
  night-surface-muted: "#26262E"
  night-ink: "#F5F5F7"
  night-ink-secondary: "#A1A1A8"
  night-ink-tertiary: "#8E8E96"
  night-on-brand: "#1D1D1F"
  night-brand-container: "#2C2C33"
  night-hairline: "#2A2A33"
  night-glow: "#1B1A36"
  night-evening-coral: "#FF8A5B"
  night-evening-coral-container: "#3F2419"
  night-success: "#5DC389"
  night-success-container: "#16311F"
  night-danger: "#FF6B5B"
  night-danger-container: "#3C1A16"
  cat-music: "#6D4AC9"
  cat-music-wash: "#EBE4FB"
  cat-sport: "#0F7F73"
  cat-sport-wash: "#DDF0EC"
  cat-art: "#C43B6B"
  cat-art-wash: "#FBE1EA"
  cat-food: "#C96A1E"
  cat-food-wash: "#FBEBD9"
  cat-games: "#2F63C4"
  cat-games-wash: "#E1EAFB"
  cat-outdoors: "#3E7D3A"
  cat-outdoors-wash: "#E4F1E2"
  cat-social: "#B8562F"
  cat-social-wash: "#FAE5DA"
  cat-comedy: "#A07813"
  cat-comedy-wash: "#F7ECD2"
  cat-kids: "#1F8A8A"
  cat-kids-wash: "#D9EFEF"
  cat-tours: "#5F7F1F"
  cat-tours-wash: "#ECF0E4"
  cat-conference: "#933FA8"
  cat-conference-wash: "#F2E8F5"
  cat-unknown: "#6B675E"
  cat-unknown-wash: "#EDEBE4"
typography:
  display:
    fontFamily: "Source Serif 4, Georgia, serif"
    fontSize: "34px"
    fontWeight: 600
    lineHeight: "40px"
    letterSpacing: "-0.5px"
  headline:
    fontFamily: "Source Serif 4, Georgia, serif"
    fontSize: "28px"
    fontWeight: 600
    lineHeight: "34px"
    letterSpacing: "-0.4px"
  title:
    fontFamily: "Source Serif 4, Georgia, serif"
    fontSize: "22px"
    fontWeight: 600
    lineHeight: "28px"
    letterSpacing: "-0.2px"
  title-small:
    fontFamily: "Source Serif 4, Georgia, serif"
    fontSize: "17px"
    fontWeight: 600
    lineHeight: "22px"
    letterSpacing: "-0.1px"
  numeral:
    fontFamily: "SF Pro, Roboto, system-ui, sans-serif"
    fontSize: "28px"
    fontWeight: 700
    lineHeight: "34px"
    letterSpacing: "-0.8px"
  row-title:
    fontFamily: "SF Pro, Roboto, system-ui, sans-serif"
    fontSize: "17px"
    fontWeight: 600
    lineHeight: "22px"
    letterSpacing: "-0.2px"
  lead:
    fontFamily: "SF Pro, Roboto, system-ui, sans-serif"
    fontSize: "17px"
    fontWeight: 400
    lineHeight: "25px"
  body:
    fontFamily: "SF Pro, Roboto, system-ui, sans-serif"
    fontSize: "16px"
    fontWeight: 400
    lineHeight: "22px"
  subhead:
    fontFamily: "SF Pro, Roboto, system-ui, sans-serif"
    fontSize: "15px"
    fontWeight: 400
    lineHeight: "21px"
  caption:
    fontFamily: "SF Pro, Roboto, system-ui, sans-serif"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: "18px"
  descriptor:
    fontFamily: "SF Pro, Roboto, system-ui, sans-serif"
    fontSize: "13px"
    fontWeight: 500
    lineHeight: "18px"
  label:
    fontFamily: "SF Pro, Roboto, system-ui, sans-serif"
    fontSize: "14px"
    fontWeight: 500
    lineHeight: "18px"
  button:
    fontFamily: "SF Pro, Roboto, system-ui, sans-serif"
    fontSize: "16px"
    fontWeight: 600
    lineHeight: "20px"
  overline:
    fontFamily: "SF Pro, Roboto, system-ui, sans-serif"
    fontSize: "11px"
    fontWeight: 600
    lineHeight: "14px"
    letterSpacing: "1px"
rounded:
  xs: "12px"
  sm: "14px"
  md: "18px"
  lg: "24px"
  xl: "28px"
  pill: "9999px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "20px"
  xxl: "24px"
  section: "32px"
  page: "16px"
components:
  button-primary:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.on-brand}"
    typography: "{typography.button}"
    rounded: "{rounded.pill}"
    height: "52px"
    padding: "0 24px"
  button-primary-disabled:
    backgroundColor: "{colors.brand-container}"
    textColor: "{colors.ink-tertiary}"
  button-secondary:
    backgroundColor: "{colors.surface-muted}"
    textColor: "{colors.ink}"
    typography: "{typography.button}"
    rounded: "{rounded.pill}"
    height: "52px"
    padding: "0 24px"
  chip:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    typography: "{typography.label}"
    rounded: "{rounded.pill}"
    height: "38px"
    padding: "0 16px"
  chip-selected:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.on-brand}"
  search-field:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.pill}"
    height: "50px"
    padding: "0 16px"
  input-field:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.sm}"
    height: "56px"
    padding: "0 16px"
  card:
    backgroundColor: "{colors.surface}"
    rounded: "{rounded.lg}"
    padding: "16px"
  card-hero:
    textColor: "{colors.on-brand}"
    typography: "{typography.headline}"
    rounded: "{rounded.xl}"
    height: "360px"
  create-event-card:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.on-brand}"
    typography: "{typography.row-title}"
    rounded: "{rounded.lg}"
    padding: "16px"
  status-badge:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    typography: "{typography.overline}"
    rounded: "{rounded.pill}"
    padding: "5px 12px"
  tab-bar:
    backgroundColor: "{colors.surface}"
    typography: "{typography.overline}"
    rounded: "{rounded.xl}"
  sheet:
    backgroundColor: "{colors.surface}"
    rounded: "{rounded.xl}"
---

# Design System: Поряд

Платформа — нативні iOS (SwiftUI) і Android (Compose) з однаковим API токенів і компонентів. Розміри тут записано в `px`: це 1 pt на iOS і 1 dp/sp на Android, і всі кеглі масштабуються Dynamic Type / `fontScale`. Джерело значень — код: [Tokens.kt](androidApp/src/main/java/app/poruch/android/ui/Tokens.kt), [DesignSystem.swift](iosApp/Poruch/DesignSystem/DesignSystem.swift), [Components.swift](iosApp/Poruch/DesignSystem/Components.swift). Для сайту ті самі токени дзеркалить [site/tokens.css](site/tokens.css). Обґрунтування й історія рішень лежать у [docs/design-system.md](docs/design-system.md). Якщо вони розходяться з кодом, правий код.

## Overview

**Creative North Star: "Спокійний аркуш"**

Екран — один тихий аркуш, на якому оживає місто. Інтерфейс майже не має кольору: прохолодне полотно, білі (вночі — трохи світліші за тло) картки й одна чорнильна дія. Колір належить змістові: постерам, категоріям і станам. Обʼєкт на аркуші виникає з різниці тону, а не з рамки чи тіні. Тому стіна афіш читається як мудборд, а не як каталог.

Настрій — преміальний, нічний, впевнений. Нічна тема тут не похідна від денної: майже чорне полотно зі сяйвом за шапкою — це місце, де бренд найбільше схожий на себе, і саме так він виглядає в роликах та на енд-картах. Денна тема — той самий аркуш у прохолодному папері, з тим самим контрастом. Впевненість іде від стриманості: одна дія на екрані має вагу, бренд не кричить хроматичним кольором, заголовки говорять засічками, як у виданні, а дані лишаються точним системним гротеском.

Щільність середня. Відкриття на головній дихає великими картками з фото, а мапа, списки й форми щільні та сканувальні, бо це робочий інструмент. Свідомо **не** беремо продуктових фото на весь екран, соціальних стрічок, астрологічного декору Moonly, стандартних Material-компонентів (плаваючий підпис поля, `AlertDialog`, системний `DatePickerDialog`) і емодзі як іконок категорій.

**Key Characteristics:**
- Прохолодне полотно, картка без рамки й тіні; нічна картка має волосяний край.
- Головна дія — чорнильна пігулка (вночі біла), хроматичного бренд-кольору нема.
- Два голоси: Source Serif 4 600 для назв подій і заголовків, системний гротеск для даних.
- Вечірній корал — рідкісна гаряча точка: терміновість, лічильник, крапка знака.
- Кожна категорія має трійку кольорів: глибокий відтінок, пастель і відтінок-сусід для градієнта обкладинки.
- Тінь є лише в того, що плаває над вмістом.
- Власні тонколінійні гліфи (штрих 1.75) і знак-пін, спільний для іконки, мапи й Lottie.

## Colors

Нейтральна база й чорнильна дія, а весь хроматичний колір віддано категоріям, станам і одному вечірньому коралу.

### Primary
- **Чорнило** (`ink`): головна дія (пігулка `PrimaryButton`, вибраний чип, `CreateEventCard`, кластер на мапі), заголовки й основний текст. Уночі дія інвертується в **Нічний папір** (`night-ink`), а текст на ній стає `night-on-brand`.
- **Текст на дії** (`on-brand`): текст і гліфи на чорнилі.
- **Тонова пігулка** (`brand-container` / `night-brand-container`): бейдж, неактивна головна кнопка (на 55 % альфи, щоб бути блідішою за другорядну).

### Secondary
- **Вечірній корал** (`evening-coral` / `night-evening-coral`): лічильник активних фільтрів, «залишилось мало місць», крапка непрочитаного на таббарі, акцентна крапка знака. Лише заливки й крапки.
- **Вечірній корал для тексту** (`evening-coral-text`): той самий корал як дрібний текст на білому (відлік «СЬОГОДНІ · 18:15 · ЧЕРЕЗ 2 ГОД»). Сам `evening-coral` дає там лише 3,75:1, цей тримає 5,1:1.
- **Вечірній корал на фото** (`evening-coral-on-photo`): акцентний текст на затемненні обкладинки в обох темах.
- **Підкладка терміновості** (`evening-coral-container`, текст `on-evening-coral-container`).

### Tertiary
**Палітра категорій.** Кожна з 11 категорій (плюс `unknown`) має глибокий відтінок (`cat-*`) для пінів, гліфів і крапок і пастель (`cat-*-wash`) для плиток. Третій стоп — відтінок-сусід, тобто відтінок іншої категорії: музика → мистецтво, спорт → ігри, мистецтво → музика, їжа → мистецтво, ігри → спорт, природа → спорт, зустрічі → їжа, стендап → мистецтво, дитяче → ігри, екскурсії → природа, конференції → музика.
- Обкладинка без фото у світлій темі — градієнт від пастелі, висвітленої до білого, через пастель до пастелі з 22 % сусіда. Уночі — відтінок на 30 % альфи → сусід на 14 %.
- Велика картка без фото (`categoryHeroGradient`) — повний відтінок → сусід, текст поверх білий.
- `categoryInk` для тексту й гліфів: удень це сам відтінок, уночі — відтінок із 45 % білого, щоб тримати 4.5:1.

### Semantic
- **Участь** (`success`, підкладка `success-container`, текст `on-success-container`): «Ви берете участь», успішний `NoticeBanner`.
- **Небезпека** (`danger`, `danger-container`): скасування, помилки, небезпечна дія в `PoruchConfirmSheet`.

### Neutral
- **Прохолодний папір** (`canvas`): полотно екрана вдень. **Нічне полотно** (`night-canvas`): майже чорне полотно вночі.
- **Картка** (`surface` / `night-surface`): картки, чипи, поле пошуку, поля форм, нижні листи. Уночі те, що плаває, бере `night-surface-raised`.
- **Тиха поверхня** (`surface-muted` / `night-surface-muted`): другорядна кнопка, плитка іконки.
- **Підкладка мапи** (`canvas-tint` / `night-canvas-tint`).
- **Сяйво** (`glow` / `night-glow`): холодний ореол 460 px за шапкою головної, що тане в полотно. Він нерухомий, картки їдуть по ньому.
- **Волосина** (`hairline` / `night-hairline`): розділювачі, ручка листа, а вночі ще й край картки.
- **Другорядне чорнило** (`ink-secondary`): метадані, підзаголовки. **Третинне чорнило** (`ink-tertiary`): overline, плейсхолдери, підписи полів. Обидва тримають ≥ 4.5:1 на `canvas` і `surface`.

### Named Rules
**Правило безбарвної дії.** Головна дія завжди чорнильна (уночі паперова), ніколи не хроматична. Колір на екрані — це зміст, а не бренд.

**Правило рідкісного коралу.** Вечірній корал позначає лише терміновість, лічильник або знак. Він не буває тлом секції, кнопкою чи прикрасою.

**Правило готового до тла відтінку.** Текст і гліфи категорії фарбує `categoryInk`, а не сирий відтінок: уночі сирий дає лише ~2.5:1.

## Typography

**Display Font:** Source Serif 4 (змінний, SIL OFL; вага 600, оптичний розмір рівний кеглю; fallback Georgia)
**Body Font:** системний гротеск — SF Pro на iOS, Roboto на Android (на сайті — Inter)

**Character:** Назва події звучить як заголовок у виданні, а дата, місце й кнопки — як точний інтерфейс. Засічки не перемагають даних. Source Serif 4 обрано за кирилицю: є Ґ Є І Ї, `ʼ`, «», № і ₴, і він вужчий за Literata, тож довгі українські назви переносяться рідше.

### Hierarchy
- **Display** (Source Serif 4 600, 34/40, −0.5): заголовок екрана («Що поруч», «Мої події»), назва події на деталях, питання онбордингу й редактора, «Поряд» на сплеші.
- **Headline** (600, 28/34, −0.4): назва на великій картці, заголовок аркуша й `PageHeader`, імʼя людини.
- **Title** (600, 22/28, −0.2): заголовок секції (`SectionHeader`), порожній стан, назва в картці плану, заголовок шторки.
- **Title small** (600, 17/22, −0.1): назва події на постері, у рядку й у списку; назва закладу; шапка чату.
- **Numeral** (sans 700, 28/34): цифри й значення («12 як організатор»), буква аватара. Це не заголовки.
- **Row title** (sans 600, 17/22): службові рядки («Коли / Де», опції онбордингу, імена в запитах).
- **Lead** (400, 17/25): опис події на деталях. **Body** (400, 16/22): текст у формах і листах. **Subhead** (400, 15/21): підзаголовок шапки.
- **Caption** (400, 13/18): адреса, метадані, час у чаті. **Descriptor** (500, 13/18, колір `categoryInk`): назва категорії під назвою події.
- **Label** (500, 14/18): чипи. **Button** (600, 16/20): кнопки.
- **Overline** (600, 11/14, +1.0, ВЕРХНІЙ РЕГІСТР): дата, бейджі, підписи полів, підписи таббару.

### Named Rules
**Правило змісту, а не кегля.** Засічки отримує назва події (від hero до рядка 17 px) і заголовок екрана чи секції. Дата, місце, чипи, кнопки, цифри й службові рядки — завжди гротеск.

**Правило людської назви.** Екрани показують `Event.displayTitle`, а не сирий `title`: капс джерела стає звичайним регістром, лапки — «ялинками», `'` — `’`. Капс лишається лише там, де несе дані: overline, бейдж, підпис поля.

## Layout

- **Сітка — крок 4.** Дозволені відступи: 4, 8, 12, 16, 20, 24, 32, 40. Край екрана (`page`) — 16, внутрішнє поле картки — 16, між картками — 12, між секціями — 24 (32 для великих зон).
- **Лише iPhone, портрет.** Розкладка — одна колонка з повнорозмірними картками. Постери «У місті» стоять сіткою у дві колонки (4:5), а великі картки гортаються каруселлю, де наступна визирає з-за краю.
- **Мапа займає весь екран.** Угорі — пошук із кнопкою фільтрів і одна стрічка чипів, унизу — карусель подій, синхронізована з мапою. Керування мапою стоїть над каруселлю, у зоні великого пальця.
- **Навігація плаває:** скляний таббар із полями від країв і окрема кругла кнопка створення. Панель головної дії на деталях теж плаває суцільною карткою, а не смугою на всю ширину.
- **Усі питання — знизу.** Модальних діалогів посеред екрана нема. Лист розгортається одразу повністю, а головна дія закріплена під прокруткою з волосиною над собою.
- **Повідомлення — згори.** `NoticeBanner` стоїть під статус-баром, бо нижній край належить навігації.
- Цілі натискання — щонайменше 44 pt / 48 dp. Візуально менші чипи (38) і «зберегти» (34) резервують повну ціль.

## Elevation & Depth

Система пласка за замовчуванням: усе в потоці лежить на одному рівні (`card` = 0), і картку від полотна відділяє лише тон. Вдень біла картка лежить на прохолодному папері без рамки й тіні. Вночі різниця тону мала, тому край картки несе волосина 1 px. Глибина зʼявляється лише в того, що плаває над вмістом: таббар, карусель над мапою, банер, панель дії, кнопка створення. Тінь одна — широка й бліда.

### Shadow Vocabulary
- **Raised** (висота 8): кругла кнопка «зберегти» поверх обкладинки; уночі картка на цій висоті бере `night-surface-raised`. На сайті — `--shadow-raised` у [site/tokens.css](site/tokens.css).
- **Overlay** (висота 24): таббар, карусель, `NoticeBanner`, панель дії; на сайті `--shadow-overlay`.
- iOS малює тінь як `shadow(color: shadowSpot, radius: висота, y: висота / 3)`. Колір — чорний на 10 % удень і 40 % вночі. Android дає ту саму висоту двома складовими: `shadowSpot` 10 % / 40 % і `shadowAmbient` 6 % / 30 %.
- **Скло таббару:** на iOS `ultraThinMaterial` під `surface` на 60 % (вночі 55 %). На Android — непрозора поверхня з тінню overlay.
- **Затемнення під листом:** теплий чорний (`ink` удень, `night-canvas` уночі) на 32 % / 62 %, ніколи нейтральний сірий.

### Named Rules
**Правило плаского потоку.** Тінь має лише те, що плаває над вмістом. Картка в стрічці не отримує ні тіні, ні рамки (рамка лише вночі, як волосина).

## Shapes

Мова форм — мʼякі предмети з великими радіусами. На iOS кути безперервні (`.continuous`), а не дуги.

- **Радіуси:** `xs` (12) — мініатюра, плитка іконки; `sm` (14) — поле форми, чип сеансу; `md` (18) — плитка категорії, превʼю мапи; `lg` (24) — картка, постер 4:5, `CreateEventCard`; `xl` (28) — велика картка, таббар, нижній лист (лише верхні кути); `pill` — кнопки, чипи, поле пошуку, бейджі.
- **Фото врівень із краєм:** картка обрізає обкладинку власним радіусом, без поля довкола. Постер стоїть без коробки, а підпис лежить просто на полотні.
- **Ручка листа** — волосяна риска 32×4 кольором `hairline`, а не залита пігулка Material.
- **Гліфи** — власний набір: штрих 1.75 з круглими кінцями на сітці 24, вміст у межах 3..21. Заливка лише там, де форма замала для контуру (закладка «збережено», очки кубика). Геометрію генерує [tools/generate_icons.py](tools/generate_icons.py) для обох платформ.
- **Знак** — пін: чорнильне тло, паперова крапля, коралова крапка. Той самий силует стоїть в іконці застосунку, гліфі `pin`, пінах мапи й Lottie-анімаціях.

## Components

Предметні й стримані: картка — це предмет, кнопка — чорнильна пігулка, дотик відповідає глибиною, а не кольором. Кожен компонент існує в Compose і SwiftUI з однаковим API.

### Buttons
- **Shape:** пігулка висотою 52.
- **Primary:** чорнило (`ink`), текст `on-brand`, бокові поля 24, на всю ширину. Може мати гліф 18 зліва або тон (`danger` для небезпечної дії), тоді заливка — вертикальний градієнт тону 92 % → 100 %. Неактивна кнопка — `brand-container` на 55 % з текстом `ink-tertiary`. Стан завантаження — індикатор замість гліфа.
- **Press:** поверхня сідає до 0.98 і повертається пружиною (response 0.28, damping 0.7). Зі зменшеним рухом лишається підсвітка, а просідання зникає.
- **Secondary:** `surface-muted` без рамки, текст `ink`, та сама пігулка.

### Chips
- **Style:** пігулка 38 (ціль 44), поля 16, label 14/500. Опційно — крапка категорії 8 або гліф 15 зліва, шеврон 13 справа (чип відкриває вибір) чи коралів лічильник непрочитаного.
- **State:** невибраний — `surface` з текстом `ink`; рамка-волосина лише вночі. Вибраний — заливка чорнилом, текст і крапка `on-brand`.
- «Стежити» — той самий чип-перемикач із дзвінком: вибраний заливається, як усі чипи.

### Cards / Containers
- **Corner Style:** `lg` (24) для звичайної картки, `xl` (28) для великої.
- **Background:** `surface`; уночі те, що плаває, бере `night-surface-raised`.
- **Shadow Strategy:** у потоці — жодної (див. Правило плаского потоку); плаваюча картка — overlay.
- **Border:** лише вночі, волосина 1 px.
- **Internal Padding:** 16.
- **`EventHeroCard`:** 360 заввишки, радіус `xl`, обкладинка `EventArt` на всю висоту, затемнення й текст унизу: назва headline, дата й місце двома рядками, бейдж ліворуч, «зберегти» праворуч.
- **`PosterCard`:** обкладинка 4:5 з радіусом 24 без коробки. Під нею дата (`ink`), назва title-small у два рядки, «● місце», підпис джерела «Афіша · джерело». На фото — плашка стану («Ви йдете», «Лишилось 2») і ціна чи «👥 3/8».
- **`CreateEventCard`:** чорнильна плашка на всю ширину під шапкою головної — кружок «+» 44 на `on-brand` 14 %, назва, підпис на 72 % і стрілка. Це єдина дія такої ваги на екрані.

### Inputs / Fields
- **Style:** `LabelledField` — підпис overline (`ink-tertiary`, капс, +1.0) **над** білим полем `surface` з радіусом `sm`, висота від 56, поля 16, без рамки. Підказка caption — під полем.
- **Search:** пігулка `surface` 50 заввишки з гліфом лупи й очищенням; рамка-волосина лише вночі. Кнопка фільтрів має кораловий лічильник 18.
- **Focus:** курсор і виділення фарбуються чорнилом, а не системним акцентом.
- **Error:** тон `danger`. Дата й час обираються власним листом (`DateTimeSheet` на Android), а не системним діалогом.

### Navigation
- **Таббар:** плаваюча скляна пігулка з радіусом `xl` і тінню overlay, поля від країв. Чотири пункти — гліф і підпис overline, висота пункту 42. Активний пункт стоїть на тоновій пігулці (`ink` на 10 %), непрочитане позначає коралова крапка 8.
- **Створення:** окрема кругла кнопка поруч із таббаром.
- **Шапка головної:** «Що поруч» display, місто з шевроном (тап — вибір міста), праворуч круглі кнопки пошуку й профілю. Позаду — сяйво.

### Sheets
- `PoruchSheet` / `sheet`: поверхня `surface`, верхні кути `xl`, ручка-волосина. Заголовок листа — справжній заголовок (title), а не overline.
- **`PoruchConfirmSheet`:** заголовок, пояснення, кнопка небезпечної дії тоном `danger` і тихіша кнопка виходу під нею. Двох однакових текстових міток не буває.
- Відповідь спершу закриває лист, і лише потім діє.

### NoticeBanner
Картка `surface` з тінню overlay під статус-баром. Ліворуч — квадрат-контейнер із гліфом тону: помилка (`danger-container` + `danger`) чи успіх (`success-container` + `success`). Далі текст і хрестик. Банер приходить зсувом згори (зі зменшеним рухом — лише прозорість), тримається 3 с для успіху й 5 с для помилки.

### EventArt (signature)
Обкладинка події, спільна для hero, постера й рядка: фото на всю площу або, без фото, насичений градієнт категорії з великим прозорим гліфом. Завдяки їй стрічка без фото не стає стіною блідих плиток.

### Map pins & clusters
Пін — диск 38 з носиком 9: `surface`, обведення 2.5 і гліф відтінком категорії. Вибраний пін — 46, залитий відтінком категорії, з обведенням і гліфом `surface`, і завжди поверх сусідів. Кластер — чорнильне коло (18 → 30 за кількістю) з обведенням `surface` 3 і ореолом чорнила на 16 % (уночі 28 %), кількість — 13 bold `on-brand`. Під мапою — карусель `EventMapCard` 116 заввишки. Підкладка — OpenFreeMap Positron удень і Dark уночі.

### Motion
Один швидкий крок (200 мс, easeInOut) і одна пружина (response 0.32, damping 0.86) на весь застосунок. При системному «зменшити рух» крок стає миттєвим, а переходи — згасанням. Фірмова анімація — Lottie зі знака: сплеш «місто оживає», лоадер-пін 56 і тло порожнього стану.

## Do's and Don'ts

### Do:
- **Do** бери кольори, радіуси й відступи лише з токенів (`Poruch.colors`, `Palette`, `Spacing`/`Space`, `Radius`/`Corner`): екрани не задають значень напряму.
- **Do** фарбуй головну дію чорнилом (`ink`, уночі `night-ink`) як пігулку 52.
- **Do** ставь Source Serif 4 600 на назви подій і заголовки екранів та секцій, а все інше набирай системним гротеском.
- **Do** показуй `Event.displayTitle`, а сиру назву віддавай лише календарю, «Маршруту», «Поділитися» й пушам.
- **Do** фарбуй текст і гліфи категорії через `categoryInk` і тримай текст ≥ 4.5:1, а великий текст і гліфи ≥ 3:1.
- **Do** став питання нижнім листом із закріпленою головною дією, а одноразові повідомлення показуй `NoticeBanner` згори.
- **Do** перевіряй кожен екран в обох темах: нічна тема рівноправна, а не похідна.
- **Do** поважай системне «зменшити рух»: крок миттєвий, переходи згасають.

### Don't:
- **Don't** вводь хроматичний бренд-колір для дій чи тла: колір належить категоріям і станам.
- **Don't** використовуй вечірній корал як тло, кнопку чи прикрасу.
- **Don't** додавай рамку чи тінь картці в потоці у світлій темі.
- **Don't** використовуй стандартні Material-компоненти з чужою мовою: плаваючий підпис поля, `AlertDialog`, системний `DatePickerDialog`, залиту ручку листа.
- **Don't** показуй категорії емодзі й не бери системні SF Symbols / Material Icons там, де є власний гліф.
- **Don't** набирай назви подій капсом і не ставь засічки на дати, місця, чипи, кнопки чи цифри.
- **Don't** використовуй продуктові фото на весь екран, соціальні стрічки чи декоративний (астрологічний) орнамент.
- **Don't** затемнюй нейтральним сірим: затемнення під листом — теплий чорний.
