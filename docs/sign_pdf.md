# Sign PDF

## Overview

Sign PDF lets the user draw a signature and place it on a chosen page of a
local PDF. Everything runs offline on the device: no network calls, no uploads,
and the source file is never modified.

## Architecture

The feature mirrors the existing tools (Watermark, Page Numbers, Protect,
Unlock):

- `lib/services/pdf_sign_service.dart` — options model, validation, and a
  `MethodChannel('sickpdf/sign')` bridge. Errors are mapped to short, safe
  English messages.
- `android/.../PdfSigner.kt` — PDFBox-based embedder.
- `android/.../MainActivity.kt` — registers the `sickpdf/sign` channel on a
  single-thread worker and the `sickpdf/share` channel.
- `lib/widgets/signature_pad.dart` — signature canvas with clear and PNG export.
- `lib/screens/sign_pdf_page.dart` — the workflow screen, reusing the existing
  file picker and `PdfOutputPreview`.
- `lib/main.dart` — the home screen tile now opens the real workflow.

## How the signature is embedded

The drawn strokes are captured to a transparent-background PNG in memory
(`PictureRecorder` → `toImage` → PNG). Strokes are rendered with quadratic
smoothing so the exported image matches the on-screen ink.

On Android, `PdfSigner` loads the document with PDFBox, decodes the PNG into a
lossless image XObject with `PDImageXObject.createFromByteArray`, and appends a
content stream to the target page using `PDPageContentStream` in `APPEND` mode.
Only the signature image is added:

- Existing page content is not rasterized; vector art, text and embedded images
  are preserved.
- Page media box, dimensions and orientation are unchanged.
- Other pages are untouched.
- The PNG alpha channel provides the transparent background.

Position and size are sent as fractions of the page media box
(`widthFraction`, `heightFraction`, `offsetXFraction`, `offsetYFraction`), so
placement scales consistently across page sizes. Six anchors are offered:
bottom right/left/center, top right/left, and center.

## Output

The output is a new file, defaulting to `<source>_signed.pdf`. The source file
is only read; it is never overwritten. The user can preview the result with the
existing PDF viewer, save it through the existing file picker, or share it with
other apps on the device via a `FileProvider` (`ACTION_SEND`). Sharing is local
and does not use the network.

## Error handling

- Empty/cancelled selections and picker failures are handled and retryable.
- Empty signature and invalid page/size/opacity values are validated in Dart
  and again natively before any work is done.
- Password-protected documents: the page-count probe detects
  `PdfPasswordException` and asks the user to unlock the file first with the
  existing Unlock PDF tool.
- Damaged, empty or unsupported PDFs surface a short message without leaking
  engine details.
- A single busy flag prevents duplicate processing.

## Native API details

`PDImageXObject.createFromByteArray` in pdfbox-android decodes images through
`android.graphics.Bitmap`, so image embedding only works on a real device or
emulator, not in plain JVM unit tests. The JVM tests therefore cover the
deterministic validation and failure paths, and the image-embedding assertions
are guarded so they run only where Android graphics are available.

## Automated verification

- `flutter analyze`: no issues.
- `flutter test`: all tests passed, including the new Sign PDF service and
  widget tests and all existing suites.
- `android/.../PdfSignerTest.kt`: validation and failure paths pass on the JVM.
- No physical-device test was performed for this change.
