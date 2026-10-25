import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'scan_document_service.dart';

/// Errors raised while preparing a captured page.
class ScanImageException implements Exception {
  const ScanImageException(this.message);

  /// User-facing explanation of what went wrong.
  final String message;

  @override
  String toString() => message;
}

/// A rectangle in image pixel coordinates.
class ScanRect {
  const ScanRect(this.left, this.top, this.right, this.bottom);

  final int left;
  final int top;
  final int right;
  final int bottom;

  int get width => right - left;
  int get height => bottom - top;

  /// Whether the rectangle has a usable, non-degenerate area.
  bool get isValid => width > 0 && height > 0;
}

/// A point in image pixel coordinates.
class ScanPoint {
  const ScanPoint(this.x, this.y);

  final double x;
  final double y;
}

/// The four corners of a detected document, in image pixel coordinates.
class ScanQuad {
  const ScanQuad(
    this.topLeft,
    this.topRight,
    this.bottomRight,
    this.bottomLeft,
  );

  final ScanPoint topLeft;
  final ScanPoint topRight;
  final ScanPoint bottomRight;
  final ScanPoint bottomLeft;

  /// Bounding box of the quad, used as the crop rectangle.
  ScanRect get bounds {
    final xs = [topLeft.x, topRight.x, bottomRight.x, bottomLeft.x];
    final ys = [topLeft.y, topRight.y, bottomRight.y, bottomLeft.y];
    return ScanRect(
      xs.reduce(math.min).round(),
      ys.reduce(math.min).round(),
      xs.reduce(math.max).round(),
      ys.reduce(math.max).round(),
    );
  }

  /// Whether the quad is a plausible document shape: it must be large enough
  /// to be a page and must not be degenerate.
  bool get isPlausible {
    final b = bounds;
    if (!b.isValid) return false;
    return b.width >= 8 && b.height >= 8;
  }
}

/// Tuning constants for the automatic edge detector.
///
/// The detector is intentionally conservative: when it is not confident it
/// reports no document, and the UI falls back to the manual crop editor.
abstract final class ScanDetection {
  /// Longest side, in pixels, that the detector works on. Detecting edges on
  /// a full-resolution capture is slow and no more accurate.
  static const int analysisSize = 480;

  /// A pixel counts as an edge when its gradient magnitude exceeds this.
  static const int edgeThreshold = 42;

  /// Minimum number of edge pixels required before a document is reported.
  static const int minimumEdgePixels = 400;

  /// The detected document must cover at least this share of the frame.
  static const double minimumCoverage = 0.12;

  /// Maximum share of the frame the document may cover. Anything larger is
  /// usually a shadow or a flat surface, not a page.
  static const double maximumCoverage = 0.995;
}

/// Prepares captured page images: decodes them, keeps them a sensible size,
/// and finds the document edges.
///
/// All of this runs locally on the device. The heavy work happens in a
/// background isolate so the camera preview never stutters.
class ScanImageProcessor {
  const ScanImageProcessor({this.useIsolate = true});

  /// Whether the heavy pixel work runs in a background isolate.
  ///
  /// An isolate keeps the camera preview smooth, but it is unavailable in
  /// the widget test environment, where the fake async zone never lets the
  /// isolate reply. Tests therefore turn it off.
  final bool useIsolate;

  /// Longest edge, in pixels, that a stored page may have.
  ///
  /// A scan only has to be sharp enough to read; keeping full camera
  /// resolution would waste memory and make the PDF needlessly large.
  static const int maxPageEdge = 2000;

  /// JPEG quality used for stored pages.
  static const int jpegQuality = 88;

  /// Decodes [bytes] and returns a page ready to be embedded in a PDF.
  ///
  /// The EXIF orientation is baked in, and the image is scaled down so its
  /// longest edge is at most [maxPageEdge].
  Future<ScanPage> prepare(Uint8List bytes) async {
    final decoded = _decode(bytes);
    final oriented = applyOrientation(decoded);
    final scaled = fitTo(oriented, maxPageEdge);
    final encoded = img.encodeJpg(scaled, quality: jpegQuality);
    return ScanPage(
      bytes: Uint8List.fromList(encoded),
      width: scaled.width,
      height: scaled.height,
    );
  }

