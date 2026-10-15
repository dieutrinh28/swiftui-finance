#!/usr/bin/env python3
"""Checks the project conventions that are easy to break and hard to see in review.

Each rule has an id. A line that is a deliberate exception carries a marker on
the same line or the line above:

    // convention-ok: C3 checkmark weight matches the system list style

Errors (exit code 1):
  C1  Calendar.current outside CalendarPolicy: days, weeks and periods must use
      the app's CalendarPolicy (Monday weeks, one time zone), never the device calendar.
  C2  .formatted(...) in the app without an explicit locale: it uses the launch
      locale, so after switching the language in the app dates, lists and
      percentages stay in the old language. Use `.formatted(style.locale(.app))`.
      (MoneyFormatter() is fine: it defaults to AppLocalization.locale.)
  C3  Raw fonts and colours in screens (.font(.footnote), .foregroundStyle(.secondary),
      Color.red, .font(.system(size:))): use the DesignSystem tokens.
  C4  A form (Form { ... }) without .keyboardDismissal(), or with a toolbar
      Save (placement: .confirmationAction) instead of PrimaryActionBar.
  C5  ToolbarItem(placement: .secondaryAction): iOS nests it in its own "..." menu.
  C6  ContentUnavailableView in a screen: use EmptyStateView.
  C7  Button/Label wording: the verb for something new is "Add", and Edit/Delete
      name their object ("Edit Budget", not "Edit"; "Add Goal", not "Create Goal").
  C10 Project settings promised by the docs: every language in the String
      Catalogs is in knownRegions, and the Info.plist keys that make Documents
      visible in Files are set when the docs say it is.

  C8  try? on a read from a service or the store, anywhere in the app or in
      FinanceFeatures (screens, App/, form models): a read error silently hides
      a row, shows a made-up zero, empties a form field or cancels reminders.
      Use ReadResult / Result(catching:) and ReadFailureLabel, or do/catch with
      the failure shown or the current state kept.

Warnings:
  C9  UserDefaults / @AppStorage outside PersonalFinance/App and the documented
      device-only settings: state that is not in the database (nor in backups).
  C11 A type named *FormView (in any file under Features) without a matching
      *FormModel in FinanceFeatures: form logic in the view is not covered by tests.

Baseline: violations that existed when the rules were introduced are listed in
scripts/conventions_baseline.txt. They are reported as "known" and do not fail
the check; anything new does. Fixing a known violation and rewriting the
baseline makes it shorter; it must never grow.

Usage (from the repository root):
  python3 scripts/check_conventions.py                  # new violations fail
  python3 scripts/check_conventions.py --all            # ignore the baseline
  python3 scripts/check_conventions.py --rule C2        # one rule only
  python3 scripts/check_conventions.py --write-baseline # after fixing known ones
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "PersonalFinance"
PACKAGE_SOURCES = ROOT / "Packages" / "FinanceKit" / "Sources"
FEATURES_MODELS = PACKAGE_SOURCES / "FinanceFeatures"
PROJECT = ROOT / "PersonalFinance.xcodeproj" / "project.pbxproj"
DOCS = [ROOT / "README.md", *sorted((ROOT / "docs").glob("*.md"))]

BASELINE = ROOT / "scripts" / "conventions_baseline.txt"
MARKER = re.compile(r"//\s*convention-ok:\s*(C\d+)")

# Files where the device-only settings live by design (see ARCHITECTURE.md › Device-only state).
DEVICE_SETTINGS_FILES = {
    "PersonalFinance/App/LanguageSettings.swift",
    "PersonalFinance/App/ReminderCoordinator.swift",
    "PersonalFinance/Features/Backup/BackupFiles.swift",
    "PersonalFinance/Features/Backup/BackupView.swift",
    "PersonalFinance/Features/More/MoreView.swift",
    "PersonalFinance/Features/More/NotificationSettingsView.swift",
}

RAW_FONT = re.compile(
    r"\.font\(\.(?:caption2?|footnote|subheadline|headline|body|callout|title[23]?|largeTitle)\b"
    r"|\.font\(\.system\(size:"
)
RAW_COLOR = re.compile(
    r"\.foregroundStyle\(\.(?:secondary|primary|tertiary)\)"
    r"|\bColor\.(?:red|green|blue|orange|yellow|gray|grey|pink|purple|black|white)\b"
    r"|\.(?:tint|foregroundStyle)\(\.(?:red|green|blue|orange|yellow|gray|pink|purple)\)"
)
# Labels starting with "New" are often statements ("New wallet: Cash"), so only
# buttons are checked for it.
# `try?` whose receiver is a service, the container or a model context.
SERVICE_TRY = re.compile(
    r"try\?\s*\(?\s*(?:self\.)?(?:app\.\w+|service|wallets|transactions|categories|budgets|reports|savings"
    r"|recurring|backup|export|importer|modelContainer|\w*[cC]ontext)\.\w+"
)
WORDING = re.compile(
    r'Button\("(?:Create [^"]*|New [^"]*|Edit|Delete)"'
    r'|Label\("(?:Create [^"]*|Edit|Delete)"'
)


class Report:
    def __init__(self, only, baseline):
        self.only = only
        self.baseline = baseline
        self.errors = []
        self.warnings = []
        self.known = []
        self.fingerprints = []

    def add(self, rule, severity, where, message, text=""):
        """`text` (the offending line) identifies a violation independent of its line number."""
        if self.only and rule != self.only:
            return
        fingerprint = f"{where.split(':')[0]}|{rule}|{text.strip() or message}"
        self.fingerprints.append(fingerprint)
        entry = f"{where}: {rule} {message}"
        if fingerprint in self.baseline:
            self.known.append(entry)
        else:
            (self.errors if severity == "error" else self.warnings).append(entry)


def swift_files(base):
    return sorted(p for p in base.rglob("*.swift") if ".build" not in p.parts)


def lines_outside_previews(path):
    """(number, line, allowed rules) for each line before the first #Preview."""
    previous = ""
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if line.startswith("#Preview"):
            return
        allowed = set(MARKER.findall(line)) | set(MARKER.findall(previous))
        previous = line
        if line.strip().startswith("//") or line.strip().startswith("///"):
            continue
        yield number, line, allowed


