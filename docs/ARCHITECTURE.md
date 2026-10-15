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
| Screen logic worth testing (multi-field input, validation, save flow) | `@MainActor @Observable` model in **FinanceFeatures**, bound with `@Bindable` | `TransactionFormModel`, `BudgetFormModel`, `RecurringFormModel`, `SavingsGoalFormModel`, `WalletFormModel`, `CategoryFormModel`, `ContributionFormModel`, `RecordOccurrenceFormModel`, `AppRouter`, `DashboardModel`, `ReportsModel`, `TransactionListModel` |
| Refresh after any save | `AppContainer.dataVersion` (from `ModelContext.didSave`) + `.task(id:)` | dashboard, reports, due items, reminders |
| Shared dependencies | `@Environment(AppContainer.self)` (services, calendar policy) and `.modelContainer` | composition root in `PersonalFinanceApp` |
| Persistent lists | `@Query` (read-only) | list screens and pickers |
| Multi-step rules, invariants, failure handling | services + pure domain rules | `FinancePersistence`, `FinanceDomain` |

Which forms have a model, and why (reviewed after M5):

| Form | State | Reason |
|---|---|---|
| Transaction, Budget, Recurring, Savings goal, Wallet, Category, Contribution, Record occurrence | `@Observable` model + tests | dependent fields (kind ↔ category, currency ↔ wallets, period ↔ end date / rollover, type ↔ sign), locks, live previews |
| Transaction list + filter sheet | `TransactionListModel` | one state shared by two views through `@Bindable` |
| Dashboard, Reports | thin `@Observable` models | own the period and a `LoadState`; the calculations live in `ReportService` / `ReportRules` |

A screen gets an `@Observable` model once it has more than trivial logic. The model:

- owns the input fields;
- exposes derived state (`canSave`, `parsedAmount`, …);
- performs actions through a service and keeps the last `failure` for the view to present.

The view creates the model lazily in `onAppear`, because services come from the environment, and binds to it with `@Bindable`. Models live in a package target so `swift test` can cover them without a simulator.

### Keeping a screen up to date

Three mechanisms, each for one kind of data. A new screen picks by what it shows:

| The screen shows | Use | Why it stays current | Examples |
|---|---|---|---|
| A list of records as stored | `@Query` | SwiftData updates it on every change | wallet, budget, goal, category lists; pickers |
| Figures computed from many records (totals, charts, due items) | a model or `@State` reloaded by `.task(id: app.dataVersion)` | `dataVersion` changes after every save of the main context | Home, Reports, Due, recurring list badge |
| One record's own figures (a budget's progress, a goal's saved amount, a wallet's balance) | a service read in `body` through `ReadResult` / `Result(catching:)` | the record and the records it reads are observed, so the body re-runs when they change; checked on 15 Oct 2026 (Home budget row updated at once after a transaction became irregular) | budget, goal and wallet rows and detail screens |

A read that fails is shown (I14). Code that runs without a screen (notifications) keeps its current state instead: a failed read never reschedules with nothing.

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
| V4 (M8) | `isIrregular` on `LedgerTransaction` and `LedgerCategory` (default false); `RecurringTransaction.categoryID` optional, new `destinationWalletID`, `receivedAmountMinorUnits` | lightweight V3 → V4 |

V1–V3 share the frozen V1 ledger classes, and a shipped version must never change. V4 therefore has its own copies of the four ledger models and of `RecurringTransaction`; `Budget` (V2) and the savings models (V3) are reused. The app-wide names (`Wallet`, `LedgerTransaction`, …) are typealiases in `CurrentSchema.swift`, the only file to edit when a new version is added.

`MigrationTests` (V1 → current, V3 → V4) write the old store through **Core Data** with the old version's model (`NSManagedObjectModel.makeManagedObjectModel(for: SchemaVn.models)`) and plain `NSManagedObject`s, then open it with `ModelContainerFactory`. Writing it with SwiftData's old classes is not possible in the same process: SwiftData resolves the old entity to the V4 class and crashes (`setValue:forUndefinedKey: isIrregular`). A new schema version adds a test the same way: write the previous version's entities by name, open with the current schema, check the data and the new fields.

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

- **What counts:** only regular expenses (irregular ones are left out, see Milestone 8). An expense counts if its category, or that category's parent, is in the budget, and its wallet is allowed. Each transaction counts at most once per budget.
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
| Income / expenses | income and **regular** expense entries whose day key is in the period. Transfers are never counted |
| Irregular expenses | irregular expense entries in the period, shown on their own line and in their own report card (M8) |
| Net cash flow | income − regular expenses − irregular expenses, so it always equals the change in balances |
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

