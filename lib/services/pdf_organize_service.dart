import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdfrx/pdfrx.dart';

/// Zero-based source identities; list positions are the output page numbers.
class PdfPageOrder {
  PdfPageOrder(int pageCount)
    : _pages = List.generate(pageCount, (index) => index);

  List<int> _pages;
  List<int>? _removed;
  List<int> get pages => List.unmodifiable(_pages);
  bool get canUndo => _removed != null;

  void move(int from, int to) {
    RangeError.checkValidIndex(from, _pages);
    RangeError.checkValidIndex(to, _pages);
    _pages.insert(to, _pages.removeAt(from));
  }

  void remove(Set<int> sourcePages) {
    final remaining = _pages
        .where((page) => !sourcePages.contains(page))
        .toList();
    if (remaining.isEmpty) {
      throw const FormatException('Keep at least one page in the PDF.');
    }
    if (remaining.length == _pages.length) return;
    _removed = List.of(_pages);
    _pages = remaining;
  }

  void undoRemoval() {
    if (_removed == null) return;
    _pages = _removed!;
    _removed = null;
  }

  static void validate(List<int> pages, int count) {
    if (pages.isEmpty) {
      throw const FormatException('Keep at least one page in the PDF.');
    }
    if (pages.toSet().length != pages.length ||
        pages.any((page) => page < 0 || page >= count)) {
      throw const FormatException(
        'Invalid source page order. Select the PDF again.',
      );
    }
  }
}

/// A local document session. Serializes renders/export/close to prevent races.
class PdfOrganizeSession {
  PdfOrganizeSession._(this.document);
  final PdfDocument document;
  Future<void> _pending = Future.value();
  bool _closed = false;

  static Future<PdfOrganizeSession> open(String path) async {
    final file = File(path);
    if (!await file.exists() || await file.length() == 0) {
      throw const FormatException(
        'The PDF is missing or empty. Select it again.',
      );
    }
    await pdfrxFlutterInitialize();
    final document = await PdfDocument.openFile(
      path,
      passwordProvider: () => null,
    );
    if (document.pages.isEmpty) {
      await document.dispose();
      throw const FormatException('This PDF has no pages.');
    }
    return PdfOrganizeSession._(document);
  }

  Future<T> _run<T>(Future<T> Function() action) {
    final result = _pending.then((_) {
      if (_closed) throw StateError('Document closed.');
      return action();
    });
    // The caller receives the error; the queue must remain usable for retries.
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<ui.Image> thumbnail(int sourceIndex) => _run(() async {
    final page = document.pages[sourceIndex];
    final scale = 160 / (page.width > page.height ? page.width : page.height);
    final rendered = await page.render(
      fullWidth: page.width * scale,
      fullHeight: page.height * scale,
    );
    if (rendered == null) throw StateError('Thumbnail rendering failed.');
    try {
      return await rendered.createImage();
    } finally {
      rendered.dispose();
    }
  });

  Future<Uint8List> generate(List<int> sourcePages) {
    final order = List<int>.of(sourcePages);
    return _run(() async {
      PdfPageOrder.validate(order, document.pages.length);
      final output = await PdfDocument.createNew(
        sourceName: 'organized-output',
      );
      try {
        output.pages = order.map((index) => document.pages[index]).toList();
        final bytes = await output.encodePdf();
        if (bytes.isEmpty) {
          throw const FormatException('The generated PDF is empty.');
        }
        return bytes;
      } finally {
        await output.dispose();
      }
    });
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _pending;
    await document.dispose();
  }
}
