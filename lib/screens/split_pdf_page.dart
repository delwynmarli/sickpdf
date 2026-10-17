import 'dart:developer' as developer;
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import '../services/pdf_split_service.dart';
import '../theme/app_theme.dart';
import '../widgets/tool_scaffold.dart';
import 'pdf_output_preview.dart';

class SplitPdfPage extends StatefulWidget {
  const SplitPdfPage({super.key});

  @override
  State<SplitPdfPage> createState() => _SplitPdfPageState();
}

class _SplitPdfPageState extends State<SplitPdfPage> {
  final _service = PdfSplitService();
  final _start = TextEditingController(text: '1');
  final _end = TextEditingController();
  PlatformFile? _file;
  int? _pageCount;
  Uint8List? _result;
  String? _resultName;
  String? _message;
  bool _error = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _start.addListener(_invalidate);
    _end.addListener(_invalidate);
  }

  void _invalidate() {
    if (!mounted) return;
    setState(() {
      _result = null;
      _resultName = null;
      _message = null;
    });
  }

  @override
  void dispose() {
    _start.dispose();
    _end.dispose();
    _result = null;
    super.dispose();
  }

  void _status(String message, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _error = error;
    });
  }

  void _log(String operation, Object error, StackTrace stack) {
    // Do not log document contents, names, paths, or exception messages.
    if (kDebugMode) {
      final code = error is PdfException ? error.errorCode : null;
      final osCode = error is FileSystemException
          ? error.osError?.errorCode
          : null;
      developer.log(
        '$operation failed (${error.runtimeType}, PDFium code=$code, OS code=$osCode): '
        '${pdfSplitLoadError(error)}',
        name: 'sickpdf.split',
        stackTrace: stack,
      );
    }
  }

  Future<void> _pick() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final selection = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: false,
      );
      if (!mounted) return;
      if (selection == null) {
        _status('Selection cancelled.');
        return;
      }
      _invalidate();
      setState(() {
        _file = null;
        _pageCount = null;
      });
      final file = selection.files.single;
      if (file.path == null) {
        throw const FormatException('The selected file cannot be accessed.');
      }
      final count = await _service.pageCount(file.path!);
      if (!mounted) return;
      _start.text = '1';
      _end.text = '$count';
      setState(() {
        _file = file;
        _pageCount = count;
      });
    } catch (error, stack) {
      _log('Selection', error, stack);
      _status(pdfSplitLoadError(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _split() async {
    if (_busy || _file == null || _pageCount == null) return;
    _invalidate();
    late PdfPageRange range;
    try {
      range = PdfPageRange.parse(_start.text, _end.text, _pageCount!);
    } on FormatException catch (error) {
      _status(error.message, error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final bytes = await _service.extract(_file!.path!, range);
      if (!mounted) return;
      final name = _file!.name.replaceFirst(
        RegExp(r'\.pdf$', caseSensitive: false),
        '',
      );
      setState(() {
        _result = bytes;
        _resultName = '${name}_pages_${range.start}-${range.end}.pdf';
      });
      _status('PDF split successfully. Preview or save the extracted pages.');
    } catch (error, stack) {
      _log('Extraction', error, stack);
      _status(
        'Could not split this PDF. Select it again or try an unlocked, undamaged PDF.',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String> _save() async {
    final bytes = _result;
    if (_busy || bytes == null) return 'Save is not available.';
    setState(() => _busy = true);
    String message;
    var failed = false;
    try {
      final destination = await FilePicker.platform.saveFile(
        dialogTitle: 'Save extracted PDF',
        fileName: _resultName,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        bytes: bytes,
      );
      message = destination == null || destination.trim().isEmpty
          ? 'Save cancelled. Your extracted PDF is still ready to save.'
          : 'PDF saved successfully.';
    } catch (error, stack) {
      _log('Save', error, stack);
      message =
          'Save failed. Check the destination and available space, then try again.';
      failed = true;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    _status(message, error: failed);
    return message;
  }

  Future<void> _preview() async {
    final bytes = _result;
    if (_busy || bytes == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PdfOutputPreview(bytes: bytes, name: _resultName!, onSave: _save),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasFile = _file != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Split PDF')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screen),
        children: [
          const ToolIntro(
            text:
                'Extract a page range into a new PDF. The original file stays unchanged.',
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.upload_file),
            label: const Text('Select PDF'),
          ),
          const SizedBox(height: AppSpacing.xl),
          if (!hasFile)
            ToolEmptyState(
              icon: Icons.call_split,
              title: 'Select one PDF to begin',
              message: 'Then choose the pages you want to keep.',
              onSelect: _busy ? null : _pick,
            )
          else ...[
            SelectedFileCard(
              name: _file!.name,
              detail: '$_pageCount pages',
              onReplace: _busy ? null : _pick,
            ),
            const SizedBox(height: AppSpacing.xl),
            ToolSection(
              title: 'Page range (inclusive)',
              subtitle: 'Earlier and later pages are left out of the new PDF.',
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _start,
                      enabled: !_busy,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: 'Start page'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextField(
                      controller: _end,
                      enabled: !_busy,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: 'End page'),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          if (_busy) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: AppSpacing.xl),
          ],
          if (_message != null) ...[
            ToolStatus(message: _message!, isError: _error),
            const SizedBox(height: AppSpacing.xl),
          ],
          FilledButton.icon(
            onPressed: _busy || !hasFile ? null : _split,
            icon: const Icon(Icons.call_split),
            label: Text(_busy ? 'Processing…' : 'Split PDF'),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy || _result == null ? null : _preview,
                  icon: const Icon(Icons.preview_outlined),
                  label: const Text('Preview'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy || _result == null ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save PDF'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
