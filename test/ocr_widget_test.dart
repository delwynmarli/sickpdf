import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sickpdf/main.dart';
import 'package:sickpdf/screens/ocr_pdf_page.dart';
import 'package:sickpdf/services/pdf_ocr_engine.dart';
import 'package:sickpdf/services/pdf_ocr_service.dart';

/// A picker that never touches the platform.
class _Picker extends FilePicker {
  bool fail = false;
  FilePickerResult? selection;
  String? destination;
  Uint8List? saved;
  String? savedName;

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

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    saved = bytes;
    savedName = fileName;
    return destination;
  }
}

/// An OCR engine that returns fixed text and records the pages it saw.
class _FakeEngine implements PdfOcrEngine {
  /// Text the fake recognizer returns for every page.
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

  /// Name of the file the fake service was asked to write.
  String? writtenName;

  /// Released by the test to let the run finish.
  Completer<void>? gate;

  /// Lets the current run finish.
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
    // The run stays open until the test releases it, so the progress state
    // is observable.
    final pending = gate;
    if (pending != null) await pending.future;
    return PdfOcrResult(
      text: '--- Page 1 ---\n${_FakeEngine.text}',
      pageCount: 3,
      processedPages: 3,
    );
  }

  @override
  Future<PdfOcrOutput> extractToTextFile(
    String path, {
    required Directory outputDirectory,
    required String fileName,
    void Function(PdfOcrProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final result = await extract(
      path,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
    // The file is not really written: real file I/O does not complete inside
    // the widget test's fake-async zone. Writing is covered by the service
    // test, so the widget test stays focused on the UI.
    writtenName = fileName;
    return PdfOcrOutput(
      file: File(
        '${outputDirectory.path}${Platform.pathSeparator}$writtenFileName',
      ),
      result: result,
    );
  }

  /// Name the written file actually has, including any collision suffix.
  String writtenFileName = 'scan_ocr.txt';

  @override
  Future<Uint8List> readTextFile(String path) async =>
      Uint8List.fromList(utf8.encode('--- Page 1 ---\n${_FakeEngine.text}'));
}

void main() {
  late _Picker picker;
  late _FakeEngine engine;
  late _FakeService service;
  late Directory outputDirectory;

  setUp(() async {
    picker = _Picker();
    engine = _FakeEngine();
    service = _FakeService(engine);
    FilePicker.platform = picker;
    outputDirectory = await Directory.systemTemp.createTemp('sickpdf_ocr_ui_');
  });

  tearDown(() async {
    FilePicker.platform = _Picker();
    if (await outputDirectory.exists()) {
      await outputDirectory.delete(recursive: true);
    }
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: OcrPdfPage(service: service, outputDirectory: outputDirectory),
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
    // The primary action stays disabled until a PDF is selected.
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

  testWidgets('extraction shows progress and a successful result', (
    tester,
  ) async {
    await open(tester);
    await select(tester);
    service.gate = Completer<void>();

    await tester.tap(find.text('Extract Text'));
    await tester.pump();

    // The run is still going, so the progress is on screen.
    expect(find.textContaining('Processing page 3 of 3'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    service.release();
    await tester.pumpAndSettle();

    expect(service.extractCalls, 1);
    expect(find.textContaining('Text extracted'), findsOneWidget);
    expect(find.text('scan_ocr.txt'), findsOneWidget);
    expect(find.text('Save TXT'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    // The output was written under the expected name.
    expect(service.writtenName, 'scan_ocr.txt');
  });

  testWidgets('a second submission is refused while a run is active', (
    tester,
  ) async {
    await open(tester);
    await select(tester);
    service.gate = Completer<void>();

    await tester.tap(find.text('Extract Text'));
    // Pump a single frame so the button is still in its busy state.
    await tester.pump();
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Extracting…'),
    );
    expect(button.onPressed, isNull);

    // Tapping the disabled action again does not start a second run.
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
    expect(find.text('Save TXT'), findsNothing);
    // A cancelled run produces no output file at all.
    expect(service.writtenName, isNull);

    // The user can try again right away.
    service.throwCancelled = false;
    await tester.tap(find.text('Extract Text'));
    await tester.pumpAndSettle();
    expect(service.extractCalls, 2);
    expect(find.text('Save TXT'), findsOneWidget);
  });

  testWidgets('a failure is shown as an error and can be retried', (
    tester,
  ) async {
    await open(tester);
    await select(tester);
    service.throwError = true;

    await tester.tap(find.text('Extract Text'));
    await tester.pumpAndSettle();

    expect(
      find.text('No text was recognized in this PDF.'),
      findsOneWidget,
    );
    expect(find.text('Save TXT'), findsNothing);

    service.throwError = false;
    await tester.tap(find.text('Extract Text'));
    await tester.pumpAndSettle();
    expect(find.text('Save TXT'), findsOneWidget);
  });

  testWidgets('the empty state offers a way to pick a PDF', (tester) async {
    await open(tester);
    expect(find.text('Select one PDF to begin'), findsOneWidget);
    await tester.tap(find.text('Tap to select'));
    await tester.pumpAndSettle();
    expect(picker.selection, isNull);
    expect(find.text('Selection cancelled.'), findsOneWidget);
  });

  testWidgets('the output name shown is the file that was actually written', (
    tester,
  ) async {
    await open(tester);
    await select(tester);
    // The service renamed the file to avoid a collision.
    service.writtenFileName = 'scan_ocr (2).txt';

    await tester.tap(find.text('Extract Text'));
    await tester.pumpAndSettle();

    // The screen shows and offers the real name, not the requested one.
    expect(find.text('scan_ocr (2).txt'), findsOneWidget);
    expect(find.text('scan_ocr.txt'), findsNothing);

    await tester.tap(find.text('Save TXT'));
    await tester.pumpAndSettle();
    expect(picker.savedName, 'scan_ocr (2).txt');
  });

  testWidgets('saving writes the text through the system picker', (
    tester,
  ) async {
    await open(tester);
    await select(tester);
    await tester.tap(find.text('Extract Text'));
    await tester.pumpAndSettle();

    picker.destination = '/tmp/scan_ocr.txt';
    await tester.tap(find.text('Save TXT'));
    await tester.pumpAndSettle();

    expect(picker.savedName, 'scan_ocr.txt');
    expect(picker.saved, isNotNull);
    expect(
      utf8.decode(picker.saved!),
      contains('Recognized text'),
    );
  });
}
