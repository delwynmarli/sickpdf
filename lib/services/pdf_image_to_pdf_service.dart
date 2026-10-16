import 'dart:math' as math;

import 'package:flutter/services.dart';

/// Page sizing strategy for each generated page.
enum ImagePageSize {
  /// Every page uses the original image proportions (no resize, no crop).
  original,

  /// Every page is A4 (595 x 842 points) in the image's orientation.
  a4,

  /// Every page is US Letter (612 x 792 points) in the image orientation.
  letter,

  /// Every page is a square of [PdfImageOptions.squareSide] points.
  square,
}

/// How the image is placed inside the page content box.
enum ImageFit {
  /// Fit the whole image inside the box; never crops. Default and safest.
  contain,

  /// Fill the box completely; may crop the image edges.
  cover,

  /// Stretch to the exact box, ignoring aspect ratio (may distort).
  stretch,
}

/// Predefined margin presets in PDF points (1 point = 1/72 inch).
enum ImageMargin {
  /// No margin at all.
  none,

  /// 18 points (~6.35 mm).
  small,

  /// 36 points (~12.7 mm).
  medium,

  /// 54 points (~19 mm).
  large,
}

const double _a4Width = 595.276;
const double _a4Height = 841.89;
const double _letterWidth = 612.0;
const double _letterHeight = 792.0;

/// Resolves the page box in PDF points for the selected [size].
///
/// [imageWidth] and [imageHeight] are the decoded pixel dimensions; they only
/// matter for [ImagePageSize.original] (proportional page) and to decide the
/// landscape/portrait orientation of fixed page sizes.
({double width, double height}) imagePageBox({
  required ImagePageSize size,
  required int imageWidth,
  required int imageHeight,
  double squareSide = 595.276,
}) {
  final portrait = imageHeight >= imageWidth;
  switch (size) {
    case ImagePageSize.original:
      // 72 dpi is a sensible neutral default: 1 pixel becomes 1 point.
      return (
        width: math.max(1.0, imageWidth.toDouble()),
        height: math.max(1.0, imageHeight.toDouble()),
      );
    case ImagePageSize.a4:
      return portrait
          ? (width: _a4Width, height: _a4Height)
          : (width: _a4Height, height: _a4Width);
    case ImagePageSize.letter:
      return portrait
          ? (width: _letterWidth, height: _letterHeight)
          : (width: _letterHeight, height: _letterWidth);
    case ImagePageSize.square:
      final side = math.max(1.0, squareSide);
      return (width: side, height: side);
  }
}

/// Returns the margin in points for the selected [margin] preset.
double imageMarginPoints(ImageMargin margin) {
  switch (margin) {
    case ImageMargin.none:
      return 0;
    case ImageMargin.small:
      return 18;
    case ImageMargin.medium:
      return 36;
    case ImageMargin.large:
      return 54;
  }
}

/// Computes the destination rectangle (in PDF points, origin bottom-left) for
/// an image inside a page content box given the [fit] strategy.
///
/// ([boxX], [boxY]) is the bottom-left corner of the content box; the returned
/// rectangle is fully inside [boxWidth] x [boxHeight]. [contain] never crops,
/// [cover] fully covers the box (may overflow and be clipped), [stretch] fills
/// exactly.
({double x, double y, double width, double height}) imageFitRect({
  required double boxX,
  required double boxY,
  required double boxWidth,
  required double boxHeight,
  required int imageWidth,
  required int imageHeight,
  required ImageFit fit,
}) {
  final safeWidth = math.max(1.0, boxWidth);
  final safeHeight = math.max(1.0, boxHeight);
  final imgWidth = math.max(1, imageWidth).toDouble();
  final imgHeight = math.max(1, imageHeight).toDouble();
  final scaleX = safeWidth / imgWidth;
  final scaleY = safeHeight / imgHeight;

  late final double drawWidth;
  late final double drawHeight;
  switch (fit) {
    case ImageFit.contain:
      final scale = math.min(scaleX, scaleY);
      drawWidth = imgWidth * scale;
      drawHeight = imgHeight * scale;
    case ImageFit.cover:
      final scale = math.max(scaleX, scaleY);
      drawWidth = imgWidth * scale;
      drawHeight = imgHeight * scale;
    case ImageFit.stretch:
      drawWidth = safeWidth;
      drawHeight = safeHeight;
  }

  final x = boxX + (safeWidth - drawWidth) / 2;
  final y = boxY + (safeHeight - drawHeight) / 2;
  return (x: x, y: y, width: drawWidth, height: drawHeight);
}

/// One selected image, described by the data the UI already has.
class PdfImageInput {
  const PdfImageInput({
    required this.name,
    required this.bytes,
  });

  /// Original file name, shown as a label and used for error messages.
  final String name;

  /// Raw encoded image bytes (JPEG, PNG, ...).
  final Uint8List bytes;
}

class PdfImageToPdfException implements Exception {
  const PdfImageToPdfException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Returns an error message, or null when the selection/options are valid.
String? validateImageSelection(
  List<PdfImageInput> images, {
  required ImagePageSize size,
  required double squareSide,
}) {
  if (images.isEmpty) return 'Select at least one image to convert.';
  if (size == ImagePageSize.square && squareSide <= 0) {
    return 'Square page side must be greater than zero.';
  }
  for (var i = 0; i < images.length; i++) {
    if (images[i].bytes.isEmpty) {
      return 'Image ${i + 1} is empty or could not be read. Remove it and select it again.';
    }
  }
  return null;
}

/// Builds a multi-page PDF with one image per page, in the given order.
///
/// The heavy lifting (decoding/embedding) happens in the native Android layer
/// so only one image is decoded at a time; this service owns validation,
/// layout math, and error mapping only.
class PdfImageToPdfService {
  static const _channel = MethodChannel('sickpdf/images');

  Future<Uint8List> convert({
    required List<PdfImageInput> images,
    ImagePageSize size = ImagePageSize.a4,
    ImageMargin margin = ImageMargin.small,
    ImageFit fit = ImageFit.contain,
    double squareSide = 595.276,
  }) async {
    final problem = validateImageSelection(
      images,
      size: size,
      squareSide: squareSide,
    );
    if (problem != null) throw PdfImageToPdfException(problem);

    final marginPoints = imageMarginPoints(margin);
    try {
      final result = await _channel.invokeMethod<Uint8List>('convert', {
        'images': [
          for (final image in images) image.bytes,
        ],
        'pageSize': size.name,
        'margin': marginPoints,
        'fit': fit.name,
        'squareSide': squareSide,
      });
      if (result == null || result.isEmpty) {
        throw const PdfImageToPdfException(
          'The PDF engine returned no output.',
        );
      }
      return result;
    } on PdfImageToPdfException {
      rethrow;
    } on MissingPluginException {
      throw const PdfImageToPdfException(
        'Image to PDF is supported on Android only.',
      );
    } on PlatformException catch (error) {
      throw PdfImageToPdfException(
        error.code == 'too_large'
            ? 'Not enough memory. Try fewer or smaller images.'
            : error.code == 'invalid_input'
            ? (error.message ?? 'Invalid image settings.')
            : error.code == 'decode_failed'
            ? (error.message ??
                'One of the images could not be decoded. It may be corrupted or unsupported.')
            : 'Could not create the PDF from these images. Try removing the affected image.',
      );
    } catch (_) {
      throw const PdfImageToPdfException(
        'Could not create the PDF from these images. Try removing the affected image.',
      );
    }
  }
}
