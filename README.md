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

## Validation and development

```sh
flutter analyze
flutter test
flutter build apk --debug
```

Tests cover basic UI presence and service validation for insufficient/empty inputs and overwrite protection. They do not prove real native merging, preview rendering, or saving on a phone. Manually check valid, corrupted, password-protected, and large PDFs; cancellation; repeated merges; page order; preview return; save failures; and airplane mode.

Keep changes incremental. Preserve the application ID and signing configuration, avoid broad storage permissions, and keep PDF processing separate from UI code. Do not introduce remote uploads or telemetry. Do not commit private PDFs as test fixtures.

## Limitations

- Split PDF, Compress PDF, Organize Pages, Image to PDF, and Sign PDF are **coming soon**, not working tools.
- Tools and Settings tabs are placeholders; recent-file history is not persisted.
- Output bytes are held in memory for preview/save. Very large documents may exhaust device memory.
- Native operations have no cancellable timeout; a stalled native call may leave processing active.
- Some damaged, encrypted, or unsupported PDFs cannot be merged. Error handling does not eliminate native-engine crash risk.
- Save feedback initiated from preview appears on the merge screen after returning.
- Accessibility text scaling, lifecycle interruption, and all supported file variants need further physical-device testing.
- Current picker/merge dependencies emit a future Kotlin Gradle Plugin compatibility warning on Android builds.

## Dependencies and licensing

The principal packages are `file_picker` (document selection/save), `pdf_combiner` (local merging), and `pdfrx` (local preview). Versions are recorded in `pubspec.lock`. Review each package's license and bundled native-library notices before redistribution; this README does not grant a license to third-party code. No project-wide license has been selected yet.

## Planned work

Additional PDF tools, persistent recent files, improved large-document handling, and broader Android/iOS reliability testing are planned rather than released features.