def rel(path):
    return str(path.relative_to(ROOT))


def check_swift(report):
    for path in swift_files(APP) + swift_files(PACKAGE_SOURCES):
        name = rel(path)
        in_app = name.startswith("PersonalFinance/")
        in_screens = name.startswith("PersonalFinance/Features/") or name.startswith("PersonalFinance/App/")
        source = path.read_text(encoding="utf-8")
        for number, line, allowed in lines_outside_previews(path):
            where = f"{name}:{number}"

            def flag(rule, severity, message, line=line):
                if rule not in allowed:
                    report.add(rule, severity, where, message, line)

            if "Calendar.current" in line and not name.endswith("FinanceDomain/Calendar.swift"):
                flag("C1", "error", "Calendar.current: use the CalendarPolicy (app.calendarPolicy)")
            if in_app and ".formatted(" in line and "locale" not in line:
                flag("C2", "error", "formatted without a locale: pass the app's locale")
            if in_screens:
                if RAW_FONT.search(line):
                    flag("C3", "error", "raw font: use a Font token (.rowTitle, .meta, .label, .cardTitle, ...)")
                if RAW_COLOR.search(line):
                    flag("C3", "error", "raw colour: use AppColor / PaletteColor")
                if "ContentUnavailableView" in line:
                    flag("C6", "error", "use EmptyStateView")
            if (in_app or name.startswith(str(FEATURES_MODELS.relative_to(ROOT)))) and SERVICE_TRY.search(line):
                flag("C8", "error", "error ignored: show the failure (ReadResult / ReadFailureLabel) or keep the current state")
            if in_app and "placement: .secondaryAction" in line:
                flag("C5", "error", "use .topBarTrailing with a Menu")
            if in_app and WORDING.search(line):
                flag("C7", "error", "wording: 'Add X' for new things, 'Edit X' / 'Delete X' name the object")
            if in_app and ("UserDefaults" in line or "@AppStorage" in line) and name not in DEVICE_SETTINGS_FILES:
                flag("C9", "warning", "device-only state: keep it in the database, or document it under Device-only state")

        if name.startswith("PersonalFinance/Features/") and re.search(r"\bForm\s*\{", source):
            visible = "\n".join(line for _, line, _ in lines_outside_previews(path))
            if ".keyboardDismissal()" not in visible:
                report.add("C4", "error", name, "form without .keyboardDismissal()")
            for number, line, allowed in lines_outside_previews(path):
                if "placement: .confirmationAction" in line and "C4" not in allowed:
                    report.add("C4", "error", f"{name}:{number}", "toolbar Save: use PrimaryActionBar", line)

        if name.startswith("PersonalFinance/Features/"):
            # Every form view (by type name, not file name: a file can hold several sheets).
            for form in sorted(set(re.findall(r"^(?:private |fileprivate )?struct (\w+)FormView\s*:", source, re.M))):
                model = FEATURES_MODELS / f"{form}FormModel.swift"
                if not model.exists():
                    report.add("C11", "warning", name, f"{form}FormView has no {model.name} in FinanceFeatures: form logic is untested")


