# Personal Finance Tracker (iOS)

A native SwiftUI personal finance app that runs fully offline. Data stays on the device: there is no backend, no account and no analytics.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for design decisions and financial invariants.

## Requirements

- Xcode 16 or later
- iOS 18.0+ (iPhone)
- macOS 15+ to run the package tests from the command line

## Getting started

1. Open `PersonalFinance.xcodeproj`. Xcode resolves the local package `Packages/FinanceKit` automatically.
2. Select the `PersonalFinance` scheme and an iPhone simulator, then press Run.
3. To run on a device, choose your team under *Signing & Capabilities*, and change the bundle identifier if needed.

UI tests and manual testing can start the app with an empty in-memory store by adding the launch argument `-UseInMemoryStore` (*Scheme → Run → Arguments*).

## Tests

```bash
cd Packages/FinanceKit
swift test
```

You can also run them in Xcode: select the `FinanceKit-Package` scheme and press ⌘U.

| Suite | Covers |
|---|---|
| Money | same-currency arithmetic, currency mismatch, overflow, precision (VND/USD/KWD), rounding policies, ratios, explicit conversion, Codable |
| Currency catalog and formatting | strict lookup, VND formatting (`4.000.000 ₫`) |
| Persisted raw values | enum raw values are frozen; only credit cards are liabilities |
| Calendar policy | half-open months, year boundary, February, Monday weeks, inclusive custom ranges, day keys in the local time zone |
| Persistence | schema, idempotent seeding, user edits not overwritten, data survives reopening the store, rollback, fixture ledger consistency |
| Ledger rules | amount > 0, currency = wallet, category required and of the right type, archived wallet/category, signed amounts, balance formula |
| Amount input | VND grouping (`65.000`), USD decimals (`12.50` / `12,50`), rejecting ambiguous input such as `1,250.00` or `65,5` |
| Wallets and balances | opening balance is not income, income/expense balances, independent wallets, 250 wallets, USD cents, credit-card debt, currency lock, archive vs delete |
| Transactions | invalid input writes nothing, edit amount/kind/wallet, rejected edit leaves data unchanged, delete restores balance, archived wallets are read-only, day key, ledger survives relaunch |
| Categories | create/rename, type locked once used, renaming doesn't touch transactions, delete only when unused |
| Transaction form model | defaults, default wallet, `canSave` rules, amount parsing per wallet currency, kind switch clears wrong category, save create/edit, failures reported with nothing written |
| Transfer rules / transfers | same-currency amounts equal, cross-currency explicit amounts and implied rate, same wallet/archived/zero rejected, totals preserved, credit-card payment, edit both sides, rejected edit unchanged, delete restores both |
| Budget rules / budgets | spec example (62.5 %), month boundaries by day key, near limit / over budget, other currencies excluded, rollover (unused and overspent, several periods), weekly/yearly/custom/end-dated windows, eligibility (kind, child categories, wallets, no double count), progress follows edits and deletes, overlapping budgets, 100 budgets, validation |
| Schema migration | a V1 store opens with the current schema (V1 → V2 → V3) and keeps balances; budgets work afterwards |
| Transfer & budget form models | kinds per mode, received amount for cross-currency, edit prefill, budget defaults (current month), `canSave`, currency change clears wallets, save/edit/failure |
| Report rules | assets/liabilities/net worth per currency, transfers don't change net worth, positions at a past day, archived wallets with money, cash flow excludes transfers, empty ledger, category and wallet breakdowns with shares, "other" folding, month ranges, monthly trend, net-worth trend, daily running total |
| Transaction query | accent-insensitive search (`pho` → Phở, `da chanh` → Đá chanh), combined filters, either side of a transfer, inclusive bounds, sort orders, 10,000 items |
| Report snapshot | snapshot balances equal wallet balances, net worth follows edits/deletes/transfers, archived wallets included, searchable summaries |
| Dashboard, reports and list models | totals from the ledger, period change, reload after new data, failures surfaced, currency switch, day/month grouping, amount sort ungrouped, period filter and clear, no results |
| Recurrence rules | month-end anchoring (31st, leap day), every N weeks with end date, windows, next occurrence, stable keys, validation, reminder times in the future |
| Savings rules | progress, months left, suggested monthly (rounded up), reached/overdue, withdrawals limited to saved |
| Budget alert rules | thresholds alerted once per period |
| Savings goals | earmarks never change balances or net worth, withdrawal/delete limits, linked wallet currency and over-allocation, cascade delete, complete/archive, currency lock |
| Recurring transactions | past occurrences due, nothing auto-generated, record once (handled list and ledger key), different amount, skip, pause, archived wallet blocks recording, upcoming, reminders, validation, references block deletes, recorded transactions kept |
| Recurring form model | defaults, `canSave`, kind switch, reminder time, next-occurrence preview, create/edit, failure |
| Savings goal form model | defaults, `canSave`, live monthly estimate (incl. money already saved), linked wallet follows currency, currency lock, legacy currency picker, create/edit, failure |
| Currency catalog (UI policy) | VND only enabled, picker keeps an existing currency, codes hidden for the default currency |
| App router | tabs and paths, notification payloads (round trip, malformed), due reminder → Home › Due, budget alert → budget or Budgets tab, reset |
| Backup format | codec round trip (milliseconds, stable bytes), other/newer files refused, duplicate ids, unknown values, missing references, unbalanced transactions, category cycles |
| CSV | quoting, formula-injection guard, BOM + CRLF, plain decimals |
| Backup, restore, export | backup contains everything, restore reproduces the same data and balances, replaces existing data (no duplicate categories), invalid backup changes nothing, CSV rows and signs, date range |
| Restore flow | review without changes, safety copy before restore, no restore if the safety copy fails, invalid file, cancel |
| CSV reading and parser | quoted fields, line numbers, export → read back, unambiguous numbers (`65.000` VND, `1,250.75`; `65,5` rejected), reordered columns, Vietnamese type names, d/m/y dates, per-row problems, whole-file problems |
| CSV import | export → import into another store (same ids, kinds, amounts, categories), same file twice adds nothing, possible duplicates opt-in, missing wallets/categories created (incl. sub-category), archived wallet and currency mismatch listed, failed commit keeps nothing |
| Import flow | review → confirm with safety copy, nothing to import, unreadable file, duplicate choice reset |

