import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:sickpdf/services/pdf_ocr_engine.dart';
import 'package:sickpdf/services/pdf_ocr_service.dart';

/// A synthetic PDF whose pages carry selectable text.
///
/// Every page holds a different marker so the tests can prove the page order
/// is preserved in the exported text.
Uint8List textPdf(int count) {
  // Object layout: catalog, page tree, one page per document page, one font
  // per page, then one content stream per page.
  final fontBase = 3 + count;
  final contentBase = fontBase + count;
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [${List.generate(count, (i) => '${i + 3} 0 R').join(' ')}] /Count $count >>',
    for (var i = 0; i < count; i++)
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 300] /Resources << /Font << /F1 ${fontBase + i} 0 R >> >> /Contents ${contentBase + i} 0 R >>',
    for (var i = 0; i < count; i++)
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  final all = <String>[
    ...objects,
    for (var i = 0; i < count; i++)
      '<< /Length ${'BT /F1 12 Tf 20 40 Td (Page marker ${i + 1}) Tj ET'.length} >>\n'
          'stream\nBT /F1 12 Tf 20 40 Td (Page marker ${i + 1}) Tj ET\nendstream',
  ];
  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < all.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${all[i]}\nendobj\n');
  }
  final xref = buffer.length;
  buffer.write('xref\n0 ${all.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer.write(
    'trailer\n<< /Size ${all.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n',
  );
  return Uint8List.fromList(buffer.toString().codeUnits);
}

/// A synthetic PDF without any text layer, used for the scanned-document path.
Uint8List scannedPdf(int count) {
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [${List.generate(count, (i) => '${i + 3} 0 R').join(' ')}] /Count $count >>',
    for (var i = 0; i < count; i++)
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 300] >>',
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

/// Records what it was asked to recognize and returns canned answers.
class _FakeEngine implements PdfOcrEngine {
  _FakeEngine({this.answers = const <int, String>{}});

  /// Text per one-based page number. Pages without an entry return ''.
  final Map<int, String> answers;

  /// Pages that were sent to the engine, in order.
  final List<int> recognizedPages = [];

  /// Width of the first page image the engine was given.
  int? renderedWidth;

  /// Height of the first page image the engine was given.
  int? renderedHeight;

  /// Pixel buffer of the first page image the engine was given.
  Uint8List? renderedPixels;

  /// Page numbers whose recognition should fail.
  final Set<int> failingPages = <int>{};

  bool closed = false;
  int closeCalls = 0;

  @override
  Future<String> recognize(PdfOcrPageImage image) async {
    recognizedPages.add(image.pageNumber);
    renderedWidth ??= image.width;
    renderedHeight ??= image.height;
    renderedPixels ??= image.bgra;
    if (failingPages.contains(image.pageNumber)) {
      throw StateError('native recognizer failed on page ${image.pageNumber}');
    }
    return answers[image.pageNumber] ?? '';
  }

  @override
  Future<void> close() async {
    closeCalls++;
    closed = true;
  }
}

