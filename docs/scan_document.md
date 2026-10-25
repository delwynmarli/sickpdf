# Scan Document

## What it does

Scan Document captures paper pages with the camera and turns them into a
single multi-page PDF. It is the counterpart of OCR PDF: OCR PDF *reads* a
scan that already exists, Scan Document *creates* one.

The workflow is:

1. Open the camera (the permission is requested at this point, not at
   launch).
2. Capture one or more pages.
3. Review them — reorder, remove, retake, or crop.
4. Export the pages as one PDF, then preview, save, or share it.

Everything happens on the device. No scan is uploaded, and no network
permission exists in the app.

## Dependencies

| Item | Value |
|---|---|
| Package | `camera` |
| Version | `0.12.1` |
| Transitive package | `camera_android_camerax` `0.7.6` |
| Package | `image_cropper` |
| Version | `13.0.0` |
| Transitive package | `image_cropper_platform_interface` `9.0.0` |
| Native library | `com.github.Yalantis:ucrop:2.2.11` (JitPack) |

Both packages are compatible with the project's pinned toolchain (Flutter
3.47.7, Dart 3.13.5): `camera` requires Dart `^3.12.0` / Flutter `>=3.44.0`
and `image_cropper` requires Flutter `>=3.47.0`.

`permission_handler` was considered and **rejected**: its Android
implementation (`permission_handler_android` 14.1.0) sets
`compileSdk = 37`, while this app and its CI install `android-36`. The
`camera` plugin requests the camera permission itself, so a separate
permission plugin is not needed.

## How the pieces fit together

| File | Responsibility |
|---|---|
| `lib/services/scan_document_service.dart` | The `ScanPage` model and the ordered `ScanPageList` |
| `lib/services/scan_camera_gateway.dart` | The `ScanCameraGateway` seam over the `camera` plugin |
| `lib/services/scan_crop_service.dart` | The `ScanCropService` seam over the `image_cropper` plugin |
| `lib/services/scan_image_processor.dart` | Decoding, downscaling, edge detection, cropping |
| `lib/services/scan_service.dart` | Orchestrates capture → crop → export |
| `lib/screens/scan_document_page.dart` | The screen |

The seams exist so the screen can be tested without hardware. The widget
tests inject a fake gateway, a fake cropper, and a fake exporter.

### Ownership of temporary files

Each component owns the files it creates and deletes them itself:

- The camera gateway reads the photo the camera wrote into the app cache and
  deletes that file before it returns. The bytes then live in memory only.
- The crop service writes the page to a temporary file for the editor, and
  deletes both that file and the editor's output.

Nothing outside the app's own storage is written, and no scan is kept on
disk after the PDF has been built.

## Memory: decoding at a reduced scale

A phone camera capture is easily 12 MP. Decoding that at full resolution and
*then* downscaling to the 2000 px page limit would allocate the whole bitmap
first, which is the peak that matters on a low-RAM device.

`scan_image_processor.dart` therefore sniffs the JPEG header with
`JpegDecoder.startDecode`, which reads only the frame header and allocates no
pixels. It then asks `JpegDecoder(scale: n)` to decode at 1/2, 1/4 or 1/8 in
the **DCT domain**, so the full bitmap is never materialised. A 4000×3000
capture decodes straight to 2000×1500.

| Detail | Behaviour |
|---|---|
| Scale selection | Largest of 8, 4, 2 that still leaves the longest edge at or above the 2000 px limit, so the later resize is a small downscale and never an upscale. |
| Supported formats | JPEG only. `JpegDecoder` accepts `scale` of 1, 2, 4 or 8 and nothing else. |
| Fallback | Any other format (PNG, …), any unreadable header, and any JPEG the scaled path rejects go through `img.decodeImage` exactly as before. |
| Pixel limit | Unchanged. `Decoder.defaultMaxPixels` is **not** raised. |
| EXIF orientation | Preserved. `JpegImageWriter` bakes the orientation into the decoded rows and clears the tag, so `applyOrientation` is a no-op for JPEGs and still correct for other formats. |
| Crop coordinates | Unaffected. The quad is computed on the already-decoded page, so the scale factor never enters the crop maths. |
| Quality | Unchanged: JPEG q88 at up to 2000 px, same as before. |

