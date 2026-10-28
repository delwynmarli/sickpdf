import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/document_share.dart';
import '../services/pdf_ocr_service.dart';
import '../theme/app_theme.dart';
import '../widgets/tool_scaffold.dart';
import 'ocr_result_page.dart';

/// Converts a scanned PDF into plain text on the device.
///
/// The whole flow stays local: pages are rendered one at a time and recognized
/// on the phone. Recognition writes nothing to disk — the text is shown in
/// [OcrResultPage], and a `.txt` file is created only when the user presses
/// **Save TXT**. The source PDF is never modified.
class OcrPdfPage extends StatefulWidget {
  const OcrPdfPage({
    super.key,
    this.service,
    this.saveFile,
    this.copyText,
    this.share,
  });

  /// Injectable service so widget tests can bypass the platform channel and
  /// the native recognizer.
  final PdfOcrService? service;

  /// Forwarded to [OcrResultPage] for tests.
  final Future<String?> Function(String fileName, Uint8List bytes)? saveFile;

  /// Forwarded to [OcrResultPage] for tests.
  final Future<void> Function(String text)? copyText;

  /// Forwarded to [OcrResultPage] for tests.
  final DocumentShare? share;

  @override
  State<OcrPdfPage> createState() => _OcrPdfPageState();
}

class _OcrPdfPageState extends State<OcrPdfPage> {
  late final _service = widget.service ?? PdfOcrService();

  String? _path;
  String? _name;
  int? _pageCount;
  String? _message;
  bool _error = false;
  bool _busy = false;
  bool _cancelled = false;
  int _processedPages = 0;
  int _totalPages = 0;

  @override
  void dispose() {
    // Ask a running extraction to stop so no page is processed after the
    // screen is closed.
    _cancelled = true;
    super.dispose();
  }

  void _status(String message, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _error = error;
    });
  }

  Future<void> _pick() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final selection = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: false,
        withData: false,
      );
      if (!mounted) return;
      if (selection == null) {
        _status('Selection cancelled.');
        return;
      }
      final file = selection.files.single;
      if (file.path == null) {
        throw const PdfOcrException('The selected PDF cannot be accessed.');
      }
      final pages = await _service.pageCount(file.path!);
      if (!mounted) return;
      setState(() {
        _path = file.path;
        _name = file.name;
        _pageCount = pages;
        _message = null;
        _error = false;
        _processedPages = 0;
        _totalPages = pages;
      });
    } on PdfOcrException catch (exception) {
      _status(exception.message, error: true);
    } catch (_) {
      _status('Could not select the PDF. Please try again.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _extract() async {
    if (_busy || _path == null) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _cancelled = false;
      _message = 'Preparing pages…';
      _error = false;
      _processedPages = 0;
      _totalPages = _pageCount ?? 0;
    });
    try {
      // Recognition only: nothing is written to disk here, so cancelling or
      // backing out cannot leave an output file behind.
      final result = await _service.extract(
        _path!,
        isCancelled: () => _cancelled,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _processedPages = progress.pageNumber;
            _totalPages = progress.totalPages;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = null;
        _error = false;
      });
      await _showResult(result);
    } on PdfOcrCancelledException {
      if (!mounted) return;
      _status('Extraction cancelled. No file was created.');
    } on PdfOcrException catch (exception) {
      if (!mounted) return;
      _status(exception.message, error: true);
    } catch (_) {
      if (!mounted) return;
      _status(
        'Could not extract text from this PDF. It may be damaged, encrypted, '
        'or use an unsupported format.',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showResult(PdfOcrResult result) async {
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => OcrResultPage(
          result: result,
          sourceName: _name ?? 'document.pdf',
          outputName: pdfOcrOutputName(_name ?? 'document.pdf'),
          saveFile: widget.saveFile,
          copyText: widget.copyText,
          share: widget.share,
        ),
      ),
    );
  }

  void _cancel() {
    if (!_busy) return;
    setState(() => _cancelled = true);
    _status('Stopping after the current page…');
  }

  @override
  Widget build(BuildContext context) {
    final hasFile = _path != null;
    return Scaffold(
      appBar: AppBar(title: const Text('OCR PDF')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screen),
        children: [
          const ToolIntro(
            text:
                'Turn a scanned document into plain text on your device. Pages '
                'are read locally and never uploaded. You can review and edit '
                'the text before saving it.',
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.upload_file),
            label: const Text('Select PDF'),
          ),
          const SizedBox(height: AppSpacing.md),
          if (hasFile)
            SelectedFileCard(
              name: _name!,
              detail: '$_pageCount pages',
              onReplace: _busy ? null : _pick,
            )
          else
            ToolEmptyState(
              icon: Icons.document_scanner_outlined,
              title: 'Select one PDF to begin',
              message: 'Scanned pages are read one at a time on this device.',
              onSelect: _busy ? null : _pick,
            ),
          const SizedBox(height: AppSpacing.lg),
          if (_busy && _totalPages > 0) ...[
            LinearProgressIndicator(value: _processedPages / _totalPages),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Processing page $_processedPages of $_totalPages',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: _cancelled ? null : _cancel,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('Cancel'),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (_message != null) ...[
            ToolStatus(message: _message!, isError: _error),
            const SizedBox(height: AppSpacing.md),
          ],
          FilledButton.icon(
            // The action stays disabled while a run is active, so a second
            // submission can never start.
            onPressed: _busy || !hasFile ? null : _extract,
            icon: const Icon(Icons.text_snippet_outlined),
            label: Text(_busy ? 'Extracting…' : 'Extract Text'),
          ),
        ],
      ),
    );
  }
}
