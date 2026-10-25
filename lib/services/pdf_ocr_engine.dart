import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// A single rendered page that is ready for on-device recognition.
///
/// [bgra] holds raw pixels in BGRA8888 order, four bytes per pixel, top-down.
/// This is the layout PDFium produces, so the rendered page can be handed
/// over without an intermediate copy. The buffer belongs to the caller of
/// [PdfOcrEngine.recognize] and may be released as soon as recognition
/// returns.
class PdfOcrPageImage {
  PdfOcrPageImage({
    required this.pageNumber,
    required this.width,
    required this.height,
    required this.bgra,
  }) : assert(bgra.length == width * height * 4, 'Pixel buffer size mismatch.');

  /// One-based page number this image was rendered from.
  final int pageNumber;

  /// Pixel width of the rendered page.
  final int width;

  /// Pixel height of the rendered page.
  final int height;

  /// Raw BGRA pixel data, `width * height * 4` bytes long.
  final Uint8List bgra;
}

/// Recognizes text inside a rendered page.
///
/// The engine exists so OCR behaviour can be exercised without the native
/// recognizer: tests substitute a deterministic fake, the app uses
/// [MlKitOcrEngine].
abstract class PdfOcrEngine {
  /// Returns the recognized text, or an empty string when nothing was found.
  Future<String> recognize(PdfOcrPageImage image);

  /// Releases native resources. Must be safe to call more than once.
  Future<void> close();
}

/// Creates an engine for a single extraction run.
typedef PdfOcrEngineFactory = PdfOcrEngine Function();

/// Converts a BGRA8888 buffer into the NV21 layout ML Kit consumes natively.
///
/// NV21 is a full-range YUV 4:2:0 image: a luma plane of `width * height`
/// bytes followed by an interleaved V/U plane of `width * height / 2` bytes.
/// Sending NV21 keeps the page image in a single buffer instead of the extra
/// copies the plugin's bitmap path allocates on the way to a native bitmap.
///
/// [width] and [height] must be even so the chroma plane stays aligned.
Uint8List bgraToNv21(Uint8List bgra, int width, int height) {
  final lumaSize = width * height;
  final out = Uint8List(lumaSize + (lumaSize ~/ 2));
  for (var y = 0; y < height; y++) {
    final rowStart = y * width;
    for (var x = 0; x < width; x++) {
      final source = (rowStart + x) * 4;
      final b = bgra[source];
      final g = bgra[source + 1];
      final r = bgra[source + 2];
      out[rowStart + x] = _clampByte(((66 * r + 129 * g + 25 * b + 128) >> 8) + 16);
    }
  }
  final chromaWidth = width ~/ 2;
  for (var blockY = 0; blockY < height ~/ 2; blockY++) {
    for (var blockX = 0; blockX < chromaWidth; blockX++) {
      var r = 0;
      var g = 0;
      var b = 0;
      for (var dy = 0; dy < 2; dy++) {
        for (var dx = 0; dx < 2; dx++) {
          final source = ((blockY * 2 + dy) * width + blockX * 2 + dx) * 4;
          b += bgra[source];
          g += bgra[source + 1];
          r += bgra[source + 2];
        }
      }
      r = (r + 2) ~/ 4;
      g = (g + 2) ~/ 4;
      b = (b + 2) ~/ 4;
      final chromaIndex = (blockY * chromaWidth + blockX) * 2;
      out[lumaSize + chromaIndex] =
          _clampByte(((112 * r - 94 * g - 18 * b + 128) >> 8) + 128);
      out[lumaSize + chromaIndex + 1] =
          _clampByte(((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128);
    }
  }
  return out;
}

int _clampByte(int value) => value < 0
    ? 0
    : (value > 255 ? 255 : value);

/// On-device text recognition backed by ML Kit.
///
/// Uses the Latin script model that ships inside the APK, so recognition works
/// offline on first use and no page image ever leaves the device. The native
/// recognizer is closed through [close] to free its native resources.
class MlKitOcrEngine implements PdfOcrEngine {
  MlKitOcrEngine({TextRecognizer? recognizer})
    : _recognizer =
          recognizer ?? TextRecognizer(script: TextRecognitionScript.latin);

  final TextRecognizer _recognizer;
  bool _closed = false;

  @override
  Future<String> recognize(PdfOcrPageImage image) async {
    if (_closed) {
      throw StateError('The OCR engine was already closed.');
    }
    // The page image is converted in memory: no temporary file is written, so
    // nothing about the document is left behind on disk.
    final nv21 = bgraToNv21(image.bgra, image.width, image.height);
    final input = InputImage.fromBytes(
      bytes: nv21,
      metadata: InputImageMetadata(
        size: ui.Size(image.width.toDouble(), image.height.toDouble()),
        rotation: InputImageRotation.rotation0deg,
        format: InputImageFormat.nv21,
        bytesPerRow: image.width,
      ),
    );
    final result = await _recognizer.processImage(input);
    return result.text;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _recognizer.close();
    } catch (_) {
      // The recognizer is already gone; nothing left to release.
    }
  }
}

