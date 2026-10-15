import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sickpdf/services/pdf_merge_service.dart';

void main() {
  test('rejects fewer than two inputs before native processing', () async {
    await expectLater(
      PdfMergeService().merge(inputPaths: [], outputPath: 'unused.pdf'),
      throwsFormatException,
    );
  });

  test('rejects empty input and preserves the input file', () async {
    final directory = await Directory.systemTemp.createTemp('sickpdf_test_');
    try {
      final input = await File('${directory.path}/input.pdf').create();
      await expectLater(
        PdfMergeService().merge(
          inputPaths: [input.path, input.path],
          outputPath: '${directory.path}/output.pdf',
        ),
        throwsFormatException,
      );
      expect(await input.exists(), isTrue);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('refuses input overwrite without deleting the input', () async {
    final directory = await Directory.systemTemp.createTemp('sickpdf_test_');
    try {
      final input = await File('${directory.path}/input.pdf')
          .writeAsString('%PDF-1.7');
      await expectLater(
        PdfMergeService().merge(
          inputPaths: [input.path, input.path],
          outputPath: input.path,
        ),
        throwsFormatException,
      );
      expect(await input.readAsString(), '%PDF-1.7');
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
