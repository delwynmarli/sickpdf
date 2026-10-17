import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sickpdf/main.dart';
import 'package:sickpdf/screens/compress_pdf_page.dart';

void main() {
  testWidgets('Compress tile opens real workflow with honest supported mode', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text('Compress PDF'),
      find.byType(CustomScrollView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compress PDF'));
    await tester.pumpAndSettle();
    expect(find.byType(CompressPdfPage), findsOneWidget);
    expect(find.textContaining('coming soon'), findsNothing);
    expect(find.text('Compression level'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Select PDF'),
          )
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Compress PDF'),
          )
          .onPressed,
      isNull,
    );
    expect(find.text('Save PDF'), findsNothing);
  });
}
