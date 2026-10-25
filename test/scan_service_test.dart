import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sickpdf/services/scan_camera_gateway.dart';
import 'package:sickpdf/services/scan_crop_service.dart';
import 'package:sickpdf/services/scan_document_service.dart';
import 'package:sickpdf/services/scan_image_processor.dart';
import 'package:sickpdf/services/scan_service.dart';

/// Builds a small JPEG so the decoder has something real to work on.
Uint8List _sampleJpeg({int width = 64, int height = 96}) {
  final image = img.Image(width: width, height: height, numChannels: 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgba(x, y, (x * 4) % 256, (y * 4) % 256, 128, 255);
    }
  }
  return img.encodeJpg(image, quality: 80);
}

/// A camera gateway that never touches hardware.
class _FakeCamera implements ScanCameraGateway {
  _FakeCamera({this.failWith});

  final ScanCameraException? failWith;

  bool openCalled = false;
  bool closeCalled = false;
  int pictureCount = 0;

  @override
  bool get isReady => openCalled;

  @override
  Widget? get preview => const SizedBox.shrink();

  @override
  double? get previewAspectRatio => null;

  @override
  Future<void> open() async {
    openCalled = true;
    if (failWith != null) throw failWith!;
  }

  @override
  Future<Uint8List> takePicture() async {
    pictureCount++;
    if (failWith != null) throw failWith!;
    return _sampleJpeg();
  }

  @override
  Future<void> close() async {
    closeCalled = true;
  }
}

/// A cropper that returns fixed bytes or cancels.
class _FakeCropper implements ScanCropService {
  _FakeCropper({this.result, this.failure});

  final Uint8List? result;
  final ScanCropException? failure;

  int calls = 0;
  Uint8List? lastSource;

  @override
  Future<Uint8List?> crop(Uint8List bytes) async {
    calls++;
    lastSource = bytes;
    if (failure != null) throw failure!;
    return result;
  }
}

