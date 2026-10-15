# sickPDF

A privacy-focused Flutter PDF toolkit, developed Android-first with a navy, white, and green interface. The current working workflow lets users combine local PDFs, inspect the result, and save it using the system document picker.

## Implemented

- Select multiple PDFs with the native document picker.
- Display filenames, prevent duplicate paths, and remove selected files.
- Reorder files before merging; output follows the displayed order.
- Merge locally through a reusable PDF service.
- Preview the actual merged document in-app with multi-page viewing.
- Save merged bytes through the native save dialog.
- Inline success/error feedback and busy-state guards.
- Invalidate old results after source additions, removal, or reordering.
- Home screen, recent-files empty state, and Home/Tools/Settings navigation.

## Privacy and offline use

The app has no account system, backend, analytics, advertising, or document-upload workflow. Merge and preview code uses local paths and bytes, not remote document URLs. Dependencies and native build assets require internet access during initial setup/build; runtime PDF operations are intended to work offline.

A complete network/security audit and exhaustive airplane-mode testing have not been performed. The system picker may expose third-party cloud document providers: choose files stored on the phone for offline use. Picker copies and temporary output may persist in app/OS cache after interrupted operations; normal merge-output cleanup is implemented.

## Requirements

- Flutter with Dart compatible with the SDK constraint in `pubspec.yaml` (currently Dart ^3.13.5).
- Flutter >=3.47.0 for the current PDF viewer dependency.
- Android SDK, a working Java/Gradle environment, and accepted Android licenses.
- A physical Android phone with USB debugging enabled for device testing.
- Git for source control.

Run `flutter doctor` to check the development environment. Android is the primary target. Other platform folders are present, but iOS and desktop workflows have not been validated for this app. iOS builds require macOS/Xcode and platform-specific validation.

## Setup and run

```sh
git clone https://github.com/delwynmarli/sickpdf.git
cd sickpdf
flutter pub get
flutter devices
flutter run
```

Use the connected physical Android phone, not an emulator. If several devices are listed, select the physical Android target when prompted.

## Build an Android APK

```sh
flutter build apk --debug
```

Output: `build/app/outputs/flutter-apk/app-debug.apk`.

To install directly with Android platform tools:

