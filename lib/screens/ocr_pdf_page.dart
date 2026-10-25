import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../services/pdf_ocr_service.dart';
import '../theme/app_theme.dart';
import '../widgets/tool_scaffold.dart';

/// Converts a scanned PDF into plain text on the device.
///
/// The whole flow stays local: pages are rendered one at a time, recognized
/// on the phone, and written to a new `.txt` file. The source PDF is never
/// modified.
class OcrPdfPage extends StatefulWidget {
  const OcrPdfPage({super.key, this.service, this.outputDirectory});

  /// Injectable service so widget tests can bypass the platform channel and
  /// the native recognizer.
  final PdfOcrService? service;

  /// Folder the extracted text is written to. Defaults to the app's own
  /// documents folder so the output stays inside app storage.
  final Directory? outputDirectory;

  @override
  State<OcrPdfPage> createState() => _OcrPdfPageState();
}

class _OcrPdfPageState extends State<OcrPdfPage> {
  late final _service = widget.service ?? PdfOcrService();

  String? _path;
  String? _name;
  int? _pageCount;

  /// Name the user asked for, before any collision suffix is applied.
  String? _requestedName;

  /// The name the output file actually has, including a collision suffix.
  String? _outputName;

  String? _outputPath;
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
        _requestedName = pdfOcrOutputName(file.name);
        _outputName = _requestedName;
        _outputPath = null;
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
      _outputPath = null;
      _message = 'Preparing pages…';
      _error = false;
      _processedPages = 0;
      _totalPages = _pageCount ?? 0;
    });
    try {
      final directory =
          widget.outputDirectory ?? await getApplicationDocumentsDirectory();
      final result = await _service.extractToTextFile(
        _path!,
        outputDirectory: directory,
        fileName: _requestedName ?? pdfOcrOutputName(_name ?? 'document.pdf'),
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
        _outputPath = result.file.path;
        // The file may have been renamed to avoid a collision, so the name
        // that is shown and offered to the picker is the real one.
        _outputName = result.file.uri.pathSegments.last;
      });
      final failures = result.result.failures;
      _status(
        failures.isEmpty
            ? 'Text extracted. Save it to keep a copy on your device.'
            : 'Text extracted, but ${failures.length} '
                  '${failures.length == 1 ? 'page' : 'pages'} could not be '
                  'read: ${failures.map((failure) => 'page ${failure.pageNumber}').join(', ')}.',
      );
    } on PdfOcrCancelledException {
      if (!mounted) return;
      // A cancelled run is not a successful one: nothing is written.
      setState(() => _outputPath = null);
      _status('Extraction cancelled. No file was created.');
    } on PdfOcrException catch (exception) {
      if (!mounted) return;
      setState(() => _outputPath = null);
      _status(exception.message, error: true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _outputPath = null);
      _status(
        'Could not extract text from this PDF. It may be damaged, encrypted, '
        'or use an unsupported format.',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _cancel() {
    if (!_busy) return;
    setState(() => _cancelled = true);
    _status('Stopping after the current page…');
  }

  Future<void> _save() async {
    if (_busy || _outputPath == null) return;
    setState(() => _busy = true);
    var message = 'Save cancelled. The extracted text is still ready to save.';
    var failed = false;
    try {
      final bytes = await _service.readTextFile(_outputPath!);
      final destination = await FilePicker.platform.saveFile(
        dialogTitle: 'Save extracted text',
        fileName: _outputName,
        type: FileType.custom,
        allowedExtensions: ['txt'],
        bytes: bytes,
      );
      if (destination != null && destination.trim().isNotEmpty) {
        // The mobile picker writes the supplied bytes. Desktop pickers only
        // return a path, so the file is written there.
        if (!Platform.isAndroid && !Platform.isIOS) {
          await File(destination).writeAsBytes(bytes, flush: true);
        }
        message = 'Text saved successfully.';
      }
    } catch (_) {
      message =
          'Save failed. Choose a different destination and check available space.';
      failed = true;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    _status(message, error: failed);
  }

  Future<void> _share() async {
    if (_busy || _outputPath == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await _service.readTextFile(_outputPath!);
      await const MethodChannel('sickpdf/share').invokeMethod<void>('share', {
        'bytes': bytes,
        'fileName': _outputName,
      });
      _status('Opening share options…');
    } on MissingPluginException {
      _status('Sharing is supported on Android only.', error: true);
    } catch (_) {
      _status('Could not share this text file.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasFile = _path != null;
    final outputReady = _outputPath != null;
    return Scaffold(
      appBar: AppBar(title: const Text('OCR PDF')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screen),
        children: [
          const ToolIntro(
            text:
                'Turn a scanned document into plain text on your device. Pages '
                'are read locally and never uploaded.',
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
            LinearProgressIndicator(
              value: _processedPages / _totalPages,
            ),
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
          if (outputReady) ...[
            const SizedBox(height: AppSpacing.lg),
            ToolSection(
              title: 'Result',
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _outputName!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        'Plain text file written to the app folder. The '
                        'original PDF is unchanged.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _share,
                    icon: const Icon(Icons.share_outlined),
                    label: const Text('Share'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save TXT'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
