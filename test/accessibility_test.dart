import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sickpdf/main.dart';
import 'package:sickpdf/navigation/tool_catalog.dart';

/// Accessibility-focused checks for the release-candidate UI.
///
/// These assert that key interactive elements expose a semantics label and are
/// reachable, and that status/text scaling do not break layouts.
void main() {
  testWidgets('every tool entry point exposes a labelled button', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 4200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    for (final tool in kTools) {
      final finder = find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label != null &&
            widget.properties.label!.startsWith(tool.name) &&
            (widget.properties.button ?? false),
      );
      expect(
        finder,
        findsWidgets,
        reason: 'Tool "${tool.name}" should be exposed as a labelled button',
      );
    }
  });

  testWidgets('navigation destinations have text labels', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('home renders without overflow at large text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
