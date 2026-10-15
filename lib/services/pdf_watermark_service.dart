import 'package:flutter/services.dart';

enum WatermarkPosition { center, top, bottom }
enum WatermarkRotation { horizontal, diagonal }

class PdfWatermarkOptions {
  const PdfWatermarkOptions({
    required this.text,
    this.fontSize = 36,
    this.opacity = 0.25,
    this.position = WatermarkPosition.center,
    this.rotation = WatermarkRotation.diagonal,
    this.pages,
  });

  final String text;
  final double fontSize;
  final double opacity;
  final WatermarkPosition position;
  final WatermarkRotation rotation;
  /// Zero-based page indexes. Null means every page.
  final Set<int>? pages;
}

String? validateWatermarkOptions(PdfWatermarkOptions options, int pageCount) {
  if (options.text.trim().isEmpty) return 'Enter watermark text.';
  if (options.fontSize < 8 || options.fontSize > 144) {
    return 'Text size must be between 8 and 144.';
  }
  if (options.opacity <= 0 || options.opacity > 1) {
    return 'Opacity must be between 1% and 100%.';
  }
  if (pageCount <= 0) return 'This PDF has no valid pages.';
  if (options.pages != null &&
      (options.pages!.isEmpty || options.pages!.any((p) => p < 0 || p >= pageCount))) {
    return 'Select at least one valid page.';
  }
  return null;
}

class PdfWatermarkException implements Exception {
  const PdfWatermarkException(this.message);
  final String message;
  @override
  String toString() => message;
}

class PdfWatermarkService {
  static const _channel = MethodChannel('sickpdf/watermark');

  Future<Uint8List> apply(Uint8List input, PdfWatermarkOptions options) async {
    if (input.isEmpty) throw const PdfWatermarkException('The PDF is empty.');
    final pages = options.pages == null ? null : (options.pages!.toList()..sort());
    try {
      final result = await _channel.invokeMethod<Uint8List>('watermark', {
        'bytes': input,
        'text': options.text.trim(),
        'fontSize': options.fontSize,
        'opacity': options.opacity,
        'position': options.position.name,
        'rotation': options.rotation.name,
        'pages': pages,
      });
      if (result == null || result.isEmpty) {
        throw const PdfWatermarkException('The PDF engine returned no output.');
      }
      return result;
    } on PdfWatermarkException {
      rethrow;
    } on MissingPluginException {
      throw const PdfWatermarkException('Watermark PDF is supported on Android only.');
    } on PlatformException catch (error) {
      throw PdfWatermarkException(
        error.code == 'too_large'
            ? 'Not enough memory. Try a smaller PDF.'
            : error.code == 'invalid_input'
            ? (error.message ?? 'Invalid watermark settings.')
            : 'Could not watermark this PDF. It may be encrypted, damaged, signed, or unsupported.',
      );
    } catch (_) {
      throw const PdfWatermarkException(
        'Could not watermark this PDF. It may be encrypted, damaged, signed, or unsupported.',
      );
    }
  }
}
