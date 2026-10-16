import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sickpdf/main.dart';
import 'package:sickpdf/screens/page_numbers_pdf_page.dart';

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
  testWidgets('Page Numbers tile opens workflow with empty export disabled', (
    tester,
  ) async {
    // Tall viewport keeps every grid tile built so the target is tappable.
    tester.view.physicalSize = const Size(430, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Page Numbers PDF'));
    await tester.tap(find.text('Page Numbers PDF'));
    await tester.pumpAndSettle();
    expect(find.byType(PageNumbersPdfPage), findsOneWidget);
    expect(find.textContaining('coming soon'), findsNothing);
    expect(find.text('Format'), findsOneWidget);
    expect(find.text('Position'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Preview numbered PDF'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('numbering and position options are all selectable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: PageNumbersPdfPage()));
    await tester.tap(find.text('1, 2, 3'));
    await tester.pumpAndSettle();
    for (final label in ['Page 1', 'Page 1 of N']) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.text('Page 1 of N').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bottom center'));
    await tester.pumpAndSettle();
    for (final label in [
      'Bottom left',
      'Bottom right',
      'Top left',
      'Top center',
      'Top right',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('picker cancellation and failure are safe and retryable', (
    tester,
  ) async {
    final picker = _Picker();
    FilePicker.platform = picker;
    addTearDown(() => FilePicker.platform = _Picker());
    await tester.pumpWidget(const MaterialApp(home: PageNumbersPdfPage()));
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
