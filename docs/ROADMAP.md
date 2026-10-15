# Roadmap after Milestone 6

Investigation of the open items, with a phased plan. Sizes: **S** ≈ a few files, no schema change; **M** ≈ one feature across layers or a schema change; **L** ≈ new target/capability or many files.

## Findings per item

| # | Item | What exists today | Gap | Size | Risk |
|---|---|---|---|---|---|
| 1 | Vietnamese UI (**done in M7**) | ~520 UI literals already go through `Text("…")` / `String(localized:)` (localizable keys); dates and money use `Locale`; `developmentRegion = en` | No String Catalog, no `vi`; ~64 user-facing strings in the package (errors, CSV problems) are plain `String`; default category names are seeded in English | M | Low (no data change) |
| 2 | Multi-currency UI | Domain/services fully multi-currency; UI driven by one constant `CurrencyCatalog.enabled = [.vnd]` (used in 6 places) | No setting to enable currencies; no base currency / exchange rates (totals stay per currency by design) | S (enable) / L (conversion) | Low / High |
| 3 | Recurring transfers (**done in M8**) | `RecurringTransaction` stores `walletID`, **non-optional** `categoryID`, `kindRaw`; recording calls `insertCashFlow` | Needs destination wallet, optional category, optional received amount; validator/backup/CSV-free | M | Medium (schema V4) |
| 4 | Sub-categories in UI (**done in M8**) | Model has `parent`/`children`; budgets include children; import/backup handle parents | Category form has no parent picker; list is flat; reports group by leaf only (no roll-up) | M | Low |
| 5 | Alert thresholds per budget (**done in M8**) | `Budget.alertThresholdPercents` stored (default `[80, 100]`) and already used by `ReminderCoordinator` | No UI or validation; no "off" option | S | Low |
| 6a | Face ID lock | — | App lock setting, `LocalAuthentication`, privacy cover in the app switcher, `NSFaceIDUsageDescription` | S–M | Low |
| 6b | Shortcuts / Siri | `AppRouter` + notification routes (Level 4) | App Intents: "Add expense/income", "Show balance", "Open due items"; URL scheme for routes | M | Medium (intents run outside the UI) |
| 6c | Widgets | — | Widget extension target, App Group, data shared with the widget | L | Medium–High (new target, signing) |
| 7 | App icon (**done in M7**: concept A, wallet) | Asset catalog entry only | Artwork (1024 px, light/dark/tinted for iOS 18) | S | Low |
| 8 | Irregular expenses (travel, …) not counted as spending (**done in M8**, option C) | Every expense counts in reports, dashboard and budgets | A way to mark expenses "irregular", excluded from spending figures but still reducing balances | M | Medium (schema V4, reporting rules) — **product decision needed** |

## Key decisions

