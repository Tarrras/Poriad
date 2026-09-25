# Поряд (Poriad) — design conventions

Поряд is a native iOS + Android app for finding events near you (a map, a feed and your own plans). All UI copy is **Ukrainian**. The real product is SwiftUI/Compose, so this project doesn't include compiled components: it has **tokens, CSS recipes that copy the native components 1:1, the app's own icon set, and screenshots of every screen**. Build phone screens at **402×874** (iPhone 16 Pro) unless asked otherwise.

## Setup
```html
<link rel="stylesheet" href="styles.css">   <!-- tokens + type classes + component recipes -->
<body>  <!-- canvas background and system font are set here -->
```
Dark theme follows `prefers-color-scheme`. To force a theme, put `data-theme="dark"` or `data-theme="light"` on any ancestor. **Every design must work in both themes.** Use only `var(--*)` tokens, never raw hex, and the dark theme comes for free.

## Look (match the screenshots, not a generic iOS kit)
- The screen is one calm sheet: `--canvas` (#F5F5F7) with white `--surface` cards. In light mode cards have **no border and no shadow**; in dark mode they get a 1px `--hairline` edge (`--card-border`). Only floating things get a shadow: the tab bar, the map carousel, the round "+" button.
- The primary action is a **flat near-black pill** (`--brand`). It turns white in dark mode. There is no chromatic brand colour: colour belongs to **categories** and **states** (`--success`, `--accent` = "few spots left", `--danger`).
- Radii: cards 24 (`--radius-lg`), fields 14, category tiles 18, sheets and tab bar 28–32, chips and buttons are pills. Photos sit **flush** with the card edge.
- One typeface. The app uses system SF Pro; designs use the bundled **Inter** (`--font`), its closest open match. Never swap in another typeface. Hierarchy comes from size and weight only. UPPERCASE with +1 tracking is used **only** for data: date overline, badges, field labels. Large titles use negative tracking.
- Spacing is a 4-pt grid. Page gutter 16, card padding 16, 12 between cards, 24 between sections.
- Questions and pickers open as **bottom sheets** (`.p-sheet`), never as centred dialogs. The sheet's primary action is pinned to the bottom.

## Vocabulary
**Type classes:** `.t-display` 34 · `.t-title1` 28 · `.t-section`/`.t-title2` 22 · `.t-title3` · `.t-card-name` 17 · `.t-lead` · `.t-body` 16 · `.t-subhead` 15 · `.t-label` · `.t-button` · `.t-caption` 13 · `.t-descriptor` · `.t-overline` 11.

**Tokens:** `--brand --on-brand --brand-container --accent(-container) --success(-container) --danger(-container) --ink --ink-secondary --ink-tertiary --surface --surface-raised --surface-muted --canvas --canvas-tint --hairline`, plus `--space-xs…section`, `--radius-xs…xl|pill|sheet`, `--shadow-raised|overlay`, `--scrim`.

**Categories** (11): `music sport art food games outdoors social comedy kids tours conference`. Each has `--cat-<key>` (hue, used for glyphs, dots and text), `--cat-<key>-wash` and `--cat-<key>-partner`. Put `.cat-<key>` on an element, then use `.p-cat-fill` for a tile or a cover without a photo, and `.p-cat-ink` for a dot or text. Category labels: Музика, Спорт, Мистецтво, Їжа, Ігри, Природа, Зустрічі, Стендап, Дітям, Екскурсії, Конференції.

**Component recipes** (in `tokens/components.css`; each one mirrors the SwiftUI component with the same name):
`.p-screen .p-section .p-page-header .p-section-title` · `.p-card .p-card__cover .p-card__body` (EventCard: overline date → `.p-card-name` → `.p-descriptor` → `.p-meta`) · `.p-btn--primary|--secondary|--danger` · `.p-chip` (+`--selected`, `.p-dot`, `.p-chip-row`) · `.p-badge--success|accent|danger|brand|on-photo` · `.p-save` · `.p-search` + `.p-icon-btn` · `.p-quick(--filled)` (QuickActionCard) · `.p-rows > .p-row` with `__icon __title __sub __value __chevron` (GroupedRows + LinkRow) · `.p-round-action` · `.p-field` (LabelledField) · `.p-segmented` · `.p-cat-tile .p-cat-card` · `.p-tabbar-wrap > .p-tabbar.p-glass > .p-tab[aria-selected]` + `.p-create` · `.p-sheet .p-sheet__grabber .p-scrim`.

**Icons:** use the app's own line set, never emoji or a stock set: `<i class="p-icon i-NAME"></i>` (22px, set width/height to resize). The icon is painted in `currentColor`. Available names: the 11 categories, `home map calendar person search filters bookmark bookmarkFilled plus pin myLocation recenter sparkle lock checkCircle alert clock queue`. Raw SVGs are in `icons/`.

## Where the truth lives
- `guidelines/screens/*.png` shows every screen of the current iOS build (`-light`, some `-dark`). **Match them.** When the text and a screenshot disagree, the screenshot wins.
- `guidelines/design-system.md` is the full design spec (Ukrainian): screen composition, states, sheets, forms and map rules. Some rows in its component table are older than the code (e.g. it says CAPS card titles; the app uses sentence case).
- `guidelines/source/*.swift` is the real component code (DesignSystem.swift for tokens, Components.swift for components). Read it for exact sizes and states.
- `components/screens/Home/Home.html` is a verified rebuild of the home screen from these classes. Start from it.

## App structure
Tabs: **Головна** (home digest), **Мапа** (MapLibre map with category pins, black count clusters, a card carousel and a list sheet), **Мої події** (grouped list of your plans), **Профіль**, plus the round "+" button, which opens the 3-step event editor. Other screens: event detail (400pt cover fading into the canvas, a row of 4 round actions, a 2×2 facts card, a pinned bottom bar with the main action), 3-step onboarding (segmented progress, one bottom action), sign-in/sign-up with a segmented switch.

## Example
```html
<article class="p-card cat-games">
  <div class="p-card__cover p-cat-fill" style="height:120px;display:grid;place-items:center">
    <i class="p-icon i-games" style="width:40px;height:40px"></i></div>
  <div class="p-card__body">
    <div class="p-overline">Завтра · 18:00</div>
    <h3 class="p-card-name">Настолки в «Барі на Подолі»</h3>
    <div class="p-descriptor"><span class="p-dot p-cat-ink"></span><b class="p-cat-ink">Ігри</b> · Поділ, Київ</div>
  </div>
</article>
<button class="p-btn p-btn--primary">Приєднатися</button>
```
