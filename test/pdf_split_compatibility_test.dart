import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:sickpdf/services/pdf_split_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final path =
      Platform.environment['SICKPDF_COMPATIBILITY_PDF'] ??
      'test/fixtures/owner_encrypted.pdf';

  test(
    'load errors distinguish passwords, parsing, and access without paths',
    () {
      expect(
        pdfSplitLoadError(const PdfPasswordException('private detail')),
        contains('requires a password'),
      );
      expect(
        pdfSplitLoadError(const PdfException('private detail', 4)),
        contains('requires a password'),
      );
      expect(
        pdfSplitLoadError(const PdfException('private detail', 3)),
        contains('Could not parse'),
      );
      expect(
        pdfSplitLoadError(
          const FileSystemException('private detail', '/private/document.pdf'),
        ),
        contains('Could not read'),
      );
      expect(
        pdfSplitLoadError(const FormatException('This PDF has no pages.')),
        'This PDF has no pages.',
      );
      expect(
        pdfSplitLoadError(const PdfException('/private/document.pdf', 3)),
        isNot(contains('/private')),
      );
    },
  );

  final passwordPath =
      Platform.environment['SICKPDF_PASSWORD_PDF'] ??
      'test/fixtures/password_required.pdf';
  test('genuine password-protected PDF remains rejected', () async {
    final directory = await Directory.systemTemp.createTemp(
      'sickpdf_password_',
    );
    Pdfrx.cacheDirectoryPath = directory.path;
    try {
      await expectLater(
        PdfSplitService().pageCount(passwordPath),
        throwsA(isA<PdfPasswordException>()),
      );
      await expectLater(
        PdfSplitService().extract(passwordPath, const PdfPageRange(1, 1)),
        throwsA(isA<PdfPasswordException>()),
      );
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test(
    'local compatibility PDF opens and extracts without a password',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'sickpdf_compat_',
      );
      Pdfrx.cacheDirectoryPath = directory.path;
      try {
        await pdfrxFlutterInitialize();
        final source = await PdfDocument.openFile(
          path,
          passwordProvider: () => null,
        );
        try {
          // Only engine metadata; never print the private path or document contents.
          // ignore: avoid_print
          print(
            'PDF metadata: encrypted=${source.isEncrypted}, '
            'pages=${source.pages.length}, '
            'permissions=${source.permissions?.permissions}, '
            'revision=${source.permissions?.securityHandlerRevision}',
          );
        } finally {
          await source.dispose();
        }
        final service = PdfSplitService();
        final count = await service.pageCount(path);
        final end = count >= 5 ? 5 : count;
        final start = count >= 5 ? 2 : 1;
        final bytes = await service.extract(path, PdfPageRange(start, end));
        final extracted = await PdfDocument.openData(bytes);
        try {
          expect(extracted.pages.length, end - start + 1);
        } finally {
          await extracted.dispose();
        }
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
}
