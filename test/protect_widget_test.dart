import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sickpdf/main.dart';
import 'package:sickpdf/screens/protect_pdf_page.dart';
import 'package:sickpdf/services/pdf_protect_service.dart';

class _Service extends PdfProtectService {
  bool loadFails = false;
  bool protectFails = false;
  int calls = 0;
  @override
  Future<Uint8List> load(String path) async {
    if (loadFails) {
      throw const PdfProtectException(
        'Could not open this PDF. It may be damaged or unsupported.',
      );
    }
    return Uint8List.fromList([1]);
  }

  @override
  Future<Uint8List> protect(
    Uint8List source,
    String password,
    String confirmation,
  ) async {
    calls++;
    if (protectFails) {
      throw const PdfProtectException('Could not protect this PDF.');
    }
    return Uint8List.fromList([2]);
  }
}

class _Picker extends FilePicker {
  bool fail = false;
  bool saveFails = false;
  String? destination;
  FilePickerResult? selection;
  Uint8List? saved;
  String? name;
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
    if (saveFails) throw Exception('sensitive failure details');
    saved = bytes;
    name = fileName;
    return destination;
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
  late _Picker picker;
  late _Service service;
  setUp(() {
    picker = _Picker();
    service = _Service();
    FilePicker.platform = picker;
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: ProtectPdfPage(service: service)),
    );
  }

  Future<void> select(WidgetTester tester) async {
    picker.selection = FilePickerResult([
      PlatformFile(name: 'input.pdf', size: 1, path: 'input.pdf'),
    ]);
    await tester.tap(find.text('Select PDF'));
    await tester.pumpAndSettle();
  }

  Future<void> password(
    WidgetTester tester,
    String value,
    String confirm,
  ) async {
    await tester.enterText(find.widgetWithText(TextField, 'Password'), value);
    await tester.enterText(
      find.widgetWithText(TextField, 'Confirm password'),
      confirm,
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
  }

  testWidgets('home entry opens Protect with exports disabled', (tester) async {
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MyApp());
    await tester.ensureVisible(find.text('Protect PDF'));
    await tester.tap(find.text('Protect PDF'));
    await tester.pumpAndSettle();
    expect(find.byType(ProtectPdfPage), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Save PDF'),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Preview PDF'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets(
    'empty/mismatched password blocks generation and visibility toggle works',
    (tester) async {
      await open(tester);
      await select(tester);
      expect(find.text('input.pdf'), findsOneWidget);
      expect(find.textContaining('Without it'), findsOneWidget);
      await tester.tap(find.text('Save PDF'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a password.'), findsOneWidget);
      await password(tester, 'secret', 'different');
      await tester.tap(find.text('Save PDF'));
      await tester.pumpAndSettle();
      expect(find.text('Passwords do not match.'), findsOneWidget);
      expect(service.calls, 0);
      expect(picker.saved, isNull);
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Password'))
            .obscureText,
        isTrue,
      );
      await tester.tap(find.byTooltip('Show passwords').first);
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Password'))
            .obscureText,
        isFalse,
      );
      await tester.tap(find.byTooltip('Hide passwords').first);
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Password'))
            .obscureText,
        isTrue,
      );
    },
  );

  testWidgets(
    'picker cancellation, failure, inaccessible and corrupt inputs are retryable',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('Select PDF'));
      await tester.pumpAndSettle();
      expect(find.text('Selection cancelled.'), findsOneWidget);
      picker.fail = true;
      await tester.tap(find.text('Select PDF'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not select'), findsOneWidget);
      picker.fail = false;
      picker.selection = FilePickerResult([
        PlatformFile(name: 'bad.pdf', size: 0),
      ]);
      await tester.tap(find.text('Select PDF'));
      await tester.pumpAndSettle();
      expect(find.text('The selected PDF cannot be accessed.'), findsOneWidget);
      service.loadFails = true;
      await select(tester);
      expect(find.textContaining('damaged or unsupported'), findsOneWidget);
      expect(picker.saved, isNull);
      service.loadFails = false;
      await select(tester);
      expect(find.text('input.pdf'), findsOneWidget);
    },
  );

  testWidgets(
    'process error, save failure, cancellation, success and edits invalidate output',
    (tester) async {
      await open(tester);
      await select(tester);
      await password(tester, 'secret', 'secret');
      service.protectFails = true;
      await tester.tap(find.text('Save PDF'));
      await tester.pumpAndSettle();
      expect(find.text('Could not protect this PDF.'), findsOneWidget);
      expect(picker.saved, isNull);
      service.protectFails = false;
      picker.saveFails = true;
      await tester.tap(find.text('Save PDF'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Save failed.'), findsOneWidget);
      expect(find.textContaining('sensitive failure'), findsNothing);
      picker.saveFails = false;
      await tester.tap(find.text('Save PDF'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Save cancelled.'), findsOneWidget);
      expect(picker.saved, [2]);
      expect(picker.name, 'input_protected.pdf');
      picker.destination = 'content://new-protected-file';
      await tester.tap(find.text('Save PDF'));
      await tester.pumpAndSettle();
      expect(find.text('Encrypted PDF saved successfully.'), findsOneWidget);
      expect(service.calls, 2);
      await password(tester, 'new secret', 'new secret');
      await tester.tap(find.text('Save PDF'));
      await tester.pumpAndSettle();
      expect(service.calls, 3);
      await select(tester);
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Password'))
            .controller!
            .text,
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
