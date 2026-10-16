import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sickpdf/main.dart';
import 'package:sickpdf/screens/sign_pdf_page.dart';
import 'package:sickpdf/widgets/signature_pad.dart';

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

void main() {
  testWidgets('Sign PDF tile opens the real workflow', (tester) async {
    tester.view.physicalSize = const Size(430, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Sign PDF'));
    await tester.tap(find.text('Sign PDF'));
    await tester.pumpAndSettle();
    expect(find.byType(SignPdfPage), findsOneWidget);
    expect(find.textContaining('coming soon'), findsNothing);
    expect(find.text('Select PDF'), findsOneWidget);
    expect(find.byType(SignaturePad), findsOneWidget);
    // Export is disabled until a PDF is loaded.
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Preview signed PDF'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('clear signature button is available after loading a PDF', (
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
    tester.view.physicalSize = const Size(430, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: SignPdfPage(pageCountLoader: (bytes, password) async => 3),
      ),
    );
    await tester.tap(find.text('Select PDF'));
    await tester.pumpAndSettle();
    expect(find.text('Clear signature'), findsOneWidget);
    expect(find.text('Target page'), findsOneWidget);
    // Preview is enabled once a PDF is loaded; the signature is validated
    // when pressed, producing a clear error instead of an empty export.
    await tester.tap(find.text('Preview signed PDF'));
    await tester.pumpAndSettle();
    expect(
      find.text('Draw your signature before continuing.'),
      findsOneWidget,
    );
  });

  testWidgets('picker cancellation and failure are safe and retryable', (
    tester,
  ) async {
    final picker = _Picker();
    FilePicker.platform = picker;
    addTearDown(() => FilePicker.platform = _Picker());
    await tester.pumpWidget(
      MaterialApp(
        home: SignPdfPage(pageCountLoader: (bytes, password) async => 1),
      ),
    );
    await tester.tap(find.text('Select PDF'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
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
