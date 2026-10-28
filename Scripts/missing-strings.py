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
# String(localized: """ … """): lines lose their indentation, and a line ending in a backslash continues.
multiline = re.compile(r'String\(localized:\s*"""\n(.*?)\n\s*"""', re.DOTALL)


def joined(body):
    lines = [line.strip() for line in body.split("\n")]
    return "".join(line[:-1] if line.endswith("\\") else line + "\n" for line in lines).rstrip("\n")


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
    source = open(path).read()
    for match in multiline.finditer(source):
        keys.add(without_interpolations(joined(match.group(1))))
    # A single-line match on a multi-line literal's opening quotes is the empty string; skip it.
    keys.update(without_interpolations(match.group(1)) for match in pattern.finditer(source) if match.group(1))
for key in sorted(keys):
    if normalized(key) not in translated:
        print(repr(key))