  /// Finds the document edges in [bytes].
  ///
  /// Returns `null` when no confident document is found, which tells the UI
  /// to fall back to the manual crop editor.
  Future<ScanQuad?> detectDocument(Uint8List bytes) async {
    if (bytes.isEmpty) return null;
    final decoded = tryDecodeScaled(bytes, maxEdge: maxPageEdge);
    if (decoded == null) return null;

    // Detection runs on a downscaled copy; the result is scaled back up to
    // the original resolution.
    final original = applyOrientation(decoded);
    final small = fitTo(original, ScanDetection.analysisSize);
    final scaleX = original.width / small.width;
    final scaleY = original.height / small.height;

    final quad = await _run(() => detectIn(small));
    if (quad == null) return null;

    final scaled = ScanQuad(
      ScanPoint(quad.topLeft.x * scaleX, quad.topLeft.y * scaleY),
      ScanPoint(quad.topRight.x * scaleX, quad.topRight.y * scaleY),
      ScanPoint(quad.bottomRight.x * scaleX, quad.bottomRight.y * scaleY),
      ScanPoint(quad.bottomLeft.x * scaleX, quad.bottomLeft.y * scaleY),
    );
    if (!scaled.isPlausible) return null;

    final bounds = scaled.bounds;
    final coverage =
        (bounds.width * bounds.height) / (original.width * original.height);
    if (coverage < ScanDetection.minimumCoverage ||
        coverage > ScanDetection.maximumCoverage) {
      return null;
    }
    return scaled;
  }

  /// Crops [bytes] to [rect] and returns the cropped page.
  Future<ScanPage> crop(Uint8List bytes, ScanRect rect) async {
    final decoded = _decode(bytes);
    final oriented = applyOrientation(decoded);

    final x = rect.left.clamp(0, math.max(0, oriented.width - 1)).toInt();
    final y = rect.top.clamp(0, math.max(0, oriented.height - 1)).toInt();
    final width = rect.width.clamp(1, oriented.width - x).toInt();
    final height = rect.height.clamp(1, oriented.height - y).toInt();
    if (width <= 0 || height <= 0) {
      throw const ScanImageException('The selected crop area was empty.');
    }

    final cropped = img.copyCrop(
      oriented,
      x: x,
      y: y,
      width: width,
      height: height,
    );
    final scaled = fitTo(cropped, maxPageEdge);
    final encoded = img.encodeJpg(scaled, quality: jpegQuality);
    return ScanPage(
      bytes: Uint8List.fromList(encoded),
      width: scaled.width,
      height: scaled.height,
    );
  }

  /// Runs [work], in a background isolate when that is enabled.
  Future<T> _run<T>(T Function() work) {
    if (!useIsolate) return Future<T>.value(work());
    return Isolate.run(work);
  }

  /// Decodes [bytes], mapping any failure to a user-facing error.
  ///
  /// JPEGs are decoded at a reduced DCT scale when they are larger than
  /// [maxPageEdge], so the full-resolution bitmap is never allocated. Every
  /// other format, and every JPEG the scaled path cannot handle, uses the
  /// general decoder.
  static img.Image _decode(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw const ScanImageException('The captured image was empty.');
    }
    final decoded = tryDecodeScaled(bytes, maxEdge: maxPageEdge);
    if (decoded == null) {
      throw const ScanImageException(
        'The captured image could not be read. Try capturing the page again.',
      );
    }
    return decoded;
  }
}

/// Scales [source] down so its longest edge is at most [maxEdge].
img.Image fitTo(img.Image source, int maxEdge) {
  final longest = math.max(source.width, source.height);
  if (longest <= maxEdge) return source;
  final scale = maxEdge / longest;
  return img.copyResize(
    source,
    width: math.max(1, (source.width * scale).round()),
    height: math.max(1, (source.height * scale).round()),
    interpolation: img.Interpolation.average,
  );
}

