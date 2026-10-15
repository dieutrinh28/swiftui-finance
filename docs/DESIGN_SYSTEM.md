# Design System

Bright, calm, minimalist native iOS: soft pastel blue (primary), green (positive) and pink (accent) on white or near-white surfaces. Pastels are **fills**; meaning is carried by readable text tokens, signs, icons and labels.

All tokens live in `PersonalFinance/DesignSystem/`. Views use token names only, never raw hex values.

## Colours (`AppColor.swift`)

| Token | Light | Dark | Use |
|---|---|---|---|
| `background` | #F8FAFD | #0F141B | Screen background (`.screenBackground()`) |
| `surface` | #FFFFFF | #19202A | Cards, list rows, sheets |
| `surfaceMuted` | #F1F5FA | #222B37 | Tracks, inset areas |
| `border` | #E8EDF4 | #2A3442 | Hairlines, card borders, dividers |
| `textPrimary` | #243247 | #E7ECF3 | Titles, values |
| `textSecondary` | **#5F6C82** | #9AA6B6 | Labels, metadata (spec #778397 was 3.7:1 → darkened) |
| `brand` | #A9C9F5 | #8DB8F2 | Primary button fill, selected highlights (fill only) |
| `onBrand` | #243247 | #10213A | Text/icons on `brand` |
| `brandGreen` / `brandPink` | #B9E4CE / #F4C6D7 | #5FCB92 / #E79BB8 | Decorative accents (fill only) |
| `accent` | #2C66B8 | #8DB8F2 | Links, tint, toolbar items, transfers (also `AccentColor` asset) |
| `softBlue` / `softGreen` / `softPink` / `softAmber` / `softCoral` | #EAF2FD / #EAF6EF / #FCEEF3 / #FDF3DC / #FCEEEA | #1C2C42 / #173126 / #382330 / #362C16 / #3A231F | Tinted surfaces: summary card, tiles, banners |
| `positive` (= `income`) | #1D7A4B | #5FCB92 | Money in, on-track |
| `negative` (= `expense`) | #C2412F | #F28A75 | Money out, debt, over budget |
| `warning` (= `liability`) | #94600A | #E9B24E | Attention: due items, near limit, paused |
| `destructive` | #C62F3A | #FF7272 | Destructive actions |
| `neutralAction` | #5F6C82 | #5F6C82 | Fill of a neutral swipe action (Skip); white label 5.3:1 |

`AppColor.income/expense/transfer/liability` are kept as role aliases so screens not yet redesigned pick up the new palette automatically.

### Contrast (WCAG 2.x, computed)

| Pair | Light | Dark |
|---|---|---|
| textPrimary on background / surface | 12.4 / 13.0 | 15.6 / 13.8 |
| textSecondary on background / surface / softBlue | 5.1 / 5.3 / 4.7 | 7.5 / 6.6 / 5.7 |
| accent on background / softBlue | 5.0 / 5.0 | 9.0 / 6.9 |
| positive on surface / softGreen | 5.3 / 4.8 | 8.2 / 7.0 |
| negative on surface / softCoral | 5.1 / 4.5 | 6.8 / 6.0 |
| warning on surface / softAmber | 5.3 / 4.8 | 8.5 / 7.2 |
| onBrand on brand (primary button) | 7.6 | 7.9 |
| *Pastel blue / green as text on white* | *1.7 / 1.4: never use as text* | — |

### Category colours (`PaletteColor`)

Same 13 persisted identifiers (`red` … `gray`), re-rendered as softened mid-tones with light and dark variants. Shown only as an icon on a 14 % (light) / 22 % (dark) tint inside `IconBadge`, never as text.

### Charts (`ChartPalette`)

| Series | Light | Dark |
|---|---|---|
| Income / single series | #3B7DD8 | #4C8CE2 |
| Expenses | #E0694F | #E06E57 |

Mid-tone steps of the brand blue and the pink/coral family (pastels are < 3:1 as marks). Validated with the dataviz palette checker; all checks pass: lightness band, chroma, CVD separation (ΔE 21.2 protan light / 20.6 dark), normal-vision floor (29.5 / 27.4), ≥ 3:1 vs surface. Charts always show a legend; values are also available as text or a table.

## Typography (`Metrics.swift`)

All styles are text styles, so they follow Dynamic Type.