def check_project(report):
    if not PROJECT.exists():
        return
    project = PROJECT.read_text(encoding="utf-8")
    regions = re.search(r"knownRegions = \((.*?)\);", project, re.S)
    known = {r.strip().strip('"') for r in regions.group(1).split(",")} if regions else set()
    languages = set()
    for catalog in ROOT.rglob("Localizable.xcstrings"):
        if ".build" in catalog.parts:
            continue
        languages |= set(re.findall(r'"localizations"\s*:\s*\{\s*"([a-zA-Z-]+)"', catalog.read_text(encoding="utf-8")))
        languages |= set(re.findall(r'^\s{8}"([a-z]{2}(?:-[A-Za-z]+)?)" : \{', catalog.read_text(encoding="utf-8"), re.M))
    for language in sorted(languages - known - {"Base"}):
        report.add("C10", "error", rel(PROJECT), f"knownRegions lacks '{language}' (it is in the String Catalogs)")

    docs = "\n".join(p.read_text(encoding="utf-8") for p in DOCS if p.exists())
    if re.search(r"visible in Files|hiện trong (?:app )?Files", docs):
        for key in ("UIFileSharingEnabled", "LSSupportsOpeningDocumentsInPlace"):
            if f"INFOPLIST_KEY_{key}" not in project:
                report.add("C10", "error", rel(PROJECT),
                           f"docs say Documents are visible in Files, but INFOPLIST_KEY_{key} is not set")


def summarize(entries):
    counts = {}
    for line in entries:
        rule = line.split(": ", 1)[1].split(" ", 1)[0]
        counts[rule] = counts.get(rule, 0) + 1
    return ", ".join(f"{rule} {count}" for rule, count in sorted(counts.items(), key=lambda kv: int(kv[0][1:])))


def main():
    only = None
    if "--rule" in sys.argv:
        only = sys.argv[sys.argv.index("--rule") + 1].upper()
    use_baseline = "--all" not in sys.argv and "--write-baseline" not in sys.argv
    baseline = set()
    if use_baseline and BASELINE.exists():
        baseline = {line for line in BASELINE.read_text(encoding="utf-8").splitlines() if line and not line.startswith("#")}
    report = Report(only, baseline)
    check_swift(report)
    check_project(report)

    if "--write-baseline" in sys.argv:
        header = "# Known convention violations; see scripts/check_conventions.py. Shrink it, never grow it.\n"
        BASELINE.write_text(header + "\n".join(sorted(set(report.fingerprints))) + "\n", encoding="utf-8")
        print(f"Wrote {len(set(report.fingerprints))} known violations to {BASELINE.relative_to(ROOT)}")
        return 0

    for line in report.errors:
        print(f"error: {line}")
    for line in report.warnings:
        print(f"warning: {line}")
    if "--verbose" in sys.argv:
        for line in report.known:
            print(f"known: {line}")

    new = summarize(report.errors + report.warnings)
    print(f"{len(report.errors)} errors, {len(report.warnings)} warnings" + (f" ({new})" if new else "")
          + (f"; {len(report.known)} known ({summarize(report.known)}), --verbose lists them" if report.known else ""))
    return 1 if report.errors else 0


if __name__ == "__main__":
    sys.exit(main())
