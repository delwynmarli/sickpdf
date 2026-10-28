import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sickpdf/screens/ocr_result_page.dart';
import 'package:sickpdf/services/document_share.dart';
import 'package:sickpdf/services/pdf_ocr_service.dart';

/// Records what the screen asked to save and can fail on demand.
class _Recorder {
  final List<(String, Uint8List)> saves = <(String, Uint8List)>[];
  final List<String> copies = <String>[];
  final List<(List<int>, String)> shares = <(List<int>, String)>[];

  /// Returned by the fake save dialog. `null` means "user cancelled".
  String? destination = '/tmp/out/scan_ocr.txt';

  bool failSave = false;
  bool failCopy = false;
  bool failShare = false;

  Future<String?> save(String fileName, Uint8List bytes) async {
    if (failSave) throw Exception('disk full');
    if (destination == null) return null;
    saves.add((fileName, bytes));
    return destination;
  }

  Future<void> copy(String text) async {
    if (failCopy) throw Exception('clipboard unavailable');
    copies.add(text);
  }

  Future<void> share(List<int> bytes, String fileName) async {
    if (failShare) {
      throw const DocumentShareException('Could not share this document.');
    }
    shares.add((bytes, fileName));
  }
}

PdfOcrResult _result({
  String text = '--- Page 1 ---\nHello world\n\n--- Page 2 ---\nSecond page',
  int pageCount = 2,
  int processedPages = 2,
  List<PdfOcrPageFailure> failures = const <PdfOcrPageFailure>[],
}) => PdfOcrResult(
  text: text,
  pageCount: pageCount,
  processedPages: processedPages,
  failures: failures,
);

