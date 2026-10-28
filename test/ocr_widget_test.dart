import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sickpdf/main.dart';
import 'package:sickpdf/screens/ocr_pdf_page.dart';
import 'package:sickpdf/screens/ocr_result_page.dart';
import 'package:sickpdf/services/pdf_ocr_engine.dart';
import 'package:sickpdf/services/pdf_ocr_service.dart';

/// A picker that never touches the platform.
class _Picker extends FilePicker {
  bool fail = false;
  FilePickerResult? selection;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    if (fail) throw Exception('picker failed');
    return selection;
  }
}

/// An OCR engine that returns fixed text and records the pages it saw.
class _FakeEngine implements PdfOcrEngine {
  static const text = 'Recognized text';

  final List<int> pages = [];
  bool closed = false;

  @override
  Future<String> recognize(PdfOcrPageImage image) async {
    pages.add(image.pageNumber);
    return text;
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

/// A service that never opens a real PDF.
///
/// The run is held open by [gate] so the progress state can be observed
/// before the result arrives.
class _FakeService extends PdfOcrService {
  _FakeService(this.engine);

  final _FakeEngine engine;
  int extractCalls = 0;
  bool throwCancelled = false;
  bool throwError = false;

  /// Released by the test to let the run finish.
  Completer<void>? gate;

  void release() {
    final pending = gate;
    gate = null;
    if (pending != null && !pending.isCompleted) pending.complete();
  }

  @override
  Future<int> pageCount(String path) async => 3;

  @override
  Future<PdfOcrResult> extract(
    String path, {
    void Function(PdfOcrProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    extractCalls++;
    if (throwCancelled) throw const PdfOcrCancelledException();
    if (throwError) {
      throw const PdfOcrException('No text was recognized in this PDF.');
    }
    for (var page = 1; page <= 3; page++) {
      onProgress?.call(
        PdfOcrProgress(
          pageNumber: page,
          totalPages: 3,
          text: _FakeEngine.text,
        ),
      );
    }
    final pending = gate;
    if (pending != null) await pending.future;
    return PdfOcrResult(
      text: '--- Page 1 ---\n${_FakeEngine.text}',
      pageCount: 3,
      processedPages: 3,
    );
  }
}

void main() {
  late _Picker picker;
  late _FakeEngine engine;
  late _FakeService service;
  late List<(String, Uint8List)> saves;

  setUp(() {
    picker = _Picker();
    engine = _FakeEngine();
    service = _FakeService(engine);
    saves = [];
    FilePicker.platform = picker;
  });

  tearDown(() {
    FilePicker.platform = _Picker();
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: OcrPdfPage(
          service: service,
          saveFile: (name, bytes) async {
            saves.add((name, bytes));
            return '/tmp/$name';
          },
          copyText: (_) async {},
          share: (_, _) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> select(WidgetTester tester) async {
    picker.selection = FilePickerResult([
      PlatformFile(name: 'scan.pdf', size: 10, path: 'scan.pdf'),
    ]);
    await tester.tap(find.text('Select PDF'));
    await tester.pumpAndSettle();
  }

  testWidgets('OCR PDF tile opens the real workflow', (tester) async {
    tester.view.physicalSize = const Size(430, 4200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text('OCR PDF'),
      find.byType(CustomScrollView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('OCR PDF'));
    await tester.pumpAndSettle();

    expect(find.byType(OcrPdfPage), findsOneWidget);
    expect(find.textContaining('coming soon'), findsNothing);
    expect(find.text('Select PDF'), findsOneWidget);
    expect(find.text('Extract Text'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Extract Text'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('selecting a PDF shows the name and page count', (tester) async {
    await open(tester);
    await select(tester);
    expect(find.text('scan.pdf'), findsOneWidget);
    expect(find.text('3 pages'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Extract Text'),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('extraction shows progress, then the result preview', (
    tester,
  ) async {
    await open(tester);
    await select(tester);
    service.gate = Completer<void>();

    await tester.tap(find.text('Extract Text'));
    await tester.pump();

    expect(find.textContaining('Processing page 3 of 3'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    service.release();
    await tester.pumpAndSettle();

    expect(service.extractCalls, 1);
    // The preview opens and shows the recognized text.
    expect(find.byType(OcrResultPage), findsOneWidget);
    expect(find.text('scan.pdf'), findsOneWidget);
    expect(find.textContaining('Recognized text'), findsWidgets);
    expect(find.text('Save TXT'), findsOneWidget);
    // Nothing has been written yet.
    expect(saves, isEmpty);
  });

  testWidgets('the preview is offered the derived output name', (
    tester,
  ) async {
    await open(tester);
    await select(tester);
    await tester.tap(find.text('Extract Text'));
    await tester.pumpAndSettle();

    expect(find.textContaining('scan_ocr.txt'), findsOneWidget);

    await tester.tap(find.text('Save TXT'));
    await tester.pumpAndSettle();

    expect(saves, hasLength(1));
    expect(saves.single.$1, 'scan_ocr.txt');
    expect(utf8.decode(saves.single.$2), contains('Recognized text'));
  });

  testWidgets('backing out of the preview creates no file', (tester) async {
    await open(tester);
    await select(tester);
    await tester.tap(find.text('Extract Text'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Discard'));
    await tester.pumpAndSettle();

    expect(find.byType(OcrPdfPage), findsOneWidget);
    expect(saves, isEmpty);
  });

  testWidgets('a second submission is refused while a run is active', (
    tester,
  ) async {
    await open(tester);
    await select(tester);
    service.gate = Completer<void>();

    await tester.tap(find.text('Extract Text'));
    await tester.pump();
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Extracting…'),
    );
    expect(button.onPressed, isNull);

    await tester.tap(find.text('Extracting…'), warnIfMissed: false);
    await tester.pump();
    expect(service.extractCalls, 1);

    service.release();
    await tester.pumpAndSettle();
    expect(service.extractCalls, 1);
  });

  testWidgets('a cancelled run reports no file and can be retried', (
    tester,
  ) async {
    await open(tester);
    await select(tester);
    service.throwCancelled = true;

    await tester.tap(find.text('Extract Text'));
    await tester.pumpAndSettle();

    expect(find.textContaining('cancelled'), findsOneWidget);
    expect(find.byType(OcrResultPage), findsNothing);

    service.throwCancelled = false;
    await tester.tap(find.text('Extract Text'));
    await tester.pumpAndSettle();
    expect(service.extractCalls, 2);
    expect(find.byType(OcrResultPage), findsOneWidget);
  });

  testWidgets('an OCR failure is shown as an error and can be retried', (
    tester,
  ) async {
    await open(tester);
    await select(tester);
    service.throwError = true;

    await tester.tap(find.text('Extract Text'));
    await tester.pumpAndSettle();

    expect(find.text('No text was recognized in this PDF.'), findsOneWidget);
    expect(find.byType(OcrResultPage), findsNothing);

    service.throwError = false;
    await tester.tap(find.text('Extract Text'));
    await tester.pumpAndSettle();
    expect(find.byType(OcrResultPage), findsOneWidget);
  });

  testWidgets('the empty state offers a way to pick a PDF', (tester) async {
    await open(tester);
    expect(find.text('Select one PDF to begin'), findsOneWidget);
    await tester.tap(find.text('Tap to select'));
    await tester.pumpAndSettle();
    expect(picker.selection, isNull);
    expect(find.text('Selection cancelled.'), findsOneWidget);
  });

  testWidgets('a picker failure is reported without crashing', (tester) async {
    await open(tester);
    picker.fail = true;
    await tester.tap(find.text('Select PDF'));
    await tester.pumpAndSettle();

    expect(
      find.text('Could not select the PDF. Please try again.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
