# Поряд (Poriad) — design conventions

Поряд is a native iOS + Android app for finding events near you (a map, a feed and your own plans). All UI copy is **Ukrainian**. The real product is SwiftUI/Compose, so this project doesn't include compiled components: it has **tokens, CSS recipes that copy the native components 1:1, the app's own icon set, and screenshots of every screen**. Build phone screens at **402×874** (iPhone 16 Pro) unless asked otherwise.

## Setup
```html
<link rel="stylesheet" href="styles.css">   <!-- tokens + type classes + component recipes -->
<body>  <!-- canvas background and system font are set here -->
```
Dark theme follows `prefers-color-scheme`. To force a theme, put `data-theme="dark"` or `data-theme="light"` on any ancestor. **Every design must work in both themes.** Use only `var(--*)` tokens, never raw hex, and the dark theme comes for free.

## Look (match the screenshots, not a generic iOS kit)
- The screen is one calm sheet: `--canvas` (#F5F5F7) with white `--surface` cards. In light mode cards have **no border and no shadow**; in dark mode they get a 1px `--hairline` edge (`--card-border-width` + `--card-border-color`). Only floating things get a shadow: the tab bar, the map carousel, the round "+" button.
- The primary action is a **flat near-black pill** (`--brand`). It turns white in dark mode. There is no chromatic brand colour: colour belongs to **categories** and **states** (`--success`, `--accent` = "few spots left", `--danger`).
- Radii: cards 24 (`--radius-lg`), fields 14, category tiles 18, sheets and tab bar 28–32, chips and buttons are pills. Photos sit **flush** with the card edge.
- Two typefaces, split by **content**. Screen titles, section titles and **every event name** are **Source Serif 4 semibold 600** (`--font-serif`, bundled, the same file the app ships). Everything else is sans: the app uses SF Pro; designs use the bundled **Inter** (`--font`). That covers dates, places, chips, buttons, numbers and service rows like "Підписки: 15 подій". Never swap in another typeface. UPPERCASE with +1 tracking is used **only** for data: date overline, badges, field labels.
- Event names are shown in sentence case even when the source sends CAPS, with «ялинки» quotes and a proper apostrophe (').
- Covers without a photo use **EventArt** (`.p-art`): a saturated category gradient with a huge white 18% glyph pushed off the corner, not a pastel tile. Pastel (`.p-cat-fill`) is only for small tiles and thumbnails.
- Home sits on a cool **glow** (`--glow` fading to `--canvas` over 460px, `.p-glow`). Other screens are plain canvas.
- Spacing is a 4-pt grid. Page gutter 16, card padding 16, 12 between cards, 24 between sections.
- Questions and pickers open as **bottom sheets** (`.p-sheet`), never as centred dialogs. The sheet's primary action is pinned to the bottom.

## Vocabulary
**Type classes:** serif: `.t-serif-display` 34 (= `.t-display`) · `.t-serif-title1` 28 · `.t-serif-title2` 22 (= `.t-section`) · `.t-serif-title3` 17 (= `.t-card-name`). Sans: `.t-title1` 28 / `.t-title2` 22 / `.t-title3` 17 (numbers and service rows only) · `.t-lead` · `.t-body` 16 · `.t-subhead` 15 · `.t-label` · `.t-button` · `.t-caption` 13 · `.t-descriptor` · `.t-overline` 11.

**Tokens:** `--brand --on-brand --brand-container --accent(-container) --accent-text --accent-on-photo --glow --success(-container) --danger(-container) --ink --ink-secondary --ink-tertiary --surface --surface-raised --surface-muted --canvas --canvas-tint --hairline`, plus `--space-xs…section`, `--radius-xs…xl|pill|sheet`, `--shadow-raised|overlay`, `--scrim`.

**Categories** (11): `music sport art food games outdoors social comedy kids tours conference`. Each has `--cat-<key>` (hue, used for glyphs, dots and text), `--cat-<key>-wash` and `--cat-<key>-partner`. Put `.cat-<key>` on an element, then use `.p-cat-fill` for a tile or a cover without a photo, and `.p-cat-ink` for a dot or text. Category labels: Музика, Спорт, Мистецтво, Їжа, Ігри, Природа, Зустрічі, Стендап, Дітям, Екскурсії, Конференції.

**Component recipes** (in `tokens/components.css`; each one mirrors the SwiftUI component with the same name):
`.p-screen .p-section .p-page-header` (home) `.p-nav-header .p-back` (inner screens) `.p-section-title` (+ action link) · `.p-glow` · `.p-icon-pill` · `.p-create-card` (CreateEventCard «Організувати подію») + `.p-quiet-row` (guest sign-in line) · `.p-art` (EventArt) · `.p-hero` (EventHeroCard) in `.p-pager` · `.p-poster` (PosterCard) in `.p-poster-grid` or `.p-rail` · `.p-plan` + `.p-plan-btn(--hot)` (NextPlanCard) · `.p-your-row` (rows in «Ваше») · `.p-card .p-card__cover .p-card__body` (EventCard: overline date → `.p-card-name` → `.p-descriptor` → `.p-meta`) · `.p-btn--primary|--secondary|--danger` · `.p-chip` (+`--selected`, `.p-dot`, `.p-chip-row`) · `.p-badge--success|accent|danger|brand|on-photo` · `.p-count` · `.p-save` · `.p-search` + `.p-icon-btn` · `.p-rows > .p-row` with `__icon __title __sub __value __chevron` (GroupedRows + LinkRow) · `.p-round-action` · `.p-field` (LabelledField) · `.p-segmented` · `.p-cat-tile .p-cat-card` · `.p-tabbar-wrap > .p-tabbar.p-glass > .p-tab[aria-selected]` + `.p-create` · `.p-sheet .p-sheet__grabber .p-scrim`.

**Icons:** use the app's own line set, never emoji or a stock set: `<i class="p-icon i-NAME"></i>` (22px, set width/height to resize). The icon is painted in `currentColor`. Available names: the 11 categories, `home map calendar person search filters bookmark bookmarkFilled plus pin myLocation recenter sparkle lock checkCircle alert clock queue`. Raw SVGs are in `icons/`. The app also uses a few SF Symbols that aren't in this set (bell for «Стежити», chat bubbles, arrow.right, chevrons). Draw those as simple 1.75-stroke inline SVGs in the same style.

## Where the truth lives
- `guidelines/screens/*.png` shows every screen of the current iOS build, 05.10.2026 (`-light`, some `-dark`). **Match them.** When the text and a screenshot disagree, the screenshot wins. Files marked `-sep25` (sign-in, sign-up, guest profile) are from the 25.09 build. Their layout is current, but their titles are still sans. Set titles in serif.
- `guidelines/design-system.md` is the full design spec (Ukrainian): screen composition, states, sheets, forms and map rules. Some rows in its component table are older than the code (e.g. it says CAPS card titles; the app uses sentence case).
- `guidelines/source/*.swift` is the real code: DesignSystem.swift (tokens), Components.swift (components), and the screen compositions HomeView, EventDetailView, MyEventsView, ProfileView, FollowsView and ArtistView. Read it for exact sizes, order and copy.
- `components/screens/Home/Home.html` is a verified rebuild of the home screen and its poster grid from these classes, next to the app screenshots. Start from it.

## App structure
Tabs: **Головна**, **Мапа**, **Мої події**, **Профіль**, plus the round "+" button, which opens the 3-step event editor.
- **Головна**, top to bottom: serif "Що поруч" + city picker ("Київ ⌄") + search and profile IconPills → «Організувати подію» slab (guests get a quiet "Увійти й зберігати події" line under it) → **Ваше** (signed in only: NextPlanCard for the next plan, then rows for other plans, "waiting" and «Підписки») → **Від людей** (176-wide poster rail, when there are enough rooms) → **У місті** ("Усі N" link, a pager of 360-tall hero cards at 86% width, filter chips, a 2-column poster grid, "Показати ще") → **Далі** (grouped LinkRows). Search replaces the header with a pinned search bar + "Скасувати" and two chip rows (city/everywhere + dates, categories). Results come as grouped rows: Події · N, then places, then **Артисти**.
- **Мапа**: MapLibre with category pins and black count clusters, a search pill + filters button, a chip row (city ⌄, Від людей, date), a card carousel, and a list sheet ("Знайдено подій: N" with category tiles). Tapping a place shows "Тут подій: N" with a follow bell.
- **Event detail**: EventArt or a photo full-bleed under the status bar, with back/save buttons. Badges, an accent date overline (`--accent-on-photo`) and a serif title sit on the scrim, then a canvas sheet with 28 top radius slides over. Inside: 4 round actions, «Хто виступає» artist chips, a 2×2 facts card, «Ідуть», «Місце» map + place card with «Стежити», «Безпека» (shelters, curfew), «Ще в …». A floating glass bottom bar holds the date, the price or state, and the main action, plus «Шукаю компанію» on listings.
- **Мої події**: serif title + summary line, chips Іду / Організовую / Збережені, overline section labels (ДАЛІ, МИНУЛІ), grouped event rows.
- **Профіль**: avatar, serif name, two stat cards, bio, Edit, «Підписки» row → the follows screen, interests chips, recommendations, toggles, settings.
- Also: the artist page, onboarding (welcome + 3 steps with segmented progress), sign-in/sign-up with a segmented switch, the chat, and sheets (city, filters, companions, person card).

## Example
```html
<article class="p-poster cat-games">
  <div class="p-poster__art"><div class="p-art"><i class="p-icon i-games"></i></div>
    <span class="p-badge p-badge--on-photo top">Для вас</span><span class="p-badge p-badge--on-photo bottom">3/8</span></div>
  <div class="p-poster__caption">
    <div class="p-overline">Завтра · 18:00</div>
    <h3 class="p-card-name">Настолки в «Барі на Подолі»</h3>
    <div class="p-descriptor"><span class="p-dot p-cat-ink"></span><span>Бар на Подолі</span></div>
  </div>
</article>
<button class="p-btn p-btn--primary">Приєднатися</button>
```
