import 'dart:io';
import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sickpdf/main.dart';
import 'package:sickpdf/screens/rotate_pdf_page.dart';

import 'pdf_split_service_test.dart' as fixture;

class _Picker extends FilePicker {
  bool fail = false;
  bool saveFails = false;
  FilePickerResult? selection;
  Uint8List? saved;
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
    if (saveFails) throw Exception('save failed');
    saved = bytes;
    return null;
  }

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

void main() {
  testWidgets(
    'selection, select all, deselect, cumulative rotation and failed save',
    (tester) async {
      final picker = _Picker();
      FilePicker.platform = picker;
      final dir = Directory.systemTemp.createTempSync('rotate_widget_');
      Pdfrx.cacheDirectoryPath = dir.path;
      final file = File('${dir.path}/input.pdf')
        ..writeAsBytesSync(fixture.syntheticPdf(3));
      picker.selection = FilePickerResult([
        PlatformFile(
          name: 'input.pdf',
          size: file.lengthSync(),
          path: file.path,
        ),
      ]);
      await tester.pumpWidget(const MaterialApp(home: RotatePdfPage()));
      await tester.tap(find.text('Select PDF'));
      for (
        var i = 0;
        i < 40 && find.text('Select all').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      await tester.pump();
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();
      await tester.tap(find.text('90° clockwise'));
      await tester.pump();
      expect(find.text('Page 1 • +90°'), findsOneWidget);
      expect(find.text('Page 2 • +0°'), findsOneWidget);
      await tester.tap(find.text('Select all'));
      await tester.pump();
      expect(find.text('3 pages selected'), findsOneWidget);
      await tester.tap(find.text('90° counterclockwise'));
      await tester.pump();
      expect(find.text('Page 1 • +0°'), findsOneWidget);
      expect(find.text('Page 2 • +270°'), findsOneWidget);
      await tester.tap(find.text('Deselect all'));
      await tester.pump();
      expect(find.text('0 pages selected'), findsOneWidget);
      picker.saveFails = true;
      await tester.tap(find.text('Save PDF'));
      for (
        var i = 0;
        i < 40 && find.textContaining('Save failed.').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      expect(find.textContaining('Save failed.'), findsOneWidget);
      expect(find.text('PDF saved successfully.'), findsNothing);
      await tester.tap(find.text('Save PDF'));
      await tester.pump();
      picker.saveFails = false;
      await tester.tap(find.text('Save PDF'));
      await tester.pump();
      expect(find.textContaining('Save cancelled.'), findsOneWidget);
      expect(picker.saved, isNotEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      dir.deleteSync(recursive: true);
    },
  );
  testWidgets('Rotate home entry opens workflow with empty export disabled', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MyApp());
    await tester.ensureVisible(find.text('Rotate PDF'));
    await tester.tap(find.text('Rotate PDF'));
    await tester.pumpAndSettle();
    expect(find.byType(RotatePdfPage), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Preview PDF'),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Save PDF'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('picker cancellation and failure are safe and retryable', (
    tester,
  ) async {
    final picker = _Picker();
    FilePicker.platform = picker;
    addTearDown(() => FilePicker.platform = _Picker());
    await tester.pumpWidget(const MaterialApp(home: RotatePdfPage()));
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
    expect(find.text('PDF saved successfully.'), findsNothing);
  });
}
