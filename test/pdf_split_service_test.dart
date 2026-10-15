import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:sickpdf/services/pdf_split_service.dart';

// Synthetic fixture: distinct dimensions identify page order without private PDFs.
Uint8List syntheticPdf(int count) {
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [${List.generate(count, (i) => '${i + 3} 0 R').join(' ')}] /Count $count >>',
    for (var i = 0; i < count; i++)
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${200 + i} 300] >>',
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

  test('accepts inclusive boundaries, full document, and single page', () {
    for (final pair in [(1, 10), (2, 5), (10, 10), (1, 1)]) {
      final range = PdfPageRange.parse('${pair.$1}', '${pair.$2}', 10);
      expect(range.start, pair.$1);
      expect(range.end, pair.$2);
    }
  });

  test('rejects invalid, missing, fractional and out-of-bounds pages', () {
    for (final pair in [
      ('0', '5'),
      ('-1', '2'),
      ('5', '2'),
      ('1', '11'),
      ('', '2'),
      ('1.5', '2'),
      ('a', '2'),
    ]) {
      expect(
        () => PdfPageRange.parse(pair.$1, pair.$2, 10),
        throwsFormatException,
      );
    }
    expect(() => PdfPageRange.parse('1', '1', 0), throwsFormatException);
  });

  test('rejects missing and empty files', () async {
    final directory = await Directory.systemTemp.createTemp('sickpdf_split_');
    try {
      final service = PdfSplitService();
      await expectLater(
        service.pageCount('${directory.path}/missing.pdf'),
        throwsFormatException,
      );
      final file = await File('${directory.path}/empty.pdf').create();
      await expectLater(service.pageCount(file.path), throwsFormatException);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test(
    'real local extraction preserves inclusive page order and source',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'sickpdf_extract_',
      );
      Pdfrx.cacheDirectoryPath = directory.path;
      try {
        final original = syntheticPdf(10);
        final file = await File('${directory.path}/input.pdf')
            .writeAsBytes(original);
        final service = PdfSplitService();
        expect(await service.pageCount(file.path), 10);
        for (final range in [
          const PdfPageRange(2, 5),
          const PdfPageRange(10, 10),
          const PdfPageRange(1, 10),
        ]) {
          final bytes = await service.extract(file.path, range);
          final output = await PdfDocument.openData(bytes);
          try {
            expect(output.pages.length, range.end - range.start + 1);
            expect(output.pages.map((page) => page.width).toList(), [
              for (var page = range.start; page <= range.end; page++)
                199.0 + page,
            ]);
          } finally {
            await output.dispose();
          }
        }
        expect(await file.readAsBytes(), original);
        await expectLater(
          service.extract(file.path, const PdfPageRange(1, 11)),
          throwsFormatException,
        );
        final invalid = await File('${directory.path}/invalid.pdf')
            .writeAsString('not a PDF');
        await expectLater(
          service.pageCount(invalid.path),
          throwsA(isA<Exception>()),
        );
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
}
