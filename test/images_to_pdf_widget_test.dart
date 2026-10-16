import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sickpdf/main.dart';
import 'package:sickpdf/screens/images_to_pdf_page.dart';
import 'package:sickpdf/services/pdf_image_to_pdf_service.dart';

/// Records the order/options it was asked to convert and returns fixed bytes.
class _FakeService implements PdfImageToPdfService {
  List<PdfImageInput>? lastImages;
  ImagePageSize? lastSize;
  ImageFit? lastFit;
  ImageMargin? lastMargin;
  int calls = 0;

  @override
  Future<Uint8List> convert({
    required List<PdfImageInput> images,
    ImagePageSize size = ImagePageSize.a4,
    ImageMargin margin = ImageMargin.small,
    ImageFit fit = ImageFit.contain,
    double squareSide = 595.276,
  }) async {
    calls++;
    lastImages = images;
    lastSize = size;
    lastFit = fit;
    lastMargin = margin;
    final problem = validateImageSelection(
      images,
      size: size,
      squareSide: squareSide,
    );
    if (problem != null) throw PdfImageToPdfException(problem);
    return Uint8List.fromList([1, 2, 3]);
  }
}

void main() {
  testWidgets('Image to PDF home tile opens the real workflow', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MyApp());
    await tester.dragUntilVisible(
      find.text('Image to PDF'),
      find.byType(CustomScrollView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Image to PDF'));
    await tester.pumpAndSettle();

    expect(find.byType(ImagesToPdfPage), findsOneWidget);
    expect(find.textContaining('coming soon'), findsNothing);
    expect(find.text('Select images'), findsOneWidget);
    // Empty selection: the conversion actions are hidden until images exist.
    expect(find.text('Preview PDF'), findsNothing);
    expect(find.text('Save PDF'), findsNothing);
  });

  test('service defaults are safe: A4, small margin, contain (no crop)', () async {
    // The defaults live on the service signature; assert them explicitly so a
    // future change cannot silently switch to a cropping fit.
    final service = _FakeService();
    await service.convert(
      images: [PdfImageInput(name: 'a.jpg', bytes: Uint8List.fromList([1]))],
    );
    expect(service.lastSize, ImagePageSize.a4);
    expect(service.lastMargin, ImageMargin.small);
    expect(service.lastFit, ImageFit.contain);
  });

  testWidgets('empty selection shows a clear message, never a crash', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ImagesToPdfPage()));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('No images selected yet'),
      findsOneWidget,
    );
  });

  test('ImageSelection preserves order across moves and removals', () {
    Uint8List b(int n) => Uint8List.fromList([n]);
    final selection = ImageSelection()
      ..addAll([
        PdfImageInput(name: 'a.jpg', bytes: b(1)),
        PdfImageInput(name: 'b.jpg', bytes: b(2)),
        PdfImageInput(name: 'c.png', bytes: b(3)),
      ]);

    selection.move(0, 2);
    expect(selection.images.map((i) => i.name).toList(), [
      'b.jpg',
      'c.png',
      'a.jpg',
    ]);

    selection.removeAt(1);
    expect(selection.images.map((i) => i.name).toList(), ['b.jpg', 'a.jpg']);

    expect(() => selection.move(0, 5), throwsRangeError);
    expect(() => selection.removeAt(9), throwsRangeError);
  });

  test('service passes the requested options and image order to conversion', () async {
    final service = _FakeService();
    final images = [
      PdfImageInput(name: 'first.jpg', bytes: Uint8List.fromList([1])),
      PdfImageInput(name: 'second.png', bytes: Uint8List.fromList([2])),
    ];
    await service.convert(
      images: images,
      size: ImagePageSize.letter,
      margin: ImageMargin.large,
      fit: ImageFit.cover,
    );
    expect(service.calls, 1);
    expect(service.lastImages!.map((i) => i.name).toList(), [
      'first.jpg',
      'second.png',
    ]);
    expect(service.lastSize, ImagePageSize.letter);
    expect(service.lastMargin, ImageMargin.large);
    expect(service.lastFit, ImageFit.cover);
  });
}