```sh
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

The application ID is `com.sickpdf.sickpdf`. The existing release build configuration uses debug signing; configure private production signing before distributing a release. Never commit signing keys or local signing properties.

## Using Merge PDF

1. Open **Merge PDF** from Home.
2. Choose **Select PDF files** and select at least two local PDFs.
3. Remove unwanted inputs or drag rows to change their order.
4. Choose **Merge PDF** and wait for the inline result.
5. Choose **Preview PDF** to inspect the merged pages.
6. Choose **Back to Merge** to return without discarding the result, or **Save PDF** to open the system save dialog.
7. Choose a local destination and filename. Open the saved file in a PDF viewer to check the output.

Changing the source list invalidates the previous result. Cancelling a save retains the merged result for retry.

## Using Split PDF

1. Open **Split PDF** from Home and choose **Select PDF**.
2. Select one local PDF that opens without a password. Its filename and page count appear. PDFs with an empty user password can be encrypted internally and are supported when the engine opens them successfully.
3. Enter inclusive **Start page** and **End page** numbers. For a ten-page document, 2–5 extracts four pages in their original order.
4. Choose **Split PDF**, then **Preview PDF** to inspect the actual extracted document.
5. Choose **Save PDF**, change the suggested `document_pages_2-5.pdf` filename if desired, and choose a local destination. Save feedback also appears within the preview.

Changing the input or either range field discards the old result. Cancelling selection keeps the current input; cancelling save retains the result for retry. Password-required PDFs remain unsupported; no password is guessed or bypassed. File-access, password, and parsing failures have distinct messages. Debug diagnostics retain exception type, PDFium/OS error codes, and stack traces without raw document paths or contents. Empty documents remain rejected.

Encrypted-loading regression tests use synthetic ten-page fixtures: one opens with an empty user password, while another requires `secret` and must be rejected. The fixture generator uses only Python's standard library; Python is not an app/runtime dependency. For a private local regression PDF, set `SICKPDF_COMPATIBILITY_PDF` before running `flutter test test/pdf_split_compatibility_test.dart`. Do not commit private PDFs.

Split reuses the installed `pdfrx`/PDFium engine: `PdfDocument.openFile` reads local paths, `createNew` plus the `pages` setter selects pages, and `encodePdf` assembles a standalone document. The existing `pdf_combiner` merge engine is unchanged; it does not expose PDF page-range extraction. The installed `pdfrx`, `pdfrx_engine`, and `pdfium_flutter` packages use MIT licenses, compatible with reuse in this app provided required notices are retained. PDFium and its bundled third-party components have their own redistribution notices; retain these when distributing native binaries. No new packages, permissions, runtime downloads, or network calls were added for splitting.

Source/output native documents are disposed in finally blocks. Split creates no temporary output files, and the preview widget owns its document lifecycle. Extracted bytes are retained in memory for preview and the native save picker, so very large outputs can still exhaust memory. Picker-managed source cache remains under the picker/OS lifecycle; do not clear it globally while Merge may still reference selected files.

### Android split checks

Use local files in airplane mode. Check 2–5 of a ten-page PDF, first/last single pages, and the full range; confirm the saved PDF page count, content, and order in another viewer. Check zero, blank, fractional, reversed, and too-large ranges. Change a range/input after splitting and verify Preview/Save disappear until splitting again. Cancel selection and saving, retry saving, rename the output, and test unavailable destinations/low storage. Try empty, corrupt, password-protected, and large inputs. Return from preview and leave the screen during processing. Finally repeat the existing select/reorder/merge/preview/save flow. Physical Android smoke testing confirmed Home opens the real Split screen and Select PDF opens the system document picker. End-to-end extraction, preview rendering, saving, and airplane-mode operation still need physical-device validation.

### Split still shows Coming Soon

Rebuild before installing. Editing Dart source does not update an already-built APK. A stale-build incident was confirmed by matching the installed APK hash to an artifact built before Split existed. From the project root, run `flutter build apk --debug`, then install the newly generated `build/app/outputs/flutter-apk/app-debug.apk` with `adb install -r build/app/outputs/flutter-apk/app-debug.apk` (or use `flutter run -d <device-id>`). Keep the existing app installed to preserve app data. Current Home navigation opens the real Split screen; the coming-soon fallback applies only to unfinished tools.

## Validation and development

```sh
flutter analyze
flutter test
flutter build apk --debug
```

Tests cover home navigation, initial split controls, page-range validation, real local extraction from a synthetic PDF (inclusive order, single-page/full ranges, and source preservation), invalid input, and existing merge validation for insufficient/empty inputs and overwrite protection. They do not prove real native merging, preview rendering, or saving on a phone. Manually check valid, corrupted, password-protected, and large PDFs; cancellation; repeated operations; page order; preview return; save failures; and airplane mode.

Keep changes incremental. Preserve the application ID and signing configuration, avoid broad storage permissions, and keep PDF processing separate from UI code. Do not introduce remote uploads or telemetry. Do not commit private PDFs as test fixtures.

## Limitations

- Compress PDF, Organize Pages, Image to PDF, and Sign PDF are **coming soon**, not working tools.
- Tools and Settings tabs are placeholders; recent-file history is not persisted.
- Output bytes are held in memory for preview/save. Very large documents may exhaust device memory.
- Native operations have no cancellable timeout; a stalled native call may leave processing active.
- Some damaged, encrypted, or unsupported PDFs cannot be merged. Error handling does not eliminate native-engine crash risk.
- Merge save feedback initiated from preview appears on the merge screen after returning; Split shows feedback in both places.
- Accessibility text scaling, lifecycle interruption, and all supported file variants need further physical-device testing.
- Current picker/merge dependencies emit a future Kotlin Gradle Plugin compatibility warning on Android builds.

## Dependencies and licensing

The principal packages are `file_picker` (document selection/save), `pdf_combiner` (local merging), and `pdfrx` (local preview and page extraction). Versions are recorded in `pubspec.lock`. Review each package's license and bundled native-library notices before redistribution; this README does not grant a license to third-party code. No project-wide license has been selected yet.

## Planned work

Additional PDF tools, persistent recent files, improved large-document handling, and broader Android/iOS reliability testing are planned rather than released features.
