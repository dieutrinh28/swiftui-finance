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

In Xcode: the app project does not list the package's test targets (Xcode doesn't offer them for a local package dependency). Close the app project, open the `Packages/FinanceKit` folder (File › Open), keep the `FinanceKit-Package` scheme with *My Mac*, and press ⌘U. Last full run: 15 Oct 2026, 358 passed, none disabled.

| Suite | Covers |
|---|---|
| Money | same-currency arithmetic, currency mismatch, overflow, precision (VND/USD/KWD), rounding policies, ratios, explicit conversion, Codable |
| Currency catalog and formatting | strict lookup, VND formatting (`4.000.000 ₫`) |
| Persisted raw values | enum raw values are frozen; only credit cards are liabilities |
| Calendar policy | half-open months, year boundary, February, Monday weeks, inclusive custom ranges, day keys in the local time zone |
| Persistence | schema, idempotent seeding, user edits not overwritten, data survives reopening the store, rollback, fixture ledger consistency, stores written by V1 and V3 open with the current schema |
| Ledger rules | amount > 0, currency = wallet, category required and of the right type, archived wallet/category, signed amounts, balance formula |
| Amount input | VND grouping (`65.000`), USD decimals (`12.50` / `12,50`), rejecting ambiguous input such as `1,250.00` or `65,5` |
| Wallets and balances | opening balance is not income, income/expense balances, independent wallets, 250 wallets, USD cents, credit-card debt, currency lock, archive vs delete |
| Transactions | invalid input writes nothing, edit amount/kind/wallet, rejected edit leaves data unchanged, delete restores balance, archived wallets are read-only, day key, ledger survives relaunch |
| Categories | create/rename, type locked once used, renaming doesn't touch transactions, delete only when unused |
| Transaction form model | defaults, default wallet, `canSave` rules, amount parsing per wallet currency, kind switch clears wrong category, save create/edit, failures reported with nothing written |
| Transfer rules / transfers | same-currency amounts equal, cross-currency explicit amounts and implied rate, same wallet/archived/zero rejected, totals preserved, credit-card payment, edit both sides, rejected edit unchanged, delete restores both |
| Budget rules / budgets | spec example (62.5 %), month boundaries by day key, near limit / over budget, other currencies excluded, rollover (unused and overspent, several periods), weekly/yearly/custom/end-dated windows, eligibility (kind, child categories, wallets, no double count), progress follows edits and deletes, overlapping budgets, 100 budgets, validation |
| Schema migration | stores written with the V1 and V3 classes open with the current schema (→ V4), keep balances, recurring items and alert thresholds, and start the V4 fields with their defaults |
| Transfer & budget form models | kinds per mode, received amount for cross-currency, edit prefill, budget defaults (current month), `canSave`, currency change clears wallets, save/edit/failure |
| Report rules | assets/liabilities/net worth per currency, transfers don't change net worth, positions at a past day, archived wallets with money, cash flow excludes transfers, empty ledger, category and wallet breakdowns with shares, "other" folding, month ranges, monthly trend, net-worth trend, daily running total |
| Transaction query | accent-insensitive search (`pho` → Phở, `da chanh` → Đá chanh), combined filters, either side of a transfer, inclusive bounds, sort orders, 10,000 items |
| Report snapshot | snapshot balances equal wallet balances, net worth follows edits/deletes/transfers, archived wallets included, searchable summaries |
| Dashboard, reports and list models | totals from the ledger, period change, reload after new data, failures surfaced, currency switch, day/month grouping, amount sort ungrouped, period filter and clear, no results |
| Recurrence rules | month-end anchoring (31st, leap day), every N weeks with end date, windows, next occurrence, stable keys, validation, reminder times in the future |
| Savings rules | progress, months left, suggested monthly (rounded up), reached/overdue, withdrawals limited to saved |
| Budget alert rules | thresholds alerted once per period |
| Savings goals | earmarks never change balances or net worth, withdrawal/delete limits, linked wallet currency and over-allocation, cascade delete, complete/archive, currency lock |
| Recurring transactions | past occurrences due, nothing auto-generated, record once (handled list and ledger key), different amount, skip, pause, archived wallet puts the item on hold, upcoming, reminders, validation, references block deletes, recorded transactions kept |
| Recurring form model | defaults, `canSave`, kind switch, reminder time, next-occurrence preview, create/edit, failure |
| Savings goal form model | defaults, `canSave`, live monthly estimate (incl. money already saved), linked wallet follows currency, currency lock, legacy currency picker, create/edit, failure |
| Wallet form model | empty opening balance is zero, icon follows the type until chosen, a card's opening balance is the amount owed (edit round trip), currency lock with transactions, refused save keeps the reason |
| Category form model | type change drops parent and irregular, only top-level same-type parents (never itself), sub-category starts like its parent, history and sub-categories lock the type, refused save |
| Currency catalog (UI policy) | VND only enabled, picker keeps an existing currency, codes hidden for the default currency |
| App router | tabs and paths, notification payloads (round trip, malformed), due reminder → Home › Due, budget alert → budget or Budgets tab, reset |
| Backup format | codec round trip (milliseconds, stable bytes), other/newer files refused, duplicate ids, unknown values, missing references, unbalanced transactions, category cycles |
| CSV | quoting, formula-injection guard, BOM + CRLF, plain decimals |
| Backup, restore, export | backup contains everything, restore reproduces the same data and balances, replaces existing data (no duplicate categories), invalid backup changes nothing, CSV rows and signs, date range |
| Restore flow | review without changes, safety copy before restore, no restore if the safety copy fails, invalid file, cancel |
| CSV reading and parser | quoted fields, line numbers, export → read back, unambiguous numbers (`65.000` VND, `1,250.75`; `65,5` rejected), reordered columns, Vietnamese type names, d/m/y dates, per-row problems, whole-file problems |
| CSV import | export → import into another store (same ids, kinds, amounts, categories), same file twice adds nothing, possible duplicates opt-in, missing wallets/categories created (incl. sub-category), archived wallet and currency mismatch listed, failed commit keeps nothing |
| Import flow | review → confirm with safety copy, nothing to import, unreadable file, duplicate choice reset |
| App localization | no choice or an unknown language falls back to the bundle |
| Category localization | language from a localization id (en/vi/ja), switching through all languages, distinct names per language (also after folding), seeding in Vietnamese, untouched built-ins follow the language, renamed and user categories never touched, references kept, lookup by name in any language |
| Spending accuracy rules | cash flow splits regular and irregular expenses (net = change in balance), sub-categories roll up into the parent with drill-down, irregular breakdown, allowed alert thresholds, filtering by a parent also finds its sub-categories |
| Irregular expenses | category default with per-transaction override (both ways), only expenses, category edits don't rewrite expenses, budgets ignore irregular expenses |
| Sub-categories | same type, two levels, never itself, a parent stays top-level, type locked by children/budgets/recurring items, hierarchy order, report roll-up |
| Budget alert thresholds | saved sorted, off, invalid level rejected with nothing changed, custom levels drive alerts |
| Recurring transfers | record moves money once (key, duplicate blocked), not spending; cross-currency needs the received amount (also when recording another amount); invalid definitions; destination wallet can't be deleted |
| Recurring schedule edits | moving the start back doesn't offer past occurrences; *Coming up* skips occurrences handled early |
| Recurring holds and reopening | archived wallet or category puts the item on hold (no due, upcoming or reminders) and restoring lifts it; deleting a recorded occurrence makes it due again; skipped occurrences can be made due again, recorded ones can't |
| Wallet currency lock | the currency changes only while nothing relies on it: recurring items (either side), budgets limited to the wallet and linked goals block it |
| Backup format 2 | round trip keeps irregular flags, sub-categories, alert levels and recurring transfers (and recording works afterwards); format 1 files restore; validator checks transfers and thresholds |
| Spending accuracy forms | irregular follows the category until chosen, budget alert levels, recurring transfer form (destination, received amount, no category) |
| CSV import across languages | an English export imports into Vietnamese built-in categories (incl. a new sub-category) without duplicates; Vietnamese and Japanese type names (`Chi tiêu`, `Chuyển tiền`, `支出`, `振替`, …) |

