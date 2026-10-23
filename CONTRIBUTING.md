# Contributing to Drovia

Thanks for helping! Bug reports, ideas and pull requests are all welcome.

## Getting started

1. Install Xcode 26+, then `brew install xcodegen swiftformat`.
2. `make run` builds and launches the app; `make test` runs the tests.
3. The Xcode project is generated from `project.yml` and isn't committed. After adding or removing files, run `make gen` (the other `make` targets do it for you).

## Before you open a pull request

- `make test` passes.
- `make lint` reports nothing (`make format` fixes it).
- New user-facing strings are in `Drovia/Resources/Localizable.xcstrings` with English and Russian. `python3 Scripts/missing-strings.py` lists strings without a Russian translation. If you don't speak Russian, leave it untranslated and say so in the PR.
- Keep pull requests focused on one change and describe what you tested by hand: drag-and-drop behavior can't be covered by unit tests.

## How the code is organized

| Folder | What lives there |
| --- | --- |
| `DragMonitor/` | Detecting file drags system-wide and polling modifier keys |
| `Wheel/` | The wheel panel, its geometry, and the coordinator tying drags, keys and actions together |
| `Actions/` | Everything a wheel can do. Each action implements `DroviaAction`; `ActionRegistry` lists them |
| `Engines/` | The actual work: images (ImageIO), PDF (PDFKit), media (AVFoundation), Vision, documents, archives |
| `Editor/` | The Crop / Annotate / Background editor and its renderer |
| `Recipes/`, `Intents/` | User recipes and the Shortcuts actions |
| `Output/`, `History/` | Where results go, naming, history and undo |
| `Shelf/`, `HUD/`, `Settings/`, `Onboarding/` | The rest of the UI |

### Adding an action

1. Implement `DroviaAction` (see `Actions/Tools/ImageTools.swift` for small examples):
   - `supports(_:)` decides from file types alone — never read the files there, it runs during a drag.
   - Set `producesFiles` if the action writes files, and get destinations from `context.planner` so naming, the output folder setting and undo work.
   - Use `context.processEach` to process files in parallel with progress.
   - If the action is a variant of an existing one for other file types (like `PDFTransformAction` for Compress), give it the same `sectorID` so they share a sector.
2. Add it to `ActionRegistry`. The position in the list is its default place on the wheel.
3. Add tests for the engine part, using generated fixtures (see `ImageEngineTests`, `MediaEngineTests`).

### README images

The images in `docs/images` are rendered by the app itself: `make docs-images`.

## Reporting bugs

Please include your macOS version, what you dragged (file type, which app it came from), which modifier you held, and what happened. `make logs` output while reproducing the problem helps a lot.
