import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sickpdf/services/pdf_image_to_pdf_service.dart';

void main() {
  group('page box sizing', () {
    test('original page follows image proportions exactly', () {
      final box = imagePageBox(
        size: ImagePageSize.original,
        imageWidth: 800,
        imageHeight: 600,
      );
      expect(box.width, 800);
      expect(box.height, 600);
    });

    test('original page never returns zero for tiny images', () {
      final box = imagePageBox(
        size: ImagePageSize.original,
        imageWidth: 0,
        imageHeight: -3,
      );
      expect(box.width, greaterThan(0));
      expect(box.height, greaterThan(0));
    });

    test('A4 page is portrait for portrait images and landscape otherwise', () {
      final portrait = imagePageBox(
        size: ImagePageSize.a4,
        imageWidth: 600,
        imageHeight: 800,
      );
      expect(portrait.width, lessThan(portrait.height));
      expect(portrait.height, closeTo(841.89, 0.01));

      final landscape = imagePageBox(
        size: ImagePageSize.a4,
        imageWidth: 800,
        imageHeight: 600,
      );
      expect(landscape.width, greaterThan(landscape.height));
      expect(landscape.width, closeTo(841.89, 0.01));
    });

    test('square page uses the requested side and clamps non-positive', () {
      final box = imagePageBox(
        size: ImagePageSize.square,
        imageWidth: 100,
        imageHeight: 200,
        squareSide: 400,
      );
      expect(box.width, 400);
      expect(box.height, 400);

      final clamped = imagePageBox(
        size: ImagePageSize.square,
        imageWidth: 100,
        imageHeight: 200,
        squareSide: 0,
      );
      expect(clamped.width, greaterThan(0));
    });
  });

  group('margin presets', () {
    test('are ordered and none is zero', () {
      expect(imageMarginPoints(ImageMargin.none), 0);
      expect(
        imageMarginPoints(ImageMargin.small),
        lessThan(imageMarginPoints(ImageMargin.medium)),
      );
      expect(
        imageMarginPoints(ImageMargin.medium),
        lessThan(imageMarginPoints(ImageMargin.large)),
      );
    });
  });

  group('image fit rectangle', () {
    test('contain keeps aspect ratio, centres and never crops', () {
      // Wide image in a square box: width fills, height shrinks.
      final rect = imageFitRect(
        boxX: 10,
        boxY: 20,
        boxWidth: 400,
        boxHeight: 400,
        imageWidth: 800,
        imageHeight: 400,
        fit: ImageFit.contain,
      );
      expect(rect.width, closeTo(400, 0.001));
      expect(rect.height, closeTo(200, 0.001));
      // Vertically centred inside the box.
      expect(rect.y, closeTo(20 + (400 - 200) / 2, 0.001));
      expect(rect.x, closeTo(10, 0.001));
      // Stays within the box.
      expect(rect.x + rect.width, lessThanOrEqualTo(410.001));
      expect(rect.y + rect.height, lessThanOrEqualTo(420.001));
    });

    test('cover fills the box and may overflow equally on both sides', () {
      final rect = imageFitRect(
        boxX: 0,
        boxY: 0,
        boxWidth: 300,
        boxHeight: 300,
        imageWidth: 800,
        imageHeight: 400,
        fit: ImageFit.cover,
      );
      // Wider than the box (cropped), but never smaller than the box.
      expect(rect.width, greaterThanOrEqualTo(300));
      expect(rect.height, closeTo(300, 0.001));
      // Centred overflow is symmetric.
      expect(rect.x, closeTo(-(rect.width - 300) / 2, 0.001));
    });

    test('stretch fills the box exactly', () {
      final rect = imageFitRect(
        boxX: 5,
        boxY: 7,
        boxWidth: 200,
        boxHeight: 100,
        imageWidth: 640,
        imageHeight: 480,
        fit: ImageFit.stretch,
      );
      expect(rect.x, 5);
      expect(rect.y, 7);
      expect(rect.width, 200);
      expect(rect.height, 100);
    });

    test('degenerate image sizes do not produce NaN or infinity', () {
      final rect = imageFitRect(
        boxX: 0,
        boxY: 0,
        boxWidth: 100,
        boxHeight: 100,
        imageWidth: 0,
        imageHeight: 0,
        fit: ImageFit.contain,
      );
      expect(rect.width.isFinite, true);
      expect(rect.height.isFinite, true);
    });
  });

  group('selection validation', () {
    Uint8List bytes(int length) => Uint8List(length);

    test('rejects empty selections with a clear message', () {
      expect(
        validateImageSelection(
          const [],
          size: ImagePageSize.a4,
          squareSide: 595.276,
        ),
        isNotNull,
      );
    });

    test('rejects empty image bytes and mentions the position', () {
      final message = validateImageSelection(
        [
          PdfImageInput(name: 'a.jpg', bytes: bytes(4)),
          PdfImageInput(name: 'b.png', bytes: bytes(0)),
        ],
        size: ImagePageSize.a4,
        squareSide: 595.276,
      );
      expect(message, isNotNull);
      expect(message, contains('2'));
    });

    test('rejects non-positive square side', () {
      final message = validateImageSelection(
        [PdfImageInput(name: 'a.jpg', bytes: bytes(4))],
        size: ImagePageSize.square,
        squareSide: 0,
      );
      expect(message, isNotNull);
    });

    test('accepts a valid selection', () {
      expect(
        validateImageSelection(
          [PdfImageInput(name: 'a.jpg', bytes: bytes(4))],
          size: ImagePageSize.a4,
          squareSide: 595.276,
        ),
        isNull,
      );
    });
  });
}
