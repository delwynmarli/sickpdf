import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sickpdf/services/pdf_open_service.dart';
import 'package:sickpdf/widgets/locked_pdf_dialog.dart';

/// Stands in for the real PDF engine so the dialog can be exercised without
/// native code, while still reporting the same [PdfOpenException] contract.
class _Verifier {
  _Verifier({required this.password});

  /// The password that is accepted.
  final String password;

  /// When set, thrown for every attempt instead of checking [password].
  PdfOpenException? failure;

  final List<String> attempts = <String>[];

  Future<void> verify(String candidate) async {
    attempts.add(candidate);
    final forced = failure;
    if (forced != null) throw forced;
    if (candidate != password) {
      throw const PdfOpenException(
        pdfWrongPasswordMessage,
        wrongPassword: true,
      );
    }
  }
}

void main() {
  late _Verifier verifier;

  setUp(() {
    verifier = _Verifier(password: 'secret');
  });

  Future<String?> showDialogAndCapture(WidgetTester tester) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showLockedPdfDialog(
                    context: context,
                    fileName: 'locked.pdf',
                    verify: verifier.verify,
                  );
                },
                child: const Text('start'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('shows the document name, a password field, and actions', (
    tester,
  ) async {
    await showDialogAndCapture(tester);

    expect(find.text('Password required'), findsOneWidget);
    expect(find.textContaining('locked.pdf'), findsOneWidget);
    // Exactly one field, and it is labelled for the password.
    expect(find.byType(TextField), findsOneWidget);
    expect(find.widgetWithText(TextField, 'PDF password'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Open'), findsOneWidget);
    // The password starts hidden.
    expect(tester.widget<TextField>(find.byType(TextField)).obscureText, isTrue);
  });

  testWidgets('the password can be revealed and hidden again', (tester) async {
    await showDialogAndCapture(tester);

    expect(tester.widget<TextField>(find.byType(TextField)).obscureText, isTrue);
    await tester.tap(find.byTooltip('Show password'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).obscureText,
      isFalse,
    );

    await tester.tap(find.byTooltip('Hide password'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).obscureText, isTrue);
  });

  testWidgets('the correct password is returned to the caller', (
    tester,
  ) async {
    await showDialogAndCapture(tester);

    await tester.enterText(find.byType(TextField), 'secret');
    await tester.tap(find.widgetWithText(FilledButton, 'Open'));
    await tester.pumpAndSettle();

    expect(verifier.attempts, <String>['secret']);
    expect(find.byType(LockedPdfDialog), findsNothing);
  });

  testWidgets('a wrong password shows an error and allows a retry', (
    tester,
  ) async {
    await showDialogAndCapture(tester);

    await tester.enterText(find.byType(TextField), 'nope');
    await tester.tap(find.widgetWithText(FilledButton, 'Open'));
    await tester.pumpAndSettle();

    expect(find.text(pdfWrongPasswordMessage), findsOneWidget);
    // The dialog stays open for another attempt.
    expect(find.byType(LockedPdfDialog), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Open'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'secret');
    await tester.tap(find.widgetWithText(FilledButton, 'Open'));
    await tester.pumpAndSettle();

    expect(verifier.attempts, <String>['nope', 'secret']);
    expect(find.byType(LockedPdfDialog), findsNothing);
  });

  testWidgets('an empty password is refused without calling the verifier', (
    tester,
  ) async {
    await showDialogAndCapture(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Open'));
    await tester.pumpAndSettle();

    expect(find.text('Enter the PDF password.'), findsOneWidget);
    expect(verifier.attempts, isEmpty);
    expect(find.byType(LockedPdfDialog), findsOneWidget);
  });

  testWidgets('cancelling returns null and closes the dialog', (tester) async {
    await showDialogAndCapture(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(LockedPdfDialog), findsNothing);
    expect(verifier.attempts, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a non-password failure is shown and is not a retry prompt', (
    tester,
  ) async {
    verifier.failure = const PdfOpenException(
      'This PDF is damaged or uses an unsupported format.',
    );
    await showDialogAndCapture(tester);

    await tester.enterText(find.byType(TextField), 'secret');
    await tester.tap(find.widgetWithText(FilledButton, 'Open'));
    await tester.pumpAndSettle();

    expect(
      find.text('This PDF is damaged or uses an unsupported format.'),
      findsOneWidget,
    );
    expect(find.byType(LockedPdfDialog), findsOneWidget);
  });

  testWidgets('the typed password is never rendered as plain text', (
    tester,
  ) async {
    await showDialogAndCapture(tester);

    await tester.enterText(find.byType(TextField), 'secret');
    await tester.pumpAndSettle();

    // The field is obscured, so no plain Text widget may expose the value.
    // (find.text would also match EditableText's controller, so the check is
    // narrowed to real Text widgets.)
    expect(
      find.byWidgetPredicate((widget) => widget is Text && widget.data == 'secret'),
      findsNothing,
    );
    expect(tester.widget<TextField>(find.byType(TextField)).obscureText, isTrue);
  });

  testWidgets('the dialog explains that nothing is stored', (tester) async {
    await showDialogAndCapture(tester);
    expect(find.textContaining('password is not stored'), findsOneWidget);
  });
}