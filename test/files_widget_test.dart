import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sickpdf/screens/files_page.dart';
import 'package:sickpdf/services/document_library.dart';
import 'package:sickpdf/services/document_share.dart';
import 'package:sickpdf/services/pdf_open_service.dart';
import 'package:sickpdf/widgets/locked_pdf_dialog.dart';

/// A fake open service so no native PDF engine is needed.
///
/// Records every password the viewer was handed, which is how the tests prove
/// that the verified password reaches the viewer and that only the verified
/// value does.
class _FakeOpenService implements PdfOpenApi {
  _FakeOpenService({this.needsPassword = false});

  bool needsPassword;

  /// Passwords the fake accepts. Any other password is rejected.
  final Set<String> accepted = <String>{'secret'};

  /// When set, [requiresPassword] throws it instead of answering.
  PdfOpenException? detectionFailure;

  final List<String> detectCalls = <String>[];
  final List<String> verifyCalls = <String>[];

  @override
  Future<bool> requiresPassword(String path) async {
    detectCalls.add(path);
    final failure = detectionFailure;
    if (failure != null) throw failure;
    return needsPassword;
  }

  @override
  Future<void> verifyPassword(String path, String password) async {
    verifyCalls.add(password);
    if (!accepted.contains(password)) {
      throw const PdfOpenException(
        pdfWrongPasswordMessage,
        wrongPassword: true,
      );
    }
  }
}

/// An in-memory store, so these tests never read or delete a real document.
class _MemoryLibrary implements DocumentLibraryApi {
  _MemoryLibrary({List<LibraryDocument>? docs}) : _docs = docs ?? [];

  final List<LibraryDocument> _docs;
  final Set<String> missing = <String>{};

  /// Sources the fake store pretends to import.
  final Map<String, String> importable = <String, String>{};

  bool failImport = false;
  int listCalls = 0;

  @override
  Future<List<LibraryDocument>> list() async {
    listCalls++;
    return List<LibraryDocument>.from(_docs);
  }

  @override
  Future<LibraryDocument> addFromPath(
    String sourcePath, {
    String? displayName,
  }) async {
    if (failImport) {
      throw const LibraryException('Could not copy this file into sickPDF.');
    }
    final source = importable[sourcePath];
    if (source == null) {
      throw const LibraryException('That file is no longer available.');
    }
    final doc = LibraryDocument(
      id: 'id-${_docs.length + 1}',
      fileName: source,
      storedPath: '/library/documents/$source',
      fileSize: 1024,
      addedAt: DateTime(2026, 1, _docs.length + 1),
      modifiedAt: DateTime(2026, 1, _docs.length + 1),
    );
    _docs.insert(0, doc);
    return doc;
  }

  @override
  Future<LibraryDocument> addFromBytes(
    List<int> bytes, {
    String? displayName,
  }) async {
    final name = displayName ?? 'document.pdf';
    final doc = LibraryDocument(
      id: 'id-${_docs.length + 1}',
      fileName: name,
      storedPath: '/library/documents/$name',
      fileSize: bytes.length,
      addedAt: DateTime(2026, 1, 1),
      modifiedAt: DateTime(2026, 1, 1),
    );
    _docs.insert(0, doc);
    return doc;
  }

  @override
  Future<LibraryDocument> rename(
    LibraryDocument doc,
    String newName,
  ) async {
    final sanitized = sanitizePdfFileName(newName);
    final index = _docs.indexWhere((d) => d.id == doc.id);
    final renamed = doc.copyWith(
      fileName: sanitized,
      storedPath: '/library/documents/$sanitized',
    );
    if (index >= 0) _docs[index] = renamed;
    return renamed;
  }

  @override
  Future<void> remove(LibraryDocument doc) async {
    _docs.removeWhere((d) => d.id == doc.id);
  }

  @override
  Future<bool> isAvailable(LibraryDocument doc) async =>
      !missing.contains(doc.id);

  @override
  Future<Uint8List> readBytes(LibraryDocument doc) async {
    if (missing.contains(doc.id)) {
      throw const LibraryException(
        'This document is no longer in sickPDF storage.',
      );
    }
    return Uint8List.fromList(const <int>[37, 80, 68, 70]);
  }
}