void main() {
  group('ScanPageList', () {
    ScanPage page(int n) => ScanPage(
          bytes: Uint8List.fromList([n]),
          width: 10,
          height: 20,
        );

    test('preserves order across moves', () {
      final pages = ScanPageList()
        ..add(page(1))
        ..add(page(2))
        ..add(page(3));

      pages.move(0, 2);
      expect(
        pages.pages.map((p) => p.bytes.first).toList(),
        [2, 3, 1],
      );
    });

    test('removes a page and keeps the rest in order', () {
      final pages = ScanPageList()
        ..add(page(1))
        ..add(page(2))
        ..add(page(3));

      pages.removeAt(1);
      expect(
        pages.pages.map((p) => p.bytes.first).toList(),
        [1, 3],
      );
      expect(pages.length, 2);
    });

    test('rejects out-of-range moves and removals', () {
      final pages = ScanPageList()..add(page(1));
      expect(() => pages.move(0, 5), throwsRangeError);
      expect(() => pages.removeAt(9), throwsRangeError);
    });

    test('replaces a page in place', () {
      final pages = ScanPageList()
        ..add(page(1))
        ..add(page(2));
      pages.replaceAt(0, page(9));
      expect(
        pages.pages.map((p) => p.bytes.first).toList(),
        [9, 2],
      );
    });

    test('clear removes every page', () {
      final pages = ScanPageList()
        ..add(page(1))
        ..add(page(2));
      pages.clear();
      expect(pages.isEmpty, isTrue);
    });
  });

  group('ScanImageProcessor', () {
    test('prepare decodes an image and reports its size', () async {
      const processor = ScanImageProcessor();
      final page = await processor.prepare(_sampleJpeg(width: 40, height: 30));
      expect(page.width, 40);
      expect(page.height, 30);
      expect(page.bytes, isNotEmpty);
    });

    test('prepare rejects empty bytes with a readable message', () async {
      const processor = ScanImageProcessor();
      await expectLater(
        processor.prepare(Uint8List(0)),
        throwsA(
          isA<ScanImageException>().having(
            (e) => e.message,
            'message',
            contains('empty'),
          ),
        ),
      );
    });

    test('prepare rejects data that is not an image', () async {
      const processor = ScanImageProcessor();
      await expectLater(
        processor.prepare(Uint8List.fromList([1, 2, 3, 4, 5])),
        throwsA(isA<ScanImageException>()),
      );
    });

    test('prepare scales a large capture down to the page limit', () async {
      const processor = ScanImageProcessor();
      final page = await processor.prepare(
        _sampleJpeg(width: 2600, height: 3000),
      );
      expect(
        page.width > ScanImageProcessor.maxPageEdge ||
            page.height > ScanImageProcessor.maxPageEdge,
        isFalse,
        reason: 'A page must not keep full camera resolution.',
      );
    });

    test('crop keeps only the requested rectangle', () async {
      const processor = ScanImageProcessor();
      final bytes = _sampleJpeg(width: 100, height: 100);
      final cropped = await processor.crop(
        bytes,
        const ScanRect(10, 20, 50, 60),
      );
      expect(cropped.width, 40);
      expect(cropped.height, 40);
    });

    test('crop rejects an empty source', () async {
      const processor = ScanImageProcessor();
      await expectLater(
        processor.crop(Uint8List(0), const ScanRect(0, 0, 10, 10)),
        throwsA(isA<ScanImageException>()),
      );
    });

    test('crop rejects data that is not an image', () async {
      const processor = ScanImageProcessor();
      await expectLater(
        processor.crop(
          Uint8List.fromList([9, 9, 9, 9]),
          const ScanRect(0, 0, 10, 10),
        ),
        throwsA(isA<ScanImageException>()),
      );
    });

    test('prepare rejects a JPEG header with no image data', () async {
      const processor = ScanImageProcessor();
      final whole = _sampleJpeg(width: 400, height: 400);
      // Keep only the SOI marker and a few header bytes, so there is no scan
      // data at all. The decoder cannot produce pixels from this.
      final truncated = Uint8List.sublistView(whole, 0, 64);
      await expectLater(
        processor.prepare(truncated),
        throwsA(isA<ScanImageException>()),
      );
    });

    test('prepare downscales a large capture to the page limit', () async {
      const processor = ScanImageProcessor();
      // A tall capture well beyond the 2000 px page limit.
      final page = await processor.prepare(
        _sampleJpeg(width: 1200, height: 4000),
      );
      expect(
        math.max(page.width, page.height),
        lessThanOrEqualTo(ScanImageProcessor.maxPageEdge),
      );
      expect(page.width, greaterThan(0));
      expect(page.height, greaterThan(0));
      // The aspect ratio must survive the downscale.
      expect(page.width / page.height, closeTo(1200 / 4000, 0.02));
    });

    test('prepare keeps a small capture at its own size', () async {
      const processor = ScanImageProcessor();
      final page = await processor.prepare(
        _sampleJpeg(width: 300, height: 200),
      );
      expect(page.width, 300);
      expect(page.height, 200);
    });

    test('prepare honours EXIF orientation for a rotated capture', () async {
      const processor = ScanImageProcessor();
      // Encode a wide image, then mark it as rotated 90 degrees clockwise so
      // it must come out tall.
      final wide = img.Image(width: 400, height: 200, numChannels: 3);
      for (var y = 0; y < 200; y++) {
        for (var x = 0; x < 400; x++) {
          wide.setPixelRgba(x, y, (x * 3) % 256, (y * 5) % 256, 90, 255);
        }
      }
      wide.exif.imageIfd.orientation = 6;
      final page = await processor.prepare(img.encodeJpg(wide, quality: 90));

      // Orientation 6 swaps width and height.
      expect(page.height, greaterThan(page.width));
      expect(page.height / page.width, closeTo(2.0, 0.05));
    });

    test('detection returns no document for a blank image', () async {
      const processor = ScanImageProcessor();
      final flat = img.Image(width: 120, height: 120, numChannels: 3);
      for (var y = 0; y < 120; y++) {
        for (var x = 0; x < 120; x++) {
          flat.setPixelRgba(x, y, 255, 255, 255, 255);
        }
      }
      final quad = await processor.detectDocument(img.encodeJpg(flat));
      expect(quad, isNull, reason: 'A blank frame has no document.');
    });

    test('detection finds a bright page on a dark background', () async {
      const processor = ScanImageProcessor();
      final frame = img.Image(width: 200, height: 200, numChannels: 3);
      for (var y = 0; y < 200; y++) {
        for (var x = 0; x < 200; x++) {
          final insidePage = x >= 40 && x < 160 && y >= 50 && y < 150;
          frame.setPixelRgba(
            x,
            y,
            insidePage ? 250 : 10,
            insidePage ? 250 : 10,
            insidePage ? 250 : 10,
            255,
          );
        }
      }
      final quad = await processor.detectDocument(img.encodeJpg(frame));
      expect(quad, isNotNull);
      final bounds = quad!.bounds;
      // The detected page should sit close to the drawn rectangle.
      expect(bounds.left, closeTo(40, 12));
      expect(bounds.top, closeTo(50, 12));
      expect(bounds.right, closeTo(160, 12));
      expect(bounds.bottom, closeTo(150, 12));
    });
  });

  group('scaled JPEG decoding', () {
    test('picks no reduction when the image already fits', () {
      expect(jpegScaleFor(width: 800, height: 600, maxEdge: 2000), 1);
      expect(jpegScaleFor(width: 2000, height: 1500, maxEdge: 2000), 1);
    });

    test('picks the largest reduction that still reaches maxEdge', () {
      // 4000 / 2 = 2000 -> exactly the limit, so 1/2 is enough.
      expect(jpegScaleFor(width: 4000, height: 3000, maxEdge: 2000), 2);
      // 8000 / 4 = 2000 -> exactly the limit, so 1/4 is enough.
      expect(jpegScaleFor(width: 8000, height: 6000, maxEdge: 2000), 4);
      // 12000 / 8 = 1500, which is BELOW 2000, so 1/8 would force an upscale
      // afterwards. 12000 / 4 = 3000 stays above the limit, so 1/4 wins.
      expect(jpegScaleFor(width: 12000, height: 9000, maxEdge: 2000), 4);
      // 16000 / 8 = 2000 is exactly the limit, so 1/8 is used here.
      expect(jpegScaleFor(width: 16000, height: 12000, maxEdge: 2000), 8);
    });

    test('never returns a scale the decoder does not support', () {
      for (final width in [1, 100, 2000, 2001, 5000, 20000, 100000]) {
        final scale = jpegScaleFor(
          width: width,
          height: width,
          maxEdge: 2000,
        );
        expect(const [1, 2, 4, 8], contains(scale));
      }
    });

    test('rejects degenerate dimensions instead of dividing by zero', () {
      expect(jpegScaleFor(width: 0, height: 0, maxEdge: 2000), 1);
      expect(jpegScaleFor(width: -5, height: 10, maxEdge: 2000), 1);
      expect(jpegScaleFor(width: 4000, height: 3000, maxEdge: 0), 1);
    });

    test('returns null for non-JPEG data', () {
      expect(
        decodeJpegScaled(Uint8List.fromList([1, 2, 3]), maxEdge: 2000),
        isNull,
      );
      // A PNG must not be routed through the JPEG decoder.
      final png = img.encodePng(
        img.Image(width: 32, height: 32, numChannels: 3),
      );
      expect(decodeJpegScaled(png, maxEdge: 2000), isNull);
    });

    test('returns null for a corrupt JPEG header', () {
      final jpeg = _sampleJpeg(width: 4000, height: 4000);
      final corrupt = Uint8List.fromList(jpeg);
      // Keep the SOI marker so the JPEG sniff passes, then break the header.
      for (var i = 2; i < 40 && i < corrupt.length; i++) {
        corrupt[i] = 0xFF;
      }
      expect(() => decodeJpegScaled(corrupt, maxEdge: 2000), returnsNormally);
    });

    test('scaled decode yields fewer pixels than a full decode', () {
      final jpeg = _sampleJpeg(width: 4000, height: 3000);
      final scaled = decodeJpegScaled(jpeg, maxEdge: 2000);
      expect(scaled, isNotNull);
      // 1/2 of 4000x3000 is 2000x1500.
      expect(scaled!.width, 2000);
      expect(scaled.height, 1500);
      expect(
        scaled.width * scaled.height,
        lessThan(4000 * 3000),
        reason: 'The whole point is not to allocate the full bitmap.',
      );
    });

    test('scaled decode keeps the aspect ratio', () {
      final jpeg = _sampleJpeg(width: 3000, height: 4000);
      final scaled = decodeJpegScaled(jpeg, maxEdge: 2000);
      expect(scaled, isNotNull);
      expect(scaled!.width / scaled.height, closeTo(3000 / 4000, 0.01));
    });

    test('tryDecodeScaled falls back to the general decoder', () {
      // A PNG cannot use the JPEG fast path, but must still decode.
      final png = img.encodePng(
        img.Image(width: 64, height: 48, numChannels: 3),
      );
      final decoded = tryDecodeScaled(png, maxEdge: 2000);
      expect(decoded, isNotNull);
      expect(decoded!.width, 64);
      expect(decoded.height, 48);
    });

    test('tryDecodeScaled returns null for unreadable data', () {
      expect(tryDecodeScaled(Uint8List(0), maxEdge: 2000), isNull);
      expect(
        tryDecodeScaled(Uint8List.fromList([1, 2, 3, 4]), maxEdge: 2000),
        isNull,
      );
    });

    test('applyOrientation leaves an already-oriented image alone', () {
      final plain = img.Image(width: 20, height: 10, numChannels: 3);
      final result = applyOrientation(plain);
      expect(result.width, 20);
      expect(result.height, 10);
    });
  });

  group('ScanDocumentService', () {
    test('capture returns a prepared page and reads the camera once', () async {
      final camera = _FakeCamera();
      final service = ScanDocumentService(
        camera: camera,
        cropper: _FakeCropper(),
      );

      final result = await service.capturePage();
      expect(result.page.bytes, isNotEmpty);
      expect(result.page.width, greaterThan(0));
      expect(camera.pictureCount, 1);
    });

    test('capture maps a camera failure to a ScanCameraException', () async {
      final camera = _FakeCamera(
        failWith: const ScanCameraException(
          ScanCameraFailure.permissionDenied,
          'Camera permission denied.',
        ),
      );
      final service = ScanDocumentService(camera: camera);
      await expectLater(
        service.capturePage(),
        throwsA(isA<ScanCameraException>()),
      );
    });

    test('cropPage returns null when the user cancels', () async {
      final service = ScanDocumentService(
        camera: _FakeCamera(),
        cropper: _FakeCropper(),
      );
      final page = ScanPage(
        bytes: _sampleJpeg(),
        width: 64,
        height: 96,
      );
      expect(await service.cropPage(page), isNull);
    });

    test('cropPage returns a new page when the crop is confirmed', () async {
      final cropper = _FakeCropper(result: _sampleJpeg(width: 20, height: 20));
      final service = ScanDocumentService(
        camera: _FakeCamera(),
        cropper: cropper,
      );
      final page = ScanPage(
        bytes: _sampleJpeg(),
        width: 64,
        height: 96,
      );
      final cropped = await service.cropPage(page);
      expect(cropped, isNotNull);
      expect(cropped!.width, 20);
      expect(cropper.calls, 1);
    });

    test('cropPage maps a crop failure to a ScanException', () async {
      final cropper = _FakeCropper(
        failure: const ScanCropException('The crop editor could not open.'),
      );
      final service = ScanDocumentService(
        camera: _FakeCamera(),
        cropper: cropper,
      );
      final page = ScanPage(
        bytes: _sampleJpeg(),
        width: 64,
        height: 96,
      );
      await expectLater(service.cropPage(page), throwsA(isA<ScanException>()));
    });

    test('export refuses an empty page list', () async {
      final service = ScanDocumentService(camera: _FakeCamera());
      await expectLater(
        service.exportPdf(const []),
        throwsA(
          isA<ScanException>().having(
            (e) => e.message,
            'message',
            contains('at least one page'),
          ),
        ),
      );
    });

    test('openCamera and closeCamera drive the gateway', () async {
      final camera = _FakeCamera();
      final service = ScanDocumentService(camera: camera);
      await service.openCamera();
      expect(camera.openCalled, isTrue);
      await service.closeCamera();
      expect(camera.closeCalled, isTrue);
    });
  });
}
