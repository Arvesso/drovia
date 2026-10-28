<!-- One focused change per pull request. Title: what it does, in the imperative ("Keep EXIF in WebP"). -->

## Problem
<!-- What was wrong or missing, and how it shows up for the user. Link the issue: "Fixes #123". -->

## Change
<!-- What changed and why this way. Name the main types or files. Mention anything left out on purpose. -->

## Tests
<!-- New or changed tests, and what they would have caught. -->
- [ ] `make test` passes
- [ ] `make lint` passes
- [ ] New user-facing strings are in `Localizable.xcstrings` in English and Russian (`python3 Scripts/missing-strings.py` prints nothing)
- [ ] Tests don't touch real user state (use `TemporaryFolder`, `TestDefaults`, `TestTrash`, `TestScriptKey`)

## Please check by hand
<!-- Drag and drop, the wheel, the menu bar and permissions can't be unit-tested: list the steps to try, or "Nothing". -->
