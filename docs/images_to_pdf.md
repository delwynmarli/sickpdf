# Convert Images to PDF

## Summary

Turns one or more selected images into a multi-page PDF with exactly one image
per page, in the order the user chose. All processing is local and offline; the
source images are never modified. A default filename of `images_to_pdf.pdf` is
offered and can be renamed before saving.

## Technology

Reuses the app's existing dependencies and patterns:

- `file_picker` for selecting multiple images (`withData: true`, custom
  extensions `jpg`, `jpeg`, `png`) and for the save destination.
- The existing `sickpdf/share` `MethodChannel` for sharing.
- The existing `PdfOutputPreview` screen for preview and save.
- PDFBox (`com.tom-roush:pdfbox-android`, already bundled by `pdf_combiner`) in
  the Android layer to build the PDF, following the same
  Dart-service → `MethodChannel` → Kotlin-object pattern used by Sign PDF,
  Add Text and Page Numbers.

No new package, permission, network call, account, analytics or cloud
dependency was added.

## Architecture

- `lib/services/pdf_image_to_pdf_service.dart` — page-size, margin and fit
  math (pure Dart, unit tested), selection validation, and the
  `MethodChannel('sickpdf/images')` bridge with error mapping. Layout logic is
  kept out of the UI.
- `lib/screens/images_to_pdf_page.dart` — selection list with thumbnails,
  filenames, drag-and-drop plus arrow reordering, per-image removal, options,
  progress, preview, save and share. An `ImageSelection` value type owns the
  ordering rules and is unit tested.
- `android/app/src/main/kotlin/com/sickpdf/sickpdf/PdfImageConverter.kt` —
  builds the PDF with PDFBox. Runs on a dedicated single-thread executor so
  duplicate conversion jobs cannot overlap.
- `MainActivity.kt` registers the `sickpdf/images` channel.

## Page geometry

- Page size: `A4` (default), `Original image proportions`, `US Letter`, or
  `Square`. A4/Letter follow the image orientation (portrait vs landscape);
  original uses one point per pixel; square uses a fixed side.
- Margin: none / small (18 pt) / medium (36 pt) / large (54 pt). Default small.
- Fitting: `Contain` (default, never crops), `Cover` (fills the page, may crop
  the edges), `Stretch` (fills exactly, may distort). The default never crops.
- The content box is clamped so a large margin cannot push the image off-page.

## Image orientation and memory

- EXIF orientation is read from the JPEG bytes by a small, dependency-free
  parser (PNG has no EXIF orientation and keeps its natural orientation). The
  effective width/height and a rotation/mirror transform are applied so phone
  photos are not rotated or cropped.
- Each image is decoded once and drawn immediately, keeping peak memory close
  to a single decoded bitmap regardless of how many images are selected. JPEGs
  are embedded without re-encoding, so quality is preserved.
- Decoding/embedding failure maps to a clear message naming the image position.

## Safety and cleanup

- The PDF is returned as bytes to Dart; the UI previews and saves them through
  the existing picker. No application-owned temporary files are created for the
  conversion, so there is nothing to clean up and no risk of deleting user
  files. The share channel writes only into the app cache directory, as it
  already does for other tools.
- Any edit (add, remove, reorder, option change, rename) invalidates the
  previous result so a stale PDF is never saved.

## Automated verification

- `flutter analyze`: no issues.
- `flutter test`: all tests pass, including new Image to PDF coverage and all
  existing suites.
- New Dart tests cover page-box sizing (A4 portrait/landscape, original,
  square, degenerate sizes), margin presets, contain/cover/stretch rectangles,
  empty-selection and empty-image validation, `ImageSelection` ordering and
  bounds, option pass-through, and navigation from the home tile.
- Native `PdfImageConverterTest`: 9 tests, 0 failures (5 skipped in plain JVM
  because PDFBox image decode needs Android `android.graphics`; those run on a
  device/emulator). The validation tests (empty selection, empty bytes,
  negative margin, non-positive square side) run everywhere.

## Required manual Android tests

Physical-device behaviour was not verified in this environment.

1. Select several JPEG and PNG photos and confirm thumbnails and page order.
2. Drag and use arrows to reorder; remove one image; convert.
3. Confirm one image per page in the chosen order, correct EXIF orientation,
   and no unintended cropping with the default `Contain` fit.
4. Try A4, original, letter and square; try each margin and the cover fit.
5. Preview, then save as `images_to_pdf.pdf` and confirm the originals are
   unchanged; then share.
6. Confirm large photos and many images do not crash or exhaust memory.
7. Confirm corrupted/unsupported/empty selections show clear messages.

## Limitations

- Only JPEG and PNG are offered; other formats are excluded because reliable
  local decoding is not guaranteed.
- Cover and stretch can crop or distort by design.
- Very large selections are bounded only by device memory; a per-image decode
  strategy keeps peak usage low but this is not a hard guarantee on all devices.