**Remaining peak-memory limitation.** The scaled path removes the
full-resolution bitmap, but three smaller peaks remain, none of which this
change can remove with the `image` package as it stands:

1. **Non-JPEG input still decodes fully.** Only the camera's JPEG output uses
   the fast path. A PNG handed in through the crop editor's output (the editor
   is configured for JPEG, so this is not expected) would take the general
   path.
2. **The page bitmap is still held while it is re-encoded.** A 2000 px page is
   about 4.6 MP, roughly 14 MB at 3 bytes per pixel, and it exists twice for a
   moment: once as the decoded image and once as the encoded JPEG buffer.
3. **Several pages are held at once.** Pages are kept in memory as encoded
   JPEG for the whole session so they can be reordered and re-cropped. Ten
   pages at ~400 KB each is about 4 MB, which is fine; the bitmap peak, not the
   encoded peak, is the one to watch.

The detection pass adds one more transient: the 480 px downscale is decoded
from the already-scaled page bytes, so it is small by construction.

## Camera preview sizing

The preview frame uses the camera's own reported ratio instead of a fixed 3:4
assumption. `ScanCameraGateway.previewAspectRatio` derives it from
`CameraValue.previewSize`, inverting it in portrait to match what
`CameraPreview` does internally, and returns `null` when the value is not
available yet. The screen falls back to 3:4 only for that unknown state, and
ignores implausible values rather than letting them collapse the layout.

## Lifecycle and the native crop editor

The `camera` plugin's README states that **lifecycle changes are no longer
handled by the plugin** as of 0.5.0, and that apps are responsible for
controlling camera resources. The native crop editor pauses the activity while
it is open, so without handling, the preview would come back dead.

`ScanDocumentPage` is now a `WidgetsBindingObserver`:

| State | Action |
|---|---|
| `inactive`, `paused`, `hidden`, `detached` | Close the camera once, and remember to reopen it. |
| `resumed` | Reopen the camera once, but only if it was released by a background transition. |

This avoids competing disposal in three ways: the release is idempotent
(guarded by `_cameraOpen`), the reopen uses a dedicated path that does not
touch the `_capturing` busy flag, and `dispose()` remains the single owner of
the final teardown. Captured pages live in the screen's state, so they survive
the round trip.

## Edge detection and perspective correction

Automatic detection is a **best-effort Sobel pass**, not a dedicated
document-scanning engine:

1. The page is downscaled so its longest edge is 480 px.
2. A Sobel gradient pass finds the strong edges.
3. The bounding box of those edges, and the extreme points along each of its
   sides, become the page corners.
4. The page is cropped to that box.

The detector is deliberately conservative. It reports "no document" when
the edge box covers less than 12 % or more than 99.5 % of the frame, when
too few edge pixels are found, or when the box is degenerate. On a plain
desk this finds the page reliably; on a cluttered desk it usually does not.

**When detection fails, the user is not stuck.** The screen opens the manual
crop editor (`image_cropper` / UCrop) instead, and the crop button on every
page reopens it.

Perspective is corrected by the crop editor's own transform when the user
drags the corners. There is no separate dewarp step.

## Permissions

`CAMERA` is the only permission the feature needs, and it is requested when
the user opens the camera.

The `camera` plugin's manifest also declares `RECORD_AUDIO`,
`WRITE_EXTERNAL_STORAGE`, and (implied by the merger) `READ_EXTERNAL_STORAGE`.
sickPDF records no audio and writes scans only to its own app-private cache,
so all three are removed again in `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" tools:node="remove" />
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" tools:node="remove" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" tools:node="remove" />
```

`android.hardware.camera.any` is marked `required="false"` so the app stays
installable on devices without a camera; every other tool works there.

Verified on the built APKs with `aapt2 dump permissions`:

```
package: com.sickpdf.sickpdf
uses-permission: name='android.permission.CAMERA'
permission: com.sickpdf.sickpdf.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION
uses-permission: name='com.sickpdf.sickpdf.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION'
```

