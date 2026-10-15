import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sickpdf/main.dart';
import 'package:sickpdf/screens/split_pdf_page.dart';

void main() {
  testWidgets('Split tile opens real workflow, never coming-soon placeholder', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MyApp());
    await tester.tap(find.text('Split PDF'));
    await tester.pumpAndSettle();
    expect(find.byType(SplitPdfPage), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.textContaining('coming soon'), findsNothing);
    expect(
      find.text('Extract pages privately on your device.'),
      findsOneWidget,
    );
    expect(find.text('Select PDF'), findsOneWidget);
    final picker = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Select PDF'),
    );
    expect(picker.onPressed, isNotNull);
    expect(find.text('Save PDF'), findsNothing);
    final action = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Split PDF'),
    );
    expect(action.onPressed, isNull);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Merge PDF'));
    await tester.pumpAndSettle();
    expect(find.byType(MergePdfPage), findsOneWidget);
  });
  testWidgets('Home screen shows the sickPDF foundation', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('sickPDF'), findsOneWidget);
    expect(find.text('Your files stay yours.'), findsOneWidget);
    expect(find.text('100% OFFLINE'), findsOneWidget);
    expect(find.text('Merge PDF'), findsOneWidget);
  });
  testWidgets('Merge screen exposes merge controls and reorder guidance', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: MergePdfPage()));

    expect(find.text('Merge PDF'), findsNWidgets(2));
    expect(find.text('Select PDF files'), findsOneWidget);
    expect(find.text('Reorder your PDFs before merging'), findsNothing);
    expect(find.text('Save PDF'), findsOneWidget);
  });
}
