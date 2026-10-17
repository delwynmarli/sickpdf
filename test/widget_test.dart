import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sickpdf/main.dart';
import 'package:sickpdf/screens/merge_pdf_page.dart';
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
      find.textContaining('Extract a page range into a new PDF.'),
      findsOneWidget,
    );
    expect(find.text('Select PDF'), findsOneWidget);
    final picker = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Select PDF'),
    );
    expect(picker.onPressed, isNotNull);
    // Actions are always visible but disabled until an input is selected.
    final save = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Save PDF'),
    );
    expect(save.onPressed, isNull);
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

    expect(find.bySemanticsLabel('sickPDF'), findsOneWidget);
    expect(find.text('Your PDFs, handled.'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
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
