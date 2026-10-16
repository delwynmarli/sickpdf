import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sickpdf/services/pdf_add_text_service.dart';

import 'pdf_split_service_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('sickpdf/addtext');
  final messenger = TestDefaultBinaryMessengerBinding
      .instance
      .defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('rejects empty text, invalid font size and invalid pages', () {
    expect(
      validateAddTextOptions(const PdfAddTextOptions(text: '   '), 2),
      'Enter the text to add.',
    );
    expect(
      validateAddTextOptions(
        const PdfAddTextOptions(text: 'x', fontSize: 4),
        2,
      ),
      'Font size must be between 6 and 144.',
    );
    expect(
      validateAddTextOptions(
        const PdfAddTextOptions(text: 'x', fontSize: 200),
        2,
      ),
      'Font size must be between 6 and 144.',
    );
    expect(
      validateAddTextOptions(const PdfAddTextOptions(text: 'x'), 0),
      'This PDF has no valid pages.',
    );
    expect(
      validateAddTextOptions(
        const PdfAddTextOptions(text: 'x', pages: {}),
        2,
      ),
      'Select at least one valid page.',
    );
    expect(
      validateAddTextOptions(
        const PdfAddTextOptions(text: 'x', pages: {2}),
        2,
      ),
      'Select at least one valid page.',
    );
    expect(
      validateAddTextOptions(
        const PdfAddTextOptions(text: 'x', pages: {-1}),
        2,
      ),
      'Select at least one valid page.',
    );
  });

  test('accepts a valid single-page and all-page selection', () {
    expect(
      validateAddTextOptions(const PdfAddTextOptions(text: 'Hello'), 3),
      isNull,
    );
    expect(
      validateAddTextOptions(
        const PdfAddTextOptions(text: 'Hello', pages: {0, 2}),
        3,
      ),
      isNull,
    );
  });

  test('serializes alignment, vertical position and all-page config', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return Uint8List.fromList(fixture.syntheticPdf(2));
    });
    final result = await PdfAddTextService().apply(
      Uint8List.fromList(fixture.syntheticPdf(2)),
      const PdfAddTextOptions(
        text: 'CONFIDENTIAL',
        fontSize: 20,
        color: 0xFFD32F2F,
        alignment: AddTextAlignment.left,
        vertical: AddTextVerticalPosition.top,
      ),
    );
    expect(result, isNotEmpty);
    expect(received!.arguments['pages'], isNull);
    expect(received!.arguments['text'], 'CONFIDENTIAL');
    expect(received!.arguments['alignment'], 'left');
    expect(received!.arguments['vertical'], 'top');
    expect(received!.arguments['colorR'], closeTo(0xD3 / 255, 0.0001));
    expect(received!.arguments['colorG'], closeTo(0x2F / 255, 0.0001));
    expect(received!.arguments['colorB'], closeTo(0x2F / 255, 0.0001));
  });

  test('serializes selected pages sorted and preserves source bytes', () async {
    MethodCall? received;
    final source = Uint8List.fromList(fixture.syntheticPdf(3));
    final original = Uint8List.fromList(source);
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return source;
    });
    await PdfAddTextService().apply(
      source,
      const PdfAddTextOptions(text: 'DRAFT', pages: {2, 0}),
    );
    expect(received!.arguments['pages'], [0, 2]);
    expect(source, orderedEquals(original));
  });

  test('maps native export errors to safe messages', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async =>
          throw PlatformException(code: 'addtext_failed', message: 'secret'),
    );
    await expectLater(
      PdfAddTextService().apply(
        Uint8List.fromList(fixture.syntheticPdf(1)),
        const PdfAddTextOptions(text: 'x'),
      ),
      throwsA(
        isA<PdfAddTextException>().having(
          (e) => e.message,
          'message',
          isNot(contains('secret')),
        ),
      ),
    );
  });

  test('reports a friendly message for a non-Android platform', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw MissingPluginException(),
    );
    await expectLater(
      PdfAddTextService().apply(
        Uint8List.fromList(fixture.syntheticPdf(1)),
        const PdfAddTextOptions(text: 'x'),
      ),
      throwsA(
        isA<PdfAddTextException>().having(
          (e) => e.message,
          'message',
          'Add text to PDF is supported on Android only.',
        ),
      ),
    );
  });
}
