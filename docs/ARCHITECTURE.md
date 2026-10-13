# Architecture

Personal Finance Tracker: native SwiftUI, offline, no backend.

## Platform

| | |
|---|---|
| Minimum iOS | **18.0**: `#Index`, `PreviewModifier`, `Tab` API, mature SwiftData predicates |
| Xcode | 16 or later (project uses synchronized folders, object version 77) |
| Swift | 6 language mode, strict concurrency |
| Dependencies | none (Apple frameworks only) |

## Modules

```
PersonalFinance (app target, SwiftUI)
   │  views, design system, composition root, previews
   ▼
FinanceFeatures (local package, Observation)
   │  @Observable screen models: input state, derived state, actions
   ▼
FinancePersistence (local package, SwiftData)
   │  versioned schema, container factory, seeding, fixtures
   │  (Milestone 2+) application services: LedgerService, BudgetService, BackupService
   ▼
FinanceDomain (local package, Foundation only)
      Money, CurrencyDefinition, ExchangeRate, RoundingPolicy,
      CalendarPolicy, DateRange, DayKey, financial enums and errors
```

The compiler enforces the boundaries: `FinanceDomain` cannot import SwiftData or SwiftUI, so financial rules stay pure and testable with `swift test` in seconds.

## State management

| Need | Tool | Where |
|---|---|---|
| View-local state (sheets, dialogs, focus, the current error) | `@State`, `@FocusState` | every screen |
| Screen logic worth testing (multi-field input, validation, save flow) | `@MainActor @Observable` model in **FinanceFeatures**, bound with `@Bindable` | `TransactionFormModel`, `BudgetFormModel`, `RecurringFormModel`, `SavingsGoalFormModel`, `AppRouter`, `DashboardModel`, `ReportsModel`, `TransactionListModel` |
| Refresh after any save | `AppContainer.dataVersion` (from `ModelContext.didSave`) + `.task(id:)` | dashboard, reports, due items, reminders |
| Shared dependencies | `@Environment(AppContainer.self)` (services, calendar policy) and `.modelContainer` | composition root in `PersonalFinanceApp` |
| Persistent lists | `@Query` (read-only) | list screens and pickers |
| Multi-step rules, invariants, failure handling | services + pure domain rules | `FinancePersistence`, `FinanceDomain` |

Which forms have a model, and why (reviewed after M5):

| Form | State | Reason |
|---|---|---|
| Transaction, Budget, Recurring, Savings goal | `@Observable` model + tests | dependent fields (kind ↔ category, currency ↔ wallets, period ↔ end date / rollover), locks, live previews |
| Transaction list + filter sheet | `TransactionListModel` | one state shared by two views through `@Bindable` |
| Dashboard, Reports | thin `@Observable` models | own the period and a `LoadState`; the calculations live in `ReportService` / `ReportRules` |
| Wallet, Category, Contribution | `@State` in the view | few fields; the real rules (liability sign, type/currency locks, withdrawal limit) are already in domain rules and services with tests |

A screen gets an `@Observable` model once it has more than trivial logic. The model:

- owns the input fields;
- exposes derived state (`canSave`, `parsedAmount`, …);
- performs actions through a service and keeps the last `failure` for the view to present.

The view creates the model lazily in `onAppear`, because services come from the environment, and binds to it with `@Bindable`. Models live in a package target so `swift test` can cover them without a simulator.

## Navigation

Sized for the app: 5 tabs, ~14 pushed screens, at most 3–4 levels deep, and notifications as the only entry from outside.

| Level | Used for | Where |
|---|---|---|
| Direct (`NavigationLink { }`, `.sheet`, `dismiss`) | create/edit forms and pickers inside a form sheet | every form; category picker in transaction/recurring forms |
| `NavigationStack(path:)` + `NavigationLink(value:)` | every push on a tab stack | detail screens (records as values) and `AppScreen` (due, reports, savings goals, recurring, categories, notifications, data & privacy) |
| Tabs | `AppRouter.selectedTab` + one `NavigationPath` per tab | `RootView`, the five tab roots |
| From outside | notification `userInfo` → `NotificationRoute` → `AppRouter.receive` → resolved by `RootView` | recurring reminder → Home › Due; budget alert → Budgets › that budget (falls back to the Budgets tab if deleted) |

- `financeDestinations()` registers every destination once; each tab root applies it.
- `NotificationResponder` is installed in `PersonalFinanceApp.init`, so a tap that launches the app is kept as `pendingRoute` until the UI is ready. Notifications are also shown while the app is open.
- Sheets stay owned by the screen that presents them; the router does not manage them.
- Not done on purpose (add when needed): URL scheme / App Intents (widgets, Shortcuts), restoring paths with `@SceneStorage` (needs `Codable` routes by id), a flow coordinator (first candidate: restore-from-backup in M6).

