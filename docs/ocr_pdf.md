# OCR PDF

## What it does

OCR PDF reads a PDF that has no usable text layer — a scan, a photo of a
document, or a mixed file — and exports the recognized text as a plain
`.txt` file.

The MVP is deliberately narrow:

- The output is **plain text (TXT)**, not a searchable PDF. Adding an invisible
  text layer back into the PDF is a separate follow-up feature.
- Pages are marked with `--- Page N ---` separators so the boundaries stay
  visible. The original layout, columns, and tables are **not** reconstructed.
- Line breaks inside a page are kept where the recognizer reports them.

## Engine and offline behaviour

| Item | Value |
|---|---|
| Package | `google_mlkit_text_recognition` |
| Version | `0.17.1` (pinned exactly) |
| Transitive package | `google_mlkit_commons` `0.13.0` |
| Native library | `com.google.mlkit:text-recognition:16.0.1` |
| Script | Latin (`TextRecognitionScript.latin`) |

The Latin model ships **inside the APK**. This was verified by inspecting the
built `app-debug.apk`: the archive contains the Latin line-recognition model
(`assets/mlkit-google-ocr-models/gocr/gocr_models/line_recognition_legacy_mobile/Latn_ctc/...`,
about 650 KB of assets) and the native pipeline
(`lib/<abi>/libmlkit_google_ocr_pipeline.so`). Nothing is downloaded at first
use, so OCR works offline immediately after installing the app, with no
Play Services model download and no network permission.

### Size impact

Measured on this machine with
`flutter build apk --release --target-platform android-arm64`:

| Build | Size |
|---|---|
| Release APK, arm64, **with** OCR | **61.4 MB** |
| Release APK, arm64, **without** OCR (dependency removed, engine stubbed) | **31.3 MB** |
| **OCR cost** | **~30 MB** |

The debug APK carries all three ABIs, so it is only a rough reference:
`app-debug.apk` went from 220.7 MB to 254.5 MB.

Inside the 61.4 MB arm64 release APK:

| Entry | Size |
|---|---|
| ML Kit entries (26 files: model assets + native pipeline) | 29.5 MB |
| `lib/arm64-v8a/libmlkit_google_ocr_pipeline.so` | 10.6 MB |
| `lib/arm64-v8a/libflutter.so` | 11.2 MB |
| `lib/arm64-v8a/libapp.so` | 7.1 MB |
| `lib/arm64-v8a/libpdfium.so` | 6.1 MB |

The remaining `armeabi-v7a` and `x86_64` ML Kit libraries are also present in
the APK even though the build targeted arm64. A split-per-ABI build
(`--split-per-abi`) would drop them from an individual device's download.

### Release build: R8 keep rules

The release build **fails without** `android/app/proguard-rules.pro`. The ML
Kit plugin's Kotlin code references the option classes of the Chinese,
Devanagari, Japanese and Korean models, but the plugin only ships the Latin
model, so R8 reports those classes as missing and aborts the build:

```
ERROR: R8: Missing class com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
       (referenced from: com.google_mlkit.vision.text.TextRecognizer
       com.google_mlkit_text_recognition.TextRecognizer.initialize(...))
```

`android/app/proguard-rules.pro` suppresses those specific warnings with
`-dontwarn`. The classes are only reached from branches sickPDF never takes:
the plugin picks the recognizer from the script index, and sickPDF always asks
for `TextRecognitionScript.latin`. The debug build is unaffected because R8
does not run there, so **a debug build alone does not prove a release build
works**. Verify both after changing OCR dependencies.

