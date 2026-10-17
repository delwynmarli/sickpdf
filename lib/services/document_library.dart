import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// A document tracked in the sickPDF library.
///
/// The library only ever contains files that sickPDF itself created and
/// copied into its own app-managed documents directory. User source files
/// are never copied here implicitly, and removing an entry never deletes a
/// user's source document.
class LibraryDocument {
  const LibraryDocument({
    required this.fileName,
    required this.storedPath,
    required this.fileSize,
    required this.addedAt,
    required this.modifiedAt,
  });

  final String fileName;
  final String storedPath;
  final int fileSize;
  final DateTime addedAt;
  final DateTime modifiedAt;

  Map<String, dynamic> toJson() => {
    'fileName': fileName,
    'storedPath': storedPath,
    'fileSize': fileSize,
    'addedAt': addedAt.toIso8601String(),
    'modifiedAt': modifiedAt.toIso8601String(),
  };

  static LibraryDocument fromJson(Map<String, dynamic> json) =>
      LibraryDocument(
        fileName: json['fileName'] as String,
        storedPath: json['storedPath'] as String,
        fileSize: json['fileSize'] as int,
        addedAt: DateTime.parse(json['addedAt'] as String),
        modifiedAt: DateTime.parse(json['modifiedAt'] as String),
      );
}

/// Privacy-friendly local document library.
///
/// Storage layout (no external storage permissions required):
/// - `<app documents>/library/documents/` — copies of sickPDF outputs.
/// - `<app documents>/library/index.json` — the metadata index.
///
/// The index is repaired defensively: entries whose stored file has been
/// removed externally are dropped on load and save.
class DocumentLibrary {
  DocumentLibrary({Directory? baseDir});

  static const _indexFileName = 'index.json';
  static const _documentsDirName = 'documents';

  Directory? _baseDir;

  Future<Directory> _resolveBase() async {
    if (_baseDir != null) return _baseDir!;
    final appDir = await getApplicationDocumentsDirectory();
    _baseDir = Directory(
      '${appDir.path}${Platform.pathSeparator}library',
    );
    return _baseDir!;
  }

  Future<File> get _indexFile async {
    final base = await _resolveBase();
    return File('${base.path}${Platform.pathSeparator}$_indexFileName');
  }

  Future<Directory> get _documentsDir async {
    final base = await _resolveBase();
    return Directory(
      '${base.path}${Platform.pathSeparator}$_documentsDirName',
    ).create(recursive: true);
  }

  /// Lists tracked documents, newest first.
  Future<List<LibraryDocument>> list() async {
    final file = await _indexFile;
    if (!await file.exists()) return [];
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw) as List<dynamic>;
      final docs = decoded
          .map((e) => LibraryDocument.fromJson(e as Map<String, dynamic>))
          .toList();
      // Drop entries whose stored file disappeared (user cleared app data
      // partially, OS cleanup, etc.).
      final existing = <LibraryDocument>[];
      var changed = false;
      for (final doc in docs) {
        if (await File(doc.storedPath).exists()) {
          existing.add(doc);
        } else {
          changed = true;
        }
      }
      if (changed) await _writeIndex(existing);
      existing.sort((a, b) => b.addedAt.compareTo(a.addedAt));
      return existing;
    } on FormatException {
      // Corrupt index: start fresh rather than crashing the Files tab.
      return [];
    }
  }

  /// Stores in-memory [bytes] (e.g. a freshly generated PDF) directly into
  /// the library. Nothing outside app storage is touched.
  Future<LibraryDocument> addFromBytes(
    List<int> bytes, {
    String? displayName,
  }) async {
    final dir = await _documentsDir;
    final name = _uniqueName(
      displayName ?? 'document.pdf',
      existing: await list(),
    );
    final storedPath = '${dir.path}${Platform.pathSeparator}$name';
    final file = await File(storedPath).writeAsBytes(bytes, flush: true);
    final stat = await file.stat();
    final doc = LibraryDocument(
      fileName: name,
      storedPath: storedPath,
      fileSize: stat.size,
      addedAt: DateTime.now(),
      modifiedAt: stat.modified,
    );
    final docs = await list();
    docs.insert(0, doc);
    await _writeIndex(docs);
    return doc;
  }

  /// Copies [sourcePath] into the app-managed library and tracks it.
  ///
  /// The source file is never modified or deleted. Returns the stored
  /// document record.
  Future<LibraryDocument> addFromPath(
    String sourcePath, {
    String? displayName,
  }) async {
    final source = File(sourcePath);
    final stat = await source.stat();
    final dir = await _documentsDir;
    final name = _uniqueName(
      displayName ?? sourcePath.split(Platform.pathSeparator).last,
      existing: await list(),
    );
    final storedPath = '${dir.path}${Platform.pathSeparator}$name';
    await source.copy(storedPath);
    final doc = LibraryDocument(
      fileName: name,
      storedPath: storedPath,
      fileSize: stat.size,
      addedAt: DateTime.now(),
      modifiedAt: stat.modified,
    );
    final docs = await list();
    docs.insert(0, doc);
    await _writeIndex(docs);
    return doc;
  }

  /// Removes a document from the library and deletes the app-managed copy.
  /// Only the stored copy is deleted — never any user source file.
  Future<void> remove(LibraryDocument doc) async {
    final docs = await list();
    docs.removeWhere((d) => d.storedPath == doc.storedPath);
    await _writeIndex(docs);
    try {
      await File(doc.storedPath).delete();
    } on FileSystemException {
      // File already gone; index entry is what matters.
    }
  }

  Future<void> _writeIndex(List<LibraryDocument> docs) async {
    final file = await _indexFile;
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode(docs.map((d) => d.toJson()).toList()),
      flush: true,
    );
  }

  String _uniqueName(String name, {required List<LibraryDocument> existing}) {
    final taken = existing.map((d) => d.fileName.toLowerCase()).toSet();
    if (!taken.contains(name.toLowerCase())) return name;
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    var counter = 2;
    while (true) {
      final candidate = '$base ($counter)$ext';
      if (!taken.contains(candidate.toLowerCase())) return candidate;
      counter++;
    }
  }
}
