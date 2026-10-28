#!/usr/bin/env python3
"""Lists localizable string literals in Swift sources that have no Russian translation yet."""
import glob, json, re

# Calls whose string argument is localized: SwiftUI views, String(localized:), and Drovia's own helpers
# that take a LocalizedStringKey (slider, Tip, OpenSettingsButton) or a LocalizedStringResource (App Intents).
pattern = re.compile(
    r'(?:String\(localized:\s*|Text\(|Toggle\(|Picker\(|Button\(|Tab\(|Section\(|LabeledContent\(|TextField\('
    r'|Label\(|Menu\(|\.help\(|slider\(|Tip\([^"]*text:\s*|OpenSettingsButton\(|Parameter\(title:\s*'
    r'|LocalizedStringResource\s*=\s*|IntentDescription\()'
    r'"((?:[^"\\]|\\.)*)"'
)
specifier = re.compile(r"%(?:\d+\$)?(?:@|l{0,2}[dfu])")


def without_interpolations(literal):
    """Replaces each \\(…) with %@, however deeply its parentheses nest."""
    out, i = [], 0
    while i < len(literal):
        if literal.startswith("\\(", i):
            depth, i = 1, i + 2
            while i < len(literal) and depth:
                depth += {"(": 1, ")": -1}.get(literal[i], 0)
                i += 1
            out.append("%@")
        else:
            out.append(literal[i])
            i += 1
    return "".join(out)


def normalized(key):
    """Keys compared with every format specifier alike: the catalog says %lld where the source has \\(count)."""
    return specifier.sub("%", key)


catalog = json.load(open("Drovia/Resources/Localizable.xcstrings"))["strings"]
translated = {normalized(key) for key, entry in catalog.items() if "ru" in entry.get("localizations", {})}
keys = set()
for path in glob.glob("Drovia/**/*.swift", recursive=True):
    for match in pattern.finditer(open(path).read()):
        keys.add(without_interpolations(match.group(1)))
for key in sorted(keys):
    if normalized(key) not in translated:
        print(repr(key))
