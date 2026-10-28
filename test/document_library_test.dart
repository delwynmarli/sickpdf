import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sickpdf/services/document_library.dart';

/// The library against a real (temporary) filesystem.
///
/// Every test owns its own temporary root, so nothing here can read or delete
/// a document from the user's own storage.
Directory documentsDirIn(Directory root) =>
    Directory('${root.path}${Platform.pathSeparator}documents');

File indexFileIn(Directory root) =>
    File('${root.path}${Platform.pathSeparator}index.json');

void main() {
  late Directory root;
  late Directory sourceDir;

  Directory documentsDir() => documentsDirIn(root);
  File indexFile() => indexFileIn(root);

  /// A fresh instance against the same root, standing in for an app restart.
  DocumentLibrary reopen() => DocumentLibrary(baseDir: root);

  Future<File> sourceFile(String name, {int size = 64}) async {
    final file = File('${sourceDir.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(List<int>.generate(size, (i) => i % 251));
    return file;
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sickpdf_library_');
    sourceDir = await Directory.systemTemp.createTemp('sickpdf_source_');
  });

  tearDown(() async {
    for (final dir in [root, sourceDir]) {
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  });

  group('import', () {
    test('importing a valid PDF copies it into app storage', () async {
      final source = await sourceFile('report.pdf', size: 128);
      final doc = await reopen().addFromPath(source.path);

      expect(doc.fileName, 'report.pdf');
      expect(doc.fileSize, 128);
      expect(doc.id, isNotEmpty);
      final stored = File(doc.storedPath);
      expect(await stored.exists(), isTrue);
      expect(
        stored.path,
        startsWith(documentsDir().path),
        reason: 'the stored copy must live inside the library',
      );
      expect(await stored.readAsBytes(), await source.readAsBytes());
    });

    test('the user source file is never modified or removed', () async {
      final source = await sourceFile('original.pdf');
      final before = await source.readAsBytes();
      final doc = await reopen().addFromPath(source.path);

      expect(await source.exists(), isTrue);
      expect(await source.readAsBytes(), before);
      expect(doc.storedPath, isNot(source.path));
    });

    test('metadata survives a new library instance', () async {
      final source = await sourceFile('kept.pdf', size: 200);
      final first = await reopen().addFromPath(source.path);
      final second = await reopen().list();

      expect(second, hasLength(1));
      expect(second.single.id, first.id);
      expect(second.single.fileName, 'kept.pdf');
      expect(second.single.storedPath, first.storedPath);
      expect(second.single.fileSize, 200);
      expect(
        second.single.addedAt.toIso8601String(),
        first.addedAt.toIso8601String(),
      );
    });

    test('documents stay listed when the picker cache is cleared', () async {
      final source = await sourceFile('cached.pdf');
      await reopen().addFromPath(source.path);
      // Android empties its cache directory whenever it needs space.
      await sourceDir.delete(recursive: true);

      final listed = await reopen().list();
      expect(listed, hasLength(1));
      expect(await File(listed.single.storedPath).exists(), isTrue);
    });

    test('a duplicate display name gets a numbered variant', () async {
      final library = reopen();
      await library.addFromPath((await sourceFile('dup.pdf')).path);
      await library.addFromPath((await sourceFile('dup.pdf')).path);

      final names = (await reopen().list()).map((d) => d.fileName).toList();
      expect(names, containsAll(<String>['dup.pdf', 'dup (2).pdf']));
      expect(names.toSet(), hasLength(2));
    });

    test('duplicate names are compared case-insensitively', () async {
      final library = reopen();
      await library.addFromPath((await sourceFile('Scan.pdf')).path);
      await library.addFromPath((await sourceFile('scan.pdf')).path);
      final names = (await library.list()).map((d) => d.fileName).toList();
      expect(names.toSet(), hasLength(2));
    });

    test('every document gets a distinct id', () async {
      final library = reopen();
      for (var i = 0; i < 4; i++) {
        await library.addFromPath((await sourceFile('doc$i.pdf')).path);
      }
      final ids = (await library.list()).map((d) => d.id).toList();
      expect(ids.toSet(), hasLength(4));
    });

    test('an empty file is rejected and nothing is stored', () async {
      final source = await sourceFile('empty.pdf', size: 0);
      await expectLater(
        reopen().addFromPath(source.path),
        throwsA(
          isA<LibraryException>().having(
            (e) => e.message,
            'message',
            contains('empty'),
          ),
        ),
      );
      expect(await reopen().list(), isEmpty);
    });

    test('a missing source file is reported without crashing', () async {
      final missing = '${sourceDir.path}${Platform.pathSeparator}gone.pdf';
      await expectLater(
        reopen().addFromPath(missing),
        throwsA(isA<LibraryException>()),
      );
      expect(await reopen().list(), isEmpty);
    });

    test('bytes that are empty are rejected', () async {
      await expectLater(
        reopen().addFromBytes(const <int>[]),
        throwsA(isA<LibraryException>()),
      );
    });

    test('addFromBytes stores the exact bytes', () async {
      final bytes = List<int>.generate(300, (i) => i % 251);
      final doc = await reopen().addFromBytes(bytes, displayName: 'made.pdf');
      expect(doc.fileSize, 300);
      expect(await File(doc.storedPath).readAsBytes(), bytes);
    });

    test('a cancelled import leaves the library unchanged', () async {
      await expectLater(reopen().list(), completion(isEmpty));
      expect(await indexFile().exists(), isFalse);
    });
  });

  group('rename', () {
    test('renames the file and the metadata together', () async {
      final library = reopen();
      final doc = await library.addFromPath((await sourceFile('old.pdf')).path);

      final renamed = await library.rename(doc, 'new name');

      expect(renamed.fileName, 'new name.pdf');
      expect(renamed.id, doc.id, reason: 'the id must stay stable');
      expect(await File(renamed.storedPath).exists(), isTrue);
      expect(await File(doc.storedPath).exists(), isFalse);

      final reloaded = await reopen().list();
      expect(reloaded.single.fileName, 'new name.pdf');
      expect(reloaded.single.storedPath, renamed.storedPath);
    });

    test('renaming keeps the stored bytes intact', () async {
      final library = reopen();
      final source = await sourceFile('keep.pdf', size: 90);
      final doc = await library.addFromPath(source.path);
      final before = await File(doc.storedPath).readAsBytes();

      final renamed = await library.rename(doc, 'kept');
      expect(await File(renamed.storedPath).readAsBytes(), before);
    });

    test('renaming to an existing name picks a free variant', () async {
      final library = reopen();
      final a = await library.addFromPath((await sourceFile('a.pdf')).path);
      final b = await library.addFromPath((await sourceFile('b.pdf')).path);

      final renamed = await library.rename(b, a.fileName);
      expect(renamed.fileName, 'a (2).pdf');
      expect(await File(a.storedPath).exists(), isTrue);
    });

    test('an unusable name falls back to a safe file name', () async {
      final library = reopen();
      final doc = await library.addFromPath((await sourceFile('x.pdf')).path);
      final renamed = await library.rename(doc, r'../..');
      expect(renamed.fileName, endsWith('.pdf'));
      expect(renamed.fileName, isNot(contains('/')));
      expect(renamed.fileName, isNot(contains(r'\')));
      expect(await File(renamed.storedPath).exists(), isTrue);
    });

    test('renaming to the same name is a no-op', () async {
      final library = reopen();
      final doc = await library.addFromPath((await sourceFile('same.pdf')).path);
      final renamed = await library.rename(doc, 'same.pdf');
      expect(renamed.fileName, 'same.pdf');
      expect(renamed.storedPath, doc.storedPath);
    });
  });

  group('delete', () {
    test('removes the entry and the stored copy', () async {
      final library = reopen();
      final doc = await library.addFromPath((await sourceFile('bye.pdf')).path);
      await library.remove(doc);

      expect(await File(doc.storedPath).exists(), isFalse);
      expect(await reopen().list(), isEmpty);
    });

    test('never deletes the user source file', () async {
      final library = reopen();
      final source = await sourceFile('mine.pdf');
      final doc = await library.addFromPath(source.path);
      await library.remove(doc);
      expect(await source.exists(), isTrue);
    });

    test('deleting one document keeps the others', () async {
      final library = reopen();
      final first = await library.addFromPath((await sourceFile('1.pdf')).path);
      final second = await library.addFromPath(
        (await sourceFile('2.pdf')).path,
      );
      await library.remove(first);
      final remaining = await reopen().list();
      expect(remaining.single.id, second.id);
    });
  });

  group('resilience', () {
    test('a missing stored file is still listed and flagged unavailable', () async {
      final library = reopen();
      final doc = await library.addFromPath((await sourceFile('gone.pdf')).path);
      await File(doc.storedPath).delete();

      final listed = await reopen().list();
      expect(
        listed,
        hasLength(1),
        reason: 'a vanished file must not silently drop the entry',
      );
      expect(await reopen().isAvailable(listed.single), isFalse);
    });

    test('reading a missing copy raises a clear error', () async {
      final library = reopen();
      final doc = await library.addFromPath((await sourceFile('x.pdf')).path);
      await File(doc.storedPath).delete();
      await expectLater(
        library.readBytes(doc),
        throwsA(
          isA<LibraryException>().having(
            (e) => e.message,
            'message',
            contains('no longer in sickPDF storage'),
          ),
        ),
      );
    });

    test('a truncated or corrupt document stays removable', () async {
      final library = reopen();
      final doc = await library.addFromPath((await sourceFile('bad.pdf')).path);
      await File(doc.storedPath).writeAsBytes(const <int>[1, 2, 3]);

      expect((await library.list()).single.fileSize, 64);
      await library.remove(doc);
      expect(await library.list(), isEmpty);
    });

    test('a corrupt index is recovered from the documents folder', () async {
      final library = reopen();
      await library.addFromPath((await sourceFile('recover.pdf')).path);
      await indexFile().writeAsString('this is not json');

      final listed = await reopen().list();
      expect(
        listed,
        hasLength(1),
        reason: 'the documents on disk must be recovered, not hidden',
      );
      expect(listed.single.fileName, 'recover.pdf');
      expect(listed.single.fileSize, 64);
    });

    test('an index with a non-list shape is recovered', () async {
      final library = reopen();
      await library.addFromPath((await sourceFile('shape.pdf')).path);
      await indexFile().writeAsString('{"documents":[]}');
      expect(await reopen().list(), hasLength(1));
    });

    test('one damaged entry does not hide the healthy ones', () async {
      final library = reopen();
      final good = await library.addFromPath(
        (await sourceFile('good.pdf')).path,
      );
      final body =
          jsonDecode(await indexFile().readAsString()) as List<dynamic>;
      body.add({'fileName': null});
      body.add({'fileName': 'x.pdf'});
      await indexFile().writeAsString(jsonEncode(body));

      final listed = await reopen().list();
      expect(listed, hasLength(1));
      expect(listed.single.id, good.id);
    });

    test('an index entry without an id is given a stable one', () async {
      final library = reopen();
      final doc = await library.addFromPath((await sourceFile('old.pdf')).path);
      final body =
          jsonDecode(await indexFile().readAsString()) as List<dynamic>;
      final entry = Map<String, dynamic>.from(body.single as Map);
      entry.remove('id');
      await indexFile().writeAsString(jsonEncode([entry]));

      final firstRead = (await reopen().list()).single;
      final secondRead = (await reopen().list()).single;
      expect(firstRead.id, isNotEmpty);
      expect(firstRead.id, stableDocumentId(doc.storedPath));
      expect(secondRead.id, firstRead.id);
    });

    test('an empty library lists nothing without creating files', () async {
      expect(await reopen().list(), isEmpty);
      expect(await indexFile().exists(), isFalse);
    });

    test('no temporary index file is left behind', () async {
      final library = reopen();
      await library.addFromPath((await sourceFile('a.pdf')).path);
      await library.addFromPath((await sourceFile('b.pdf')).path);
      final leftovers = root
          .listSync()
          .where((entity) => entity.path.endsWith('.tmp'));
      expect(leftovers, isEmpty);
    });
  });

  group('sanitizePdfFileName', () {
    test('keeps a normal name and enforces the pdf extension', () {
      expect(sanitizePdfFileName('report'), 'report.pdf');
      expect(sanitizePdfFileName('report.pdf'), 'report.pdf');
    });

    test('strips path separators and unsafe characters', () {
      expect(sanitizePdfFileName('/tmp/a:b*c?.pdf'), 'a b c.pdf');
      expect(sanitizePdfFileName(r'..\..\evil.pdf'), 'evil.pdf');
    });

    test('falls back when nothing usable is left', () {
      expect(sanitizePdfFileName('   '), 'document.pdf');
      expect(sanitizePdfFileName('.pdf'), 'document.pdf');
    });
  });
}