The rules are scoped to exactly the four missing script packages. The Latin
package is deliberately not suppressed, so a genuinely missing Latin class
would still fail the build. The file itself documents which classes the rules
cover and when they should be revisited — in short: when the OCR dependency is
upgraded, when a non-Latin script is ever enabled (delete that script's rule),
or when the OCR engine is replaced (delete the file).

To keep this honest, `.github/workflows/release-validation.yml` builds the
release APK on every push and pull request, so a change in this area cannot
silently break the release build.

The dependency requires Dart `^3.12.0` and Flutter `>=3.44.0`. The project
runs on Dart `3.13.5` / Flutter `3.47.7`, so no toolchain upgrade was needed.

Only `google_mlkit_text_recognition` was added. The umbrella
`google_ml_kit` package was deliberately not used, and the Chinese,
Devanagari, Japanese, and Korean models were not enabled — the app only
claims Latin-script recognition.

## How a page is processed

1. The file is validated: it must exist, be non-empty, and parse as a PDF.
2. The page is opened with `pdfrx`/PDFium.
3. The page's own text layer is read first. If the page already carries
   extractable text, that text is used and **the page is not rendered and not
   sent through OCR**. This keeps mixed documents correct and avoids
   needlessly recognizing pages that already have text.
4. A page without a text layer is rendered once, at `2.0x` the PDF's own point
   size (roughly 144 dpi for A4). The rendered bitmap is capped at 3 megapixels
   so a large page cannot blow up the heap.
5. The rendered pixels are converted to NV21 in memory and passed to ML Kit.
   No temporary image file is written, so nothing about the document is left
   on disk.
6. The recognized text is collected in page order.

Pages are processed **sequentially**. Only one page bitmap is held at a time:
the native render buffer is copied, freed, and the copy goes out of scope as
soon as the page is recognized.

## Output

- File name: `<original name>_ocr.txt`. The suffix always differs from the
  source, so the original PDF can never be overwritten.
- Encoding: UTF-8.
- Location: the app's own documents directory. The user can then save a copy
  elsewhere through the system document picker or share it.
- If a file with the same name already exists, a numbered variant is written
  (`report_ocr (2).txt`). An existing output is never silently replaced.

## Network permissions and telemetry

The ML Kit dependency pulls in Google's **datatransport** CCT backend, which
collects usage events (`FIREBASE_ML_SDK`) and uploads them when a network is
available. On the first device run this was observed directly in logcat:

```
D/TransportRuntime.SQLiteEventStore: Storing event with priority=VERY_LOW,
   name=FIREBASE_ML_SDK for destination cct
```

and the app gained `INTERNET` and `ACCESS_NETWORK_STATE` permissions plus a
`com.google.android.datatransport.events` database. That contradicts sickPDF's
"files are never uploaded, no telemetry" promise, so both manifests now undo
it:

- `tools:node="remove"` on the `TransportBackendDiscovery` service removes the
  CCT uploader from the merged manifest.
- `tools:node="remove"` on `INTERNET` and `ACCESS_NETWORK_STATE` strips the
  network permissions the dependency would otherwise add. The debug manifest
  removes them too, so a debug build cannot phone home either.
- `firebase_analytics_collection_deferred` and
  `firebase_analytics_collection_enabled=false` stop the events from being
  queued in the first place.

Verified after the change:

| Check | Result |
|---|---|
| Merged release manifest `uses-permission` | only `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` |
| `TransportBackendDiscovery` in the merged manifest | 0 entries |
| `adb shell dumpsys package com.sickpdf.sickpdf` | no `INTERNET`, no `ACCESS_NETWORK_STATE` |
| logcat after an OCR run | no `Storing event` / `FIREBASE_ML_SDK` lines |

The `datatransport` runtime library still ships inside the APK and still
creates its (now empty) database, because ML Kit loads it internally. What
changed is that the uploader is gone, the app holds **no network permission
at all**, and no telemetry event is recorded. The app therefore cannot make a
network request, whatever a future dependency might try to do.

## Cancellation and failures

- The screen shows `Processing page N of M` and offers a **Cancel** action.
  Cancelling stops scheduling further pages, releases the native recognizer
  and the document, and writes **no** file. A cancelled run is never reported
  as a successful one.
- A page that fails recognition is recorded, marked in the output with
  `[No text recognized on this page]`, and named in the final status message
  (`page 4` and so on). The remaining pages still complete.
- If **no** page produced text, the run fails with a clear message instead of
  writing an empty file.
- Password-protected PDFs are rejected with a message asking for an unlocked
  copy. sickPDF's Unlock PDF tool produces one.

## What is not claimed

- OCR accuracy depends on scan quality, resolution, rotation, contrast, and
  text layout. A skewed or low-resolution scan will produce worse text.
- Only Latin script is supported. Chinese, Japanese, Korean, and Devanagari
  are not enabled, so documents in those scripts will not be recognized
  correctly.
- This tool does **not** create a searchable PDF.
- Only Android is supported and tested. The plugin also has an iOS
  implementation, but this project has not been set up or tested for iOS,
  desktop, or web.
- OCR quality on a physical device has not been verified in this environment.
  See the manual test list below.

## Testing

Automated tests use a fake OCR engine injected through
`PdfOcrService(engineFactory: ...)`, so no native recognizer runs in the test
suite:

- `test/pdf_ocr_service_test.dart` — page order, page separators, line-break
  handling, empty and whitespace-only results, page-level failure handling,
  cancellation and engine cleanup, output filename generation and collision
  handling, invalid/unreadable input, progress updates, the text-layer
  shortcut, and the guarantee that the source file is never modified. It also
  covers the password-protected and corrupt-PDF messages, a mixed
  text/scan document, the marker written on a page with no readable text,
  the rendered page size and pixel buffer handed to the engine, and the
  guarantee that a cancelled job writes no file.
- `test/ocr_widget_test.dart` — the tool tile, the empty state, the selected
  file details, the progress state, the success state, the error state, the
  cancel path, the prevention of duplicate submissions, and the fact that
  the name shown and offered to the save picker is the name of the file that
  was actually written.

A mocked test proves the surrounding behaviour, **not** that the native ML
Kit recognizer produces correct text.

### What was checked against the real PDF engine

These were verified with throwaway probe tests against PDFium itself, not
just against the mock:

- PDFium reports page dimensions **already adjusted for `/Rotate`**, and the
  rendered bitmap size matches the requested size exactly. A rotated page is
  therefore rendered upright without any extra handling.
- The rendered pixels are **BGRA8888** (a solid red page reads as
  `B=0, G=0, R=255, A=255`), which is the order `bgraToNv21` expects, and the
  alpha channel is fully opaque.
- A page with no text layer returns an empty string from
  `loadStructuredText()` rather than throwing, so the OCR path is reached.
- A password-protected PDF raises `PdfPasswordException` and a corrupt file
  raises `PdfException`, and both are mapped to their own messages.

## Physical-device test matrix

Record for each case: device model, Android version, APK build, the source
document used, the observed behaviour, and a screenshot or the exported `.txt`
where it matters.

### What was already verified on a device

The engine itself was exercised on a real device (Xiaomi 22101316G, Android 14
API 34, arm64) with a synthetic 150 dpi two-page Indonesian scan that was
rendered to an image-only PDF, so it has no text layer. The recognized text
came back essentially verbatim, including the deliberately confusable words
`Olah`, `Bangs`, `Industri`, `Dasar` and the `form` / `farm` pair, and the
`--- Page 1 ---` / `--- Page 2 ---` markers were correct. The same run
succeeded with the app's data cleared and the device in airplane mode, which
confirms the model is bundled and the first run needs no network.

That is a **synthetic** scan, so it does not cover real scanner output, skew,
noise, or a real low-contrast page. The cases below are still open.

### A. Clean, high-resolution Indonesian scan

- **Setup**: a 300 dpi A4 scan of a page of clear Indonesian text.
- **Expected**: the TXT contains the page text with correct spelling and
  diacritics, one `--- Page 1 ---` marker, and line breaks matching the
  printed lines. No `[No text recognized on this page]` marker.
- **Evidence**: the exported `.txt` next to the scan, plus a note on any
  misread words.

### B. Rotated or low-contrast scan

- **Setup**: a scan rotated by roughly 5-15 degrees, and a second scan with
  low contrast (light grey text on white).
- **Expected**: the app does not crash and does not hang. The rotated page
  may be recognized poorly — the MVP does not deskew. Low contrast should
  still yield most words. A page with no readable words shows
  `[No text recognized on this page]` rather than a blank section.
- **Evidence**: the exported `.txt` for both scans, and a note on how much
  text was recovered.

### C. Mixed PDF with native text pages and scanned pages

- **Setup**: a PDF where some pages have a real text layer and others are
  scans.
- **Expected**: every page produces text. Text-layer pages are extracted
  directly (their wording is exact); scanned pages are recognized. Page
  order is preserved, so `--- Page 1 ---` is followed by the text of page 1,
  and so on.
- **Evidence**: the exported `.txt`, checked page by page against the source.

### D. First OCR run in airplane mode after a fresh installation

- **Setup**: enable airplane mode, uninstall sickPDF, install the APK, then
  run OCR without ever connecting to a network.
- **Expected**: the first run works immediately. No model download, no
  "downloading model" prompt, no Play Services error, and no network
  permission prompt. The app must not request network access.
- **Evidence**: a screen recording of the first run plus
  `adb shell dumpsys package com.sickpdf.sickpdf | grep -i internet` output
  showing no INTERNET permission is held.

### E. Cancellation during a multi-page job

- **Setup**: a PDF of at least 20 scanned pages. Press **Cancel** while the
  progress counter is still climbing.
- **Expected**: the run stops after the current page. The status says the
  extraction was cancelled, **no** output file is created, and no
  `--- Page N ---` document is left behind in the app folder. The Extract
  button becomes usable again so the job can be restarted.
- **Evidence**: a screen recording, plus a listing of the app documents
  folder before and after.

### F. Larger PDF on a lower-memory Android device

- **Setup**: a device with 2 GB RAM or less, and a 50+ page scanned PDF.
- **Expected**: the job completes without the app being killed. Memory stays
  bounded because pages are processed one at a time. The progress counter
  keeps moving and the UI stays responsive.
- **Evidence**: `adb shell dumpsys meminfo com.sickpdf.sickpdf` sampled
  during the run (record the peak), and confirmation that the app was not
  killed.

### G. Save and Share of the resulting TXT file

- **Setup**: a completed extraction.
- **Expected**: **Save TXT** opens the system document picker and writes a
  `.txt` file that opens correctly in a text editor. **Share** offers the
  file to another app and the receiving app sees the correct name and
  `text/plain` type (not `application/pdf`).
- **Evidence**: a screenshot of the picker with the suggested file name, and
  a screenshot of the share sheet with the target app.

### H. The original PDF remains unchanged

- **Setup**: record the size and a checksum of the source PDF before the run.
- **Expected**: after the run, the source file has the same size and
  checksum. The OCR output is a new file with a different name.
- **Evidence**: `sha256sum` of the source before and after, and a directory
  listing showing both the untouched source and the new `_ocr.txt` file.