| Token | Style | Use |
|---|---|---|
| navigation title | `.largeTitle` (system) | Screen titles |
| `.amountHero` | largeTitle, rounded, bold, monospaced digits | The one dominant figure (net worth) |
| `.amountLarge` | title3, rounded, semibold, monospaced | Summary tiles |
| `.amountRow` | body, rounded, semibold, monospaced | Amounts in rows |
| `.amountDetail` | subheadline, rounded, medium, monospaced | Small amounts beside labels |
| `.sectionTitle` | title3 semibold | Section headers |
| `.cardTitle` | headline | Titles inside cards/banners |
| `.rowTitle` | body medium | Row titles |
| `.label` | subheadline | Labels over values |
| `.meta` | footnote | Metadata, timestamps, secondary row text |
| `.supporting` | subheadline | Explanatory sentences in a card: empty messages, descriptions, errors |
| `.fine` | caption | Notes under a card or chart, table labels; `.fine.weight(.semibold)` for status badges and currency codes |
| `.heroTitle` | largeTitle bold | Title of a full-screen message (welcome card, store error) |
| `.lead` | body | The sentence under a hero title |
| `.checkmark` | body semibold | Checkmark of the selected row in a single-choice list |
| `.selectionCircle` | title3 | Circle / filled circle of a multiple-choice row |
| `.code` | footnote monospaced | Technical details to copy |

Weights of a token are fine in screens (`.label.weight(.semibold)` for a list group header, `.label.weight(.medium)` for chips and inline links, `.meta.weight(.semibold)`); raw text styles (`.caption`, `.subheadline`, …) are not (convention C3).

Bold is reserved for the hero amount, screen titles and `.heroTitle`.

## Spacing, radius, elevation, sizes

- `Spacing`: 2 · 4 · 8 · 12 · 16 · 24 · 32; `screen` margin 20; `section` gap 28.
- `Radius`: `card` 20, `control` 14 (buttons, banners, tiles), `chip` 10. Always `.continuous`.
- `Elevation`: light mode shadow `#243247` at 6 %, radius 14, y 4; dark mode no shadow. Cards also have a 1 pt `border`.
- `ComponentSize`: button height 50, icon badge 30 / 38 / 46 (small / regular / large, scaled), meter 8 (scaled).

## Components (`DesignSystem/Components/`)

| Component | Purpose |
|---|---|
| `.cardStyle(fill:padding:elevated:)` | The only card surface. One card per group of rows, not per row. Tinted fill (`softBlue`) for the single highlighted surface of a screen. |
| `.screenBackground()` | Background of scrolling screens and lists |
| `.appGroupedStyle()` | Native grouped `List`/`Form` on `background`: hidden system background, `border` separators, sentence-case headers |
| `.surfaceRows()` / `.highlightedRows()` | Row background for a section: `surface`, or `softBlue` for the one highlighted section (detail header, budget summary) |
| `PrimaryActionBar` | Form Save button pinned with `.safeAreaInset(edge: .bottom)`; stays above the keyboard; replaces the toolbar Save |
| `.keyboardDismissal()` | Every form with text or amount fields: Done above the keyboard (ends editing of whichever field is focused) and drag-to-dismiss |
| `CategoryFieldLabel` | A form's "Category" row: the chosen category as "Parent / Child" with its icon, or "Required" |
| `PrimaryButtonStyle` (`.appPrimary`) | Main action: pastel blue fill, dark label, full width |
| `SecondaryButtonStyle` (`.appSecondary`) | Supporting action: soft blue fill, accent label |
| `SectionHeader` | Section title outside the card, optional trailing control; header trait for VoiceOver |
| `IconBadge` | SF Symbol on a soft rounded square (small for settings rows / regular for list rows / large for detail headers) |
| `MoneyText` | Every amount: sign, semantic colour **and** VoiceOver label ("Expense 65.000 ₫") |
| `AmountField` | Amount entry: hero-size digits, currency code, live formatted value or an error with an icon |
| `MeterBar` | Progress meter; always next to the same value as text |
| `NoticeBanner` | Calm attention/info/success message on a soft tint |
| `EmptyStateView` | Icon in a soft circle, title, one sentence, actions |
| `ReadFailureLabel`, `ReadResult` | A read from the store that failed: warning icon and text in `negative`, as a row or a `LabeledContent` value. `ReadResult { try … } content: { … }` shows the value or the label. Never `try?` in a view (C8) |
| `SummaryTile` (Home) | Label + icon + amount on a soft tint |
| `TransactionRow`, `WalletRow`, `BudgetRow` | Shared rows; amounts right-aligned and never truncated (`layoutPriority`) |

## Rules

1. Meaning never by colour alone: amounts have a sign and an accessibility label; status has an icon and text; charts have legends.
2. Pastels never as text or thin lines on white.
3. One highlighted surface per screen; everything else is white cards with titles outside.
4. Stable identity in `ForEach` (model ids or derived keys, never array indices for changing data).
5. Raw hex values only in `AppColor.swift`, `PaletteColor` and `ChartPalette`.
6. Forms and detail screens stay native grouped lists (`.appGroupedStyle()`), not custom cards: they keep system pickers, swipe actions, Dynamic Type and VoiceOver behaviour. Dashboards and reports use cards.
7. A failed read is shown, never hidden: no missing row, made-up zero or empty list in its place (`ReadFailureLabel`; a whole-screen failure is a `NoticeBanner` with tone `.attention`).