PdfOcrService _serviceWith(_FakeEngine engine) =>
    PdfOcrService(engineFactory: () => engine);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('text aggregation', () {
    test('keeps page order and inserts a separator for every page', () {
      final document = buildPdfOcrDocument({
        1: 'Hello',
        2: 'World',
        3: 'Again',
      });
      expect(document, contains('--- Page 1 ---'));
      expect(document, contains('--- Page 2 ---'));
      expect(document, contains('--- Page 3 ---'));
      expect(
        document.indexOf('--- Page 1 ---'),
        lessThan(document.indexOf('--- Page 2 ---')),
      );
      expect(
        document.indexOf('--- Page 2 ---'),
        lessThan(document.indexOf('--- Page 3 ---')),
      );
      expect(document, contains('Hello'));
      expect(document, contains('World'));
      expect(document, contains('Again'));
    });

    test('preserves line breaks inside a page', () {
      final document = buildPdfOcrDocument({
        1: 'Baris satu\nBaris dua\nBaris tiga',
      });
      expect(document, contains('Baris satu\nBaris dua\nBaris tiga'));
    });

    test('marks pages that produced no text', () {
      final document = buildPdfOcrDocument(
        {1: 'Readable', 2: ''},
        failedPages: const [2],
      );
      expect(document, contains('[No text recognized on this page]'));
      expect(document, contains('Readable'));
    });

    test('an empty page set produces an empty document', () {
      expect(buildPdfOcrDocument(const <int, String>{}), isEmpty);
    });
  });

  group('output naming', () {
    test('derives the OCR filename from the source name', () {
      expect(pdfOcrOutputName('report.pdf'), 'report_ocr.txt');
      expect(pdfOcrOutputName('Report.PDF'), 'Report_ocr.txt');
      expect(pdfOcrOutputName('scan'), 'scan_ocr.txt');
      expect(pdfOcrOutputName(''), 'document_ocr.txt');
      expect(pdfOcrOutputName('a/b/deep.pdf'), 'deep_ocr.txt');
    });

    test('never produces the source name itself', () {
      expect(pdfOcrOutputName('report.pdf'), isNot('report.pdf'));
    });

    test('does not overwrite an existing output file', () async {
      final directory = await Directory.systemTemp.createTemp(
        'sickpdf_ocr_name_',
      );
      try {
        final service = PdfOcrService();
        final first = await service.writeTextFile(
          directory,
          'report_ocr.txt',
          'first',
        );
        expect(first.path, endsWith('report_ocr.txt'));
        final second = await service.writeTextFile(
          directory,
          'report_ocr.txt',
          'second',
        );
        expect(second.path, endsWith('report_ocr (2).txt'));
        expect(await first.readAsString(), 'first');
        expect(await second.readAsString(), 'second');
      } finally {
        await directory.delete(recursive: true);
      }
    });

    test('writes UTF-8 text', () async {
      final directory = await Directory.systemTemp.createTemp('sickpdf_ocr_utf8_');
      try {
        final service = PdfOcrService();
        final file = await service.writeTextFile(
          directory,
          'unicode_ocr.txt',
          'Halo dunia — halo',
        );
        expect(await file.readAsString(encoding: utf8), contains('—'));
      } finally {
        await directory.delete(recursive: true);
      }
    });
  });

  group('extraction', () {
    test('rejects a missing or empty file', () async {
      final directory = await Directory.systemTemp.createTemp(
        'sickpdf_ocr_missing_',
      );
      Pdfrx.cacheDirectoryPath = directory.path;
      try {
        final service = _serviceWith(_FakeEngine());
        await expectLater(
          service.extract('${directory.path}/missing.pdf'),
          throwsA(isA<PdfOcrException>()),
        );
        final empty = await File('${directory.path}/empty.pdf').create();
        await expectLater(
          service.extract(empty.path),
          throwsA(isA<PdfOcrException>()),
        );
      } finally {
        await directory.delete(recursive: true);
      }
    });

    test('rejects a file that is not a PDF', () async {
      final directory = await Directory.systemTemp.createTemp(
        'sickpdf_ocr_invalid_',
      );
      // The cache directory is set so the PDF engine never asks the platform
      // for a temporary folder inside the test.
      Pdfrx.cacheDirectoryPath = directory.path;
      try {
        final file = await File('${directory.path}/broken.pdf').writeAsString(
          'this is not a pdf',
        );
        final service = _serviceWith(_FakeEngine());
        await expectLater(
          service.extract(file.path),
          throwsA(isA<PdfOcrException>()),
        );
      } finally {
        await directory.delete(recursive: true);
      }
    });

    test('reports the page count of a real document', () async {
      final directory = await Directory.systemTemp.createTemp(
        'sickpdf_ocr_pages_',
      );
      Pdfrx.cacheDirectoryPath = directory.path;
      try {
        final file = await File('${directory.path}/input.pdf').writeAsBytes(
          scannedPdf(3),
        );
        final service = _serviceWith(_FakeEngine());
        expect(await service.pageCount(file.path), 3);
      } finally {
        await directory.delete(recursive: true);
      }
    });

    test('aggregates pages in order and reports progress', () async {
      final directory = await Directory.systemTemp.createTemp(
        'sickpdf_ocr_run_',
      );
      Pdfrx.cacheDirectoryPath = directory.path;
      try {
        final file = await File('${directory.path}/input.pdf').writeAsBytes(
          scannedPdf(3),
        );
        final engine = _FakeEngine(
          answers: const {1: 'Satu', 2: 'Dua', 3: 'Tiga'},
        );
        final service = _serviceWith(engine);
        final progress = <PdfOcrProgress>[];
        final result = await service.extract(
          file.path,
          onProgress: progress.add,
        );
        expect(engine.recognizedPages, [1, 2, 3]);
        expect(progress.map((p) => p.pageNumber), [1, 2, 3]);
        expect(progress.first.label, 'Processing page 1 of 3');
        expect(progress.last.label, 'Processing page 3 of 3');
        expect(result.pageCount, 3);
        expect(result.processedPages, 3);
        expect(result.failures, isEmpty);
        expect(
          result.text.indexOf('Satu'),
          lessThan(result.text.indexOf('Dua')),
        );
        expect(
          result.text.indexOf('Dua'),
          lessThan(result.text.indexOf('Tiga')),
        );
        expect(result.text, contains('--- Page 1 ---'));
        expect(result.text, contains('--- Page 3 ---'));
      } finally {
        await directory.delete(recursive: true);
      }
    });

    test('a page-level failure is reported and does not abort the run', () async {
      final directory = await Directory.systemTemp.createTemp(
        'sickpdf_ocr_failure_',
      );
      Pdfrx.cacheDirectoryPath = directory.path;
      try {
        final file = await File('${directory.path}/input.pdf').writeAsBytes(
          scannedPdf(3),
        );
        final engine = _FakeEngine(
          answers: const {1: 'Satu', 3: 'Tiga'},
        )..failingPages.add(2);
        final service = _serviceWith(engine);
        final result = await service.extract(file.path);
        expect(result.failures.length, 1);
        expect(result.failures.first.pageNumber, 2);
        expect(result.text, contains('Satu'));
        expect(result.text, contains('Tiga'));
        expect(result.text, contains('[No text recognized on this page]'));
        expect(engine.closed, isTrue);
      } finally {
        await directory.delete(recursive: true);
      }
    });

    test('an empty result on every page is an error, not an empty file', () async {
      final directory = await Directory.systemTemp.createTemp(
        'sickpdf_ocr_empty_',
      );
      Pdfrx.cacheDirectoryPath = directory.path;
      try {
        final file = await File('${directory.path}/input.pdf').writeAsBytes(
          scannedPdf(2),
        );
        final service = _serviceWith(_FakeEngine());
        await expectLater(
          service.extract(file.path),
          throwsA(isA<PdfOcrException>()),
        );
      } finally {
        await directory.delete(recursive: true);
      }
    });

    test('cancellation stops the run and releases the engine', () async {
      final directory = await Directory.systemTemp.createTemp(
        'sickpdf_ocr_cancel_',
      );
      Pdfrx.cacheDirectoryPath = directory.path;
      try {
        final file = await File('${directory.path}/input.pdf').writeAsBytes(
          scannedPdf(5),
        );
        final engine = _FakeEngine(
          answers: const {1: 'Satu', 2: 'Dua', 3: 'Tiga', 4: 'Empat', 5: 'Lima'},
        );
        final service = _serviceWith(engine);
        var processed = 0;
        await expectLater(
          service.extract(
            file.path,
            isCancelled: () => processed >= 2,
            onProgress: (_) => processed++,
          ),
          throwsA(isA<PdfOcrCancelledException>()),
        );
        // The run stopped early, so the later pages were never sent to OCR.
        expect(engine.recognizedPages.length, lessThan(5));
        expect(engine.closed, isTrue);
      } finally {
        await directory.delete(recursive: true);
      }
    });

    test('a cancelled run reports no successful result', () async {
      final directory = await Directory.systemTemp.createTemp(
        'sickpdf_ocr_cancel_result_',
      );
      Pdfrx.cacheDirectoryPath = directory.path;
      try {
        final file = await File('${directory.path}/input.pdf').writeAsBytes(
          scannedPdf(3),
        );
        final service = _serviceWith(_FakeEngine());
        Object? caught;
        try {
          await service.extract(file.path, isCancelled: () => true);
        } catch (error) {
          caught = error;
        }
        expect(caught, isA<PdfOcrCancelledException>());
      } finally {
        await directory.delete(recursive: true);
      }
    });

    test('pages that already carry text skip the recognizer', () async {
      final directory = await Directory.systemTemp.createTemp(
        'sickpdf_ocr_text_layer_',
      );
      Pdfrx.cacheDirectoryPath = directory.path;
      try {
        final file = await File('${directory.path}/input.pdf').writeAsBytes(
          textPdf(2),
        );
        final engine = _FakeEngine();
        final service = _serviceWith(engine);
        expect(await service.hasExtractableText(file.path), isTrue);
        final result = await service.extract(file.path);
        expect(engine.recognizedPages, isEmpty);
        expect(result.extractedPages, 2);
        expect(result.text, contains('Page marker 1'));
        expect(result.text, contains('Page marker 2'));
      } finally {
        await directory.delete(recursive: true);
      }
    });

    test('the original file is never modified', () async {
      final directory = await Directory.systemTemp.createTemp(
        'sickpdf_ocr_source_',
      );
      Pdfrx.cacheDirectoryPath = directory.path;
      try {
        final original = scannedPdf(2);
        final file = await File('${directory.path}/input.pdf').writeAsBytes(
          original,
        );
        final service = _serviceWith(_FakeEngine(answers: const {1: 'A', 2: 'B'}));
        await service.extract(file.path);
        expect(await file.readAsBytes(), original);
      } finally {
        await directory.delete(recursive: true);
      }
    });

    test('a password-protected PDF asks for an unlocked copy', () async {
      final directory = await Directory.systemTemp.createTemp(
        'sickpdf_ocr_password_',
      );
      Pdfrx.cacheDirectoryPath = directory.path;
      try {
        final service = _serviceWith(_FakeEngine());
        await expectLater(
          service.extract('test/fixtures/password_required.pdf'),
          throwsA(
            isA<PdfOcrException>().having(
              (error) => error.message,
              'message',
              contains('requires a password'),
            ),
          ),
        );
      } finally {
        await directory.delete(recursive: true);
      }
    });

    test('a corrupt PDF reports a parse problem, not a crash', () async {
      final directory = await Directory.systemTemp.createTemp(
        'sickpdf_ocr_corrupt_',
      );
      Pdfrx.cacheDirectoryPath = directory.path;
      try {
        final file = await File('${directory.path}/corrupt.pdf').writeAsBytes(
          Uint8List.fromList(List<int>.filled(512, 0x41)),
        );
        final service = _serviceWith(_FakeEngine());
        await expectLater(
          service.extract(file.path),
          throwsA(
            isA<PdfOcrException>().having(
              (error) => error.message,
              'message',
              contains('damaged'),
            ),
          ),
        );
      } finally {
        await directory.delete(recursive: true);
      }
    });

    test('a cancelled run never writes an output file', () async {
      final directory = await Directory.systemTemp.createTemp(
        'sickpdf_ocr_cancel_write_',
      );
      Pdfrx.cacheDirectoryPath = directory.path;
      try {
        final file = await File('${directory.path}/input.pdf').writeAsBytes(
          scannedPdf(3),
        );
        final outputDirectory = Directory('${directory.path}/out');
        final service = _serviceWith(_FakeEngine(answers: const {1: 'A'}));
        // The cancel lands after the last page was recognized but before the
        // file is written.
        var pages = 0;
        await expectLater(
          service.extractToTextFile(
            file.path,
            outputDirectory: outputDirectory,
            fileName: 'out_ocr.txt',
            isCancelled: () => pages >= 1,
            onProgress: (_) => pages++,
          ),
          throwsA(isA<PdfOcrCancelledException>()),
        );
        final written = File('${outputDirectory.path}/out_ocr.txt');
        expect(await written.exists(), isFalse);
      } finally {
        await directory.delete(recursive: true);
      }
    });

    test('a page with no readable text is marked in the output', () async {
      final directory = await Directory.systemTemp.createTemp(
        'sickpdf_ocr_blank_page_',
      );
      Pdfrx.cacheDirectoryPath = directory.path;
      try {
        final file = await File('${directory.path}/input.pdf').writeAsBytes(
          scannedPdf(2),
        );
        // Page 2 has nothing on it.
        final service = _serviceWith(_FakeEngine(answers: const {1: 'Ada teks'}));
        final result = await service.extract(file.path);
        expect(result.processedPages, 1);
        expect(result.text, contains('Ada teks'));
        expect(result.text, contains(pdfOcrEmptyPageMarker));
      } finally {
        await directory.delete(recursive: true);
      }
    });

    test('a mixed document keeps text pages and recognizes scanned pages', () async {
      final directory = await Directory.systemTemp.createTemp(
        'sickpdf_ocr_mixed_',
      );
      Pdfrx.cacheDirectoryPath = directory.path;
      try {
        // Page 1 carries a text layer, page 2 does not.
        final objects = <String>[
          '<< /Type /Catalog /Pages 2 0 R >>',
          '<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>',
          // Page 1 has a text layer; page 2 is a bare scan.
          '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 300] '
              '/Resources << /Font << /F1 5 0 R >> >> /Contents 6 0 R >>',
          '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 300] >>',
          '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
        ];
        const content = 'BT /F1 12 Tf 20 40 Td (Halaman asli) Tj ET';
        final all = <String>[
          ...objects,
          '<< /Length ${content.length} >>\nstream\n$content\nendstream',
        ];
        final buffer = StringBuffer('%PDF-1.4\n');
        final offsets = <int>[];
        for (var i = 0; i < all.length; i++) {
          offsets.add(buffer.length);
          buffer.write('${i + 1} 0 obj\n${all[i]}\nendobj\n');
        }
        final xref = buffer.length;
        buffer.write('xref\n0 ${all.length + 1}\n0000000000 65535 f \n');
        for (final offset in offsets) {
          buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
        }
        buffer.write(
          'trailer\n<< /Size ${all.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n',
        );
        final file = await File('${directory.path}/mixed.pdf').writeAsBytes(
          Uint8List.fromList(buffer.toString().codeUnits),
        );
        final engine = _FakeEngine(answers: const {2: 'Teks hasil OCR'});
        final service = _serviceWith(engine);
        final result = await service.extract(file.path);
        // Only the scanned page went through the recognizer.
        expect(engine.recognizedPages, [2]);
        expect(result.extractedPages, 1);
        expect(result.processedPages, 2);
        expect(result.text, contains('Halaman asli'));
        expect(result.text, contains('Teks hasil OCR'));
        // The page order is preserved.
        expect(
          result.text.indexOf('Halaman asli'),
          lessThan(result.text.indexOf('Teks hasil OCR')),
        );
      } finally {
        await directory.delete(recursive: true);
      }
    });

    test('the rendered page reaches the engine at the page size', () async {
      final directory = await Directory.systemTemp.createTemp(
        'sickpdf_ocr_render_',
      );
      Pdfrx.cacheDirectoryPath = directory.path;
      try {
        final file = await File('${directory.path}/input.pdf').writeAsBytes(
          scannedPdf(1),
        );
        final engine = _FakeEngine(answers: const {1: 'Teks'});
        final service = _serviceWith(engine);
        await service.extract(file.path);
        expect(engine.renderedWidth, isNotNull);
        expect(engine.renderedHeight, isNotNull);
        // The synthetic page is 200x300 points at scale 2.0.
        expect(engine.renderedWidth, 400);
        expect(engine.renderedHeight, 600);
        // The pixel buffer matches the reported size.
        expect(
          engine.renderedPixels!.length,
          400 * 600 * 4,
        );
      } finally {
        await directory.delete(recursive: true);
      }
    });
  });

  group('engine', () {
    test('the ML Kit engine closes exactly once and refuses work afterwards', () async {
      final engine = MlKitOcrEngine();
      await engine.close();
      await engine.close();
      expect(
        () => engine.recognize(
          PdfOcrPageImage(
            pageNumber: 1,
            width: 2,
            height: 2,
            bgra: Uint8List(16),
          ),
        ),
        throwsStateError,
      );
    });

    test('the BGRA to NV21 conversion keeps the plane sizes', () {
      final rgba = Uint8List(4 * 4 * 4);
      final nv21 = bgraToNv21(rgba, 4, 4);
      // Luma plane plus a half-size chroma plane.
      expect(nv21.length, 4 * 4 + (4 * 4 ~/ 2));
    });

    test('the NV21 conversion maps white and black correctly', () {
      final white = Uint8List.fromList(
        List<int>.filled(2 * 2 * 4, 0xFF),
      );
      final black = Uint8List(2 * 2 * 4);
      final whiteNv21 = bgraToNv21(white, 2, 2);
      final blackNv21 = bgraToNv21(black, 2, 2);
      // Full-range luma: white is 235, black is 16.
      expect(whiteNv21[0], 235);
      expect(blackNv21[0], 16);
      // Neutral chroma sits at the mid point.
      expect(whiteNv21[4], closeTo(128, 2));
      expect(blackNv21[4], closeTo(128, 2));
    });
  });
}
