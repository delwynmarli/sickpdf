import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sickpdf/main.dart';

void main() {
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