**Irregular expenses (#8).** Balances and net worth must always include them (the money really left). Only *spending* views exclude them. Options:

| Option | How | Pros | Cons |
|---|---|---|---|
| A. Flag per transaction | `LedgerTransaction.isIrregular` toggle in the form | Precise; one-off big purchases | Must remember to tick it |
| B. Flag per category | `LedgerCategory.isIrregular` ("Travel" → all its expenses) | Zero effort per entry | A normal expense in that category is excluded too |
| **C. A + B (recommended)** | Category sets the default, transaction can override | Easy and precise | Slightly more UI |
| D. Events / trips | A "Đà Lạt trip" event with its own budget, transactions tagged to it | Rich (trip totals) | Larger feature; can come later on top of C |

With C: dashboard and reports show **regular spending** and, separately, **irregular spending**; budgets ignore irregular expenses (option per budget later); cash flow shows both lines so income − all expenses still matches the balance change.

**Widget data (#6c).** Don't open the SwiftData store from the widget. The app writes a small JSON snapshot (balances, today's/this month's spending, top budgets, next due items) into the App Group container after each save; the widget only reads it. No store move, no concurrent SQLite access. Buttons in the widget open the app via a URL (`financeapp://add-expense`) handled by `AppRouter`.

**Multi-currency (#2).** Make `enabled` a user setting ("Currencies you use", VND always on). No conversion: keep totals per currency. Conversion with rates is a separate, later decision.

**Schema V4 (#3, #4 roll-up needs none, #8).** One lightweight migration for all model changes:
- `LedgerTransaction.isIrregular: Bool = false`
- `LedgerCategory.isIrregular: Bool = false`
- `RecurringTransaction.destinationWalletID: UUID?`, `receivedAmountMinorUnits: Int64?`, `categoryID` → optional (verify lightweight migration of optionality with a V3 → V4 migration test; fallback: keep `categoryID` and add `categoryIDValue: UUID?` copied in a custom stage)
- Backup format v2 (new optional fields; v1 files still restore; v2 files are refused by older app versions).

## Phases

### M7 — Vietnamese and identity (no data changes) — done

Added afterwards: Japanese, and a language switch inside the app (More › Language), applied without relaunching.
1. String Catalog `Localizable.xcstrings` in the app, `vi` added, `en` kept; build setting to extract strings.
2. Package strings: `defaultLocalization: "en"`, `resources: [.process("Resources")]` per target, `String(localized:bundle: .module)` for errors and import problems.
3. Default categories: seeded in the device language (vi/en) by `seedKey`; existing English seeds renamed only if the user never edited them (name still equals the English seed name).
4. CSV import already accepts Vietnamese type names; export headers stay English (stable format) — documented.
5. App icon: 3 original concepts (`docs/app-icon/concepts.png`: A wallet, B coin with sprout, C rising bars); A is installed in light/dark/tinted. Swap by re-rendering another concept's SVGs into `AppIcon.appiconset`.
6. Tests: every catalog key has a `vi` value (script), seeded names per locale, rename-only-if-untouched.

### M8 — Data model V4: spending accuracy — done

Also fixed from the audit: editing a schedule no longer offers past occurrences of the new schedule as due, and *Coming up* skips occurrences handled early.
1. Irregular expenses (option C): flags, form toggle, category setting, `ReportRules`/`BudgetRules` filters, dashboard + reports split, CSV column "Irregular", import/backup support.
2. Sub-categories: parent picker (same type, two levels max, can't move a category that has children under another), indented list, reports roll up children into parents with drill-down.
3. Per-budget alerts: thresholds editor (off / 50 / 80 / 90 / 100 %), validation, keep sent-alert keys.
4. Recurring transfers: kind "Transfer" in the form, destination wallet, received amount for cross-currency, `RecurringService.record` → `insertTransfer`.
5. V3 → V4 migration test, backup v2 round trip, v1 restore test.

### M9 — Security and system integration
1. Face ID / passcode lock: setting, lock on launch and after N minutes in background, privacy cover when inactive, fallback to device passcode, never blocks data export of the device owner.
2. App Intents: Add Expense / Add Income (amount, wallet, category; confirm dialog), Show Balance, Open Due Items; App Shortcuts phrases in Vietnamese and English.
3. URL scheme routes (`financeapp://…`) → `AppRouter`.
4. Widgets (requires Xcode steps by the developer: add Widget Extension target, App Group capability on both targets): JSON snapshot writer in the app, small/medium widgets (balance, month spending vs budget, next due), lock-screen accessory widget, "Add expense" button via URL.

### M10 — Multi-currency UI (when needed)
1. Settings › Currencies: enable/disable (VND fixed; can't disable a currency still used).
2. Replace the constant with an injected `CurrencyPreferences`; UI rules unchanged (`offersChoice`, `showsCode`).
3. Exchange-rate conversion only after a separate product decision.

## Backlog (not scheduled)

| # | Item | Notes |
|---|---|---|
| B1 | **Archiving a wallet that still holds money** (requested 15 Oct 2026): when the user taps *Archive Wallet* and the balance is not zero, show a popup asking them to move the money to another wallet first (a transfer), then archive. | Today archiving is allowed with any balance; the money stays in net worth and Home notes "Includes N archived wallet(s) that still hold money". Decide: block until the balance is zero, or warn and allow. A liability (credit card) with a debt needs the same check. Offer a shortcut that opens a transfer prefilled with the wallet and its balance. |
| B2 | **Confirm before archiving a budget, category or goal** (requested 15 Oct 2026), the same way wallets already do (`WalletDetailView`: "Archive <name>?" with what archiving means, then *Archive Wallet* / Cancel). | Today *Archive* on these three acts at once. Each dialog says what archiving does there: a budget stops being tracked and alerting; a category is hidden from pickers but stays on past transactions; a goal leaves the active list and keeps its contributions. Archiving is reversible (Restore), so a dialog is for consistency, not safety. |
| B3 | **Currencies that aren't enabled arriving through CSV import or a backup restore** (found in the 15 Oct 2026 audit). The UI offers VND only (`CurrencyCatalog.enabled`), but import and restore accept USD, JPY… and create wallets in them. With several currencies, the transaction filter and the amount sort compare raw numbers across currencies (100 USD < 100,000 ₫, `TransactionQuery`), and the filter's amount field is read as VND. | Options: (a) import and restore reject currencies that aren't enabled, with a clear message (recommended until M10), or (b) filter and sort compare amounts only within one currency. Revisit with M10 (multi-currency UI). |

## Prerequisites outside the code

- **Widgets and App Groups** need a signing team that supports App Groups (a paid Apple Developer account; free personal teams can't use them) and two targets added in Xcode by the developer.
- **Info.plist keys** (`NSFaceIDUsageDescription`, file sharing keys from M6) are build settings in `project.pbxproj`; add them in Xcode, or close Xcode before the files are updated, because an open Xcode overwrites the project file.
- **Translations**: machine-drafted Vietnamese strings should be reviewed by a native speaker for tone (finance wording such as "ngân sách", "số dư", "khoản định kỳ").
