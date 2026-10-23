#!/usr/bin/env python3
"""Lists localizable string literals in Swift sources that have no Russian translation yet."""
import glob, json, re

pattern = re.compile(
    r'(?:String\(localized:\s*|Text\(|Toggle\(|Picker\(|Button\(|Tab\(|Section\(|LabeledContent\(|TextField\(|Label\(|Menu\(|\.help\()'
    r'"((?:[^"\\]|\\.)*)"'
)
catalog = json.load(open("Drovia/Resources/Localizable.xcstrings"))["strings"]
keys = set()
for path in glob.glob("Drovia/**/*.swift", recursive=True):
    for match in pattern.finditer(open(path).read()):
        keys.add(re.sub(r"\\\((?:[^()]|\([^()]*\))*\)", "%@", match.group(1)))
for key in sorted(keys):
    entry = catalog.get(key) or catalog.get(key.replace("%@", "%lld"))
    if not entry or "ru" not in entry.get("localizations", {}):
        print(repr(key))
