# Compress PDF

## Diagnosis

The original implementation only called pdfrx's full non-incremental PDFium save. It could compress eligible unfiltered streams and remove obsolete incremental revisions, but did not resize images, JPEG-recompress existing images, explicitly remove metadata, or deduplicate resources. Already compressed image streams therefore often changed by only a few bytes. The original UI exposed only lossless optimization, not three functioning quality presets.

Byte accounting was correct: original file length and encoded output byte length, with `(original - output) / original * 100`. Unit formatting is display-only. The reported user's original PDF was not supplied, so its particular four-byte result was not independently reproduced.

## Technology and presets

Retains pdfrx 2.6.5 / pdfrx_engine 0.6.1 and its existing PDFium native library. Uses the public exclusive native-document callback while the engine worker is suspended. Image editing runs in a separate Dart isolate, processing images sequentially. No second PDF engine, page rasterization, platform channel, backend, runtime download, permissions, or tracking was introduced.

Existing transitive packages are now declared direct dependencies (no version upgrades): pdfium_dart 0.3.1 (native editing bindings), ffi 2.2.0 (scoped native allocations/callbacks), image 4.12.0 (local resizing and JPEG encoding).

- Low: lossless full-document rewrite; leaves all image pixels unchanged.
- Medium (screen default): eligible image objects downsampled toward 150 dpi, JPEG quality 80.
- High: eligible image objects downsampled toward 100 dpi, JPEG quality 55.

Resolution comes from each image object's transform in PDF points; aspect ratio is retained, images are not upscaled, and tiny resize differences are avoided. JPEG replacement occurs only if its actual stream bytes are smaller than the existing stream. Medium/High introduce lossy image artifacts; they do not alter text or vector objects. Overall output can still grow because of PDF structure overhead, which the UI reports honestly. The UI also reports the number of recompressed image objects.

Edits replace eligible image data on existing top-level page objects, regenerate only changed page content, and then save the original document (not a new page-import document). Form XObject images are explicitly not edited because PDFium did not persist that mutation in testing. This retains page transforms, order, dimensions and document structures rather than reconstructing a raster PDF. Reopened outputs are checked for page count and dimensions. No guaranteed metadata stripping, unused-resource elimination, or deduplication is claimed.

## Conservative limits

Only top-level, opaque DeviceRGB 24-bit images are eligible. Transparent objects, alpha bitmaps, grayscale/mask images, CMYK/ICC/other color spaces, marked-content images, images inside Form XObjects, images smaller than 64 pixels on either side, and images over 16 megapixels are left unchanged. This intentionally limits coverage to avoid unsafe conversions. Large scanned PDFs can therefore still receive little benefit when their image representation is unsupported. Repeated/shared image resource and complex document compatibility need real-world validation.

Full-document encoding and mobile preview/save still retain output bytes in memory. Input is limited to 64 MiB, and per-image processing is bounded, but this is not a guarantee against memory exhaustion on all devices. Native calls and callbacks are scoped and document handles are disposed in finally blocks. No application-owned temporary output files are created. Source files are never rewritten during optimization. Picker-owned cache is not globally cleared while other tools may use it.

Rewriting invalidates digital signatures; the UI warns against processing signed PDFs. Password-required documents fail gracefully, and security is not intentionally removed. Complex forms, tags, attachments and unusual PDF features require representative compatibility testing; basic output reopening is not proof of every PDF semantic property.

## Actual measured results

Generated deterministic local fixtures, measured from actual file/output bytes on the Windows test host. All outputs reopened and rendered successfully. Negative reduction means growth.

| Input | Preset | Original bytes | Output bytes | Reduction | Images changed |
|---|---|---:|---:|---:|---:|
| Repetitive unfiltered text/vector content | Low | 32,790 | 995 | 96.9655% | 0 |
| Same text | Medium | 32,790 | 995 | 96.9655% | 0 |
| Same text | High | 32,790 | 995 | 96.9655% | 0 |
| Oversized 1600x1600 JPEG, quality 98 | Low | 1,927,157 | 1,927,228 | -0.0037% | 0 |
| Same oversized JPEG | Medium | 1,927,157 | 99,427 | 94.8407% | 1 |
| Same oversized JPEG | High | 1,927,157 | 34,357 | 98.2172% | 1 |
| Small 200x200 JPEG, quality 35 | Low | 6,076 | 6,147 | -1.1685% | 0 |
| Same optimized JPEG | Medium | 6,076 | 6,147 | -1.1685% | 0 |
| Same optimized JPEG | High | 6,076 | 6,147 | -1.1685% | 0 |

The text fixture is deliberately repetitive and uncompressed, not representative of already optimized office PDFs. The JPEG fixture contains selectable text and a link annotation, both verified after every preset. Lower quality output is intentionally not pixel-identical. Existing lossless fixture tests continue to assert identical rendered pixels and unchanged source bytes.

## Automated verification

- flutter analyze: no issues.
- flutter test: all 29 tests passed, including existing Merge, Split and Organize coverage.
- New tests verify distinct preset parameters, measured file/output sizes, actual large JPEG reduction, optimized-image no-replacement behavior, successful reopening/rendering, selectable text, link annotation survival, page dimensions, and original preservation.
- Existing compression tests cover missing, empty, damaged, oversized and password-required inputs and signed size metrics (including growth).
- git diff --check passed; Git emitted only its existing line-ending conversion notice for the lockfile.

No Android build, emulator, or physical-device test was performed.

## Required manual Android tests

1. In airplane mode, run all presets on photographic scans and text PDFs; inspect fine print, color, page order, links and image artifacts in the preview and an independent reader.
2. Check representative nested images, transparency, CMYK/ICC, shared resources, tagged documents and forms. Confirm unsupported images remain intact, not blank or recolored.
3. Save with edited filenames through the system picker, cancel and retry, and test filename collisions/full destinations. Verify reported output length equals saved file length and originals remain unchanged.
4. Try encrypted, damaged, near-limit and large-image PDFs on a low-memory device. Navigate back during processing and repeat to check cleanup and responsiveness.
5. Recheck Merge, Split, Organize, preview and saving end to end.
