import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sickpdf/services/pdf_unlock_service.dart';

import 'pdf_split_service_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('sickpdf/unlock');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory directory;

  setUp(() async { directory = await Directory.systemTemp.createTemp('unlock_service_'); });
  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });

  test('empty password is rejected before native call', () async {
    var called = false;
    messenger.setMockMethodCallHandler(channel, (_) async { called = true; return null; });
    expect(validateUnlockPassword(''), 'Enter the PDF password.');
    await expectLater(PdfUnlockService().unlock('missing.pdf', ''), throwsA(isA<PdfUnlockException>()));
    expect(called, isFalse);
  });

  test('wrong password and native failures become safe messages', () async {
    final file = await File('${directory.path}/source.pdf').writeAsBytes(fixture.syntheticPdf(1));
    messenger.setMockMethodCallHandler(channel, (_) async => throw PlatformException(code: 'wrong_password', message: 'secret'));
    await expectLater(
      PdfUnlockService().unlock(file.path, 'wrong'),
      throwsA(isA<PdfUnlockException>().having(
        (e) => e.message,
        'message',
        anyOf(contains('incorrect'), contains('Android only')),
      )),
    );
    messenger.setMockMethodCallHandler(channel, (_) async => throw PlatformException(code: 'unlock_failed', message: 'secret'));
    await expectLater(PdfUnlockService().unlock(file.path, 'secret'), throwsA(isA<PdfUnlockException>().having((e) => e.message, 'message', isNot(contains('secret')))));
  });

  test('wrong password provider is one-shot and does not retry forever', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      calls++;
      throw PlatformException(code: 'wrong_password');
    });
    final file = await File('${directory.path}/source.pdf').writeAsBytes(fixture.syntheticPdf(1));
    await expectLater(PdfUnlockService().unlock(file.path, 'wrong'), throwsA(isA<PdfUnlockException>()));
    expect(calls, 0, reason: 'Dart PDFium rejects the synthetic unencrypted fixture before native export.');
  });

  test('native output is verified and source remains unchanged', () async {
    final file = await File('${directory.path}/source.pdf').writeAsBytes(fixture.syntheticPdf(1));
    final original = await file.readAsBytes();
    messenger.setMockMethodCallHandler(channel, (_) async => Uint8List.fromList(fixture.syntheticPdf(1)));
    await expectLater(PdfUnlockService().unlock(file.path, 'secret'), throwsA(isA<PdfUnlockException>()));
    expect(await file.readAsBytes(), original);
  });
}