/// Runs the edge detector on an already-decoded, downscaled image.
///
/// Lives at the top level so it can be handed to [Isolate.run].
ScanQuad? detectIn(img.Image image) {
  final width = image.width;
  final height = image.height;
  if (width < 16 || height < 16) return null;

  // Grayscale, then a Sobel gradient pass. The gradient magnitude tells us
  // where the strong lines of a page are.
  final gray = img.grayscale(img.Image.from(image, noAnimation: true));
  final gradient = gradientMagnitude(gray, width, height);

  // Find the bounding box of the strongest edges.
  var minX = width, maxX = -1, minY = height, maxY = -1;
  var edgeCount = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (gradient[y * width + x] < ScanDetection.edgeThreshold) continue;
      edgeCount++;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
  }
  if (edgeCount < ScanDetection.minimumEdgePixels) return null;
  if (maxX <= minX || maxY <= minY) return null;

  // Require the edge box to be a large part of the frame, otherwise the
  // "document" is a small object on a desk and cropping to it would be wrong.
  final boxArea = (maxX - minX) * (maxY - minY);
  final frameArea = width * height;
  final coverage = boxArea / frameArea;
  if (coverage < ScanDetection.minimumCoverage ||
      coverage > ScanDetection.maximumCoverage) {
    return null;
  }

  // The extreme edge points along each side of the box define the corners.
  final bandX = math.max(1, ((maxX - minX) * 0.12).round());
  final bandY = math.max(1, ((maxY - minY) * 0.12).round());
  final midX = (minX + maxX) / 2;

  var topLeftX = double.infinity, topLeftY = double.infinity;
  var topRightX = double.negativeInfinity, topRightY = double.infinity;
  var bottomRightX = double.negativeInfinity, bottomRightY = double.negativeInfinity;
  var bottomLeftX = double.infinity, bottomLeftY = double.negativeInfinity;

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (gradient[y * width + x] < ScanDetection.edgeThreshold) continue;
      final nearLeft = x - minX <= bandX;
      final nearRight = maxX - x <= bandX;
      final nearTop = y - minY <= bandY;
      final nearBottom = maxY - y <= bandY;

      if (nearTop && nearLeft && x <= midX) {
        if (x < topLeftX) topLeftX = x.toDouble();
        if (y < topLeftY) topLeftY = y.toDouble();
      }
      if (nearTop && nearRight) {
        if (x > topRightX) topRightX = x.toDouble();
        if (y < topRightY) topRightY = y.toDouble();
      }
      if (nearBottom && nearRight) {
        if (x > bottomRightX) bottomRightX = x.toDouble();
        if (y > bottomRightY) bottomRightY = y.toDouble();
      }
      if (nearBottom && nearLeft) {
        if (x < bottomLeftX) bottomLeftX = x.toDouble();
        if (y > bottomLeftY) bottomLeftY = y.toDouble();
      }
    }
  }

  if (!topLeftX.isFinite ||
      !topRightX.isFinite ||
      !bottomRightX.isFinite ||
      !bottomLeftX.isFinite) {
    return null;
  }

  final quad = ScanQuad(
    ScanPoint(topLeftX, topLeftY),
    ScanPoint(topRightX, topRightY),
    ScanPoint(bottomRightX, bottomRightY),
    ScanPoint(bottomLeftX, bottomLeftY),
  );
  if (!quad.isPlausible) return null;
  return quad;
}

