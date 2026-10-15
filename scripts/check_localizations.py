#!/usr/bin/env python3
"""Checks the String Catalogs (Localizable.xcstrings) of the app and FinanceKit.

Errors (exit code 1):
  - a key has no Vietnamese ("vi") or Japanese ("ja") value, or it is not
    marked translated;
  - a translation uses different format specifiers than its key
    (e.g. the key has %lld and %@, the translation only %@).

Warnings:
  - a key is marked "stale" by Xcode (no longer found in the code);
  - --sources: a string literal in a localizable position in the Swift code
    has no key in any catalog (heuristic; Xcode's own extraction at build
    time is the reference).

Usage:
  python3 scripts/check_localizations.py            # from the repository root
  python3 scripts/check_localizations.py --sources
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LANGUAGES = ("vi", "ja")
SPECIFIER = re.compile(r"%(?:(\d+)\$)?(lld|ld|d|@|lf|f|%)")


def specifiers(text):
    """Format specifiers in argument order; positional ones are re-ordered."""
    found = []
    implicit = 0
    for match in SPECIFIER.finditer(text):
        position, kind = match.groups()
        if kind == "%":
            continue
        if position:
            found.append((int(position), kind))
        else:
            implicit += 1
            found.append((implicit, kind))
    return [kind for _, kind in sorted(found)]


def values(localization):
    """Every string of one localization: a plain value or plural/device variations."""
    if "stringUnit" in localization:
        yield localization["stringUnit"]
    for variation in localization.get("variations", {}).values():
        for case in variation.values():
            yield from values(case)


def check_catalog(path, errors, warnings):
    catalog = json.loads(path.read_text(encoding="utf-8"))
    source = catalog.get("sourceLanguage", "en")
    keys = catalog.get("strings", {})
    for key, entry in keys.items():
        if entry.get("shouldTranslate") is False:
            continue
        if entry.get("extractionState") == "stale":
            warnings.append(f"{path.relative_to(ROOT)}: stale key {key!r}")
        localizations = entry.get("localizations", {})
        expected = specifiers(key)
        for language in LANGUAGES:
            target = localizations.get(language)
            if not target:
                errors.append(f"{path.relative_to(ROOT)}: no {language} value for {key!r}")
                continue
            for unit in values(target):
                if unit.get("state") not in ("translated", None) or not unit.get("value", "").strip():
                    errors.append(f"{path.relative_to(ROOT)}: {language} value of {key!r} is not translated")
                elif specifiers(unit["value"]) != expected:
                    errors.append(
                        f"{path.relative_to(ROOT)}: {language} value of {key!r} has specifiers "
                        f"{specifiers(unit['value'])}, expected {expected}"
                    )
        # English plural variations must keep the key's specifiers too.
        for unit in values(localizations.get(source, {})):
            if specifiers(unit.get("value", "")) != expected:
                errors.append(f"{path.relative_to(ROOT)}: {source} variation of {key!r} changes its specifiers")
    return set(keys)


# --- Optional: literals in the code without a key (heuristic) -------------

LOCALIZABLE_CALL = re.compile(
    r'(?:\b(?:Text|Label|Button|Section|Toggle|Picker|TextField|LabeledContent|Menu|SectionHeader|'
    r'NoticeBanner|EmptyStateView|ReadFailureLabel|navigationTitle|confirmationDialog|alert|String\(localized:)\s*\(?\s*'
    r'|\b(?:title|message|subtitle|label|prompt|failure):\s*)"((?:[^"\\]|\\.)*)"'
)


def literal_to_key(literal):
    if "\\(" in literal:
        return None  # interpolations: Xcode decides the specifiers; not checked here
    return literal.replace('\\"', '"').replace("\\n", "\n")


def check_sources(known, warnings):
    for swift in list((ROOT / "PersonalFinance").rglob("*.swift")) + list((ROOT / "Packages").rglob("Sources/**/*.swift")):
        for number, line in enumerate(swift.read_text(encoding="utf-8").splitlines(), 1):
            if line.startswith("#Preview"):
                break  # previews close the file and are not shown to users
            if line.strip().startswith("//"):
                continue
            for match in LOCALIZABLE_CALL.finditer(line):
                key = literal_to_key(match.group(1))
                if key and re.search(r"[A-Za-z]{2}", key) and key not in known:
                    warnings.append(f"{swift.relative_to(ROOT)}:{number}: no catalog key for {key!r}")


def main():
    errors, warnings = [], []
    catalogs = sorted(p for p in ROOT.rglob("Localizable.xcstrings") if ".build" not in p.parts)
    if not catalogs:
        print("No Localizable.xcstrings found.")
        return 1
    known = set()
    for path in catalogs:
        known |= check_catalog(path, errors, warnings)
    if "--sources" in sys.argv:
        check_sources(known, warnings)

    for message in warnings:
        print("warning:", message)
    for message in errors:
        print("error:", message)
    total = sum(len(json.loads(p.read_text(encoding="utf-8"))["strings"]) for p in catalogs)
    print(f"{len(catalogs)} catalogs, {total} keys, {len(errors)} errors, {len(warnings)} warnings")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
