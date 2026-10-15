// ignore_for_file: avoid_print
// Synthetic fixture byte measurements are intentionally emitted by tests.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart';
import 'package:sickpdf/services/pdf_compress_service.dart';

Uint8List jpegPdf(
  int side,
  int quality, {
  bool nested = false,
  bool gray = false,
}) {
  final image = img.Image(width: side, height: side, numChannels: gray ? 1 : 3);
  for (var y = 0; y < side; y++) {
    for (var x = 0; x < side; x++) {
      image.setPixelRgb(
        x,
        y,
        (x * 3 + y) % 256,
        (y * 2 + x ~/ 3) % 256,
        (x + y * 3) % 256,
      );
    }
  }
  final jpeg = img.encodeJpg(image, quality: quality);
  final content =
      'BT /F1 12 Tf 10 280 Td (Image and selectable text) Tj ET\nq 200 0 0 200 0 0 cm /${nested ? "Fm1" : "Im1"} Do Q\n';
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 300] /Resources << /Font << /F1 5 0 R >> /XObject << /Im1 6 0 R /Fm1 8 0 R >> >> /Contents 4 0 R /Annots [7 0 R] >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    '<< /Type /XObject /Subtype /Image /Width $side /Height $side /ColorSpace /${gray ? "DeviceGray" : "DeviceRGB"} /BitsPerComponent 8 /Filter /DCTDecode /Length ${jpeg.length} >>\nstream\n${String.fromCharCodes(jpeg)}\nendstream',
    '<< /Type /Annot /Subtype /Link /Rect [0 0 50 50] /A << /S /URI /URI (https://example.com) >> >>',
    '<< /Type /XObject /Subtype /Form /BBox [0 0 1 1] /Resources << /XObject << /Im1 6 0 R >> >> /Length 8 >>\nstream\n/Im1 Do\n\nendstream',
  ];
  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = buffer.length;
  buffer.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer.write(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n',
  );
  return Uint8List.fromList(buffer.toString().codeUnits);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('candidate selection retains original for equal or larger output', () {
    final original = Uint8List.fromList([1, 2, 3]);
    for (final candidate in [Uint8List(3), Uint8List(4)]) {
      final result = PdfCompressionResult.choose(original, candidate, 1);
      expect(result.retainedOriginal, true);
      expect(result.bytes, original);
      expect(result.bytesSaved, 0);
      expect(result.reduced, false);
      expect(result.candidateSize, candidate.length);
    }
    final smaller = PdfCompressionResult.choose(original, Uint8List(2), 1);
    expect(smaller.reduced, true);
    expect(smaller.outputSize, 2);
  });
  for (final kind in ['oversized', 'optimized', 'nested', 'gray']) {
    final optimized = kind == 'optimized';
    test('measure $kind across presets', () async {
      final dir = await Directory.systemTemp.createTemp('sickpdf_images_');
      Pdfrx.cacheDirectoryPath = dir.path;
      try {
        final original = jpegPdf(
          optimized ? 200 : 1600,
          optimized ? 35 : 98,
          nested: kind == 'nested',
          gray: kind == 'gray',
        );
        final input = await File('${dir.path}/input.pdf')
            .writeAsBytes(original);
        final sizes = <int>[];
        for (final mode in PdfCompressionMode.values) {
          final result = await PdfCompressService().compress(
            input.path,
            mode: mode,
          );
          print(
            '$kind ${mode.name} dpi=${mode.dpi} quality=${mode.jpegQuality}: ${result.originalSize} -> candidate=${result.candidateSize} retained=${result.outputSize}; ${result.reductionPercent.toStringAsFixed(4)}%; ${result.diagnostics}',
          );
          sizes.add(result.outputSize);
          final outputFile = await File('${dir.path}/${mode.name}.pdf')
              .writeAsBytes(result.bytes);
          expect(await outputFile.length(), result.outputSize);
          final doc = await PdfDocument.openFile(outputFile.path);
          try {
            expect(doc.pages.length, 1);
            expect(doc.pages.first.width, 200);
            expect(doc.pages.first.height, 300);
            expect(
              (await doc.pages.first.loadText())?.fullText,
              contains('selectable text'),
            );
            expect(await doc.pages.first.loadLinks(), isNotEmpty);
            final render = await doc.pages.first.render(
              fullWidth: 200,
              fullHeight: 300,
            );
            expect(render, isNotNull);
            render?.dispose();
          } finally {
            await doc.dispose();
          }
          if (kind == 'nested' && mode != PdfCompressionMode.lossless) {
            expect(result.diagnostics['Form XObject unsupported'], 1);
            expect(result.imagesChanged, 0);
            expect(result.retainedOriginal, true);
          }
          if (!optimized &&
              kind != 'nested' &&
              mode != PdfCompressionMode.lossless) {
            expect(result.imagesChanged, 1);
            expect(result.reductionPercent, greaterThan(40));
          }
        }
        if (!optimized && kind != 'nested') {
          expect(sizes[2], lessThan(sizes[1]));
        }
        expect(await input.readAsBytes(), original);
      } finally {
        await dir.delete(recursive: true);
      }
    });
  }
}