/// Computes the Sobel gradient magnitude of a grayscale image.
///
/// The result is a flat list of `width * height` values, each in `0..255`.
List<int> gradientMagnitude(img.Image gray, int width, int height) {
  final result = List<int>.filled(width * height, 0);
  for (var y = 1; y < height - 1; y++) {
    for (var x = 1; x < width - 1; x++) {
      final tl = gray.getPixel(x - 1, y - 1).luminance.toDouble();
      final tc = gray.getPixel(x, y - 1).luminance.toDouble();
      final tr = gray.getPixel(x + 1, y - 1).luminance.toDouble();
      final ml = gray.getPixel(x - 1, y).luminance.toDouble();
      final mr = gray.getPixel(x + 1, y).luminance.toDouble();
      final bl = gray.getPixel(x - 1, y + 1).luminance.toDouble();
      final bc = gray.getPixel(x, y + 1).luminance.toDouble();
      final br = gray.getPixel(x + 1, y + 1).luminance.toDouble();

      final h = -tl - 2 * tc - tr + bl + 2 * bc + br;
      final v = -bl - 2 * ml - tl + br + 2 * mr + tr;
      final magnitude = math.sqrt(h * h + v * v);
      result[y * width + x] = magnitude.round().clamp(0, 255);
    }
  }
  return result;
}

/// Applies any EXIF orientation that is still present on [image].
///
/// The `image` package's JPEG decoder already bakes the EXIF orientation into
/// the pixels and clears the tag, so this is a no-op for JPEGs. It still
/// matters for formats whose decoders leave the tag in place.
img.Image applyOrientation(img.Image image) {
  if (!image.exif.imageIfd.hasOrientation) return image;
  final orientation = image.exif.imageIfd.orientation;
  if (orientation == null || orientation == 1) return image;
  return img.bakeOrientation(image);
}

/// Chooses the JPEG DCT scale factor that keeps the decoded image at or above
/// [maxEdge] while decoding as few pixels as possible.
///
/// `JpegDecoder` only supports 1, 2, 4 and 8. Scaling in the DCT domain means
/// the full-resolution bitmap is never materialised, which is the whole point
/// of this path: a 12 MP capture decoded at 1/4 costs about 0.75 MP of pixels.
///
/// Returns 1 when the image is small enough that no reduction is warranted.
int jpegScaleFor({
  required int width,
  required int height,
  required int maxEdge,
}) {
  if (width <= 0 || height <= 0 || maxEdge <= 0) return 1;
  final longest = math.max(width, height);
  if (longest <= maxEdge) return 1;

  var scale = 1;
  // Prefer the largest reduction that still leaves a longest edge at or above
  // maxEdge, so the subsequent resize is a small downscale rather than an
  // upscale.
  for (final candidate in const [8, 4, 2]) {
    if ((longest / candidate).ceil() >= maxEdge) {
      scale = candidate;
      break;
    }
  }
  return scale;
}

/// Decodes JPEG [bytes] at a reduced DCT scale when that is possible and
/// useful.
///
/// Returns `null` when [bytes] is not a JPEG, cannot be read, or the header
/// does not report usable dimensions. Callers treat `null` as "use the
/// general path".
img.Image? decodeJpegScaled(Uint8List bytes, {required int maxEdge}) {
  if (bytes.length < 2 || bytes[0] != 0xFF || bytes[1] != 0xD8) return null;

  try {
    final header = img.JpegDecoder();
    final info = header.startDecode(bytes);
    if (info == null || info.width <= 0 || info.height <= 0) return null;

    final scale = jpegScaleFor(
      width: info.width,
      height: info.height,
      maxEdge: maxEdge,
    );
    if (scale == 1) return null;

    return img.JpegDecoder(scale: scale).decode(bytes);
  } catch (_) {
    // Any malformed-header or unsupported-JPEG case falls back to the
    // general decoder, which produces the same user-facing error.
    return null;
  }
}

/// Decodes [bytes], preferring a memory-frugal scaled JPEG decode.
///
/// Returns `null` instead of throwing so callers can decide how to report the
/// failure. Never raises the pixel limit.
img.Image? tryDecodeScaled(Uint8List bytes, {required int maxEdge}) {
  if (bytes.isEmpty) return null;

  final scaled = decodeJpegScaled(bytes, maxEdge: maxEdge);
  if (scaled != null) return scaled;

  try {
    return img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
}
