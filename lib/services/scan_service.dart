import 'dart:typed_data';

import 'pdf_image_to_pdf_service.dart';
import 'scan_camera_gateway.dart';
import 'scan_crop_service.dart';
import 'scan_document_service.dart';
import 'scan_image_processor.dart';

/// Raised when a scan cannot be produced.
class ScanException implements Exception {
  const ScanException(this.message);

  /// User-facing explanation of what went wrong.
  final String message;

  @override
  String toString() => message;
}

/// Owns the Scan Document workflow: capture, page preparation, and export.
///
/// The service never writes outside the app's own storage. Temporary files
/// live in the app cache and are removed as soon as their bytes have been
/// read, so a scan does not leave anything behind on the device.
class ScanDocumentService {
  ScanDocumentService({
    ScanCameraGateway? camera,
    ScanCropService? cropper,
    ScanImageProcessor? processor,
    PdfImageToPdfService? exporter,
  })  : _camera = camera ?? PluginScanCameraGateway(),
        _cropper = cropper ?? PluginScanCropService(),
        _processor = processor ?? const ScanImageProcessor(),
        _exporter = exporter ?? PdfImageToPdfService();

  final ScanCameraGateway _camera;
  final ScanCropService _cropper;
  final ScanImageProcessor _processor;
  final PdfImageToPdfService _exporter;

  /// The camera session used to capture pages.
  ScanCameraGateway get camera => _camera;

  /// Opens the camera.
  ///
  /// Throws a [ScanCameraException] when the camera cannot be started, for
  /// example because the permission was denied.
  Future<void> openCamera() => _camera.open();

  /// Releases the camera.
  Future<void> closeCamera() => _camera.close();

  /// Captures one page and returns the prepared page.
  ///
  /// When the document edges can be found, the page is cropped to them.
  /// Otherwise the page is returned uncropped and [needsManualCrop] is true,
  /// so the caller can offer the crop editor.
  Future<ScanCaptureResult> capturePage() async {
    final Uint8List bytes;
    try {
      bytes = await _camera.takePicture();
    } on ScanCameraException {
      rethrow;
    } catch (_) {
      throw const ScanException('The photo could not be taken. Try again.');
    }

    if (bytes.isEmpty) {
      throw const ScanException(
        'The captured page was empty. Try capturing it again.',
      );
    }

    return _prepare(bytes);
  }

  /// Replaces [page] with a manually cropped version.
  ///
  /// Returns `null` when the user cancelled the crop, which means the page
  /// stays as it was.
  Future<ScanPage?> cropPage(ScanPage page) async {
    final Uint8List? cropped;
    try {
      cropped = await _cropper.crop(page.bytes);
    } on ScanCropException catch (error) {
      throw ScanException(error.message);
    }
    if (cropped == null) return null;
    final result = await _prepare(cropped, detectEdges: false);
    return result.page;
  }

  /// Prepares raw image bytes into a page, cropping to the detected document
  /// when one is found.
  Future<ScanCaptureResult> _prepare(
    Uint8List bytes, {
    bool detectEdges = true,
  }) async {
    ScanPage page;
    try {
      page = await _processor.prepare(bytes);
    } on ScanImageException catch (error) {
      throw ScanException(error.message);
    }

    if (!detectEdges) {
      return ScanCaptureResult(page: page, needsManualCrop: false);
    }

    ScanQuad? quad;
    try {
      quad = await _processor.detectDocument(page.bytes);
    } catch (_) {
      // Detection is a convenience. When it fails the page is still usable.
      quad = null;
    }
    if (quad == null) {
      return ScanCaptureResult(page: page, needsManualCrop: true);
    }

    try {
      final cropped = await _processor.crop(page.bytes, quad.bounds);
      return ScanCaptureResult(page: cropped, needsManualCrop: false);
    } catch (_) {
      // A failed crop must not lose the capture; keep the full page.
      return ScanCaptureResult(page: page, needsManualCrop: true);
    }
  }

  /// Turns the captured [pages] into a multi-page PDF.
  ///
  /// The PDF is built by the app's existing image-to-PDF engine, so the
  /// output matches every other tool in the app.
  Future<Uint8List> exportPdf(
    List<ScanPage> pages, {
    ImagePageSize size = ImagePageSize.a4,
    ImageMargin margin = ImageMargin.small,
    ImageFit fit = ImageFit.contain,
  }) async {
    if (pages.isEmpty) {
      throw const ScanException('Capture at least one page before exporting.');
    }
    try {
      return await _exporter.convert(
        images: [
          for (final page in pages)
            PdfImageInput(name: 'scan_${page.width}x${page.height}.jpg', bytes: page.bytes),
        ],
        size: size,
        margin: margin,
        fit: fit,
      );
    } on PdfImageToPdfException catch (error) {
      throw ScanException(error.message);
    } catch (_) {
      throw const ScanException(
        'Could not create the PDF from these pages. Try removing a page and '
        'try again.',
      );
    }
  }

}

/// The result of capturing one page.
class ScanCaptureResult {
  const ScanCaptureResult({required this.page, required this.needsManualCrop});

  /// The prepared page.
  final ScanPage page;

  /// Whether the page was not cropped and the user should be offered the
  /// crop editor.
  final bool needsManualCrop;
}