void main() {
  late _Recorder recorder;

  setUp(() {
    recorder = _Recorder();
  });

  Future<void> open(
    WidgetTester tester,
    PdfOcrResult result, {
    String sourceName = 'scan.pdf',
    String outputName = 'scan_ocr.txt',
  }) async {
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: OcrResultPage(
          result: result,
          sourceName: sourceName,
          outputName: outputName,
          saveFile: recorder.save,
          copyText: recorder.copy,
          share: recorder.share,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('recognized text is shown before anything is saved', (
    tester,
  ) async {
    await open(tester, _result());

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, contains('Hello world'));
    expect(field.controller!.text, contains('Second page'));
    expect(recorder.saves, isEmpty, reason: 'nothing may be written on open');
  });

  testWidgets('page separators are preserved', (tester) async {
    await open(tester, _result());
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, contains('--- Page 1 ---'));
    expect(field.controller!.text, contains('--- Page 2 ---'));
  });

  testWidgets('the source name and page counts are shown', (tester) async {
    await open(tester, _result());
    expect(find.text('scan.pdf'), findsOneWidget);
    expect(find.textContaining('2 of 2 pages produced text'), findsOneWidget);
    expect(find.textContaining('scan_ocr.txt'), findsOneWidget);
  });

  testWidgets('Save TXT writes the recognized text', (tester) async {
    await open(tester, _result());

    await tester.tap(find.text('Save TXT'));
    await tester.pumpAndSettle();

    expect(recorder.saves, hasLength(1));
    final (name, bytes) = recorder.saves.single;
    expect(name, 'scan_ocr.txt');
    expect(utf8.decode(bytes), contains('Hello world'));
    expect(find.textContaining('Saved "scan_ocr.txt"'), findsOneWidget);
  });

  testWidgets('edited text is what gets saved', (tester) async {
    await open(tester, _result());

    await tester.enterText(find.byType(TextField), '--- Page 1 ---\nEdited');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save TXT'));
    await tester.pumpAndSettle();

    final (_, bytes) = recorder.saves.single;
    expect(utf8.decode(bytes), '--- Page 1 ---\nEdited');
  });

  testWidgets('the confirmation names the file that was really written', (
    tester,
  ) async {
    recorder.destination = '/storage/emulated/0/Download/scan_ocr (2).txt';
    await open(tester, _result());

    await tester.tap(find.text('Save TXT'));
    await tester.pumpAndSettle();

    expect(find.textContaining('scan_ocr (2).txt'), findsWidgets);
  });

  testWidgets('Copy Text uses the clipboard mechanism', (tester) async {
    await open(tester, _result());

    await tester.tap(find.text('Copy Text'));
    await tester.pumpAndSettle();

    expect(recorder.copies, hasLength(1));
    expect(recorder.copies.single, contains('Hello world'));
    expect(find.text('Text copied to the clipboard.'), findsOneWidget);
  });

  testWidgets('copied text includes the edits', (tester) async {
    await open(tester, _result());

    await tester.enterText(find.byType(TextField), 'edited copy');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy Text'));
    await tester.pumpAndSettle();

    expect(recorder.copies.single, 'edited copy');
  });

  testWidgets('Share sends the text as a txt file', (tester) async {
    await open(tester, _result());

    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();

    expect(recorder.shares, hasLength(1));
    expect(recorder.shares.single.$2, 'scan_ocr.txt');
    expect(utf8.decode(recorder.shares.single.$1), contains('Hello world'));
  });

  testWidgets('Cancel discards without creating a file', (tester) async {
    await open(tester, _result());

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    // The text was never saved, so a discard confirmation is offered.
    expect(find.text('Discard the text?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Discard'));
    await tester.pumpAndSettle();

    expect(recorder.saves, isEmpty);
    expect(find.byType(OcrResultPage), findsNothing);
  });

  testWidgets('a cancelled discard keeps the user on the result screen', (
    tester,
  ) async {
    await open(tester, _result());

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Keep editing'));
    await tester.pumpAndSettle();

    expect(find.byType(OcrResultPage), findsOneWidget);
    expect(recorder.saves, isEmpty);
  });

  testWidgets('backing out after saving does not ask again', (tester) async {
    await open(tester, _result());
    await tester.tap(find.text('Save TXT'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Discard the text?'), findsNothing);
    expect(find.byType(OcrResultPage), findsNothing);
  });

  testWidgets('a save dialog cancel keeps the text and writes nothing', (
    tester,
  ) async {
    recorder.destination = null;
    await open(tester, _result());

    await tester.tap(find.text('Save TXT'));
    await tester.pumpAndSettle();

    expect(recorder.saves, isEmpty);
    expect(find.textContaining('Save cancelled'), findsOneWidget);
    expect(find.byType(OcrResultPage), findsOneWidget);
  });

  testWidgets('an empty result cannot be saved', (tester) async {
    await open(tester, _result(text: '', processedPages: 0));

    await tester.tap(find.text('Save TXT'));
    await tester.pumpAndSettle();

    expect(recorder.saves, isEmpty);
    expect(find.text('There is no text to save.'), findsOneWidget);
  });

  testWidgets('an empty result is explained to the user', (tester) async {
    await open(tester, _result(text: '', processedPages: 0));
    expect(find.textContaining('No text recognized in 2 pages'), findsOneWidget);
  });

  testWidgets('a storage error is reported and the text is kept', (
    tester,
  ) async {
    recorder.failSave = true;
    await open(tester, _result());

    await tester.tap(find.text('Save TXT'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Save failed'), findsOneWidget);
    expect(find.byType(OcrResultPage), findsOneWidget);
  });

  testWidgets('a clipboard error is reported without crashing', (
    tester,
  ) async {
    recorder.failCopy = true;
    await open(tester, _result());

    await tester.tap(find.text('Copy Text'));
    await tester.pumpAndSettle();

    expect(find.text('Could not copy the text.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a share error is reported without crashing', (tester) async {
    recorder.failShare = true;
    await open(tester, _result());

    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();

    expect(find.text('Could not share this document.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pages that failed are named', (tester) async {
    await open(
      tester,
      _result(failures: [PdfOcrPageFailure(2, 'unreadable')]),
    );
    expect(find.textContaining('could not be read'), findsOneWidget);
    expect(find.textContaining('page 2'), findsOneWidget);
  });
}
