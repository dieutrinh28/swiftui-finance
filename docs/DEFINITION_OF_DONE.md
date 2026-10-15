# Definition of done

A change (a milestone, a feature, a fix) is done only when every applicable item
below is true **and was checked**, not assumed. The report of a change says which
items were checked and how, and lists anything that could not be checked.

Why this exists: an audit in October 2026 found bugs that no single milestone
introduced. Later features added references to older models without revisiting
their edit and delete paths; documents described settings that were never applied;
tests had never been run. See ARCHITECTURE.md › Invariants.

## 1. Before writing code

- [ ] Read ARCHITECTURE.md › Invariants. Note which ones the change touches.
- [ ] List every model the change **reads, references or copies data from**
      (an id, a currency code, a name). Each one gets a row in step 2.

## 2. While writing code

For each new reference from model A to model B (relationship, stored id, copied value):

- [ ] Edit of B: can it make A invalid (type, currency, parent change)? Block it or update A.
- [ ] Delete of B: blocked by a service check, or A handles B's absence.
- [ ] Archive / restore of B: what A does with an archived B, decided and tested.
- [ ] Delete of A's products: anything derived from A (a recorded transaction, a
      handled key) is undone or deliberately kept, and the user can recover.
- [ ] Backup, restore, CSV import and export carry the new data; the validator checks it.

For each new persisted field:

- [ ] New schema version (never edit a shipped one), migration stage and migration test.
- [ ] Backup format: optional field, older files still restore, format version bumped.

For each screen touched:

- [ ] Follows DESIGN_SYSTEM.md › Screen patterns (form, detail, collection, settings).
- [ ] Dates, numbers and amounts use the app's locale (`.locale(.app)`, `MoneyFormatter()`)
      and `CalendarPolicy` (`@Environment(\.calendar)` in views, `app.calendarPolicy` in models).
- [ ] Every visible text is in the String Catalogs with Vietnamese and Japanese.
- [ ] A list for picking a wallet uses `WalletChoices.selectable` (archived wallets never offered, I15).
- [ ] Every read from the store that can fail shows its failure (`ReadResult`, `ReadFailureLabel`); no `try?` on a service or store read anywhere in the app or FinanceFeatures (C8); code without a screen keeps its current state on a read error.

## 3. Checks that must pass (run them; paste the result in the report)

```bash
python3 scripts/check_localizations.py --sources   # 0 errors
python3 scripts/check_conventions.py               # 0 new errors (known ones are in the baseline)
```

- [ ] Package tests: close the app project, open `Packages/FinanceKit` in Xcode,
      scheme `FinanceKit-Package` on *My Mac*, ⌘U (or `swift test` on macOS).
      All pass; the report gives the count from the test report ("332 passed").
      "Not run" is reported as not run, never as passed.
- [ ] App build: Xcode › Run on a simulator with no errors.
- [ ] Xcode overwrites: Xcode can save its open copy of a file over a version
      written from outside (seen several times). Close the file in Xcode
      (File › Close "…") before changing it on disk, then confirm on disk
      (hash) that the change is still there before building or testing.
- [ ] Every touched screen opened in the simulator (light mode at least); the
      changed behaviour exercised once.
- [ ] A fixed known violation is removed from the baseline
      (`check_conventions.py --write-baseline`); the baseline never grows.

## 4. Documents

- [ ] ARCHITECTURE.md, README.md, DESIGN_SYSTEM.md and ROADMAP.md describe what
      the code does **now**. A claim about project settings (Info.plist keys,
      languages) is only written once the setting is in `project.pbxproj`.
- [ ] Invariants table updated: new invariants added with how they are enforced.
- [ ] Project docs (claude.ai Project) updated with the same content.

## 5. Delivering to the Mac

- [ ] Compare the **whole** repository with the Mac by hash, not only the files
      just changed, so drift in other files is noticed.
- [ ] A file the user changed since the last delivery is merged, never overwritten.
- [ ] `project.pbxproj` is only written while Xcode is closed.
- [ ] After every write, the file's hash on the Mac equals the local one. The copy tool can
      deliver an earlier version of a path it has sent before (seen three times); when the
      hash differs, send the file again from a new staging path.