## Persistence boundary (decision)

SwiftData is the persistence layer. There is **no** generic repository layer that pretends the store could be swapped transparently: returning `@Model` objects through a protocol would still leak SwiftData.

- **Reads:** views may use `@Query` for straightforward lists.
- **Writes:** every mutation goes through an application service (from Milestone 2). Services validate invariants, write on a context with autosave disabled, and finish with exactly one `saveOrRollback()`.
- **Calculations** (balances, budget utilisation, reports) are pure functions over value snapshots, so they can be tested without a store.

If SwiftData's guarantees ever prove insufficient, only the services and the schema need replacing.

## Consistency rule

1. `mainContext.autosaveEnabled = false` (set in `AppContainer`).
2. One user operation = one `save()`. A transfer's header and both entries are inserted and then saved together.
3. When validation or the save fails, call `rollback()`. The store is left exactly as it was.
4. Restore and CSV export currently run on the main context: restore must be one save on the context the UI observes. If performance tests with large ledgers show stalls, CSV and reports move to a `@ModelActor` first (passing `PersistentIdentifier`s, never model objects, across actors).

## Ledger model (schema V1, unchanged in V2)

```
Wallet 1 ──< LedgerEntry >── 1 LedgerTransaction >── 0..1 LedgerCategory
              signed amount        kind, date, dayKey,       (parent/child)
              wallet currency      note, merchant, rate
```

| Kind | Entries | Category |
|---|---|---|
| income | 1 positive | income category required |
| expense | 1 negative | expense category required |
| transfer | 1 negative (source) + 1 positive (destination) | none |

- **Wallet balance** = `openingBalanceMinorUnits + Σ entries.amountMinorUnits`. This is the single source of truth. A cached projection is added only if measured performance requires it, and it must be rebuildable from the ledger.
- **Opening balance** is not income.
- **Transfers** never count as income, expense or budget spending (`TransactionKind.countsAsCashFlow`).
- **Cross-currency transfers** store both legs in their own currency, plus the explicit rate in `exchangeRateText`.
- **Delete rules:** Wallet → entries `.deny`, Category → transactions `.deny`, Transaction → entries `.cascade`. Wallets and categories with history are archived (`archivedAt`), not deleted. Services also enforce these rules; the delete rules are a second line of defence.
- **No `@Attribute(.unique)` / `#Unique`.** On conflict they silently upsert. Uniqueness (ids, recurring occurrence keys) is checked by services.
- **Enums are stored as raw strings**, because enum properties are unreliable inside `#Predicate`. Raw values are frozen and covered by tests.
- Relationships are set after `insert`, never in `init`.

## Schema versions

| Version | Change | Stage |
|---|---|---|
| V1 (M1) | Wallet, LedgerCategory, LedgerTransaction, LedgerEntry | — |
| V2 (M3) | adds `Budget`; the four V1 models are reused unchanged | lightweight V1 → V2 |
| V3 (M5) | adds `SavingsGoal`, `SavingsContribution`, `RecurringTransaction`; earlier models reused | lightweight V2 → V3 |

`MigrationTests` writes a store with the V1 schema only, then reopens it through `ModelContainerFactory`. The test checks that balances and categories survive and that budgets work afterwards.

## Application services (Milestones 2–3)

| Service | Operations | Key rules |
|---|---|---|
| `WalletService` | create, update, archive, restore, delete | name required; opening balance entered ≥ 0 (stored negative for liabilities); currency locked once the wallet has entries; delete only when empty |
| `TransactionService` | create, update, delete (income/expense); createTransfer, updateTransfer | `LedgerRules.validateCashFlow` / `validateTransfer`; the header and all its entries are saved together; transactions touching an archived wallet are read-only; a transfer stays a transfer |
| `CategoryService` | create, update, archive, restore, delete | type locked once used; delete only when unused by transactions and budgets; renaming never rewrites transactions |
| `BudgetService` | create, update, archive, restore, delete; progress, spending | validation below; budgets never change transactions or balances |

Wallets named in a budget's wallet restriction cannot be deleted. Archive them instead.

Every method validates **before** touching a model, then calls `saveOrRollback()` exactly once. A rejected operation leaves the store and the in-memory models unchanged (covered by tests).

Forms never bind to `@Model` objects. They keep local `@State` copies and pass a draft (`WalletDraft`, `CashFlowDraft`, `CategoryDraft`) to a service on Save, so cancelling a form can't leave unsaved edits in the main context.

