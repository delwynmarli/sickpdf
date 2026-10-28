import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// A user-facing failure from the local document library.
///
/// The message is plain English, contains no document content, and always
/// describes something the user can act on.
class LibraryException implements Exception {
  const LibraryException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Turns any user-supplied name into a safe `.pdf` file name.
///
/// Directory separators and characters Android refuses in a file name are
/// removed, whitespace is collapsed, and the `.pdf` extension is enforced. An
/// empty or unusable name falls back to `document.pdf`, so a name can never
/// produce a path that escapes the library directory.
String sanitizePdfFileName(String raw, {String fallbackBase = 'document'}) {
  var name = raw.trim();
  final slash = math.max(name.lastIndexOf('/'), name.lastIndexOf(r'\'));
  if (slash >= 0) name = name.substring(slash + 1);
  // Control characters and the characters Windows/Android reject.
  name = name.replaceAll(RegExp(r'[\x00-\x1F\x7F<>:"/\\|?*]'), ' ');
  name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (name.toLowerCase().endsWith('.pdf')) {
    name = name.substring(0, name.length - 4).trim();
  }
  if (name.length > 100) name = name.substring(0, 100).trim();
  if (name.isEmpty) {
    final base = fallbackBase.trim();
    name = base.isEmpty ? 'document' : base;
  }
  return '$name.pdf';
}

/// A document tracked in the sickPDF library.
///
/// The library only ever contains files that sickPDF itself created and
/// copied into its own app-managed documents directory. User source files
/// are never copied here implicitly, and removing an entry never deletes a
/// user's source document.
class LibraryDocument {
  const LibraryDocument({
    required this.id,
    required this.fileName,
    required this.storedPath,
    required this.fileSize,
    required this.addedAt,
    required this.modifiedAt,
  });

  /// Stable identifier for the entry.
  ///
  /// It never changes when the document is renamed, so the UI can keep
  /// referring to the same document across rebuilds and reloads.
  final String id;

  /// Display name, always ending in `.pdf`.
  final String fileName;

  /// Absolute path of the library-owned copy inside app storage.
  final String storedPath;

  final int fileSize;
  final DateTime addedAt;
  final DateTime modifiedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'fileName': fileName,
    'storedPath': storedPath,
    'fileSize': fileSize,
    'addedAt': addedAt.toIso8601String(),
    'modifiedAt': modifiedAt.toIso8601String(),
  };

  /// Reads one index entry, returning `null` when the entry is unusable.
  ///
  /// A single damaged entry must never take the whole library down: an index
  /// written by an older build, or truncated by the OS killing the app
  /// mid-write, would otherwise throw while parsing and make every document
  /// look like it had vanished.
  static LibraryDocument? tryFromJson(Object? value) {
    if (value is! Map) return null;
    final fileName = value['fileName'];
    final storedPath = value['storedPath'];
    if (fileName is! String || fileName.trim().isEmpty) return null;
    if (storedPath is! String || storedPath.trim().isEmpty) return null;
    final size = value['fileSize'];
    final addedAt = _parseDate(value['addedAt']);
    final modifiedAt = _parseDate(value['modifiedAt']) ?? addedAt;
    if (addedAt == null) return null;
    final rawId = value['id'];
    final id = rawId is String && rawId.trim().isNotEmpty
        ? rawId
        : stableDocumentId(storedPath);
    return LibraryDocument(
      id: id,
      fileName: fileName,
      storedPath: storedPath,
      fileSize: size is int && size >= 0 ? size : 0,
      addedAt: addedAt,
      modifiedAt: modifiedAt ?? addedAt,
    );
  }

  /// Same document, new name and path, after a rename.
  LibraryDocument copyWith({
    String? fileName,
    String? storedPath,
    int? fileSize,
    DateTime? modifiedAt,
  }) => LibraryDocument(
    id: id,
    fileName: fileName ?? this.fileName,
    storedPath: storedPath ?? this.storedPath,
    fileSize: fileSize ?? this.fileSize,
    addedAt: addedAt,
    modifiedAt: modifiedAt ?? this.modifiedAt,
  );

  static DateTime? _parseDate(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value);
  }

  @override
  String toString() => 'LibraryDocument($fileName)';
}

/// Deterministic identifier derived from a stored path.
///
/// Used for entries written before ids existed, so a legacy index keeps the
/// same ids across restarts instead of regenerating them on every load.
String stableDocumentId(String storedPath) {
  // FNV-1a, 32-bit: short, stable, and dependency-free.
  var hash = 0x811c9dc5;
  for (final unit in storedPath.codeUnits) {
    hash ^= unit & 0xff;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

/// The operations the Files UI needs from a document store.
///
/// [DocumentLibrary] is the persistent implementation. The interface exists
/// so widget tests can supply an in-memory store instead of touching the
/// device filesystem.
abstract class DocumentLibraryApi {
  Future<List<LibraryDocument>> list();

  Future<LibraryDocument> addFromPath(String sourcePath, {String? displayName});

  Future<LibraryDocument> addFromBytes(List<int> bytes, {String? displayName});

  Future<LibraryDocument> rename(LibraryDocument doc, String newName);

  Future<void> remove(LibraryDocument doc);

  Future<bool> isAvailable(LibraryDocument doc);

  Future<Uint8List> readBytes(LibraryDocument doc);
}

/// Privacy-friendly local document library.
///
/// Storage layout (no external storage permissions required):
/// - `<app documents>/library/documents/` — copies of sickPDF documents.
/// - `<app documents>/library/index.json` — the metadata index.
///
/// Everything lives inside the app's private storage, so no storage
/// permission is requested and nothing is uploaded. The trade-off is that
/// uninstalling sickPDF removes these documents; that is stated in the Files
/// UI rather than worked around with a shared-storage permission.
///
/// The index is written atomically (temp file + rename) and parsed
/// defensively. If the index cannot be read at all, the documents directory is
/// rescanned so a damaged index cannot silently hide the user's documents.
class DocumentLibrary implements DocumentLibraryApi {
  /// [baseDir] overrides the library root itself (the directory that holds
  /// `index.json` and `documents/`). Tests use it to point the library at a
  /// temporary directory; production leaves it null so the root resolves to
  /// `<app documents>/library`.
  DocumentLibrary({Directory? baseDir}) {
    _baseDir = baseDir;
  }

  static const _indexFileName = 'index.json';
  static const _documentsDirName = 'documents';

  Directory? _baseDir;

  Future<Directory> _resolveBase() async {
    final existing = _baseDir;
    if (existing != null) return existing;
    final appDir = await getApplicationDocumentsDirectory();
    final base = Directory('${appDir.path}${Platform.pathSeparator}library');
    _baseDir = base;
    return base;
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
  ///
  /// Entries whose stored file has disappeared are still returned: dropping
  /// them here would silently delete a document the user imported. The UI
  /// checks availability when the document is opened and offers a removal.
  @override
  Future<List<LibraryDocument>> list() async {
    final file = await _indexFile;
    if (!await file.exists()) return [];
    List<LibraryDocument> docs;
    try {
      final raw = await file.readAsString();
      docs = _decodeIndex(raw);
    } on FileSystemException {
      return [];
    } on FormatException {
      // Unreadable index: rebuild from the files that are actually there.
      return _rebuildFromDisk();
    }
    docs.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return docs;
  }

  List<LibraryDocument> _decodeIndex(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw const FormatException('The library index is not a list.');
    }
    final docs = <LibraryDocument>[];
    final seenIds = <String>{};
    for (final entry in decoded) {
      final doc = LibraryDocument.tryFromJson(entry);
      if (doc == null) continue;
      if (!seenIds.add(doc.id)) continue;
      docs.add(doc);
    }
    return docs;
  }

  /// Rebuilds the index by scanning the library's own documents directory.
  ///
  /// Only `<app documents>/library/documents` is read — never device storage.
  Future<List<LibraryDocument>> _rebuildFromDisk() async {
    final dir = await _documentsDir;
    final docs = <LibraryDocument>[];
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (!name.toLowerCase().endsWith('.pdf')) continue;
        final stat = await entity.stat();
        docs.add(
          LibraryDocument(
            id: stableDocumentId(entity.path),
            fileName: name,
            storedPath: entity.path,
            fileSize: stat.size,
            addedAt: stat.modified,
            modifiedAt: stat.modified,
          ),
        );
      }
    } on FileSystemException {
      return [];
    }
    if (docs.isNotEmpty) await _writeIndex(docs);
    docs.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return docs;
  }

  /// Stores in-memory [bytes] (e.g. a freshly generated PDF) directly into
  /// the library. Nothing outside app storage is touched.
  @override
  Future<LibraryDocument> addFromBytes(
    List<int> bytes, {
    String? displayName,
  }) async {
    if (bytes.isEmpty) {
      throw const LibraryException(
        'The document is empty, so there is nothing to save.',
      );
    }
    final dir = await _documentsDir;
    final existing = await list();
    final name = _uniqueName(
      sanitizePdfFileName(displayName ?? 'document.pdf'),
      existing: existing,
    );
    final storedPath = '${dir.path}${Platform.pathSeparator}$name';
    final file = File(storedPath);
    try {
      await file.writeAsBytes(bytes, flush: true);
    } on FileSystemException {
      throw const LibraryException(
        'Could not save the document. Check that there is free space on the '
        'device.',
      );
    }
    final stat = await file.stat();
    if (stat.size != bytes.length) {
      await _deleteQuietly(file);
      throw const LibraryException(
        'The document could not be written completely. Try saving it again.',
      );
    }
    final now = DateTime.now();
    final doc = LibraryDocument(
      id: _newId(existing),
      fileName: name,
      storedPath: storedPath,
      fileSize: stat.size,
      addedAt: now,
      modifiedAt: stat.modified,
    );
    await _writeIndex([doc, ...existing]);
    return doc;
  }

  /// Copies [sourcePath] into the app-managed library and tracks it.
  ///
  /// The source file is never modified or deleted. The copy is verified
  /// against the source size, so a truncated copy is reported instead of
  /// being listed as a document that cannot be opened.
  @override
  Future<LibraryDocument> addFromPath(
    String sourcePath, {
    String? displayName,
  }) async {
    final source = File(sourcePath);
    final stat = await _statSource(source);
    final dir = await _documentsDir;
    final existing = await list();
    final name = _uniqueName(
      sanitizePdfFileName(displayName ?? _baseName(sourcePath)),
      existing: existing,
    );
    final storedPath = '${dir.path}${Platform.pathSeparator}$name';
    final target = File(storedPath);
    try {
      await source.copy(storedPath);
    } on FileSystemException {
      throw const LibraryException(
        'Could not copy this file into sickPDF. Check that there is free '
        'space on the device.',
      );
    }
    final copied = await target.stat();
    if (copied.size != stat.size) {
      await _deleteQuietly(target);
      throw const LibraryException(
        'The file could not be copied completely. Try importing it again.',
      );
    }
    final now = DateTime.now();
    final doc = LibraryDocument(
      id: _newId(existing),
      fileName: name,
      storedPath: storedPath,
      fileSize: copied.size,
      addedAt: now,
      modifiedAt: copied.modified,
    );
    await _writeIndex([doc, ...existing]);
    return doc;
  }

  Future<FileStat> _statSource(File source) async {
    FileStat stat;
    try {
      stat = await source.stat();
    } on FileSystemException {
      throw const LibraryException(
        'That file is no longer available. Choose it again.',
      );
    }
    if (stat.type == FileSystemEntityType.notFound) {
      throw const LibraryException(
        'That file is no longer available. Choose it again.',
      );
    }
    if (stat.size == 0) {
      throw const LibraryException(
        'That file is empty, so there is nothing to import.',
      );
    }
    return stat;
  }

  /// Renames a document and its stored copy together.
  ///
  /// Either both the file and the metadata change, or neither does: a failed
  /// rename leaves the index untouched.
  @override
  Future<LibraryDocument> rename(
    LibraryDocument doc,
    String newName,
  ) async {
    final sanitized = sanitizePdfFileName(newName);
    if (sanitized == doc.fileName) return doc;
    final docs = await list();
    final others = docs.where((entry) => entry.id != doc.id).toList();
    final unique = _uniqueName(sanitized, existing: others);
    final base = await _resolveBase();
    final dir = Directory(
      '${base.path}${Platform.pathSeparator}$_documentsDirName',
    );
    final targetPath = '${dir.path}${Platform.pathSeparator}$unique';
    final source = File(doc.storedPath);
    try {
      await source.rename(targetPath);
    } on FileSystemException {
      throw const LibraryException(
        'Could not rename this document. Check that there is free space on '
        'the device.',
      );
    }
    final renamed = doc.copyWith(
      fileName: unique,
      storedPath: targetPath,
      modifiedAt: DateTime.now(),
    );
    await _writeIndex([
      for (final entry in docs)
        if (entry.id == doc.id) renamed else entry,
    ]);
    return renamed;
  }

  /// Removes a document from the library and deletes the app-managed copy.
  /// Only the stored copy is deleted — never any user source file.
  @override
  Future<void> remove(LibraryDocument doc) async {
    final docs = await list();
    final remaining = docs.where((entry) => entry.id != doc.id).toList();
    await _writeIndex(remaining);
    await _deleteQuietly(File(doc.storedPath));
  }

  /// True when the library-owned copy is still present on disk.
  @override
  Future<bool> isAvailable(LibraryDocument doc) async {
    try {
      return await File(doc.storedPath).exists();
    } on FileSystemException {
      return false;
    }
  }

  /// Reads the stored bytes for sharing or exporting.
  @override
  Future<Uint8List> readBytes(LibraryDocument doc) async {
    try {
      return await File(doc.storedPath).readAsBytes();
    } on FileSystemException {
      throw const LibraryException(
        'This document is no longer in sickPDF storage.',
      );
    }
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      await file.delete();
    } on FileSystemException {
      // Already gone; nothing else to do.
    }
  }

  /// Writes the index atomically so a kill mid-write cannot leave a truncated
  /// file behind.
  Future<void> _writeIndex(List<LibraryDocument> docs) async {
    final file = await _indexFile;
    await file.parent.create(recursive: true);
    final body = jsonEncode(docs.map((d) => d.toJson()).toList());
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(body, flush: true);
    try {
      if (await file.exists()) await file.delete();
      await temp.rename(file.path);
    } on FileSystemException {
      // Fall back to writing in place rather than losing the update.
      await file.writeAsString(body, flush: true);
      await _deleteQuietly(temp);
    }
  }

  String _newId(List<LibraryDocument> existing) {
    final taken = existing.map((d) => d.id).toSet();
    var seed = DateTime.now().microsecondsSinceEpoch;
    while (true) {
      final candidate = seed.toRadixString(36);
      if (!taken.contains(candidate)) return candidate;
      seed++;
    }
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

  String _baseName(String path) {
    final slash = math.max(path.lastIndexOf('/'), path.lastIndexOf(r'\'));
    return slash >= 0 ? path.substring(slash + 1) : path;
  }
}