Translations are checked by a script (no Xcode needed):

```bash
python3 scripts/check_localizations.py            # every key has Vietnamese and Japanese, specifiers match
python3 scripts/check_localizations.py --sources  # also lists literals in the code without a key
python3 scripts/check_conventions.py              # calendar, locale, design tokens, forms, wording, project settings
```

`check_conventions.py` fails on new violations only; the ones that existed when it was introduced are listed in `scripts/conventions_baseline.txt` and are removed as they get fixed. What "done" means for any change is in [docs/DEFINITION_OF_DONE.md](docs/DEFINITION_OF_DONE.md).

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
| 7: Vietnamese and identity | done: String Catalogs for the app and FinanceKit (English, Vietnamese, Japanese, ~516 keys), language switch inside the app (More › Language, no relaunch), package messages via `String(localized:bundle: .module)`, built-in categories seeded in the app's language and renamed with it while untouched, CSV import matches built-in categories across languages, app icon (light/dark/tinted), translation check script |
| 8: Spending accuracy (schema V4) | done: irregular expenses (category default + per-expense override; balances include them, spending, budgets and spending reports don't; shown apart on the dashboard and in reports; CSV column), sub-categories (parent picker, indented lists, reports roll up with drill-down), alert levels per budget (off/50/80/90/100 %), recurring transfers (also cross-currency), backup format 2 |

### Known limitations

- Totals are shown per currency; there is no conversion to a single base currency (by design for now; the app is used with VND only). Currency pickers and codes are hidden while `CurrencyCatalog.enabled` has a single currency.
- An asset wallet cannot start with a negative opening balance (overdraft); enter it as 0 and record the difference, or use a credit-card wallet.
- Notifications depend on iOS and on the user's permission; the app never records anything in the background (see Settings → Notifications in the app).
- Budget alert thresholds are 80 % and 100 % for every budget; they can't be edited per budget yet.
- Recurring transfers are not supported (income and expenses only).
- Sub-categories can be used by budgets, but the category screen can't create them yet.
- Backups are manual files; there is no automatic or iCloud backup. The app shows when the last backup is older than 30 days.
- CSV import reads the app's own export format (columns found by name). Files from other apps or bank statements are not supported yet. New wallets created by an import have no opening balance.
- The interface is in English, Vietnamese and Japanese, chosen in *More › Language* (or iOS *Settings › Apps › Finance › Language*). The switch is immediate; a few date formats change fully at the next launch. Vietnamese and Japanese texts were written for this app and should get a native review for tone.
- CSV export headers and type names stay in English (`Date`, `Expense`, …) so files stay stable across languages; import also accepts Vietnamese type names.