LibraryDocument _doc(String id, String name, {int day = 1}) => LibraryDocument(
  id: id,
  fileName: name,
  storedPath: '/library/documents/$name',
  fileSize: 2048,
  addedAt: DateTime(2026, 1, day),
  modifiedAt: DateTime(2026, 1, day),
);

void main() {
  late _MemoryLibrary library;

  setUp(() {
    library = _MemoryLibrary();
  });

  Future<void> open(
    WidgetTester tester, {
    Future<String?> Function()? pickPath,
    DocumentShare? share,
    PdfOpenApi? openService,
    Widget Function(LibraryDocument doc, String password)? viewerBuilder,
  }) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: FilesPage(
          library: library,
          pickPath: pickPath,
          share: share,
          openService: openService,
          viewerBuilder: viewerBuilder,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openMenu(WidgetTester tester, String fileName) async {
    await tester.tap(find.byTooltip('Actions for $fileName'));
    await tester.pumpAndSettle();
  }

  testWidgets('empty state explains how to add a document', (tester) async {
    await open(tester);
    expect(find.text('No documents yet'), findsOneWidget);
    expect(find.textContaining('Import a PDF'), findsWidgets);
    expect(find.textContaining('stay in this list'), findsOneWidget);
  });

  testWidgets('importing a PDF adds it to the list', (tester) async {
    library.importable['/picker/scan.pdf'] = 'scan.pdf';
    await open(tester, pickPath: () async => '/picker/scan.pdf');

    await tester.tap(find.widgetWithText(FilledButton, 'Import a PDF'));
    await tester.pumpAndSettle();

    expect(find.text('scan.pdf'), findsOneWidget);
    expect(find.textContaining('Added "scan.pdf" to Files'), findsOneWidget);
  });

  testWidgets('a cancelled import reports and adds nothing', (tester) async {
    await open(tester, pickPath: () async => null);

    await tester.tap(find.widgetWithText(FilledButton, 'Import a PDF'));
    await tester.pumpAndSettle();

    expect(find.text('Import cancelled.'), findsOneWidget);
    expect(find.text('No documents yet'), findsOneWidget);
  });

  testWidgets('a failed import shows the reason and no document', (
    tester,
  ) async {
    library.importable['/picker/broken.pdf'] = 'broken.pdf';
    library.failImport = true;
    await open(tester, pickPath: () async => '/picker/broken.pdf');

    await tester.tap(find.widgetWithText(FilledButton, 'Import a PDF'));
    await tester.pumpAndSettle();

    expect(
      find.text('Could not copy this file into sickPDF.'),
      findsOneWidget,
    );
    expect(find.text('No documents yet'), findsOneWidget);
  });

  testWidgets('documents stored earlier appear on open', (tester) async {
    library = _MemoryLibrary(
      docs: [_doc('1', 'kept.pdf'), _doc('2', 'older.pdf', day: 2)],
    );
    await open(tester);

    expect(find.text('kept.pdf'), findsOneWidget);
    expect(find.text('older.pdf'), findsOneWidget);
    expect(find.text('No documents yet'), findsNothing);
  });

  testWidgets('the list reloads when the tab becomes visible', (tester) async {
    library = _MemoryLibrary();
    await tester.pumpWidget(
      MaterialApp(
        home: FilesPage(library: library, active: false),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No documents yet'), findsOneWidget);

    // A tool added a document while the tab was hidden.
    await library.addFromBytes(const <int>[1, 2, 3], displayName: 'new.pdf');

    await tester.pumpWidget(
      MaterialApp(
        home: FilesPage(library: library, active: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('new.pdf'), findsOneWidget);
  });

  testWidgets('rename updates the entry', (tester) async {
    library = _MemoryLibrary(docs: [_doc('1', 'before.pdf')]);
    await open(tester);
    await openMenu(tester, 'before.pdf');

    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'after');
    await tester.tap(find.widgetWithText(TextButton, 'Rename'));
    await tester.pumpAndSettle();

    expect(find.text('after.pdf'), findsOneWidget);
    expect(find.text('before.pdf'), findsNothing);
    expect(find.textContaining('Renamed to "after.pdf"'), findsOneWidget);
  });

  testWidgets('a rename dialog can be dismissed without changes', (
    tester,
  ) async {
    library = _MemoryLibrary(docs: [_doc('1', 'same.pdf')]);
    await open(tester);
    await openMenu(tester, 'same.pdf');

    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('same.pdf'), findsOneWidget);
  });

  testWidgets('delete asks first and keeps the document on cancel', (
    tester,
  ) async {
    library = _MemoryLibrary(docs: [_doc('1', 'keep.pdf')]);
    await open(tester);
    await openMenu(tester, 'keep.pdf');

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Remove document?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('keep.pdf'), findsOneWidget);
  });

  testWidgets('confirmed delete removes the document', (tester) async {
    library = _MemoryLibrary(docs: [_doc('1', 'bye.pdf')]);
    await open(tester);
    await openMenu(tester, 'bye.pdf');

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Remove'));
    await tester.pumpAndSettle();

    expect(find.text('bye.pdf'), findsNothing);
    expect(find.text('No documents yet'), findsOneWidget);
  });

  testWidgets('share sends the stored bytes and the real name', (tester) async {
    library = _MemoryLibrary(docs: [_doc('1', 'share me.pdf')]);
    final shared = <(List<int>, String)>[];
    await open(
      tester,
      share: (bytes, name) async => shared.add((bytes, name)),
    );
    await openMenu(tester, 'share me.pdf');

    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();

    expect(shared, hasLength(1));
    expect(shared.single.$2, 'share me.pdf');
    expect(shared.single.$1, hasLength(4));
    expect(find.textContaining('Opening share options'), findsOneWidget);
  });

  testWidgets('a missing stored file is reported, not silently deleted', (
    tester,
  ) async {
    library = _MemoryLibrary(docs: [_doc('1', 'gone.pdf')]);
    library.missing.add('1');
    await open(tester);

    await tester.tap(find.text('gone.pdf'));
    await tester.pumpAndSettle();

    expect(find.text('Document not found'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Keep'));
    await tester.pumpAndSettle();
    expect(find.text('gone.pdf'), findsOneWidget);
  });

  testWidgets('a missing file entry can be removed from the dialog', (
    tester,
  ) async {
    library = _MemoryLibrary(docs: [_doc('1', 'gone.pdf')]);
    library.missing.add('1');
    await open(tester);

    await tester.tap(find.text('gone.pdf'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Remove entry'));
    await tester.pumpAndSettle();

    expect(find.text('No documents yet'), findsOneWidget);
  });

  testWidgets('the storage note is visible with documents present', (
    tester,
  ) async {
    library = _MemoryLibrary(docs: [_doc('1', 'a.pdf')]);
    await open(tester);
    expect(find.textContaining('Uninstalling'), findsOneWidget);
  });

  group('opening a document', () {
    /// Records the password each opened viewer received.
    Widget fakeViewer(LibraryDocument doc, String password) => Scaffold(
      body: Center(child: Text('viewer:${doc.fileName}|$password')),
    );

    testWidgets('an unprotected PDF opens without a password prompt', (
      tester,
    ) async {
      final service = _FakeOpenService();
      library = _MemoryLibrary(docs: [_doc('1', 'plain.pdf')]);
      await open(tester, openService: service, viewerBuilder: fakeViewer);

      await tester.tap(find.text('plain.pdf'));
      await tester.pumpAndSettle();

      expect(find.byType(LockedPdfDialog), findsNothing);
      expect(find.text('viewer:plain.pdf|'), findsOneWidget);
      expect(service.detectCalls, hasLength(1));
      expect(service.verifyCalls, isEmpty);
    });

    testWidgets('a protected PDF shows the password prompt', (tester) async {
      final service = _FakeOpenService(needsPassword: true);
      library = _MemoryLibrary(docs: [_doc('1', 'locked.pdf')]);
      await open(tester, openService: service, viewerBuilder: fakeViewer);

      await tester.tap(find.text('locked.pdf'));
      await tester.pumpAndSettle();

      expect(find.byType(LockedPdfDialog), findsOneWidget);
      expect(find.textContaining('locked.pdf'), findsWidgets);
      // Nothing is opened until a password is accepted.
      expect(find.textContaining('viewer:'), findsNothing);
    });

    testWidgets('the correct password opens the document', (tester) async {
      final service = _FakeOpenService(needsPassword: true);
      library = _MemoryLibrary(docs: [_doc('1', 'locked.pdf')]);
      await open(tester, openService: service, viewerBuilder: fakeViewer);

      await tester.tap(find.text('locked.pdf'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'secret');
      await tester.tap(find.widgetWithText(FilledButton, 'Open'));
      await tester.pumpAndSettle();

      expect(service.verifyCalls, <String>['secret']);
      expect(find.byType(LockedPdfDialog), findsNothing);
      // The verified password reached the viewer.
      expect(find.text('viewer:locked.pdf|secret'), findsOneWidget);
    });

    testWidgets('a wrong password keeps the prompt open for another try', (
      tester,
    ) async {
      final service = _FakeOpenService(needsPassword: true);
      library = _MemoryLibrary(docs: [_doc('1', 'locked.pdf')]);
      await open(tester, openService: service, viewerBuilder: fakeViewer);

      await tester.tap(find.text('locked.pdf'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'guess');
      await tester.tap(find.widgetWithText(FilledButton, 'Open'));
      await tester.pumpAndSettle();

      expect(find.text(pdfWrongPasswordMessage), findsOneWidget);
      expect(find.byType(LockedPdfDialog), findsOneWidget);
      expect(find.textContaining('viewer:'), findsNothing);

      await tester.enterText(find.byType(TextField), 'secret');
      await tester.tap(find.widgetWithText(FilledButton, 'Open'));
      await tester.pumpAndSettle();

      expect(find.text('viewer:locked.pdf|secret'), findsOneWidget);
      expect(service.verifyCalls, <String>['guess', 'secret']);
    });

    testWidgets('cancelling the prompt returns to Files without opening', (
      tester,
    ) async {
      final service = _FakeOpenService(needsPassword: true);
      library = _MemoryLibrary(docs: [_doc('1', 'locked.pdf')]);
      await open(tester, openService: service, viewerBuilder: fakeViewer);

      await tester.tap(find.text('locked.pdf'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(LockedPdfDialog), findsNothing);
      expect(find.textContaining('viewer:'), findsNothing);
      expect(find.text('locked.pdf'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a damaged PDF is reported without a password prompt', (
      tester,
    ) async {
      final service = _FakeOpenService()
        ..detectionFailure = const PdfOpenException(
          'This PDF is damaged or uses an unsupported format.',
        );
      library = _MemoryLibrary(docs: [_doc('1', 'broken.pdf')]);
      await open(tester, openService: service, viewerBuilder: fakeViewer);

      await tester.tap(find.text('broken.pdf'));
      await tester.pumpAndSettle();

      expect(find.byType(LockedPdfDialog), findsNothing);
      expect(
        find.text('This PDF is damaged or uses an unsupported format.'),
        findsOneWidget,
      );
      expect(find.textContaining('viewer:'), findsNothing);
    });

    testWidgets('the password never reaches the library metadata', (
      tester,
    ) async {
      final service = _FakeOpenService(needsPassword: true);
      library = _MemoryLibrary(docs: [_doc('1', 'locked.pdf')]);
      await open(tester, openService: service, viewerBuilder: fakeViewer);

      await tester.tap(find.text('locked.pdf'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'secret');
      await tester.tap(find.widgetWithText(FilledButton, 'Open'));
      await tester.pumpAndSettle();

      final stored = (await library.list()).single;
      final serialized = stored.toJson().toString();
      expect(serialized, isNot(contains('secret')));
      expect(stored.fileName, 'locked.pdf');
      expect(stored.storedPath, '/library/documents/locked.pdf');
    });

    testWidgets('opening the same locked document twice prompts each time', (
      tester,
    ) async {
      final service = _FakeOpenService(needsPassword: true);
      library = _MemoryLibrary(docs: [_doc('1', 'locked.pdf')]);
      await open(tester, openService: service, viewerBuilder: fakeViewer);

      for (var attempt = 0; attempt < 2; attempt++) {
        await tester.tap(find.text('locked.pdf'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'secret');
        await tester.tap(find.widgetWithText(FilledButton, 'Open'));
        await tester.pumpAndSettle();
        expect(find.text('viewer:locked.pdf|secret'), findsOneWidget);

        // Leave the viewer and return to the list.
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(LockedPdfDialog), findsNothing);
      }

      expect(service.verifyCalls, hasLength(2));
    });
  });
}