The `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` entry comes from
`androidx.core` and is a signature-level permission of the app itself, not
a system permission. There is **no** `INTERNET` or `ACCESS_NETWORK_STATE`
permission in either the debug or the release APK, so the release-validation
workflow's permission check still passes.

## Error handling

| Situation | Behaviour |
|---|---|
| Permission denied | The screen explains that the camera permission must be enabled in the app settings, and offers to try again. |
| No camera on the device | Reported as "No camera was found on this device." |
| Camera busy or fails to start | Reported with a "close other apps that use it" hint. |
| Unreadable or empty capture | The page is rejected; existing pages are kept. |
| Crop editor cancelled | The page is left exactly as it was. |
| Crop editor fails | The failure is reported; the page is kept. |
| Export fails | The specific reason (for example "Not enough memory") is shown, not a generic message. |
| Low storage | The underlying failure is surfaced through the export error path. |

The camera controller is disposed when the screen is closed, and the export
button is disabled while a run is active, so a second tap cannot start a
second export.

## Size impact

Measured on this machine with
`flutter build apk --release --target-platform android-arm64`:

| Build | Size |
|---|---|
| Release APK, arm64, before Scan Document | 61.4 MB |
| Release APK, arm64, with Scan Document | 63.6 MB |
| **Scan Document cost** | **~2.2 MB** |

## Verification

Automated (run on this machine):

- `flutter pub get` — resolves.
- `flutter analyze` — no issues.
- `flutter test` — all tests pass (170 before hardening; the hardening adds
  24 more, all green).
- `flutter build apk --debug` — builds.
- `flutter build apk --release --target-platform android-arm64` — builds, so
  R8 does not break on the new dependencies.
- `aapt2 dump permissions` on both APKs — only `CAMERA` was added.

The tests cover:

- **Memory / decoding** — the DCT scale chooser (no reduction, 1/2, 1/4, 1/8,
  degenerate dimensions, never an unsupported value), scaled decode producing
  fewer pixels than a full decode, aspect-ratio preservation, non-JPEG input
  returning `null` so it falls back, corrupt headers, and a large capture
  downscaling to the page limit with its aspect ratio intact.
- **Preview sizing** — the frame adopts the camera-reported ratio, falls back
  to 3:4 when the ratio is unknown, and ignores an implausible ratio without
  throwing.
- **Lifecycle** — a background transition releases the camera exactly once, a
  resume reopens it exactly once, a resume with no prior release does nothing,
  a release before the camera ever opened is a no-op, and captured pages
  survive a full background round trip.

- `test/scan_service_test.dart` — page ordering, removal, replacement, and
  range checks; decoding, downscaling, cropping, and edge detection;
  capture, crop, and export error mapping.
- `test/scan_widget_test.dart` — the home tile opens the real screen; the
  camera opens; pages are captured, reordered, removed, retaken, and
  cropped; a cancelled crop keeps the page; a denied permission and a
  failed capture show actionable errors; a failed export shows the specific
  reason; a second export tap cannot start a second export; the camera is
  released when the screen closes.

**Not verified on a physical device.** The camera preview, the runtime
permission prompt, the crop editor's appearance and interaction, and the
capture-to-PDF round trip still need a real device. See
[Manual device checks](#manual-device-checks).

## Manual device checks

Still required before this is considered device-verified:

1. Install the debug APK and open **Scan Document**.
2. Confirm the camera permission prompt appears only when the camera is
   opened, and that denying it shows the settings hint.
3. Grant the permission and confirm the live preview appears and is
   correctly oriented in portrait and landscape.
4. Capture a page of text on a plain desk. Confirm the page is cropped to
   the paper automatically.
5. Capture the same page on a cluttered desk. Confirm the manual crop
   editor opens and that dragging the corners works.
6. Capture three pages, reorder them with the arrows and the drag handle,
   remove one, and retake another. Confirm the list matches.
7. Export to PDF. Confirm one page per sheet, the correct order, and that
   the text is legible.
8. Preview, save to a device location, and share. Confirm both work.
9. Confirm the app has no network access: disable Wi-Fi and mobile data and
   repeat a full scan.
10. Confirm the app cache does not accumulate scan images after the session.