## Status

| Milestone | Status |
|---|---|
| 0: Architecture | done ([docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)) |
| 1: App foundation | done: tabs, navigation, design system, light/dark, SwiftData schema V1 + migration plan, store error screen, default categories, empty states, preview data |
| 2: Wallets, income/expense vertical slice | done: create/edit/archive/restore/delete wallets, opening balances, balances from the ledger, quick entry for income/expense, edit/delete with confirmation, history per wallet and per category, day-grouped transaction list, category management |
| 3: Transfers and budgets | done: transfers (same and cross-currency, edit/delete, per-wallet signs), budgets (weekly/monthly/yearly/custom, categories incl. children, wallet limits, rollover, progress, daily allowance, spending list, archive), schema V2 with migration test |
| 4: Dashboard and reports | done: dashboard (net worth, assets, liabilities, period income/expenses/net, spending by category, 6-month chart, budgets, wallets, recent), period picker incl. custom range, Reports screen (income vs expenses, spending trend, by category, by wallet, budget vs actual, 12-month cash flow + table, net worth trend), transaction search/filters/sort/grouping |
| 5: Savings and recurring | done: savings goals (earmarks, contributions/withdrawals, plan per month, linked wallet warning, complete/archive), recurring income/expense (daily/weekly/monthly/yearly every N, due review: record/skip/record with another amount, pause), local reminders and budget alerts with permission handling, dashboard due/upcoming cards, savings in reports, schema V3 |
| 6: Data safety and release | done: full JSON backup to Files/iCloud Drive, validated all-or-nothing restore with an automatic safety copy, CSV export of transactions, CSV import (files exported by the app, also after editing in a spreadsheet), last-backup reminder, privacy manifest, Documents visible in Files |

### Known limitations

- Totals are shown per currency; there is no conversion to a single base currency (by design for now; the app is used with VND only). Currency pickers and codes are hidden while `CurrencyCatalog.enabled` has a single currency.
- An asset wallet cannot start with a negative opening balance (overdraft); enter it as 0 and record the difference, or use a credit-card wallet.
- Notifications depend on iOS and on the user's permission; the app never records anything in the background (see Settings → Notifications in the app).
- Budget alert thresholds are 80 % and 100 % for every budget; they can't be edited per budget yet.
- Recurring transfers are not supported (income and expenses only).
- Sub-categories can be used by budgets, but the category screen can't create them yet.
- Backups are manual files; there is no automatic or iCloud backup. The app shows when the last backup is older than 30 days.
- CSV import reads the app's own export format (columns found by name). Files from other apps or bank statements are not supported yet. New wallets created by an import have no opening balance.
- The app icon is not designed yet.
- Default category names are in English and can be edited later; localisation (vi) is planned.
