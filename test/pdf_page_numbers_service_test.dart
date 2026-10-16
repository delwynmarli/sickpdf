import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sickpdf/services/pdf_page_numbers_service.dart';

import 'pdf_split_service_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('sickpdf/pagenumbers');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  PdfPageNumbersOptions options({
    PageNumberFormat format = PageNumberFormat.plain,
    int start = 1,
    int first = 1,
    int last = 3,
    double fontSize = 12,
  }) => PdfPageNumbersOptions(
    format: format,
    startNumber: start,
    firstPage: first,
    lastPage: last,
    fontSize: fontSize,
  );

  test('builds each numbering format with the correct label', () {
    expect(pageNumberLabel(options(), 0), '1');
    expect(pageNumberLabel(options(), 2), '3');
    expect(
      pageNumberLabel(options(format: PageNumberFormat.page), 1),
      'Page 2',
    );
    expect(
      pageNumberLabel(options(format: PageNumberFormat.pageOfN), 0),
      'Page 1 of 3',
    );
    expect(
      pageNumberLabel(options(format: PageNumberFormat.pageOfN), 2),
      'Page 3 of 3',
    );
  });

  test('applies the starting number and offsets from the first page', () {
    final opts = options(start: 10, first: 2, last: 4, format: PageNumberFormat.plain);
    expect(pageNumberLabel(opts, 1), '10');
    expect(pageNumberLabel(opts, 2), '11');
    expect(pageNumberLabel(opts, 3), '12');
    // In "X of N" the total reflects the numbered range starting at startNumber.
    final ranged = options(start: 10, first: 2, last: 4, format: PageNumberFormat.pageOfN);
    expect(pageNumberLabel(ranged, 1), 'Page 10 of 12');
  });

  test('accepts valid ranges and rejects invalid ones', () {
    expect(validatePageNumberOptions(options(), 3), isNull);
    expect(
      validatePageNumberOptions(options(first: 2, last: 2), 3),
      isNull,
    );
    expect(
      validatePageNumberOptions(options(), 0),
      'This PDF has no valid pages.',
    );
    expect(
      validatePageNumberOptions(options(start: -1), 3),
      'Starting number cannot be negative.',
    );
    expect(
      validatePageNumberOptions(options(last: 4), 3),
      'Last page must be between 1 and 3.',
    );
    expect(
      validatePageNumberOptions(options(first: 0), 3),
      'First page must be between 1 and 3.',
    );
    expect(
      validatePageNumberOptions(options(first: 3, last: 2), 3),
      'First page must not exceed the last page.',
    );
    expect(
      validatePageNumberOptions(options(fontSize: 100), 3),
      'Font size must be between 6 and 72.',
    );
  });

  test('serializes configuration and preserves source bytes', () async {
    final source = Uint8List.fromList(fixture.syntheticPdf(4));
    final original = Uint8List.fromList(source);
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return source;
    });
    await PdfPageNumbersService().apply(
      source,
      const PdfPageNumbersOptions(
        format: PageNumberFormat.pageOfN,
        position: PageNumberPosition.topRight,
        startNumber: 5,
        firstPage: 2,
        lastPage: 4,
        fontSize: 14,
        color: 0xFF1565C0,
      ),
    );
    expect(source, orderedEquals(original));
    expect(received!.method, 'addPageNumbers');
    expect(received!.arguments['format'], 'pageOfN');
    expect(received!.arguments['position'], 'topRight');
    expect(received!.arguments['startNumber'], 5);
    expect(received!.arguments['firstPage'], 2);
    expect(received!.arguments['lastPage'], 4);
    // Color is split into normalized channels.
    expect(received!.arguments['colorR'], closeTo(0x15 / 255, 0.0001));
    expect(received!.arguments['colorG'], closeTo(0x65 / 255, 0.0001));
    expect(received!.arguments['colorB'], closeTo(0xC0 / 255, 0.0001));
  });

  test('rejects empty input before calling the platform', () async {
    await expectLater(
      PdfPageNumbersService().apply(
        Uint8List(0),
        const PdfPageNumbersOptions(firstPage: 1, lastPage: 1),
      ),
      throwsA(isA<PdfPageNumbersException>()),
    );
  });

  test('maps native errors to safe messages without leaking details', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(
        code: 'pagenumber_failed',
        message: 'secret native details',
      ),
    );
    await expectLater(
      PdfPageNumbersService().apply(
        Uint8List.fromList(fixture.syntheticPdf(1)),
        const PdfPageNumbersOptions(firstPage: 1, lastPage: 1),
      ),
      throwsA(
        isA<PdfPageNumbersException>().having(
          (e) => e.message,
          'message',
          isNot(contains('secret native details')),
        ),
      ),
    );
  });
}
