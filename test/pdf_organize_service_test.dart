import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:sickpdf/services/pdf_organize_service.dart';

import 'pdf_split_service_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('zero-based source mapping follows forward and backward moves', () {
    final order = PdfPageOrder(5);
    order.move(0, 4);
    expect(order.pages, [1, 2, 3, 4, 0]);
    order.move(3, 0);
    expect(order.pages, [4, 1, 2, 3, 0]);
    order.move(2, 2);
    expect(order.pages, [4, 1, 2, 3, 0]);
    expect(() => order.pages.add(6), throwsUnsupportedError);
  });

  test('removal uses source identity, preserves order and supports undo', () {
    final order = PdfPageOrder(4)..move(3, 0);
    order.remove({0, 2});
    expect(order.pages, [3, 1]);
    order.move(1, 0);
    order.undoRemoval();
    expect(order.pages, [3, 0, 1, 2]);
    expect(order.canUndo, false);
    order.remove({3, 0, 1});
    expect(order.pages, [2]);
    expect(() => order.remove({2}), throwsFormatException);
    expect(order.pages, [2]);
  });

  test('export boundary rejects empty, duplicate and invalid indexes', () {
    for (final pages in <List<int>>[
      [],
      [-1],
      [3],
      [0, 0],
    ]) {
      expect(() => PdfPageOrder.validate(pages, 3), throwsFormatException);
    }
    PdfPageOrder.validate([2, 0], 3);
  });

  test(
    'real PDF export follows order, removal and single-page output',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'sickpdf_organize_test_',
      );
      Pdfrx.cacheDirectoryPath = dir.path;
      PdfOrganizeSession? session;
      try {
        final original = fixture.syntheticPdf(5);
        final file = await File('${dir.path}/input.pdf').writeAsBytes(original);
        session = await PdfOrganizeSession.open(file.path);
        expect(session.document.pages.length, 5);
        final thumbnail = await session.thumbnail(0);
        try {
          expect(thumbnail.width, lessThanOrEqualTo(160));
          expect(thumbnail.height, lessThanOrEqualTo(160));
          expect(thumbnail.width, greaterThan(0));
        } finally {
          thumbnail.dispose();
        }
        for (final order in [
          [4, 0, 2],
          [1],
          [0, 1, 2, 3, 4],
        ]) {
          final bytes = await session.generate(order);
          final output = await PdfDocument.openData(bytes);
          try {
            expect(output.pages.map((p) => p.width).toList(), [
              for (final i in order) 200.0 + i,
            ]);
          } finally {
            await output.dispose();
          }
        }
        await expectLater(session.generate([]), throwsFormatException);
        await expectLater(session.generate([5]), throwsFormatException);
        // Validation failures do not poison the serialized export queue.
        expect(await session.generate([0]), isNotEmpty);
        expect(await file.readAsBytes(), original);
        await session.close();
        await expectLater(session.generate([0]), throwsStateError);
      } finally {
        await session?.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'password-required, missing and corrupt PDFs fail; owner encryption loads',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'sickpdf_organize_errors_',
      );
      Pdfrx.cacheDirectoryPath = dir.path;
      try {
        await expectLater(
          PdfOrganizeSession.open('${dir.path}/missing.pdf'),
          throwsFormatException,
        );
        final bad = await File('${dir.path}/bad.pdf').writeAsString('not pdf');
        await expectLater(
          PdfOrganizeSession.open(bad.path),
          throwsA(isA<Exception>()),
        );
        await expectLater(
          PdfOrganizeSession.open('test/fixtures/password_required.pdf'),
          throwsA(isA<PdfPasswordException>()),
        );
        final owner = await PdfOrganizeSession.open(
          'test/fixtures/owner_encrypted.pdf',
        );
        try {
          expect(await owner.generate([0]), isNotEmpty);
        } finally {
          await owner.close();
        }
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}
