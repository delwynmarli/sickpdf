import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sickpdf/services/pdf_watermark_service.dart';

import 'pdf_split_service_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('sickpdf/watermark');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('rejects blank watermark text and invalid page selection', () {
    expect(validateWatermarkOptions(const PdfWatermarkOptions(text: ''), 2), 'Enter watermark text.');
    expect(validateWatermarkOptions(const PdfWatermarkOptions(text: 'x', pages: {}), 2), 'Select at least one valid page.');
    expect(validateWatermarkOptions(const PdfWatermarkOptions(text: 'x', pages: {2}), 2), 'Select at least one valid page.');
  });

  test('serializes all-page, position, and rotation configuration', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return Uint8List.fromList(fixture.syntheticPdf(2));
    });
    final result = await PdfWatermarkService().apply(
      Uint8List.fromList(fixture.syntheticPdf(2)),
      const PdfWatermarkOptions(text: 'CONFIDENTIAL', position: WatermarkPosition.top, rotation: WatermarkRotation.horizontal),
    );
    expect(result, isNotEmpty);
    expect(received!.arguments['pages'], isNull);
    expect(received!.arguments['position'], 'top');
    expect(received!.arguments['rotation'], 'horizontal');
  });

  test('serializes selected pages and preserves source bytes', () async {
    final source = Uint8List.fromList(fixture.syntheticPdf(3));
    final original = Uint8List.fromList(source);
    messenger.setMockMethodCallHandler(channel, (call) async => source);
    await PdfWatermarkService().apply(source, const PdfWatermarkOptions(text: 'DRAFT', pages: {0, 2}));
    expect(source, orderedEquals(original));
  });

  test('maps native export errors to safe messages', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => throw PlatformException(code: 'watermark_failed', message: 'secret details'));
    await expectLater(PdfWatermarkService().apply(Uint8List.fromList(fixture.syntheticPdf(1)), const PdfWatermarkOptions(text: 'x')), throwsA(isA<PdfWatermarkException>().having((e) => e.message, 'message', isNot(contains('secret details')))));
  });
}
