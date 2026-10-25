import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

import 'pdf_ocr_engine.dart';

/// A page that failed recognition, kept so the result can name it.
class PdfOcrPageFailure {
  PdfOcrPageFailure(this.pageNumber, this.reason);

  /// One-based page number that failed.
  final int pageNumber;

  /// Short, user-facing reason. Never contains document content.
  final String reason;

  @override
  String toString() => 'Page $pageNumber: $reason';
}

/// The outcome of an OCR run.
class PdfOcrResult {
  PdfOcrResult({
    required this.text,
    required this.pageCount,
    required this.processedPages,
    this.extractedPages = 0,
    this.failures = const <PdfOcrPageFailure>[],
  });

  /// The aggregated text, ready to be written to a `.txt` file.
  final String text;

  /// Total number of pages in the source document.
  final int pageCount;

  /// Number of pages that produced text, from either source.
  final int processedPages;

  /// Number of pages whose text was taken from the PDF's own text layer.
  final int extractedPages;

  /// Pages that could not be recognized.
  final List<PdfOcrPageFailure> failures;

  /// True when nothing could be read from the document at all.
  bool get isEmpty => text.trim().isEmpty;
}

/// Raised when a document cannot be read or processed.
class PdfOcrException implements Exception {
  const PdfOcrException(this.message);

  /// Plain-English, content-free explanation for the user.
  final String message;

  @override
  String toString() => message;
}

/// Raised when the user cancels a running extraction.
class PdfOcrCancelledException implements Exception {
  const PdfOcrCancelledException();

  @override
  String toString() => 'OCR cancelled.';
}

/// The written text file and the result that produced it.
class PdfOcrOutput {
  const PdfOcrOutput({required this.file, required this.result});

  /// The written `.txt` file.
  final File file;

  /// The extraction result, including any pages that could not be read.
  final PdfOcrResult result;
}

/// Progress reported while pages are processed.
class PdfOcrProgress {
  const PdfOcrProgress({
    required this.pageNumber,
    required this.totalPages,
    required this.text,
  });

  /// One-based page that was just finished.
  final int pageNumber;

  /// Total number of pages in the document.
  final int totalPages;

  /// Text recognized on this page.
  final String text;

  /// Human readable progress, for example "Processing page 3 of 20".
  String get label => 'Processing page $pageNumber of $totalPages';
}

/// Builds the `--- Page N ---` separator used in the exported text.
String pdfOcrPageSeparator(int pageNumber) => '--- Page $pageNumber ---';

/// Marker written on a page that produced no readable text.
const String pdfOcrEmptyPageMarker = '[No text recognized on this page]';

/// Joins recognized page texts into the final document.
///
/// Pages keep their order and are separated by a blank line and a page
/// marker, so the boundaries stay visible in a plain text file.
///
/// Every page that yielded no text is marked with [pdfOcrEmptyPageMarker],
/// whether it failed outright or simply contained nothing readable. A page is
/// never left silently blank.
String buildPdfOcrDocument(
  Map<int, String> pages, {
  Iterable<int> failedPages = const <int>[],
}) {
  final buffer = StringBuffer();
  final numbers = pages.keys.toList()..sort();
  for (final number in numbers) {
    if (buffer.isNotEmpty) buffer.write('\n\n');
    buffer.write(pdfOcrPageSeparator(number));
    buffer.write('\n');
    final text = pages[number] ?? '';
    // Keep the recognized line breaks, but drop trailing padding so the file
    // does not carry a wall of blank lines.
    final trimmed = text.replaceAll(RegExp(r'[ \t]+$'), '').trimRight();
    buffer.write(trimmed);
    if (trimmed.isEmpty || failedPages.contains(number)) {
      buffer.write('\n$pdfOcrEmptyPageMarker');
    }
  }
  return buffer.toString();
}

