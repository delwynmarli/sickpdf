import 'dart:io';
import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

/// Inclusive, one-based range shared by the form and extraction boundary.
class PdfPageRange {
  const PdfPageRange(this.start, this.end);

  final int start;
  final int end;

  static PdfPageRange parse(String start, String end, int pageCount) {
    final first = int.tryParse(start.trim());
    final last = int.tryParse(end.trim());
    if (first == null || last == null) {
      throw const FormatException('Enter whole numbers for both pages.');
    }
    final range = PdfPageRange(first, last);
    range.validate(pageCount);
    return range;
  }

  void validate(int pageCount) {
    if (pageCount < 1) {
      throw const FormatException('This PDF has no pages.');
    }
    if (start < 1) {
      throw const FormatException('Start page must be at least 1.');
    }
    if (start > end) {
      throw const FormatException('Start page must not exceed end page.');
    }
    if (end > pageCount) {
      throw FormatException('End page must not exceed $pageCount.');
    }
  }
}

/// Stable UI diagnostics without filenames, paths, or document contents.
String pdfSplitLoadError(Object error) {
  if (error is PdfPasswordException ||
      (error is PdfException && error.errorCode == 4)) {
    return 'This PDF requires a password. Open an unlocked copy to split it.';
  }
  if (error is FileSystemException ||
      (error is PdfException && error.errorCode == 2)) {
    return 'Could not read the PDF. Select an accessible local copy and try again.';
  }
  if (error is FormatException) return error.message;
  if (error is PdfException) {
    return 'Could not parse this PDF. It may be damaged or use an unsupported format.';
  }
  return 'Could not load the PDF. The file picker or PDF engine failed. Try again.';
}

class PdfSplitService {
  Future<PdfDocument> _open(String path) async {
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
    // PDFium already tried the empty password and parsed the document. Encryption
    // can describe owner restrictions, not a password required to open the PDF.
    // Keep password-required rejection in openFile; do not reject a successful
    // load solely because a security handler exists.
    if (document.pages.isEmpty) {
      await document.dispose();
      throw const FormatException('This PDF has no pages.');
    }
    return document;
  }

  Future<int> pageCount(String path) async {
    final document = await _open(path);
    try {
      return document.pages.length;
    } finally {
      await document.dispose();
    }
  }

  Future<Uint8List> extract(String path, PdfPageRange range) async {
    final source = await _open(path);
    try {
      range.validate(source.pages.length);
      final output = await PdfDocument.createNew(sourceName: 'split-output');
      try {
        output.pages = source.pages.sublist(range.start - 1, range.end);
        final bytes = await output.encodePdf();
        if (bytes.isEmpty) {
          throw const FormatException('The extracted PDF is empty.');
        }
        return bytes;
      } finally {
        await output.dispose();
      }
    } finally {
      await source.dispose();
    }
  }
}
