# Drovia

**Your files. One gesture away.** File utilities for macOS.

Drag any file, hold a modifier key, and drop it onto a radial wheel:

| Modifier | Wheel | Examples |
| --- | --- | --- |
| ⇧ Shift | **Convert** | PNG, JPEG, HEIC, WebP, AVIF, TIFF, PDF |
| ⌘ Command | **Tools** | Compress, Crop, Redact, Metadata, Remove BG, Annotate |
| ⌃ Control | **Actions** | AirDrop, Float, Copy, Move, Copy Path, Terminal |

Everything runs locally — no network, no accounts.

> Status: early development — image conversion, image tools and file actions work; PDF, video and Vision tools are next.

## Requirements

- macOS 26 or later
- Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen), [SwiftFormat](https://github.com/nicklockwood/SwiftFormat)

## Building

```sh
make run      # generate the Xcode project, build and launch
make test     # run unit tests
make format   # format sources
```

The Xcode project is generated from `project.yml` and is not checked in. Run `make gen` and open `Drovia.xcodeproj` to work in Xcode.

## License

MIT
