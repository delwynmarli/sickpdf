import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../services/pdf_split_service.dart';

const _navy = Color(0xFF0B172A);

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
      message = 'Save failed. Check the destination and available space, then try again.';
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
        builder: (_) =>
            _SplitPreview(bytes: bytes, name: _resultName!, onSave: _save),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Split PDF'), foregroundColor: _navy),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Extract pages privately on your device.',
            style: TextStyle(color: _navy, fontSize: 16),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.upload_file),
            label: const Text('Select PDF'),
          ),
          if (_file != null) ...[
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: _navy),
                title: Text(_file!.name),
                subtitle: Text('$_pageCount pages'),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Page range (inclusive)',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _start,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Start page',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _end,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'End page',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          if (_busy) const LinearProgressIndicator(),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                _message!,
                style: TextStyle(
                  color: _error ? Colors.red.shade700 : Colors.green.shade800,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy || _file == null ? null : _split,
            style: FilledButton.styleFrom(
              backgroundColor: _navy,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.call_split),
            label: Text(_busy ? 'Processing...' : 'Split PDF'),
          ),
          if (_result != null) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : _preview,
              icon: const Icon(Icons.preview_outlined),
              label: const Text('Preview PDF'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save PDF'),
            ),
          ],
        ],
      ),
    );
  }
}

class _SplitPreview extends StatefulWidget {
  const _SplitPreview({
    required this.bytes,
    required this.name,
    required this.onSave,
  });
  final Uint8List bytes;
  final String name;
  final Future<String> Function() onSave;

  @override
  State<_SplitPreview> createState() => _SplitPreviewState();
}

class _SplitPreviewState extends State<_SplitPreview> {
  bool _saving = false;
  String? _message;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final message = await widget.onSave();
    if (!mounted) return;
    setState(() {
      _saving = false;
      _message = message;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Preview PDF'),
      actions: [
        TextButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Save PDF'),
        ),
      ],
    ),
    // PdfViewer owns and disposes its document reference when unmounted.
    body: PdfViewer.data(widget.bytes, sourceName: widget.name),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_saving) const LinearProgressIndicator(),
            if (_message != null)
              Semantics(liveRegion: true, child: Text(_message!)),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back to Split'),
            ),
          ],
        ),
      ),
    ),
  );
}
