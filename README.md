# sickPDF

sickPDF is an offline-first PDF toolkit for Android, built with Flutter. It lets you merge, split, organize, compress, rotate, protect, unlock, watermark, number, sign, annotate, scan documents, OCR scans, and create PDF documents — entirely on your device. A built-in **Files** tab keeps the documents you import or create in a private, persistent on-device library. No accounts, no cloud services, no telemetry.

## Status

- **Platform:** Android. The repository contains Flutter scaffolding for iOS, web, and desktop, but only Android has been set up and tested.
- **Stability:** All fourteen tools, the Files document library, and the OCR result preview are implemented and covered by unit/widget tests. Physical-device UI and accessibility testing is partially complete (see [Limitations](#known-limitations)).
- Current version: 1.1.0 (see [CHANGELOG.md](CHANGELOG.md)).

## Features

All of the following are implemented with their own service, screen, and tests:

| Tool | Description |
|------|-------------|
| Merge PDF | Combine multiple PDFs in user-defined order |
| Split PDF | Extract an inclusive page range into a new PDF |
| Organize PDF | Reorder, rotate, remove, and restore pages with thumbnails |
| Compress PDF | Three compression presets with a result summary |
| Rotate PDF | Rotate individual pages or all pages |
| Protect PDF | AES-256 encryption with password confirmation |
| Unlock PDF | Export a copy with the open password removed (see the distinction below) |
| Watermark PDF | Text watermarks with style and page selection |
| Page Numbers | Configurable format, position, color, and numbering |
| Sign PDF | Draw a signature and place it on the document |
| Add Text | Insert styled text at a chosen placement |
| Image to PDF | Convert multiple images to a PDF with page size, margin, and fit options |
| OCR PDF | Read a scanned PDF on-device, review the text, then save it as TXT |
| Scan Document | Capture pages with the camera, crop them, and export them as a PDF |

Common workflow across tools: select input → configure → process → in-app preview (via `pdfrx`/PDFium) → save through the Android system document picker (or share, where supported).

### Files: a persistent local document library

The **Files** tab is a document library owned by sickPDF, not a temporary picker preview.

- **Import** a PDF from the system picker. The chosen file is copied into sickPDF's private app storage under a sanitized, collision-free name; the original file is never modified or deleted.
- **Persistent.** The list is reloaded from storage whenever the tab becomes visible and survives closing the screen, force-stopping the app, and rebooting the device. It does not depend on in-memory state or the picker's temporary URI.
- **Open / preview** any document in the built-in viewer.
- **Rename** updates both the stored file and its metadata, or neither if the rename fails.
- **Share** hands a copy to another app through Android's share sheet; the library copy is untouched.
- **Delete** asks for confirmation, removes the library entry, and deletes only sickPDF's own copy.
- Missing or damaged documents are reported with a recovery path instead of crashing; a document whose file disappeared is never silently removed from the list.
- On first run the tab explains how to add a document instead of showing an empty list.

Metadata kept per document: a stable ID, display name, internal path, import date, and file size.

### Opening a password-protected PDF from Files

When a document in Files needs a password to open, sickPDF asks for it and opens the document **in place**:

- The prompt appears only for documents that actually require a password; unprotected documents and documents that merely carry owner restrictions open normally.
- A **show/hide password** toggle matches the pattern used elsewhere in the app.
- A correct password opens the document for viewing. **No copy is written, the library file is not modified, and the password is not stored** — not in library metadata, logs, or the clipboard.
- A wrong password shows a clear message and allows another attempt.
- **Cancel** returns to Files without opening anything.
- Damaged, unsupported, or empty files are reported separately from a wrong password.

This is deliberately different from **Unlock PDF**: opening a locked document only reads it for the current session, whereas Unlock PDF verifies a password and **exports a new, unprotected copy** that you then save or share.

### OCR PDF with a preview before saving

OCR runs fully offline and never writes a file until you ask it to:

1. Select a scanned PDF.
2. Pages are rendered and recognized one at a time with a progress indicator and a Cancel action.
3. A **result preview** opens showing the source file name, how many pages produced text, and the recognized text in a scrollable, **editable** field. Page separators (`--- Page N ---`) are preserved, and pages that produced nothing are marked rather than left blank.
4. Choose **Save TXT** (through the system save dialog, confirming the file name actually written), **Copy Text**, **Share**, or **Cancel/Back**. Leaving without saving discards the text and creates no file.

Recognized script support is **Latin only** (which includes Indonesian text). OCR PDF produces plain text; it does not build a searchable PDF.

### Adding tool output to Files

Tool outputs still require one deliberate step: after a tool produces a result, its preview screen offers **Add to Files**. Outputs are **not** added to the library automatically, so the library only ever contains documents you chose to keep. Tools also continue to offer their normal Save/Share path.

## Privacy and offline-first design

- No account system, backend, analytics, advertising, or document-upload workflow.
- Document processing uses local file paths and in-memory bytes. No network calls are made during document operations.
- The merged release manifest for the shipped app declares **only `CAMERA`** (plus an internal, non-exported Android plugin permission). `INTERNET`, `ACCESS_NETWORK_STATE`, `READ_EXTERNAL_STORAGE`, `WRITE_EXTERNAL_STORAGE`, and `RECORD_AUDIO` are explicitly removed with `tools:node="remove"`. The on-device OCR dependency pulls in Google's telemetry uploader and network permissions by default; both Android manifests strip them again so the app is structurally unable to make a network request. See [docs/ocr_pdf.md](docs/ocr_pdf.md).
- **Scan Document is the only tool that needs a runtime permission: `CAMERA`.** It is requested only when the user opens the camera, and the scan is processed entirely on the device. See [docs/scan_document.md](docs/scan_document.md).
- **Files documents live in private app storage** (`<app documents>/library/`), which no other app can read and which requires no storage permission.
- **Uninstalling sickPDF deletes everything in that private storage, including documents you imported into Files.** Export or share anything you need to keep before uninstalling. Documents saved through the system save dialog live wherever you saved them.
- The system document picker may expose third-party cloud providers (e.g. Drive); choose files stored on the device for offline use.
- Picker copies and temporary output can persist in app/OS cache after interrupted operations.

A complete network audit has not been performed, but the dependency set (`file_picker`, `path_provider`, `pdf_combiner`, `pdfrx`, `image`, `pdfium_dart`, `ffi`, `google_mlkit_text_recognition`, `camera`, `image_cropper`) contains no analytics or networking packages.

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

At the time of writing the suite reports 290 passing tests and 1 skipped test on Flutter 3.47.7; run it yourself rather than relying on that number.

Tests cover tool services (including real extraction from synthetic encrypted fixtures), widget behavior for each tool screen, the document library against a real temporary filesystem, the password prompt flow, and accessibility basics.

The encrypted-PDF fixtures are synthetic and committed. If they are missing, regenerate them:

```sh
python test/fixtures/generate_encrypted_pdfs.py
```

`test/fixtures/password_required.pdf` requires the user password `secret`; `test/fixtures/owner_encrypted.pdf` has an empty user password and opens normally. Override the paths for a private regression corpus with `SICKPDF_PASSWORD_PDF` and `SICKPDF_COMPATIBILITY_PDF`.

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

The current arm64 release build is about 64 MB. Most of that is the bundled
OCR model, which is what allows offline recognition on first use.

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
  main.dart            App entry, Home/Files/Settings navigation
  navigation/          Tool catalog
  screens/             One screen per tool, Files library, OCR result preview, output preview
  services/            PDF processing services, document library, document share, PDF open/password
  theme/               Material 3 theme (light + dark)
  widgets/             Shared scaffold, signature pad, locked-PDF dialog
android/               Native code: PdfSigner, PdfTextAdder, PdfImageConverter (+ tests)
test/                  Unit and widget tests, encrypted-PDF fixtures
tools/                 Asset-generation scripts
docs/                  Per-tool design notes
```

## Dependencies

- [`file_picker`](https://pub.dev/packages/file_picker) — document selection and save
- [`pdf_combiner`](https://pub.dev/packages/pdf_combiner) — local PDF merging
- [`pdfrx`](https://pub.dev/packages/pdfrx) (+ `pdfium_dart`) — local rendering, page extraction, and opening password-protected documents
- [`image`](https://pub.dev/packages/image) — image optimization for Image to PDF, and page decoding/edge detection for Scan Document
- [`google_mlkit_text_recognition`](https://pub.dev/packages/google_mlkit_text_recognition) — on-device OCR (Latin script, bundled model, Apache-2.0)
- [`camera`](https://pub.dev/packages/camera) — live camera capture for Scan Document
- [`image_cropper`](https://pub.dev/packages/image_cropper) — the manual crop editor for Scan Document
- [`path_provider`](https://pub.dev/packages/path_provider), `ffi`, `cupertino_icons`

Native Android PDF operations (signing, text insertion, image conversion, protection, unlocking) use bundled libraries declared in `android/app/build.gradle.kts`. Retain all third-party license notices when redistributing.

## Known limitations

- Output bytes are held in memory for preview and saving; very large documents may exhaust device memory.
- Native operations have no cancellable timeout; a stalled native call keeps processing active.
- Some damaged, encrypted, or unsupported PDFs cannot be processed; error handling does not eliminate native-engine crash risk.
- Tool outputs are not added to Files automatically; you press **Add to Files** on the result screen.
- Opening a password-protected document only unlocks it for that session; the password is requested again next time.
- Documents in the Files library are lost if the app is uninstalled unless they were exported or shared first.
- OCR PDF recognizes **Latin script only** (including Indonesian) and exports plain text. It does not create a searchable PDF. Accuracy depends on scan quality, rotation, contrast, and layout.
- The OCR model is bundled in the APK, which is why a release arm64 APK is roughly 64 MB.
- Scan Document's automatic edge detection is a best-effort Sobel pass, not a full document scanner. It finds a page on a plain background; on a cluttered desk it reports no document and the manual crop editor is used instead. Perspective is corrected only by the crop editor's own transform, not by a dedicated dewarp step. Scan Document does not run OCR on its own output.
- iOS, web, and desktop are untested and unsupported.
- Accessibility (text scaling, TalkBack), lifecycle interruption, and all supported file variants need further physical-device testing.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Bug reports and feature requests go through [GitHub Issues](https://github.com/delwynmarli/sickpdf/issues) with the provided templates.

## Security

See [SECURITY.md](SECURITY.md) for reporting vulnerabilities.

## License

Released under the [MIT License](LICENSE).