## Screen patterns

| Pattern | Where | How |
|---|---|---|
| Form | Every add/edit sheet: Transaction, Wallet, Budget, Category, Recurring, Savings goal, Add Money, Record a Different Amount | Sections on `surfaceRows`; `PrimaryActionBar` with a specific title ("Save Expense", "Save Budget"; "Save Changes" when editing); Cancel on the left of the navigation bar; `.keyboardDismissal()`. Sheets about a single amount focus it on open and use `.presentationDetents([.medium, .large])`; full forms open full height and focus nothing |
| Detail | Transaction, Wallet, Budget, Category, Recurring, Savings goal | First section `highlightedRows`: large `IconBadge`, title, hero amount, one line of context, state (archived, paused) as a `NoticeBanner`; then facts on `surfaceRows`. Every action in one "…" menu (`.topBarTrailing`): "Edit X" first, then state changes (Archive/Restore, Pause/Resume, Mark as Done), "Delete X" last and destructive. A screen-specific shortcut (Wallet's "+" add transaction) may sit next to it |
| Collection | Transactions, Wallets, Budgets, Categories, Recurring, Savings goals, Due | `EmptyStateView` with an `.appPrimary` "Add X" action and a "+" toolbar button with the same label; grouped sections with labelled headers and explanatory footers; rows use `.rowTitle` / `.meta` and right-aligned `.amountRow` amounts |
| Report | Reports | `ScrollView`, `SectionHeader` outside, content in `.cardStyle()`, `NoticeBanner` for failures |
| Settings | More, Notifications, Data & Privacy, Backup, Language | Rows with small tinted `IconBadge` (separator aligned to the text); status trailing with icon when it needs attention |

Titles: tab roots, collections and Reports use the large title; detail, settings and form screens use `.inline`.

Wording: the verb is "Add" for anything new (Add Wallet, Add Goal, Add Category); "Edit X", "Delete X", "Save X" name the object. Sub-categories show as "Parent / Child" where the category stands alone (detail rows, form fields) and as the child name with the parent leading the detail line in transaction rows.

## App icon

Concept A ("wallet"): a blue wallet with a pastel green and a pastel pink card tucked in, on a soft blue gradient. Sources and the other concepts are in `docs/app-icon/` (`icons.py` writes the SVGs).

| Appearance | File | Notes |
|---|---|---|
| Light | `AppIcon.png` | Opaque (no alpha), gradient #EEF4FD → #B7D2F7, wallet `accent` #2C66B8 |
| Dark | `AppIcon-Dark.png` | Transparent background (iOS draws the dark backdrop), lighter wallet #4C8CE2 |
| Tinted | `AppIcon-Tinted.png` | Grayscale on black; iOS applies the user's tint |

## Text and languages

- Every visible text is localizable (English, Vietnamese, Japanese); see ARCHITECTURE.md › Localization.
- Vietnamese runs about 20–30 % longer than English; Japanese is shorter but taller (line height), so never fix a text frame's height. Layouts must wrap rather than truncate labels: buttons and banners allow two lines, amounts keep `layoutPriority(1)` and never truncate.
- Write short, plain sentences; the same term everywhere:
  - vi: Ví, Giao dịch, Ngân sách, Danh mục, Thu nhập, Chi tiêu, Chuyển tiền, Tài sản ròng, Sao lưu, Lưu trữ.
  - ja: 口座, 取引, 予算, カテゴリ, 収入, 支出, 振替, 純資産, バックアップ, アーカイブ.
- Language names are always shown in their own language (English, Tiếng Việt, 日本語).
- Dates, numbers and percentages are formatted with the app's language: `value.formatted(style.locale(.app))`, e.g. `date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(.app))`. A plain `.formatted()` uses the launch language and stays in it after a switch (convention C2). Amounts go through `MoneyText` / `MoneyFormatter()`, which already use it.
- Days and months in views come from `@Environment(\.calendar)` (the app's `CalendarPolicy`), never `Calendar.current` (convention C1).

## Redesign status

| Round | Scope | Status |
|---|---|---|
| 1 | Design system, Home/Dashboard, Transactions list, shared rows (transaction, wallet, budget), charts palette, accent colour | done |
| 2 | Add/Edit Transaction, transaction detail, category picker, filters; Wallets (list, detail, form); Budgets (list, detail, form); Reports; More, Notifications, Data & Privacy, Backup | done |
| 3 | Savings goals (list, detail, forms), Recurring (list, detail, form), Due occurrences, Categories, Transaction detail menu; one Save bar, keyboard handling and naming across every form | done |
| 4 | Remaining raw fonts and colours replaced by tokens (C3 at 0), Categories empty state, store error screen (app buttons, tokens), failed reads (`ReadFailureLabel`) | done |
