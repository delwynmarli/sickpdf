# sickPDF

sickPDF is an offline-first PDF toolkit for Android, built with Flutter. It lets you merge, split, organize, compress, rotate, protect, unlock, watermark, number, sign, annotate, OCR scans, and create PDF documents — entirely on your device. No accounts, no cloud services, no telemetry.

## Status

- **Platform:** Android. The repository contains Flutter scaffolding for iOS, web, and desktop, but only Android has been set up and tested.
- **Stability:** All thirteen tools are implemented and covered by unit/widget tests. Physical-device UI and accessibility testing is partially complete (see [Limitations](#limitations)).
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
| OCR PDF | Read a scanned PDF on-device and export the recognized text as TXT |

Common workflow across tools: select input → configure → process → in-app preview (via `pdfrx`/PDFium) → save through the Android system document picker (or share, where supported).

## Privacy and offline-first design

- No account system, backend, analytics, advertising, or document-upload workflow.
- PDF processing uses local file paths and in-memory bytes. No network calls are made during document operations.
- **The installed app holds no `INTERNET` permission at all.** The on-device OCR dependency pulls in Google's telemetry uploader and network permissions by default; both Android manifests strip them again, so the app is structurally unable to make a network request. See [docs/ocr_pdf.md](docs/ocr_pdf.md).
- The system document picker may expose third-party cloud providers (e.g. Drive); choose files stored on the device for offline use.
- Picker copies and temporary output can persist in app/OS cache after interrupted operations.

A complete network audit has not been performed, but the dependency set (`file_picker`, `path_provider`, `pdf_combiner`, `pdfrx`, `image`, `pdfium_dart`, `ffi`, `google_mlkit_text_recognition`) contains no analytics or networking packages.

OCR uses the ML Kit text recognition model that ships inside the APK, so a scan can be read with no network access at all. See [docs/ocr_pdf.md](docs/ocr_pdf.md).

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

### Continuous integration

`.github/workflows/release-validation.yml` runs on every push to `main`, on
every pull request, and on demand. It runs the same checks as above plus the
release APK build, and reports pass/fail only. It does not publish anything,
create tags, commit, or upload artifacts.

The release build is part of the workflow on purpose: R8 only runs in release
mode, so a green debug build does not prove the release build works.

## Building an APK

```sh
flutter build apk --debug
# Output: build/app/outputs/flutter-apk/app-debug.apk
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

A release build is separate and must be checked too, because R8 only runs
there:

```sh
flutter build apk --release --target-platform android-arm64
# Output: build/app/outputs/flutter-apk/app-release.apk
```

`android/app/proguard-rules.pro` keeps the release build working with the
on-device OCR dependency. A debug build does **not** exercise R8, so a green
debug build is not proof that the release build succeeds. The file documents
which missing classes the rules cover and when they should be revisited.

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
- [`google_mlkit_text_recognition`](https://pub.dev/packages/google_mlkit_text_recognition) — on-device OCR (Latin script, bundled model, Apache-2.0)
- [`path_provider`](https://pub.dev/packages/path_provider), `ffi`, `cupertino_icons`

Native Android PDF operations (signing, text insertion, image conversion, protection, unlocking) use bundled libraries declared in `android/app/build.gradle.kts`. Retain all third-party license notices when redistributing.

## Known limitations

- Output bytes are held in memory for preview and saving; very large documents may exhaust device memory.
- Native operations have no cancellable timeout; a stalled native call keeps processing active.
- Some damaged, encrypted, or unsupported PDFs cannot be processed; error handling does not eliminate native-engine crash risk.
- Recent-file history is not persisted.
- OCR PDF recognizes **Latin script only** (including Indonesian) and exports plain text. It does not create a searchable PDF. Accuracy depends on scan quality, rotation, contrast, and layout.
- The OCR model is bundled in the APK. A release arm64 APK is 61.4 MB with OCR and 31.3 MB without, so the feature costs about 30 MB.
- iOS, web, and desktop are untested and unsupported.
- Accessibility (text scaling, TalkBack), lifecycle interruption, and all supported file variants need further physical-device testing.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Bug reports and feature requests go through [GitHub Issues](https://github.com/delwynmarli/sickpdf/issues) with the provided templates.

## Security

See [SECURITY.md](SECURITY.md) for reporting vulnerabilities.

## License

Released under the [MIT License](LICENSE).
