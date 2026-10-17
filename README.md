# sickPDF

sickPDF is an offline-first PDF toolkit for Android, built with Flutter. It lets you merge, split, organize, compress, rotate, protect, unlock, watermark, number, sign, annotate, and create PDF documents — entirely on your device. No accounts, no cloud services, no telemetry.

## Status

- **Platform:** Android. The repository contains Flutter scaffolding for iOS, web, and desktop, but only Android has been set up and tested.
- **Stability:** All twelve tools are implemented and covered by unit/widget tests. Physical-device UI and accessibility testing is partially complete (see [Limitations](#limitations)).
- Current version: 1.1.0 (see [CHANGELOG.md](CHANGELOG.md)).

## Features

All of the following are implemented with their own service, screen, and tests:

| Tool | Description |
|------|-------------|
| Merge PDF | Combine multiple PDFs in user-defined order |
| Split PDF | Extract an inclusive page range into a new PDF |
| Organize PDF | Reorder, remove, and restore pages with thumbnails |
| Compress PDF | Three compression presets with a result summary |
| Rotate PDF | Rotate individual pages or all pages |
| Protect PDF | AES-256 encryption with password confirmation |
| Unlock PDF | Remove an open password you supply |
| Watermark PDF | Text watermarks with style and page selection |
| Page Numbers | Configurable format, position, color, and numbering |
| Sign PDF | Draw a signature and place it on the document |
| Add Text | Insert styled text at a chosen placement |
| Image to PDF | Convert multiple images to a PDF with page size, margin, and fit options |

Common workflow across tools: select input → configure → process → in-app preview (via `pdfrx`/PDFium) → save through the Android system document picker (or share, where supported).

## Privacy and offline-first design

- No account system, backend, analytics, advertising, or document-upload workflow.
- PDF processing uses local file paths and in-memory bytes. No network calls are made during document operations.
- The system document picker may expose third-party cloud providers (e.g. Drive); choose files stored on the device for offline use.
- Picker copies and temporary output can persist in app/OS cache after interrupted operations.

A complete network audit has not been performed, but the dependency set (`file_picker`, `path_provider`, `pdf_combiner`, `pdfrx`, `image`, `pdfium_dart`, `ffi`) contains no analytics or networking packages.

## Requirements

- Flutter ≥ 3.47 with Dart ≥ 3.13 (see `pubspec.yaml`)
- Android SDK with accepted licenses, Java, and Gradle
- A physical Android device with USB debugging for device testing
- Python 3 (standard library only) to regenerate the launcher icons or the encrypted-PDF test fixtures — not a runtime dependency

## Development setup

```sh
git clone https://github.com/delwynmarli/sickpdf.git
cd sickpdf
flutter pub get
flutter doctor   # verify the toolchain
```

## Running the app

```sh
flutter devices   # list connected devices
flutter run       # select the physical Android device when prompted
```

## Analysis and tests

```sh
flutter analyze
flutter test
```

Tests cover tool services (including real extraction from synthetic encrypted fixtures), widget behavior for each tool screen, and accessibility basics. See [test/README notes in pdf_split_compatibility_test.dart] for a private local regression option via `SICKPDF_COMPATIBILITY_PDF`.

## Building an APK

```sh
flutter build apk --debug
# Output: build/app/outputs/flutter-apk/app-debug.apk
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

The application ID is `com.sickpdf.sickpdf`. The release build currently uses debug signing; configure production signing before distributing a release and never commit signing keys or `key.properties`.

### Regenerating launcher icons

```sh
python tools/generate_launcher_icons.py
```

## Project structure

```
lib/
  main.dart            App entry, Home/Tools/About navigation
  navigation/          Tool catalog
  screens/             One screen per tool + output preview
  services/            PDF processing services (one per tool)
  theme/               Material 3 theme (light + dark)
  widgets/             Shared scaffold, signature pad
android/               Native code: PdfSigner, PdfTextAdder, PdfImageConverter (+ tests)
test/                  Unit and widget tests, encrypted-PDF fixtures
tools/                 Asset-generation scripts
docs/                  Per-tool design notes
```

## Dependencies

- [`file_picker`](https://pub.dev/packages/file_picker) — document selection and save
- [`pdf_combiner`](https://pub.dev/packages/pdf_combiner) — local PDF merging
- [`pdfrx`](https://pub.dev/packages/pdfrx) (+ `pdfium_dart`) — local rendering, page extraction
- [`image`](https://pub.dev/packages/image) — image optimization for Image to PDF
- [`path_provider`](https://pub.dev/packages/path_provider), `ffi`, `cupertino_icons`

Native Android PDF operations (signing, text insertion, image conversion, protection, unlocking) use bundled libraries declared in `android/app/build.gradle.kts`. Retain all third-party license notices when redistributing.

## Known limitations

- Output bytes are held in memory for preview and saving; very large documents may exhaust device memory.
- Native operations have no cancellable timeout; a stalled native call keeps processing active.
- Some damaged, encrypted, or unsupported PDFs cannot be processed; error handling does not eliminate native-engine crash risk.
- Recent-file history is not persisted.
- iOS, web, and desktop are untested and unsupported.
- Accessibility (text scaling, TalkBack), lifecycle interruption, and all supported file variants need further physical-device testing.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Bug reports and feature requests go through [GitHub Issues](https://github.com/delwynmarli/sickpdf/issues) with the provided templates.

## Security

See [SECURITY.md](SECURITY.md) for reporting vulnerabilities.

## License

Released under the [MIT License](LICENSE).
