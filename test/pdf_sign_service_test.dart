import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sickpdf/services/pdf_sign_service.dart';

import 'pdf_split_service_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('sickpdf/sign');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('rejects empty signatures and invalid page selections', () {
    expect(
      validateSignOptions(
        PdfSignOptions(signaturePng: _empty, pageIndex: 0),
        2,
      ),
      'Draw or upload a signature first.',
    );
    expect(
      validateSignOptions(
        PdfSignOptions(signaturePng: _png, pageIndex: 5),
        2,
      ),
      'Choose a page between 1 and 2.',
    );
    expect(
      validateSignOptions(
        PdfSignOptions(signaturePng: _png, pageIndex: -1),
        2,
      ),
      'Choose a page between 1 and 2.',
    );
    expect(
      validateSignOptions(PdfSignOptions(signaturePng: _png, pageIndex: 0), 0),
      'This PDF has no valid pages.',
    );
  });

  test('rejects out-of-range size and opacity settings', () {
    expect(
      validateSignOptions(
        PdfSignOptions(signaturePng: _png, pageIndex: 0, widthFraction: 0),
        1,
      ),
      'Signature width must be between 1% and 100%.',
    );
    expect(
      validateSignOptions(
        PdfSignOptions(signaturePng: _png, pageIndex: 0, heightFraction: 2),
        1,
      ),
      'Signature height must be between 1% and 100%.',
    );
    expect(
      validateSignOptions(
        PdfSignOptions(signaturePng: _png, pageIndex: 0, opacity: 0),
        1,
      ),
      'Opacity must be between 1% and 100%.',
    );
  });

  test('accepts a well-formed signature request', () {
    expect(
      validateSignOptions(PdfSignOptions(signaturePng: _png, pageIndex: 1), 2),
      isNull,
    );
  });

  test('serializes placement configuration to the native channel', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return Uint8List.fromList(fixture.syntheticPdf(2));
    });
    final result = await PdfSignService().apply(
      Uint8List.fromList(fixture.syntheticPdf(2)),
      PdfSignOptions(
        signaturePng: _png,
        pageIndex: 1,
        position: SignaturePosition.topLeft,
        widthFraction: 0.4,
        heightFraction: 0.2,
        offsetXFraction: 0.05,
        offsetYFraction: 0.07,
        opacity: 0.8,
      ),
    );
    expect(result, isNotEmpty);
    expect(received!.method, 'sign');
    expect(received!.arguments['pageIndex'], 1);
    expect(received!.arguments['position'], 'topLeft');
    expect(received!.arguments['widthFraction'], 0.4);
    expect(received!.arguments['heightFraction'], 0.2);
    expect(received!.arguments['opacity'], 0.8);
  });

  test('preserves the source bytes and never mutates the input', () async {
    final source = Uint8List.fromList(fixture.syntheticPdf(3));
    final original = Uint8List.fromList(source);
    messenger.setMockMethodCallHandler(channel, (_) async => source);
    await PdfSignService().apply(
      source,
      PdfSignOptions(signaturePng: _png, pageIndex: 0),
    );
    expect(source, orderedEquals(original));
  });

  test('maps native export errors to safe messages', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async =>
          throw PlatformException(code: 'sign_failed', message: 'secret'),
    );
    await expectLater(
      PdfSignService().apply(
        Uint8List.fromList(fixture.syntheticPdf(1)),
        PdfSignOptions(signaturePng: _png, pageIndex: 0),
      ),
      throwsA(
        isA<PdfSignException>().having(
          (e) => e.message,
          'message',
          isNot(contains('secret')),
        ),
      ),
    );
  });

  test('rejects empty input before calling the channel', () async {
    await expectLater(
      PdfSignService().apply(
        Uint8List(0),
        PdfSignOptions(signaturePng: _png, pageIndex: 0),
      ),
      throwsA(isA<PdfSignException>()),
    );
  });
}

final _empty = Uint8List(0);
final _png = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 0, 1]);
