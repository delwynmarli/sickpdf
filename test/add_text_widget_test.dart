import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sickpdf/main.dart';
import 'package:sickpdf/screens/add_text_pdf_page.dart';
import 'package:sickpdf/services/pdf_add_text_service.dart';

import 'pdf_split_service_test.dart' as fixture;

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

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async => null;
}

class _FakeService extends PdfAddTextService {
  int calls = 0;
  PdfAddTextOptions? lastOptions;
  @override
  Future<Uint8List> apply(Uint8List input, PdfAddTextOptions options) async {
    calls++;
    lastOptions = options;
    return Uint8List.fromList(input);
  }
}

void main() {
  testWidgets('Add Text to PDF tile opens the real workflow', (tester) async {
    tester.view.physicalSize = const Size(430, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Add Text to PDF'));
    await tester.tap(find.text('Add Text to PDF'));
    await tester.pumpAndSettle();
    expect(find.byType(AddTextPdfPage), findsOneWidget);
    expect(find.textContaining('coming soon'), findsNothing);
    expect(find.text('Select PDF'), findsOneWidget);
    // Export is disabled until a PDF is loaded.
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Preview & Save'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('generates text for all pages and for a single page', (
    tester,
  ) async {
    final picker = _Picker()
      ..selection = FilePickerResult([
        PlatformFile(
          name: 'sample.pdf',
          size: 100,
          bytes: Uint8List.fromList(fixture.syntheticPdf(3)),
        ),
      ]);
    FilePicker.platform = picker;
    addTearDown(() => FilePicker.platform = _Picker());
    final service = _FakeService();
    tester.view.physicalSize = const Size(430, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: AddTextPdfPage(
          service: service,
          pageCountLoader: (bytes) async => 3,
        ),
      ),
    );
    await tester.tap(find.text('Select PDF'));
    await tester.pumpAndSettle();
    expect(find.textContaining('sample.pdf'), findsOneWidget);
    expect(find.textContaining('3 pages'), findsOneWidget);

    // Empty text is rejected before any processing is requested.
    await tester.tap(find.text('Preview & Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter the text to add.'), findsOneWidget);
    expect(service.calls, 0);

    // All pages: pages is null. Trimming is owned by the service under test,
    // so the widget forwards the field's current value.
    await tester.enterText(
      find.widgetWithText(TextField, 'Text to add'),
      '  Hello PDF  ',
    );
    await tester.pump();
    await tester.tap(find.text('Preview & Save'));
    await tester.pumpAndSettle();
    expect(service.calls, 1);
    expect(service.lastOptions!.pages, isNull);
    expect(service.lastOptions!.text.trim(), 'Hello PDF');

    // A successful preview pushes the output preview route; return to the
    // editor before changing settings.
    await tester.tap(find.text('Back to Add Text'));
    await tester.pumpAndSettle();

    // Single page selection passes the zero-based page index. Entering text
    // scrolled the list toward the field, so pull it back to reach the switch.
    await tester.drag(find.byType(ListView), const Offset(0, 600));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply to every page'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preview & Save'));
    await tester.pumpAndSettle();
    expect(service.calls, 2);
    expect(service.lastOptions!.pages, {0});
  });

  testWidgets('picker cancellation and failure are safe and retryable', (
    tester,
  ) async {
    final picker = _Picker();
    FilePicker.platform = picker;
    addTearDown(() => FilePicker.platform = _Picker());
    tester.view.physicalSize = const Size(430, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: AddTextPdfPage(pageCountLoader: (bytes) async => 1),
      ),
    );
    await tester.tap(find.text('Select PDF'));
    await tester.pumpAndSettle();
    expect(find.text('Selection cancelled.'), findsOneWidget);
    picker.fail = true;
    await tester.tap(find.text('Select PDF'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Select PDF'),
          )
          .onPressed,
      isNotNull,
    );
  });
}