**Definition.** A `RecurringTransaction` holds the name, kind (income, expense or — since M8 — transfer), amount, wallet id, category id (income/expense) or destination wallet id and, between currencies, the received amount (transfer), frequency, interval, start date, optional end date, reminder settings, paused flag and `handledOccurrenceKeys`.

**Occurrences** (`RecurrenceRules`):
- Occurrences are anchored to the start date, so they never drift (31 Jan → 28 Feb → 31 Mar; 29 Feb → 28 Feb in non-leap years).
- Each occurrence has a stable key: `<definition id>-<yyyymmdd>`.

**Due and recording:**
- **Due** = occurrences on or before today, not handled, for definitions that aren't paused (at most 100 at once).
- They are computed when the app is active. There is no background processing.
- **Recording** inserts the transaction, tagged with `recurringOccurrenceKey`, and adds the key to `handledOccurrenceKeys` in **one save**.
- Duplicates are blocked twice: by the handled list, and by a ledger lookup on the key. **Skipping** only marks the key handled.
- Editing a definition affects future occurrences only. When the schedule changes, occurrences of the new schedule before today are marked handled, so they are not offered as due. Deleting a definition keeps the transactions already recorded.
- Deleting a recorded transaction makes its occurrence due again. Skipped occurrences (and ones passed over by a schedule change) are listed on the definition and can be made due again.
- A definition whose wallet (either side of a transfer) or category is archived is **on hold**: nothing becomes due and no reminders are scheduled, and the screen says why. Archiving stays possible (it is the way out when a wallet can't be deleted); restoring the wallet or category, or editing the item, lifts the hold.
- *Coming up* skips occurrences already recorded or skipped early.
- Wallets (on either side of a transfer) and categories used by a definition can't be deleted.

## Notifications (Milestone 5)

`ReminderCoordinator` (app target) uses UserNotifications. Permission is requested only when the user turns on a reminder or taps *Allow* in Settings → Notifications.

- **Recurring reminders:** the next 3 occurrences of each definition with reminders on, at most 60 in total (iOS keeps 64 pending). They are rescheduled after every save and whenever the app becomes active.
- **Budget alerts:** when a budget reaches one of its thresholds in the current period, one notification is sent. Each budget chooses any of 50 / 80 / 90 / 100 % (default 80 and 100; none = off for that budget; `BudgetAlertRules.allowedThresholds`). Thresholds already alerted are remembered per budget period in `UserDefaults` (no financial data stored there). Alerts can be switched off.
- **Read errors:** if the planned reminders or the budgets can't be read, nothing is rescheduled or forgotten; the reminders already scheduled stay until the next refresh. A tapped budget alert whose budget can't be read opens Budgets with an alert saying so (`AppRouter.routeFailure`).
- **Limits, also shown in the app:** iOS controls delivery, and nothing is recorded automatically. The app has no background execution, so due items wait until the app is opened.

## Backup, restore and export (Milestone 6)

| Piece | Where | Notes |
|---|---|---|
| `BackupDocument` | FinanceDomain | plain `Codable` records for every entity; `format` + `formatVersion` (2) independent of the database schema; nested entries and contributions. Format 2 (M8) adds optional `isIrregular` on categories and transactions and recurring transfers (`categoryID` optional, `destinationWalletID`, `receivedAmountMinorUnits`); format 1 files still restore, missing fields meaning "not irregular", and older apps refuse format 2 files |
| `BackupCodec` | FinanceDomain | pretty, sorted-key JSON; ISO 8601 dates with milliseconds; other JSON → `notABackup`, newer format → `newerFormat` |
| `BackupValidator` | FinanceDomain | unique ids, known enum values and currencies, every reference resolvable, no category cycles, alert thresholds from the allowed set, recurring transfers with a different existing destination wallet (income/expenses with a category), balanced transactions (income +, expense −, transfer −/+ between two wallets, equal amounts in one currency), savings never below zero |
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

## Spending accuracy (Milestone 8)

**Irregular expenses** (option C of the roadmap): a one-off cost such as a trip or a laptop.
- `LedgerCategory.isIrregular` is the default for new expenses in that category; `LedgerTransaction.isIrregular` is what counts, and the expense form can override it (`CashFlowDraft.isIrregular`: nil = category default). Only expenses can be irregular. Changing a category's default never rewrites existing expenses.
- Irregular expenses change balances and net worth like any expense.
- They are **not spending**: `CashFlowSummary.expenses`, category/wallet breakdowns, daily spending and budgets (`BudgetRules`) use regular expenses only. `irregularExpenses` and `irregularExpensesByCategory` report them apart, and `net` includes both.
- CSV export has an "Irregular" column (`Yes` / empty); import reads it (missing column → category default). Backups keep the flags.

**Sub-categories.** Two levels: a parent is a top-level category of the same type, never the category itself, and a category that has sub-categories can't move under another (`CategoryService`). The type of a category with transactions, sub-categories, budgets or recurring items can't change. Lists show children indented under their parent (`inHierarchy()`). Reports roll children up into the parent (`expensesByCategory`) and a parent row expands to itself plus each child (`expensesWithin`). Budgets already included children (M3).

**Per-budget alerts.** `BudgetDraft.alertThresholds`, a subset of 50/80/90/100 (`BudgetAlertRules.normalizedThresholds`); empty turns alerts off for that budget. The global switch in Notifications still applies.

**Recurring transfers.** `RecurringDraft` with kind `.transfer`, `destination` and (between currencies) `receivedAmount`, validated with the same `LedgerRules.validateTransfer` as a manual transfer. Recording calls `TransactionService.insertTransfer` with the occurrence key, so duplicates are blocked as for income and expenses. Recording a different amount between currencies requires the received amount too (it can't be derived without converting).

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

## Localization (Milestone 7)

- **Languages:** English (development language), Vietnamese and Japanese. Dates, numbers and money follow `Locale`; number and currency formats keep the device's region.
- **Choosing the language:** *More › Language* (Same as device / English / Tiếng Việt / 日本語) or iOS *Settings › Apps › Finance › Language*. Both write the same value, the app's own `AppleLanguages` preference, so they always agree (`LanguageSettings`).
- **Switching without relaunching:** iOS fixes a process's language at launch, so the app switches in three places at once: (1) the root view gets `environment(\.locale)` in the chosen language, which SwiftUI uses for `Text`, `Button`, `Label` … keys; (2) `AppLocalization.languageCode` is set, and every `String(localized:bundle: .l10n)` looks the key up in that language's `.lproj` inside the bundle (`.main` in the app, `.module` in each FinanceKit target); (3) the root view is rebuilt (`.id(language)`), so every computed text is evaluated again. Tabs and navigation paths live in `AppRouter`, so the user stays on the same screen. Formats that use `Locale.current` directly (`date.formatted()`) switch fully on the next launch.
- **Rule for new code:** computed texts use `String(localized: "…", bundle: .l10n)`, never plain `String(localized:)` or `bundle: .module`; SwiftUI literals need nothing.
- **Where texts live:** one String Catalog per bundle: `PersonalFinance/Resources/Localizable.xcstrings` for the app, and `Sources/<Target>/Resources/Localizable.xcstrings` for each FinanceKit target. The English text is the key, and English values are written out so every bundle has an `en.lproj` to switch to. SwiftUI literals (`Text("…")`, `Button("…")`, `LocalizedStringKey` parameters) are extracted by Xcode at build time.
- **Format specifiers:** keys use `%@` for text and `%lld` for integers, as Xcode generates them. Translations reorder arguments with positional specifiers (`%1$@`, `%2$lld`). English plural variations are used where a count changes the wording.
- **Check:** `scripts/check_localizations.py` fails when a key has no Vietnamese or Japanese value or a translation changes the specifiers. Xcode adds new keys to the catalogs when you build; run the script (or open the catalog in Xcode) to find what still needs translating.
- **Built-in categories are data, not UI text.** They are seeded in the app's language (`SeedLanguage`: en, vi, ja). At launch and whenever the language changes in the app, `DefaultCategorySeeder.localizeUntouched` renames a built-in category to the current language only while its name still equals one of its seed names; anything the user renamed or created is never touched. Only the name changes; transactions, budgets and recurring items refer to categories by identity.
- **CSV stays English** (headers, `Income`/`Expense`/`Transfer`) so a file exported in one language imports in another. Import also accepts Vietnamese and Japanese type names (`Chi tiêu`, `Chuyển tiền`, `支出`, `振替`, …) and matches built-in categories by any of their seed names (`Food & Drinks` ↔ `Ăn uống` ↔ `食費`), unless the user renamed them.
- **Backup** stores names as they are; after restoring a backup made in another language, untouched built-ins are renamed at the next launch or language change.
- **Reminders** are written in the language active when they are scheduled; they are rescheduled when the app becomes active or data changes.

## Dates

`CalendarPolicy` is the only place where instants become days or periods. It uses the Gregorian calendar, the user's time zone, and weeks starting on Monday. Periods are half-open `[start, end)`. Each transaction stores `dayKey` (yyyymmdd, local at entry time), so grouping by day doesn't shift when the user travels.

## Invariants

Rules the data and the app must always satisfy. Every change checks the ones it
touches (DEFINITION_OF_DONE.md). "Not enforced" rows are known gaps, to be fixed;
they are listed so nobody assumes otherwise.

| # | Invariant | Enforced by | Status |
|---|---|---|---|
| I1 | A wallet's balance is its opening balance plus the sum of its entries; no balance is stored | `Wallet.currentBalance()`, `ReportRules.balances`; tests compare both | enforced |
| I2 | Income has one positive entry, an expense one negative entry, a transfer one out and one in between two wallets | `TransactionService`, `LedgerRules`, `BackupValidator` | enforced |
| I3 | A transaction's category has the type its kind requires; a category's type can't change while transactions, sub-categories, budgets or recurring items use it | `LedgerRules`, `CategoryService` | enforced |
| I4 | Sub-categories: two levels, same type as the parent, never the category itself | `CategoryService.validateParent`, `BackupValidator` (cycles) | enforced |
| I5 | A recurring occurrence becomes at most one transaction | handled keys + ledger lookup of `recurringOccurrenceKey` | enforced |
| I6 | Deleting a transaction recorded from a recurring item makes that occurrence due again; a skip can be undone | `TransactionService.delete` removes the handled key in the same save; `RecurringService.skippedOccurrences` / `reopen`; tests | enforced |
| I7 | A wallet's currency does not change while anything refers to it (recurring items copy it; budgets and goals require it) | `WalletService.update` (history, recurring on either side, budgets, goals); tests | enforced |
| I8 | Archiving a wallet or category never leaves something due that can't be recorded | `RecurringService`: an item whose wallet (either side) or category is archived is on hold (`hold(of:)`): no due occurrences, upcoming or reminders; restoring lifts it; tests | enforced |
| I9 | Every stored id (budget categories/wallets, recurring wallet/category/destination, goal wallet) resolves | delete checks in `WalletService`, `CategoryService`; `BackupValidator` | enforced |
| I10 | Irregular expenses change balances but are not spending: not in budgets or spending reports; cash-flow net includes them | `ReportRules`, `BudgetRules` | enforced |
| I11 | Days, weeks and periods come from `CalendarPolicy` | root `.environment(\.calendar, calendarPolicy.calendar)`; views read `@Environment(\.calendar)`; `check_conventions.py` C1 | enforced. One marked exception: notification triggers use the device calendar (`ReminderCoordinator`) |
| I12 | Every text, date, number and amount follows the language chosen in the app | `String(localized:bundle: .l10n)`, root `locale`; `AppLocalization.locale` (`Locale.app` in the app) passed to every `.formatted(...)`; `MoneyFormatter()` defaults to it; C2; `AppLocalizationTests` | enforced |
| I13 | Settings the docs promise are in the project (languages in `knownRegions`, Files sharing keys) | `check_conventions.py` C10 | enforced |
| I14 | A failed read is shown on screen, never replaced by nothing, zero or an empty list; code without a screen keeps its current state | `ReadResult` / `Result(catching:)` + `ReadFailureLabel`; form models expose `loadFailure` and block saving; `AppRouter.routeFailure`; reminders keep their schedule on a read error; `check_conventions.py` C8 (error) flags any `try?` on a service, container or context read in the app and FinanceFeatures | enforced |
| I15 | Archived wallets are never offered where a wallet is picked (transaction, recurring item, goal, budget, transaction filter) | `WalletChoices.selectable` in every form model/view; services reject linking an archived wallet (recurring: `LedgerRules`; goal: `SavingsService`; budget: can keep, can't add); an edited item on an archived wallet asks for another; `ArchivedWalletChoiceTests` | enforced |

### Device-only state

Kept in `UserDefaults`, not in the database and not in backups: `AppleLanguages`
(app language), `lastBackupAt`, `budgetAlertsEnabled`, `sentBudgetAlerts`
(alerts already sent; only the current period of each budget is kept, see `BudgetAlertRules.keysToKeep`). Anything else belongs in the database.

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
  Resources/Assets.xcassets      app icon (light/dark/tinted), accent colour
  Resources/Localizable.xcstrings   app texts (en, vi, ja)
Packages/FinanceKit/
  Sources/FinanceDomain/
  Sources/<Target>/Resources/Localizable.xcstrings
  Sources/FinancePersistence/Schema/
  Tests/FinanceDomainTests/
  Tests/FinancePersistenceTests/
docs/
  app-icon/                      icon concepts (SVG sources) and the comparison sheet
scripts/
  check_localizations.py         translation check
```