**Balances in the UI** are computed by `Wallet.currentBalance()` (opening balance + live entries, via `LedgerRules.balance`) when a row renders. They follow SwiftData's observation of the `entries` relationship, so they update after every save. If this is ever slow, add a cached projection that can be rebuilt from the ledger. An unreadable balance is shown as "Balance unavailable", never as zero.

**Archived wallets** are read-only: no new transactions, and existing ones cannot be edited or deleted until the wallet is restored. This keeps archived history stable.

## Transfers (Milestone 3)

- **Structure:** one `LedgerTransaction` (kind `transfer`, no category) with two entries: −sent on the source wallet and +received on the destination. Both entries are saved in one `save()`.
- **Same currency:** sent must equal received, so the combined total of all wallets is unchanged.
- **Different currencies:** the user enters both amounts. The implied rate (received ÷ sent, in major units) is stored in `exchangeRateText` for display only. Nothing is converted automatically.
- **Not cash flow:** transfers are never income, expense or budget spending.
- **Credit card payment** = transfer from bank to card (bank −, card +).
- **Editing:** the amounts, both wallets, date and note can change. A transfer can't become income or an expense, and the reverse isn't allowed either.

## Budgets (Milestone 3)

Stored as `Budget`: planned amount and currency, period, start date, optional end date, category ids, wallet ids (empty means all wallets), rollover flag and alert thresholds (for M5). Ids are used instead of relationships so budgets never block or cascade ledger changes.

Rules (`BudgetRules`, all covered by tests):

- **What counts:** only expenses. An expense counts if its category, or that category's parent, is in the budget, and its wallet is allowed. Each transaction counts at most once per budget.
- **Overlap:** budgets are independent. Two budgets sharing a category both count that spending, and the UI says budgets don't add up.
- **Currency:** only expenses in the budget's currency count. Others in the current period are reported (`excludedOtherCurrencyCount`), not converted. Wallet restrictions may only name wallets in the budget's currency.
- **Periods:** weekly (Monday weeks), monthly and yearly follow `CalendarPolicy`.
  - The first window starts on the start day. An optional end day (inclusive) shortens the last window.
  - Custom = a single window from start through end.
  - Membership uses the transaction's `dayKey`, so expenses on the last day of a month count in that month.
- **Rollover:** when on, the sum of (planned − spent) over all completed periods is added to the current one. Overspending carries over too, as a negative amount.
- **Derived numbers:** remaining = available − spent. Utilization = spent ÷ available (exact `Decimal`).
- **Daily allowance:** remaining ÷ days left including today, rounded down; zero when over budget.
- **Status:** not started / on track / near limit (≥ 80 %) / over budget / ended.
- **Editing a budget** only changes how existing transactions are measured; it never rewrites them.

## Dashboard and reports (Milestone 4)

**Data flow**
- `ReportService.snapshot()` reads wallets, entries and categories into plain values (`LedgerSnapshot`) in one pass. A record it can't read is an error; it is never skipped.
- All numbers on a screen are computed from that one snapshot by `ReportRules` (pure, tested), so they always agree with each other.
- `DashboardModel` and `ReportsModel` (`@Observable`) hold the selected period and currency and the computed result (`LoadState`: idle, loaded or failed). A failure is shown to the user; it is never replaced by zeros.
- **Refresh:** `AppContainer.dataVersion` increases on every `ModelContext.didSave`. The dashboard and reports reload in `.task(id: dataVersion)` and when the period changes.

**Definitions**

| Figure | Rule |
|---|---|
| Assets | sum of balances of asset wallets (current balance, not limited to the period) |
| Liabilities | amount owed on liability wallets, as a positive number |
| Net worth | assets − liabilities = sum of every wallet balance |
| Income / expenses | income and expense entries whose day key is in the period. Transfers are never counted |
| Net cash flow | income − expenses |
| Archived wallets | included in balances, net worth and historical cash flow. The dashboard notes how many archived wallets still hold money |
| Opening balances | count from the beginning of time (they have no date). They are not income |
| Net worth trend | net worth from all entries before the end of each month |
| Currencies | every figure is per currency. Charts and breakdowns use one currency (the default first). Nothing is converted |

**Charts** use Swift Charts.
- Two-series charts (income vs expenses) use a blue/orange pair that was run through a colour-vision validator. The app's green/red failed that check (ΔE 4.2 for deuteranopia).
- Every chart has a legend or title naming its series, tap-to-inspect selection, and per-mark accessibility values.
- The monthly chart also has a table of exact monthly net figures.
- Breakdowns are labelled rows with thin bars rather than pie charts.

