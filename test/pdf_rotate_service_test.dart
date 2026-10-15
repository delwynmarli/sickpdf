import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:sickpdf/services/pdf_organize_service.dart';
import 'package:sickpdf/services/pdf_rotate_service.dart';

import 'pdf_split_service_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('selected pages, all pages, CW, CCW and cumulative wrap', () {
    final state = PdfPageRotations(3);
    state.rotate({1}, 1);
    expect(state.turns, [0, 1, 0]);
    state.rotate({1}, 1);
    expect(state.turns, [0, 2, 0]);
    state.rotate({1}, 2);
    expect(state.turns, [0, 0, 0]);
    state.rotate({0, 1, 2}, -1);
    expect(state.turns, [3, 3, 3]);
    state.rotate({}, 1);
    expect(state.turns, [3, 3, 3]);
    expect(() => state.rotate({0, 4}, 1), throwsRangeError);
    expect(state.turns, [3, 3, 3]);
  });

  test(
    'real multipage export persists rotation and preserves source orientation',
    () async {
      final dir = await Directory.systemTemp.createTemp('rotate_test_');
      Pdfrx.cacheDirectoryPath = dir.path;
      PdfOrganizeSession? session;
      try {
        final seed = await PdfDocument.openData(fixture.syntheticPdf(3));
        late final List<int> original;
        try {
          seed.pages = [
            seed.pages[0].rotatedCW90(),
            seed.pages[1],
            seed.pages[2],
          ];
          original = await seed.encodePdf();
        } finally {
          await seed.dispose();
        }
        final file = await File('${dir.path}/input.pdf').writeAsBytes(original);
        session = await PdfOrganizeSession.open(file.path);
        for (final turns in [
          [1, 0, 3],
          [2, 0, 0],
          [0, 0, 0],
          [1, 1, 1],
        ]) {
          final bytes = await generateRotatedPdf(session.document, turns);
          final output = await PdfDocument.openData(bytes);
          try {
            expect(output.pages.length, 3);
            expect(output.pages.map((p) => p.rotation.index), [
              (1 + turns[0]) % 4,
              turns[1],
              turns[2],
            ]);
            for (var i = 0; i < 3; i++) {
              final source = session.document.pages[i];
              expect(
                output.pages[i].width,
                turns[i].isOdd ? source.height : source.width,
              );
              expect(
                output.pages[i].height,
                turns[i].isOdd ? source.width : source.height,
              );
            }
          } finally {
            await output.dispose();
          }
        }
        expect(session.document.pages.map((p) => p.rotation.index), [1, 0, 0]);
        expect(await file.readAsBytes(), original);
        await expectLater(
          generateRotatedPdf(session.document, []),
          throwsFormatException,
        );
        await expectLater(
          generateRotatedPdf(session.document, [4, 0, 0]),
          throwsFormatException,
        );
      } finally {
        await session?.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'missing, empty, corrupt and password protected inputs fail safely',
    () async {
      final dir = await Directory.systemTemp.createTemp('rotate_errors_');
      Pdfrx.cacheDirectoryPath = dir.path;
      try {
        await expectLater(
          PdfOrganizeSession.open('${dir.path}/missing.pdf'),
          throwsFormatException,
        );
        final file = await File('${dir.path}/bad.pdf').writeAsString('');
        await expectLater(
          PdfOrganizeSession.open(file.path),
          throwsFormatException,
        );
        await file.writeAsString('not a PDF');
        await expectLater(
          PdfOrganizeSession.open(file.path),
          throwsA(isA<Exception>()),
        );
        await expectLater(
          PdfOrganizeSession.open('test/fixtures/password_required.pdf'),
          throwsA(isA<PdfPasswordException>()),
        );
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}
