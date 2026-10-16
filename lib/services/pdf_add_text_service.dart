import 'package:flutter/services.dart';

/// Vertical band on the page where the text is anchored.
enum AddTextVerticalPosition { top, center, bottom }

/// Horizontal alignment of the text within the page.
enum AddTextAlignment { left, center, right }

class PdfAddTextOptions {
  const PdfAddTextOptions({
    required this.text,
    this.fontSize = 18,
    this.color = 0xFF000000,
    this.alignment = AddTextAlignment.center,
    this.vertical = AddTextVerticalPosition.center,
    this.pages,
  });

  final String text;

  /// Font size in points.
  final double fontSize;

  /// Text color as an ARGB 32-bit integer.
  final int color;

  final AddTextAlignment alignment;
  final AddTextVerticalPosition vertical;

  /// Zero-based page indexes. Null means every page.
  final Set<int>? pages;
}

/// Returns an error message, or null when the options are valid.
String? validateAddTextOptions(PdfAddTextOptions options, int pageCount) {
  if (options.text.trim().isEmpty) return 'Enter the text to add.';
  if (options.fontSize < 6 || options.fontSize > 144) {
    return 'Font size must be between 6 and 144.';
  }
  if (pageCount <= 0) return 'This PDF has no valid pages.';
  if (options.pages != null &&
      (options.pages!.isEmpty ||
          options.pages!.any((p) => p < 0 || p >= pageCount))) {
    return 'Select at least one valid page.';
  }
  return null;
}

class PdfAddTextException implements Exception {
  const PdfAddTextException(this.message);
  final String message;
  @override
  String toString() => message;
}

class PdfAddTextService {
  static const _channel = MethodChannel('sickpdf/addtext');

  Future<Uint8List> apply(Uint8List input, PdfAddTextOptions options) async {
    if (input.isEmpty) throw const PdfAddTextException('The PDF is empty.');
    final color = options.color;
    final pages = options.pages == null ? null : (options.pages!.toList()..sort());
    try {
      final result = await _channel.invokeMethod<Uint8List>('addText', {
        'bytes': input,
        'text': options.text.trim(),
        'fontSize': options.fontSize,
        'colorR': ((color >> 16) & 0xFF) / 255.0,
        'colorG': ((color >> 8) & 0xFF) / 255.0,
        'colorB': (color & 0xFF) / 255.0,
        'alignment': options.alignment.name,
        'vertical': options.vertical.name,
        'pages': pages,
      });
      if (result == null || result.isEmpty) {
        throw const PdfAddTextException('The PDF engine returned no output.');
      }
      return result;
    } on PdfAddTextException {
      rethrow;
    } on MissingPluginException {
      throw const PdfAddTextException('Add text to PDF is supported on Android only.');
    } on PlatformException catch (error) {
      throw PdfAddTextException(
        error.code == 'too_large'
            ? 'Not enough memory. Try a smaller PDF.'
            : error.code == 'invalid_input'
            ? (error.message ?? 'Invalid text settings.')
            : 'Could not add text to this PDF. It may be encrypted, damaged, signed, or unsupported.',
      );
    } catch (_) {
      throw const PdfAddTextException(
        'Could not add text to this PDF. It may be encrypted, damaged, signed, or unsupported.',
      );
    }
  }
}