**Transaction search and filters** (`TransactionQuery`, `TransactionListModel`):
- **Search:** all words must match. Matching ignores case and Vietnamese accents ("pho" finds "Phở", "da" finds "Đá"). It looks in the note, merchant, category and wallet names.
- **Filters:** period, type, wallets (either side of a transfer), categories, and an inclusive amount range in each transaction's own currency.
- **Sort:** newest, oldest, largest or smallest amount.
- **Grouping:** by day or month when sorted by date. Amount sorts show one ungrouped list.

## Savings goals (Milestone 5)

**Model.** A goal is an *earmark*: it records how much of your money is set aside for a purpose.
- Contributions (+) and withdrawals (−) are `SavingsContribution` rows owned by the goal (cascade delete).
- They never create transactions, never move money and never change balances or net worth, so nothing is counted twice. Moving money into a savings account is a separate transfer.
- `linkedWalletID` is informational. The detail screen warns when the goals linked to a wallet add up to more than that wallet's balance; it never blocks or moves money.

**Rules** (`SavingsRules`):
- saved = Σ entries
- remaining = max(target − saved, 0)
- progress capped at 100 %
- A withdrawal can't take saved below zero, and neither can deleting a contribution.
- Months left = calendar months from the current month through the target month, inclusive.
- Suggested monthly = remaining ÷ months left, rounded up to the next minor unit.
- Overdue = the target date has passed and the goal isn't reached.

The currency is locked once a goal has contributions. A wallet linked to a goal can't be deleted.

## Recurring transactions (Milestone 5)

**Definition.** A `RecurringTransaction` holds the name, kind (income/expense), amount, wallet and category ids, frequency, interval, start date, optional end date, reminder settings, paused flag and `handledOccurrenceKeys`.

**Occurrences** (`RecurrenceRules`):
- Occurrences are anchored to the start date, so they never drift (31 Jan → 28 Feb → 31 Mar; 29 Feb → 28 Feb in non-leap years).
- Each occurrence has a stable key: `<definition id>-<yyyymmdd>`.

**Due and recording:**
- **Due** = occurrences on or before today, not handled, for definitions that aren't paused (at most 100 at once).
- They are computed when the app is active. There is no background processing.
- **Recording** inserts the transaction, tagged with `recurringOccurrenceKey`, and adds the key to `handledOccurrenceKeys` in **one save**.
- Duplicates are blocked twice: by the handled list, and by a ledger lookup on the key. **Skipping** only marks the key handled.
- Editing a definition affects future occurrences only. Deleting it keeps the transactions already recorded.
- Wallets and categories used by a definition can't be deleted.

## Notifications (Milestone 5)

`ReminderCoordinator` (app target) uses UserNotifications. Permission is requested only when the user turns on a reminder or taps *Allow* in Settings → Notifications.

- **Recurring reminders:** the next 3 occurrences of each definition with reminders on, at most 60 in total (iOS keeps 64 pending). They are rescheduled after every save and whenever the app becomes active.
- **Budget alerts:** when a budget reaches its thresholds (80 % and 100 % by default) in the current period, one notification is sent. Thresholds already alerted are remembered per budget period in `UserDefaults` (no financial data stored there). Alerts can be switched off.
- **Limits, also shown in the app:** iOS controls delivery, and nothing is recorded automatically. The app has no background execution, so due items wait until the app is opened.

## Backup, restore and export (Milestone 6)

| Piece | Where | Notes |
|---|---|---|
| `BackupDocument` | FinanceDomain | plain `Codable` records for every entity; `format` + `formatVersion` (1) independent of the database schema; nested entries and contributions |
| `BackupCodec` | FinanceDomain | pretty, sorted-key JSON; ISO 8601 dates with milliseconds; other JSON → `notABackup`, newer format → `newerFormat` |
| `BackupValidator` | FinanceDomain | unique ids, known enum values and currencies, every reference resolvable, no category cycles, balanced transactions (income +, expense −, transfer −/+ between two wallets, equal amounts in one currency), savings never below zero |
| `BackupService` | FinancePersistence | `makeBackup()`, `restore(_:)`, `hasUserData()` |
| `ExportService` | FinancePersistence | transactions CSV, signed per wallet, transfers with receiving wallet/amount, optional date range |
| `CSVTable` | FinanceDomain | RFC 4180, CRLF, UTF-8 BOM for Excel, `'` prefix on user text starting with `= + - @` |
| `RestoreFlowModel` | FinanceFeatures | idle → review(summary) → finished / failed; safety copy before restore |
| `BackupView` | app | Save Backup (`fileExporter`), Restore (`fileImporter`), Export CSV; last-backup date in More |

