import 'package:flutter/services.dart';

/// Supported numbering formats.
enum PageNumberFormat { plain, page, pageOfN }

/// Supported placement of the number on the page.
enum PageNumberPosition {
  bottomLeft,
  bottomCenter,
  bottomRight,
  topLeft,
  topCenter,
  topRight,
}

class PdfPageNumbersOptions {
  const PdfPageNumbersOptions({
    this.format = PageNumberFormat.plain,
    this.position = PageNumberPosition.bottomCenter,
    this.startNumber = 1,
    required this.firstPage,
    required this.lastPage,
    this.fontSize = 12,
    this.color = 0xFF000000,
  });

  final PageNumberFormat format;
  final PageNumberPosition position;

  /// Number printed on [firstPage]. Defaults to 1.
  final int startNumber;

  /// First page to number, 1-based and inclusive.
  final int firstPage;

  /// Last page to number, 1-based and inclusive.
  final int lastPage;

  /// Font size in points.
  final double fontSize;

  /// Text color as an ARGB 32-bit integer.
  final int color;
}

/// Builds the visible label for a page. [pageIndex] is zero-based.
String pageNumberLabel(PdfPageNumbersOptions options, int pageIndex) {
  final number = options.startNumber + (pageIndex - (options.firstPage - 1));
  switch (options.format) {
    case PageNumberFormat.page:
      return 'Page $number';
    case PageNumberFormat.pageOfN:
      final total =
          options.startNumber + (options.lastPage - options.firstPage);
      return 'Page $number of $total';
    case PageNumberFormat.plain:
      return '$number';
  }
}

/// Returns an error message, or null when the options are valid.
String? validatePageNumberOptions(PdfPageNumbersOptions options, int pageCount) {
  if (pageCount <= 0) return 'This PDF has no valid pages.';
  if (options.startNumber < 0) return 'Starting number cannot be negative.';
  if (options.firstPage < 1 || options.firstPage > pageCount) {
    return 'First page must be between 1 and $pageCount.';
  }
  if (options.lastPage < 1 || options.lastPage > pageCount) {
    return 'Last page must be between 1 and $pageCount.';
  }
  if (options.firstPage > options.lastPage) {
    return 'First page must not exceed the last page.';
  }
  if (options.fontSize < 6 || options.fontSize > 72) {
    return 'Font size must be between 6 and 72.';
  }
  return null;
}

class PdfPageNumbersException implements Exception {
  const PdfPageNumbersException(this.message);
  final String message;
  @override
  String toString() => message;
}

class PdfPageNumbersService {
  static const _channel = MethodChannel('sickpdf/pagenumbers');

  Future<Uint8List> apply(
    Uint8List input,
    PdfPageNumbersOptions options,
  ) async {
    if (input.isEmpty) throw const PdfPageNumbersException('The PDF is empty.');
    final color = options.color;
    try {
      final result = await _channel.invokeMethod<Uint8List>('addPageNumbers', {
        'bytes': input,
        'format': options.format.name,
        'position': options.position.name,
        'startNumber': options.startNumber,
        'firstPage': options.firstPage,
        'lastPage': options.lastPage,
        'fontSize': options.fontSize,
        'colorR': ((color >> 16) & 0xFF) / 255.0,
        'colorG': ((color >> 8) & 0xFF) / 255.0,
        'colorB': (color & 0xFF) / 255.0,
      });
      if (result == null || result.isEmpty) {
        throw const PdfPageNumbersException('The PDF engine returned no output.');
      }
      return result;
    } on PdfPageNumbersException {
      rethrow;
    } on MissingPluginException {
      throw const PdfPageNumbersException(
        'Add page numbers is supported on Android only.',
      );
    } on PlatformException catch (error) {
      throw PdfPageNumbersException(
        error.code == 'too_large'
            ? 'Not enough memory. Try a smaller PDF.'
            : error.code == 'invalid_input'
            ? (error.message ?? 'Invalid page numbering settings.')
            : 'Could not add page numbers. It may be encrypted, damaged, signed, or unsupported.',
      );
    } catch (_) {
      throw const PdfPageNumbersException(
        'Could not add page numbers. It may be encrypted, damaged, signed, or unsupported.',
      );
    }
  }
}