/// Derives the output filename for a source document.
///
/// `report.pdf` becomes `report_ocr.txt`. The original file is never
/// overwritten: the suffix always differs from the source name.
String pdfOcrOutputName(String sourceName) {
  var name = sourceName.trim();
  final slash = math.max(name.lastIndexOf('/'), name.lastIndexOf(r'\'));
  if (slash >= 0) name = name.substring(slash + 1);
  name = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  if (name.toLowerCase().endsWith('.pdf')) {
    name = name.substring(0, name.length - 4);
  }
  name = name.trim();
  if (name.isEmpty) name = 'document';
  return '${name}_ocr.txt';
}

/// Picks a filename that does not collide with an existing file.
///
/// `report_ocr.txt` becomes `report_ocr (2).txt` when the first name is
/// taken, so an existing output is never silently replaced.
Future<String> resolvePdfOcrOutputPath(
  Directory directory,
  String fileName,
) async {
  var candidate = File('${directory.path}${Platform.pathSeparator}$fileName');
  if (!await candidate.exists()) return candidate.path;
  final dot = fileName.lastIndexOf('.');
  final base = dot > 0 ? fileName.substring(0, dot) : fileName;
  final extension = dot > 0 ? fileName.substring(dot) : '';
  var counter = 2;
  while (true) {
    candidate = File(
      '${directory.path}${Platform.pathSeparator}$base ($counter)$extension',
    );
    if (!await candidate.exists()) return candidate.path;
    counter++;
  }
}

/// Extracts text from a PDF, using OCR only where it is needed.
///
/// The service owns the whole flow: it validates the file, detects pages that
/// already carry extractable text, renders the remaining pages one at a time,
/// recognizes them with the injected engine, and aggregates the result.
///
/// The engine is injected so the behaviour can be tested without the native
/// recognizer.
class PdfOcrService {
  PdfOcrService({
    PdfOcrEngineFactory? engineFactory,
    this.renderScale = defaultRenderScale,
    this.maxRenderPixels = defaultMaxRenderPixels,
  }) : _engineFactory = engineFactory ?? _defaultEngineFactory;

  /// Rendering resolution relative to the PDF's own point size.
  ///
  /// 2.0 renders an A4 page at roughly 144 dpi, which keeps small print
  /// readable for recognition without producing very large bitmaps.
  static const double defaultRenderScale = 2.0;

  /// Upper bound for the pixel count of a single rendered page.
  ///
  /// 3 megapixels is about 12 MiB of BGRA data per page. An A4 page at the
  /// default scale is roughly 2 megapixels, so only unusually large pages are
  /// scaled down. The page bitmap and its NV21 copy together stay well
  /// inside the heap of a low-memory device.
  static const int defaultMaxRenderPixels = 3 * 1024 * 1024;

  final PdfOcrEngineFactory _engineFactory;
  final double renderScale;
  final int maxRenderPixels;

  static PdfOcrEngine _defaultEngineFactory() => MlKitOcrEngine();

  /// Opens the document and reports its page count.
  Future<int> pageCount(String path) async {
    final document = await _open(path);
    try {
      return document.pages.length;
    } finally {
      await document.dispose();
    }
  }

  /// Reports whether the document already contains extractable text.
  ///
  /// Used to skip OCR for PDFs that already have a text layer.
  Future<bool> hasExtractableText(String path) async {
    final document = await _open(path);
    try {
      for (final page in document.pages) {
        final text = await page.loadText();
        if (text != null && text.fullText.trim().isNotEmpty) return true;
      }
      return false;
    } finally {
      await document.dispose();
    }
  }

  /// Runs the extraction.
  ///
  /// [onProgress] is called after every page. [isCancelled] is checked before
  /// each page so the run can be stopped promptly.
  ///
  /// Each page is handled on its own: a page that already carries extractable
  /// text is taken from the PDF, and only pages without a text layer are
  /// rendered and sent through OCR. This keeps mixed documents correct and
  /// avoids needlessly recognizing pages that already have text.
  Future<PdfOcrResult> extract(
    String path, {
    void Function(PdfOcrProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final document = await _open(path);
    final engine = _engineFactory();
    final pages = <int, String>{};
    final failures = <PdfOcrPageFailure>[];
    var extractedPages = 0;
    try {
      final total = document.pages.length;
      if (total == 0) {
        throw const PdfOcrException('This PDF has no pages.');
      }

      for (var index = 0; index < total; index++) {
        if (isCancelled?.call() ?? false) {
          throw const PdfOcrCancelledException();
        }
        final pageNumber = index + 1;
        final page = document.pages[index];
        String text;
        try {
          final existing = await _existingPageText(page);
          if (existing != null) {
            extractedPages++;
            text = existing;
          } else {
            final image = await _renderPage(page, pageNumber);
            if (image == null) {
              throw const PdfOcrException('The page could not be rendered.');
            }
            // The page image goes out of scope as soon as the page is done,
            // so only one rendered page is held in memory at a time.
            text = await engine.recognize(image);
          }
        } on PdfOcrException catch (error) {
          failures.add(PdfOcrPageFailure(pageNumber, error.message));
          text = '';
        } catch (_) {
          failures.add(
            PdfOcrPageFailure(
              pageNumber,
              'This page could not be recognized.',
            ),
          );
          text = '';
        }
        pages[pageNumber] = text;
        onProgress?.call(
          PdfOcrProgress(
            pageNumber: pageNumber,
            totalPages: total,
            text: text,
          ),
        );
        // The cancellation flag is re-checked after every page, including
        // the last one. Without this, a cancel pressed while the final page
        // was being recognized would still publish a result the user asked
        // to stop.
        if (isCancelled?.call() ?? false) {
          throw const PdfOcrCancelledException();
        }
      }

      final recognized = pages.values
          .where((value) => value.trim().isNotEmpty)
          .length;
      if (recognized == 0) {
        // The page markers alone would make the document look non-empty, so
        // the check is made on the recognized text itself.
        throw PdfOcrException(
          failures.isEmpty
              ? 'No text was recognized in this PDF.'
              : 'No text could be recognized on any page. The scan may be too '
                    'low quality or too small to read.',
        );
      }
      return PdfOcrResult(
        text: buildPdfOcrDocument(
          pages,
          failedPages: failures.map((failure) => failure.pageNumber),
        ),
        pageCount: total,
        processedPages: recognized,
        extractedPages: extractedPages,
        failures: failures,
      );
    } finally {
      // The engine and the document are released on every path, including
      // errors and cancellation. A failing close must not keep the document
      // open.
      try {
        await engine.close();
      } finally {
        await document.dispose();
      }
    }
  }

  /// Writes the recognized text as a UTF-8 `.txt` file.
  ///
  /// An existing file with the same name is never replaced: a numbered
  /// variant is written instead.
  Future<File> writeTextFile(
    Directory directory,
    String fileName,
    String text,
  ) async {
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final path = await resolvePdfOcrOutputPath(directory, fileName);
    final file = File(path);
    await file.writeAsString(text, encoding: utf8, flush: true);
    return file;
  }

  /// Reads back a written text file so it can be saved or shared.
  Future<Uint8List> readTextFile(String path) => File(path).readAsBytes();

  /// Extracts the text and writes it out in one step.
  ///
  /// Returns the written file together with the extraction result, so the
  /// caller can show the name and report pages that could not be read.
  ///
  /// The cancellation flag is checked once more before the file is written.
  /// A job cancelled between the last page and the write leaves no output
  /// file behind, so a cancelled job can never publish a result.
  Future<PdfOcrOutput> extractToTextFile(
    String path, {
    required Directory outputDirectory,
    required String fileName,
    void Function(PdfOcrProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final result = await extract(
      path,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
    if (isCancelled?.call() ?? false) {
      throw const PdfOcrCancelledException();
    }
    final file = await writeTextFile(outputDirectory, fileName, result.text);
    return PdfOcrOutput(file: file, result: result);
  }

  Future<PdfDocument> _open(String path) async {
    final file = File(path);
    if (!await file.exists() || await file.length() == 0) {
      throw const PdfOcrException(
        'The PDF is missing or empty. Select it again.',
      );
    }
    try {
      await pdfrxFlutterInitialize();
      final document = await PdfDocument.openFile(
        path,
        passwordProvider: () => null,
      );
      if (document.pages.isEmpty) {
        // The document was opened, so it has to be released before the
        // error is raised. It is not returned, so the caller's cleanup
        // cannot do it.
        await document.dispose();
        throw const PdfOcrException('This PDF has no pages.');
      }
      return document;
    } on PdfOcrException {
      rethrow;
    } on PdfPasswordException {
      throw const PdfOcrException(
        'This PDF requires a password. Open an unlocked copy to read it.',
      );
    } on FileSystemException {
      throw const PdfOcrException(
        'Could not read the PDF. Select an accessible local copy and try again.',
      );
    } on FormatException catch (error) {
      throw PdfOcrException(error.message);
    } on PdfException {
      throw const PdfOcrException(
        'Could not parse this PDF. It may be damaged or use an unsupported '
        'format.',
      );
    } catch (_) {
      throw const PdfOcrException(
        'Could not load the PDF. The file picker or PDF engine failed. Try again.',
      );
    }
  }

  /// Returns the page's own text when it carries a usable text layer.
  ///
  /// Structured text is used so the line breaks of the original layout are
  /// kept, matching what the OCR path produces.
  ///
  /// Returns null for a scanned page, so OCR is used instead.
  Future<String?> _existingPageText(PdfPage page) async {
    final text = await page.loadStructuredText();
    final fullText = text.fullText;
    if (fullText.trim().isEmpty) return null;
    return fullText;
  }

  /// Renders one page into a bitmap the recognizer can consume.
  Future<PdfOcrPageImage?> _renderPage(PdfPage page, int pageNumber) async {
    final pageWidth = page.width;
    final pageHeight = page.height;
    if (!pageWidth.isFinite ||
        !pageHeight.isFinite ||
        pageWidth <= 0 ||
        pageHeight <= 0) {
      return null;
    }
    var scale = renderScale;
    final pixels = pageWidth * pageHeight * scale * scale;
    if (pixels > maxRenderPixels) {
      scale = math.sqrt(maxRenderPixels / (pageWidth * pageHeight));
    }
    // Keep the dimensions even: the NV21 chroma plane is subsampled by two.
    final width = _even((pageWidth * scale).round());
    final height = _even((pageHeight * scale).round());
    if (width <= 0 || height <= 0) return null;
    final rendered = await page.render(
      fullWidth: width.toDouble(),
      fullHeight: height.toDouble(),
    );
    if (rendered == null) return null;
    try {
      // `pixels` is a view over the native render buffer, so it is copied
      // before the native bitmap is freed.
      final bgra = Uint8List.fromList(rendered.pixels);
      return PdfOcrPageImage(
        pageNumber: pageNumber,
        width: width,
        height: height,
        bgra: bgra,
      );
    } finally {
      // The native bitmap backing the pixels is released right away.
      rendered.dispose();
    }
  }

  static int _even(int value) => value.isEven ? value : value - 1;
}
