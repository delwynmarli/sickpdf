import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sickpdf/main.dart';
import 'package:sickpdf/screens/organize_pdf_page.dart';

void main() {
  testWidgets(
    'Organize home tile opens working workflow with empty export disabled',
    (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MyApp());
      await tester.tap(find.text('Organize PDF'));
      await tester.pumpAndSettle();
      expect(find.byType(OrganizePdfPage), findsOneWidget);
      expect(find.textContaining('coming soon'), findsNothing);
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
              find.widgetWithText(FilledButton, 'Preview PDF'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Save PDF'),
            )
            .onPressed,
        isNull,
      );
    },
  );
}