**Restore is all-or-nothing.** The whole file is decoded and validated before the store is touched. Then a safety copy of the current data is written to `Documents/Safety Copies` (visible in Files; skipped when there is no user data). Only then are all records deleted and the backup's records inserted on the main context, committed by **one** `save()`. Any failure rolls the context back and nothing changes. After a restore the router resets to Home because pushed screens may show replaced records.

Backups contain ids, so restoring the same file twice gives the same data (no duplicates), and default categories from the backup replace the device's.

**CSV import** (`TransactionCSVParser` in FinanceDomain, `ImportService` in FinancePersistence, `ImportFlowModel` in FinanceFeatures) reads the app's own export, also after a spreadsheet edited it:

- Columns are found by header name; required: Date, Type, Wallet, Amount, Currency. Amount signs are ignored (the type decides the direction). Numbers are accepted only when unambiguous: `65000`, `65.000` (VND), `1,250.75`; `65,5` is rejected rather than guessed. Dates: `yyyy-MM-dd[ HH:mm]` or `dd/MM/yyyy[ HH:mm]`.
- Import only **adds**. Rows whose ID already exists (or repeats in the file) are skipped, so the same file can be imported again safely. Rows without a known ID that match an existing transaction (same day, kind, wallet, amount) are "possible duplicates", skipped unless the user opts in.
- Wallets and categories are matched by name ignoring case, accents and extra spaces (active before archived); missing ones are created (wallets as "Other" with no opening balance, categories incl. "Parent / Child").
- Every row is checked with the same `LedgerRules` as manual entry during the preview; bad rows are listed with their line number and left out. Confirming writes a safety copy, then inserts everything through `TransactionService.insertCashFlow/insertTransfer` and saves once.

## Amount input

`AmountInputParser` accepts only unambiguous input:

- **No minor unit (VND):** digits, optionally grouped in threes with `.` or `,`.
- **With minor unit (USD):** digits plus one decimal mark (`.` or the locale's mark), with no grouping.

Anything else is rejected with a message, never guessed.

## Money

- `Int64` minor units plus an ISO 4217 code. Never `Double`.
- Precision comes from `CurrencyDefinition.minorUnitDigits`: VND 0, USD 2, KWD 3.
- Mixing currencies throws `currencyMismatch`. Conversion requires an explicit `ExchangeRate`.
- Overflow throws instead of trapping.
- Every rounding names a `RoundingPolicy`. Ratios are exact `Decimal` values, rounded only for display.

## Account classes

`creditCard` is a **liability**; every other wallet type is an asset. All balances use the same sign convention: negative means owed. A card with 2,000,000 VND of debt has a balance of −2,000,000. A card purchase is an expense when it happens. Paying the card is a transfer (bank −, card +), not an expense.

## Dates

`CalendarPolicy` is the only place where instants become days or periods. It uses the Gregorian calendar, the user's time zone, and weeks starting on Monday. Periods are half-open `[start, end)`. Each transaction stores `dayKey` (yyyymmdd, local at entry time), so grouping by day doesn't shift when the user travels.

## Open product decisions

These must be settled before the milestone that needs them:

1. ~~Totals across currencies~~: decided in M4. Totals are per currency and never converted; the app currently uses VND only.
   The UI follows `CurrencyCatalog.enabled` (`[.vnd]`): currency pickers, currency codes next to wallet names and
   multi-currency footnotes are hidden while only one currency is enabled. A record already stored in another currency
   still shows its code and keeps it selectable. Domain and services keep full multi-currency support, so enabling
   another currency is a one-line change.
2. ~~Savings goals~~: decided in M5. Goals are earmarks, and the linked wallet is informational only.
3. ~~Overlapping budgets~~: decided in M3, budgets are independent.
4. ~~Parent categories in budgets~~: decided in M3, children are included.
5. ~~Store replacement on restore~~: decided in M6. Instead of swapping store files (which needs the container closed and reopened while views hold models), the backup is fully validated in memory, a safety copy is written, and the replacement happens in one save on the main context. SQLite makes that save atomic, so a failure leaves the old data untouched.

## Folder layout

```
PersonalFinance.xcodeproj
PersonalFinance/                 app target (synchronized folder: new files are picked up automatically)
  App/                           entry point, composition root, launch/error handling, tabs
  DesignSystem/                  colours, metrics, type, reusable components
  Features/<Feature>/            views (and view models when a screen needs one)
  Support/                       preview traits
  Resources/Assets.xcassets
Packages/FinanceKit/
  Sources/FinanceDomain/
  Sources/FinancePersistence/Schema/
  Tests/FinanceDomainTests/
  Tests/FinancePersistenceTests/
docs/
```
