import 'package:flutter/services.dart';

/// Where the signature is anchored on the page. The size is always applied
/// relative to the chosen anchor and the page media box.
enum SignaturePosition {
  bottomRight,
  bottomLeft,
  bottomCenter,
  topRight,
  topLeft,
  center,
}

class PdfSignOptions {
  const PdfSignOptions({
    required this.signaturePng,
    required this.pageIndex,
    this.position = SignaturePosition.bottomRight,
    this.widthFraction = 0.3,
    this.heightFraction = 0.12,
    this.offsetXFraction = 0.04,
    this.offsetYFraction = 0.04,
    this.opacity = 1.0,
  });

  /// Transparent-background PNG bytes of the drawn signature.
  final Uint8List signaturePng;

  /// Zero-based index of the target page.
  final int pageIndex;

  final SignaturePosition position;

  /// Signature width as a fraction of the page width (0..1].
  final double widthFraction;

  /// Signature height as a fraction of the page height (0..1].
  final double heightFraction;

  /// Horizontal margin from the anchor edge as a fraction of page width.
  final double offsetXFraction;

  /// Vertical margin from the anchor edge as a fraction of page height.
  final double offsetYFraction;

  /// Signature opacity, 0 < opacity <= 1.
  final double opacity;
}

/// Returns an error message, or null when the options are valid.
String? validateSignOptions(PdfSignOptions options, int pageCount) {
  if (options.signaturePng.isEmpty) return 'Draw or upload a signature first.';
  if (pageCount <= 0) return 'This PDF has no valid pages.';
  if (options.pageIndex < 0 || options.pageIndex >= pageCount) {
    return 'Choose a page between 1 and $pageCount.';
  }
  if (options.widthFraction <= 0 || options.widthFraction > 1) {
    return 'Signature width must be between 1% and 100%.';
  }
  if (options.heightFraction <= 0 || options.heightFraction > 1) {
    return 'Signature height must be between 1% and 100%.';
  }
  if (options.offsetXFraction < 0 ||
      options.offsetXFraction > 1 ||
      options.offsetYFraction < 0 ||
      options.offsetYFraction > 1) {
    return 'Signature margins must be between 0% and 100%.';
  }
  if (options.opacity <= 0 || options.opacity > 1) {
    return 'Opacity must be between 1% and 100%.';
  }
  return null;
}

class PdfSignException implements Exception {
  const PdfSignException(this.message);
  final String message;
  @override
  String toString() => message;
}

class PdfSignService {
  static const _channel = MethodChannel('sickpdf/sign');

  Future<Uint8List> apply(Uint8List input, PdfSignOptions options) async {
    if (input.isEmpty) throw const PdfSignException('The PDF is empty.');
    try {
      final result = await _channel.invokeMethod<Uint8List>('sign', {
        'bytes': input,
        'signature': options.signaturePng,
        'pageIndex': options.pageIndex,
        'position': options.position.name,
        'widthFraction': options.widthFraction,
        'heightFraction': options.heightFraction,
        'offsetXFraction': options.offsetXFraction,
        'offsetYFraction': options.offsetYFraction,
        'opacity': options.opacity,
      });
      if (result == null || result.isEmpty) {
        throw const PdfSignException('The PDF engine returned no output.');
      }
      return result;
    } on PdfSignException {
      rethrow;
    } on MissingPluginException {
      throw const PdfSignException('Sign PDF is supported on Android only.');
    } on PlatformException catch (error) {
      throw PdfSignException(
        error.code == 'too_large'
            ? 'Not enough memory. Try a smaller PDF.'
            : error.code == 'invalid_input'
            ? (error.message ?? 'Invalid signature settings.')
            : 'Could not sign this PDF. It may be encrypted, damaged, signed, or unsupported.',
      );
    } catch (_) {
      throw const PdfSignException(
        'Could not sign this PDF. It may be encrypted, damaged, signed, or unsupported.',
      );
    }
  }
}
