import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:sickpdf/services/pdf_protect_service.dart';

import 'pdf_split_service_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('sickpdf/protect');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('protect_service_');
    Pdfrx.cacheDirectoryPath = directory.path;
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });

  test(
    'password validation: empty, whitespace, mismatch, limits and exact spaces',
    () {
      expect(validatePdfPassword('', ''), 'Enter a password.');
      expect(validatePdfPassword('   ', '   '), 'Enter a password.');
      expect(
        validatePdfPassword('secret', 'different'),
        'Passwords do not match.',
      );
      expect(
        validatePdfPassword(' secret ', 'secret'),
        'Passwords do not match.',
      );
      expect(validatePdfPassword(' secret ', ' secret '), isNull);
      expect(validatePdfPassword('z' * 127, 'z' * 127), isNull);
      expect(validatePdfPassword('z' * 128, 'z' * 128), isNotNull);
      expect(validatePdfPassword('caf\u00e9', 'caf\u00e9'), isNotNull);
      expect(validatePdfPassword('line\nbreak', 'line\nbreak'), isNotNull);
    },
  );

  test(
    'invalid validation never sends password or source to native engine',
    () async {
      var called = false;
      messenger.setMockMethodCallHandler(channel, (_) async {
        called = true;
        return null;
      });
      for (final values in [('', ''), ('a', 'b')]) {
        await expectLater(
          PdfProtectService().protect(Uint8List(0), values.$1, values.$2),
          throwsA(isA<PdfProtectException>()),
        );
      }
      expect(called, isFalse);
    },
  );

  test(
    'missing, empty, corrupt and encrypted source fail with safe messages',
    () async {
      final service = PdfProtectService();
      await expectLater(
        service.load('${directory.path}/missing.pdf'),
        throwsA(isA<PdfProtectException>()),
      );
      for (final bytes in [
        <int>[],
        [1, 2, 3],
      ]) {
        final file = await File('${directory.path}/invalid.pdf')
            .writeAsBytes(bytes);
        await expectLater(
          service.load(file.path),
          throwsA(isA<PdfProtectException>()),
        );
      }
      for (final name in ['password_required.pdf', 'owner_encrypted.pdf']) {
        await expectLater(
          service.load('test/fixtures/$name'),
          throwsA(
            isA<PdfProtectException>().having(
              (e) => e.message,
              'message',
              contains('encrypted copy'),
            ),
          ),
        );
      }
    },
  );

  test('native errors never expose exception details or passwords', () async {
    for (final code in ['protect_failed', 'locked_pdf', 'too_large']) {
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(
          code: code,
          message: 'secret should never appear',
          details: 'private',
        );
      });
      await expectLater(
        PdfProtectService().protect(
          fixture.syntheticPdf(2),
          'secret',
          'secret',
        ),
        throwsA(
          isA<PdfProtectException>().having(
            (e) => e.message,
            'safe message',
            isNot(contains('secret')),
          ),
        ),
      );
    }
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw MissingPluginException(),
    );
    await expectLater(
      PdfProtectService().protect(fixture.syntheticPdf(2), 'secret', 'secret'),
      throwsA(
        isA<PdfProtectException>().having(
          (e) => e.message,
          'platform',
          contains('Android only'),
        ),
      ),
    );
  });

  test(
    'null, empty, corrupt and unencrypted engine output fails closed',
    () async {
      final service = PdfProtectService();
      final file = await File('${directory.path}/source.pdf')
          .writeAsBytes(fixture.syntheticPdf(2));
      final original = await file.readAsBytes();
      final snapshot = await service.load(file.path);
      for (final output in [
        null,
        Uint8List(0),
        Uint8List.fromList([1]),
        fixture.syntheticPdf(2),
      ]) {
        messenger.setMockMethodCallHandler(channel, (_) async => output);
        await expectLater(
          service.protect(snapshot, 'secret', 'secret'),
          throwsA(isA<PdfProtectException>()),
        );
        expect(await file.readAsBytes(), original);
      }
    },
  );

  test('independent verifier accepts known required-password fixture and rejects wrong password', () async {
    final bytes = await File('test/fixtures/password_required.pdf')
        .readAsBytes();
    await verifyProtectedPdf(bytes, 'secret');
    await expectLater(
      verifyProtectedPdf(bytes, 'wrong'),
      throwsA(isA<PdfPasswordException>()),
    );
    await expectLater(
      verifyProtectedPdf(
        await File('test/fixtures/owner_encrypted.pdf').readAsBytes(),
        'owner',
      ),
      throwsA(isA<PdfProtectException>()),
    );
  });

  const proofPath = String.fromEnvironment('PROTECT_PROOF');
  test(
    'PDFium independently opens real PDFBox AES-256 output, renders content, rejects missing/wrong passwords and preserves source',
    () async {
      final input = File('$proofPath/source.pdf');
      final original = await input.readAsBytes();
      final bytes = await File('$proofPath/protected.pdf').readAsBytes();
      await verifyProtectedPdf(bytes, 'Test-only strong password 42!');
      var supplied = false;
      final document = await PdfDocument.openData(
        bytes,
        passwordProvider: () {
          if (supplied) return null;
          supplied = true;
          return 'Test-only strong password 42!';
        },
      );
      try {
        expect(document.pages.length, 2);
        final image = await document.pages.first.render(
          width: 100,
          height: 100,
        );
        expect(image, isNotNull);
        image?.dispose();
      } finally {
        await document.dispose();
      }
      // Run the complete production Dart service against bytes from the native writer.
      messenger.setMockMethodCallHandler(channel, (_) async => bytes);
      expect(
        await PdfProtectService().protect(
          original,
          'Test-only strong password 42!',
          'Test-only strong password 42!',
        ),
        bytes,
      );
      expect(await input.readAsBytes(), original);
    },
    skip: proofPath.isEmpty
        ? 'Run native PdfProtectorTest first, then pass --dart-define=PROTECT_PROOF=build/protect-proof'
        : false,
  );
}
