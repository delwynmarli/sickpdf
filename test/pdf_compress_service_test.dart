// ignore_for_file: avoid_print
// Synthetic fixture byte measurements are intentionally emitted by tests.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:sickpdf/services/pdf_compress_service.dart';

// Real unfiltered content/image streams: PDFium must perform actual compression.
Uint8List compressionFixture({required bool image}) {
  final stream = image
      ? List.filled(256 * 256 * 3, 120).map(String.fromCharCode).join()
      : 'BT /F1 12 Tf 20 40 Td (Selectable text) Tj ET\n${List.filled(2000, '0 0 m 10 10 l S\n').join()}';
  final content = image ? 'q 100 0 0 100 0 0 cm /Im1 Do Q\n' : stream;
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 300] /Resources << /Font << /F1 5 0 R >> /XObject << /Im1 6 0 R >> >> /Contents 4 0 R >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    '<< /Type /XObject /Subtype /Image /Width 256 /Height 256 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Length ${image ? stream.length : 3} >>\nstream\n${image ? stream : 'xxx'}\nendstream',
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

  test('only genuine non-incremental mode; accurate signed size metrics', () {
    expect(PdfCompressionMode.values.length, 3);
    expect(PdfCompressionMode.medium.dpi, 150);
    expect(PdfCompressionMode.medium.jpegQuality, 80);
    expect(PdfCompressionMode.high.dpi, 100);
    expect(PdfCompressionMode.high.jpegQuality, 55);
    expect(PdfCompressionMode.lossless.incremental, false);
    final smaller = PdfCompressionResult(Uint8List(75), 100, 1);
    expect(smaller.bytesSaved, 25);
    expect(smaller.reductionPercent, 25);
    expect(PdfCompressionResult(Uint8List(120), 100, 1).reductionPercent, -20);
    expect(PdfCompressionResult(Uint8List(100), 100, 1).bytesSaved, 0);
    expect(PdfCompressionResult(Uint8List(0), 0, 1).reductionPercent, 0);
    expect(formatPdfSize(1024), '1.00 KiB');
  });

  for (final image in [false, true]) {
    test('real ${image ? 'image' : 'text'} compression preserves rendered content and original', () async {
      final dir = await Directory.systemTemp.createTemp('sickpdf_compress_');
      Pdfrx.cacheDirectoryPath = dir.path;
      try {
        final original = compressionFixture(image: image);
        final file = await File('${dir.path}/input.pdf').writeAsBytes(original);
        final result = await PdfCompressService().compress(file.path);
        // Recorded measurements are from actual bytes, not size labels.
        print(
          'lossless ${image ? "image" : "text"}: ${result.originalSize} -> ${result.outputSize}; ${result.reductionPercent.toStringAsFixed(4)}%',
        );
        if (!image) {
          for (final mode in [
            PdfCompressionMode.medium,
            PdfCompressionMode.high,
          ]) {
            final other = await PdfCompressService().compress(
              file.path,
              mode: mode,
            );
            print(
              'text ${mode.name}: ${other.originalSize} -> ${other.outputSize}; ${other.reductionPercent.toStringAsFixed(4)}%; changed=${other.imagesChanged}',
            );
            expect(other.imagesChanged, 0);
            expect(other.outputSize, result.outputSize);
          }
        }
        expect(result.originalSize, await file.length());
        expect(result.outputSize, result.bytes.length);
        expect(result.bytesSaved, greaterThan(0));
        expect(await file.readAsBytes(), original);
        final source = await PdfDocument.openFile(file.path);
        final output = await PdfDocument.openData(result.bytes);
        try {
          expect(output.pages.length, 1);
          final before = await source.pages.first.render(
            fullWidth: 200,
            fullHeight: 300,
          );
          final after = await output.pages.first.render(
            fullWidth: 200,
            fullHeight: 300,
          );
          try {
            expect(before, isNotNull);
            expect(after, isNotNull);
            expect(after!.pixels, before!.pixels);
          } finally {
            before?.dispose();
            after?.dispose();
          }
          if (!image) {
            expect(
              (await output.pages.first.loadText())?.fullText,
              contains('Selectable text'),
            );
          }
        } finally {
          await source.dispose();
          await output.dispose();
        }
      } finally {
        await dir.delete(recursive: true);
      }
    });
  }

  test(
    'missing, empty, damaged, oversized and password-required inputs fail',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'sickpdf_compress_errors_',
      );
      Pdfrx.cacheDirectoryPath = dir.path;
      final service = PdfCompressService();
      try {
        await expectLater(
          service.compress('${dir.path}/missing.pdf'),
          throwsA(isA<FileSystemException>()),
        );
        final file = await File('${dir.path}/bad.pdf').writeAsString('');
        await expectLater(service.compress(file.path), throwsFormatException);
        await file.writeAsString('not pdf');
        await expectLater(
          service.compress(file.path),
          throwsA(isA<Exception>()),
        );
        final handle = await file.open(mode: FileMode.write);
        await handle.truncate(PdfCompressService.maxInputBytes + 1);
        await handle.close();
        await expectLater(service.compress(file.path), throwsFormatException);
        await expectLater(
          service.compress('test/fixtures/password_required.pdf'),
          throwsA(isA<PdfPasswordException>()),
        );
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}
