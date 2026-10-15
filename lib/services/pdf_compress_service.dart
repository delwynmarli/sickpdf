import 'dart:io';
import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

import 'pdf_image_optimizer.dart';

/// Low keeps all images intact; other presets edit eligible image objects only.
enum PdfCompressionMode {
  lossless,
  medium,
  high;

  bool get incremental => false;
  int get dpi => this == high ? 100 : 150;
  int get jpegQuality => this == high ? 55 : 80;
}

class PdfCompressionResult {
  PdfCompressionResult(
    this.bytes,
    this.originalSize,
    this.pageCount, {
    this.imagesChanged = 0,
    int? candidateSize,
    this.retainedOriginal = false,
    this.diagnostics = const {},
  }) : candidateSize = candidateSize ?? bytes.length;
  final int candidateSize;
  final bool retainedOriginal;
  final Map<String, int> diagnostics;
  bool get reduced => !retainedOriginal && outputSize < originalSize;
  final int imagesChanged;

  /// Call only after candidate validation. Equal/larger candidates are not used.
  static PdfCompressionResult choose(
    Uint8List original,
    Uint8List candidate,
    int pages, {
    int imagesChanged = 0,
    Map<String, int> diagnostics = const {},
  }) {
    final retain = candidate.length >= original.length;
    return PdfCompressionResult(
      retain ? original : candidate,
      original.length,
      pages,
      candidateSize: candidate.length,
      retainedOriginal: retain,
      imagesChanged: imagesChanged,
      diagnostics: diagnostics,
    );
  }

  final Uint8List bytes;
  final int originalSize;
  final int pageCount;
  int get outputSize => bytes.length;
  int get bytesSaved => originalSize - outputSize;
  double get reductionPercent =>
      originalSize == 0 ? 0 : bytesSaved * 100 / originalSize;
}

String formatPdfSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KiB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MiB';
}

class PdfCompressService {
  // encodePdf and the mobile save/preview APIs require complete output bytes.
  // Bound the input rather than promising streaming for arbitrarily large PDFs.
  static const maxInputBytes = 64 * 1024 * 1024;

  Future<PdfDocument> _open(String path, {Uint8List? data}) async {
    final file = File(path);
    final size = data?.length ?? await file.length();
    if (size == 0) throw const FormatException('The selected PDF is empty.');
    if (size > maxInputBytes) {
      throw const FormatException(
        'Select a PDF smaller than 64 MiB for local optimization.',
      );
    }
    await pdfrxFlutterInitialize();
    final document = data == null
        ? await PdfDocument.openFile(path, passwordProvider: () => null)
        : await PdfDocument.openData(data, passwordProvider: () => null);
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

  Future<PdfCompressionResult> compress(
    String path, {
    PdfCompressionMode mode = PdfCompressionMode.lossless,
  }) async {
    final file = File(path);
    if (await file.length() > maxInputBytes) {
      throw const FormatException(
        'Select a PDF smaller than 64 MiB for local optimization.',
      );
    }
    // Native processing and fallback both use this exact input snapshot.
    final original = await file.readAsBytes();
    // openData owns isolate-local read callbacks; native editing runs elsewhere.
    // A private file snapshot avoids cross-isolate callback crashes and source races.
    final temporary = await Directory.systemTemp.createTemp(
      'sickpdf_compress_',
    );
    PdfDocument? opened;
    try {
      final snapshot = await File('${temporary.path}/source.pdf')
          .writeAsBytes(original, flush: true);
      final document = opened = await _open(snapshot.path);
      final diagnostics = mode == PdfCompressionMode.lossless
          ? <String, int>{'lossless rewrite only': 1}
          : await optimizePdfImages(document, mode.dpi, mode.jpegQuality);
      final imagesChanged = diagnostics['images changed'] ?? 0;
      // Save the original document, NOT an imported page-only document: retain
      // document-level structures. PDFium compresses eligible streams and drops
      // obsolete incremental revisions. Images were edited above, not whole pages.
      final bytes = await document.encodePdf(incremental: mode.incremental);
      if (bytes.isEmpty) {
        throw const FormatException('The PDF engine produced no output.');
      }
      final verified = await PdfDocument.openData(
        bytes,
        passwordProvider: () => null,
      );
      try {
        if (verified.pages.length != document.pages.length) {
          throw const FormatException(
            'Output validation failed: page count changed.',
          );
        }
        for (var i = 0; i < verified.pages.length; i++) {
          if (verified.pages[i].width != document.pages[i].width ||
              verified.pages[i].height != document.pages[i].height) {
            throw const FormatException(
              'Output validation failed: page dimensions changed.',
            );
          }
        }
      } finally {
        await verified.dispose();
      }
      return PdfCompressionResult.choose(
        original,
        bytes,
        document.pages.length,
        imagesChanged: imagesChanged,
        diagnostics: diagnostics,
      );
    } finally {
      try {
        await opened?.dispose();
      } finally {
        await temporary.delete(recursive: true);
      }
    }
  }
}
