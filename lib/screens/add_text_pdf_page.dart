import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import '../services/pdf_add_text_service.dart';
import 'pdf_output_preview.dart';

class AddTextPdfPage extends StatefulWidget {
  const AddTextPdfPage({super.key, this.service, this.pageCountLoader});

  final PdfAddTextService? service;

  /// Injectable page-count reader so tests can avoid loading a real PDF.
  final Future<int> Function(Uint8List bytes)? pageCountLoader;

  @override
  State<AddTextPdfPage> createState() => _AddTextPdfPageState();
}

class _AddTextPdfPageState extends State<AddTextPdfPage> {
  late final _service = widget.service ?? PdfAddTextService();
  final _text = TextEditingController();
  final _filename = TextEditingController(text: 'document_text_added.pdf');

  Uint8List? _input;
  Uint8List? _result;
  String? _sourceName;
  String? _message;
  bool _error = false;
  bool _busy = false;

  int _pageCount = 0;
  int _pageIndex = 0;
  bool _allPages = true;
  double _fontSize = 18;
  int _color = 0xFF000000;
  AddTextAlignment _alignment = AddTextAlignment.center;
  AddTextVerticalPosition _vertical = AddTextVerticalPosition.center;

  static const _palette = <int, String>{
    0xFF000000: 'Black',
    0xFF37474F: 'Slate',
    0xFFD32F2F: 'Red',
    0xFF1565C0: 'Blue',
    0xFF2E7D32: 'Green',
  };

  @override
  void dispose() {
    _text.dispose();
    _filename.dispose();
    super.dispose();
  }

  void _status(String value, {bool error = false}) =>
      setState(() {
        _message = value;
        _error = error;
      });

  Future<int> _loadPageCount(Uint8List bytes) async {
    if (widget.pageCountLoader != null) return widget.pageCountLoader!(bytes);
    return addTextPageCountFromBytes(bytes);
  }

  Future<void> _pick() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final selection = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );
      if (!mounted) return;
      if (selection == null) {
        _status('Selection cancelled.');
        return;
      }
      final file = selection.files.single;
      if (file.bytes == null || file.bytes!.isEmpty) {
        throw const FormatException('The selected PDF cannot be accessed.');
      }
      final bytes = file.bytes!;
      int count;
      try {
        count = await _loadPageCount(bytes);
      } on MissingPluginException {
        throw const FormatException(
          'This PDF is password-protected. Unlock it first with the Unlock PDF tool.',
        );
      } catch (error) {
        if (error is FormatException) rethrow;
        throw const FormatException(
          'Could not open this PDF. It may be damaged or unsupported.',
        );
      }
      if (!mounted) return;
      if (count <= 0) {
        throw const FormatException('This PDF has no pages.');
      }
      setState(() {
        _input = bytes;
        _sourceName = file.name;
        _pageCount = count;
        _pageIndex = 0;
        _filename.text =
            '${file.name.replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '')}_text_added.pdf';
        _result = null;
        _message = null;
      });
    } catch (error) {
      if (mounted) {
        _status(
          error.toString().replaceFirst('FormatException: ', ''),
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  PdfAddTextOptions get _options => PdfAddTextOptions(
    text: _text.text,
    fontSize: _fontSize,
    color: _color,
    alignment: _alignment,
    vertical: _vertical,
    pages: _allPages ? null : {_pageIndex},
  );

  Future<bool> _generate() async {
    if (_busy) return false;
    if (_input == null) {
      _status('Select one PDF first.', error: true);
      return false;
    }
    final options = _options;
    final validation = validateAddTextOptions(options, _pageCount);
    if (validation != null) {
      _status(validation, error: true);
      return false;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final output = await _service.apply(_input!, options);
      if (!mounted) return false;
      setState(() => _result = output);
      return true;
    } catch (error) {
      if (mounted) {
        _status(
          error.toString().replaceFirst('PdfAddTextException: ', ''),
          error: true,
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _outputName {
    var name = _filename.text.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (name.isEmpty) name = 'document_text_added.pdf';
    return name.toLowerCase().endsWith('.pdf') ? name : '$name.pdf';
  }

  Future<String> _save() async {
    if (_busy) return 'Please wait for the current operation.';
    if (!await _generate() || !mounted) return 'Could not generate the PDF.';
    setState(() => _busy = true);
    var message = '';
    var failed = false;
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save PDF with added text as a new file',
        fileName: _outputName,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        bytes: _result!,
      );
      message = path == null || path.trim().isEmpty
          ? 'Save cancelled. Your PDF is still ready to save.'
          : 'PDF saved successfully.';
    } catch (_) {
      message = 'Save failed. Check the destination and available space.';
      failed = true;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    _status(message, error: failed);
    return message;
  }

  Future<void> _share() async {
    if (_busy) return;
    if (_result == null && !await _generate()) return;
    if (!mounted || _result == null) return;
    try {
      await const MethodChannel('sickpdf/share').invokeMethod<void>('share', {
        'bytes': _result!,
        'fileName': _outputName,
      });
      _status('Opening share options…');
    } on MissingPluginException {
      _status('Sharing is supported on Android only.', error: true);
    } catch (_) {
      _status('Could not share this PDF.', error: true);
    }
  }

  Future<void> _preview() async {
    if (_busy || !await _generate() || !mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PdfOutputPreview(
          bytes: _result!,
          name: _outputName,
          onSave: _save,
          backLabel: 'Back to Add Text',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Text to PDF')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Add custom text to a PDF locally. The original file stays unchanged.',
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.upload_file),
            label: const Text('Select PDF'),
          ),
          if (_sourceName != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _pageCount > 0
                    ? '$_sourceName • $_pageCount pages'
                    : _sourceName!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            enabled: !_busy,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Text to add',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() => _result = null),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Apply to every page'),
            value: _allPages,
            onChanged: _busy
                ? null
                : (value) => setState(() {
                    _allPages = value;
                    _result = null;
                  }),
          ),
          if (_pageCount > 0 && !_allPages)
            DropdownButtonFormField<int>(
              initialValue: _pageIndex,
              decoration: const InputDecoration(
                labelText: 'Target page',
                border: OutlineInputBorder(),
              ),
              items: [
                for (var i = 0; i < _pageCount; i++)
                  DropdownMenuItem(value: i, child: Text('Page ${i + 1}')),
              ],
              onChanged: _busy
                  ? null
                  : (value) => setState(() {
                      _pageIndex = value ?? 0;
                      _result = null;
                    }),
            ),
          const SizedBox(height: 8),
          Text('Font size: ${_fontSize.round()} pt'),
          Slider(
            value: _fontSize,
            min: 6,
            max: 72,
            divisions: 66,
            onChanged: _busy
                ? null
                : (value) => setState(() {
                    _fontSize = value;
                    _result = null;
                  }),
          ),
          DropdownButtonFormField<int>(
            initialValue: _color,
            decoration: const InputDecoration(labelText: 'Text color'),
            items: [
              for (final entry in _palette.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: _busy
                ? null
                : (value) => setState(() {
                    _color = value!;
                    _result = null;
                  }),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<AddTextAlignment>(
            initialValue: _alignment,
            decoration: const InputDecoration(
              labelText: 'Horizontal alignment',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                value: AddTextAlignment.left,
                child: Text('Left'),
              ),
              DropdownMenuItem(
                value: AddTextAlignment.center,
                child: Text('Center'),
              ),
              DropdownMenuItem(
                value: AddTextAlignment.right,
                child: Text('Right'),
              ),
            ],
            onChanged: _busy
                ? null
                : (value) => setState(() {
                    _alignment = value ?? AddTextAlignment.center;
                    _result = null;
                  }),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<AddTextVerticalPosition>(
            initialValue: _vertical,
            decoration: const InputDecoration(
              labelText: 'Vertical position',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                value: AddTextVerticalPosition.top,
                child: Text('Top'),
              ),
              DropdownMenuItem(
                value: AddTextVerticalPosition.center,
                child: Text('Center'),
              ),
              DropdownMenuItem(
                value: AddTextVerticalPosition.bottom,
                child: Text('Bottom'),
              ),
            ],
            onChanged: _busy
                ? null
                : (value) => setState(() {
                    _vertical = value ?? AddTextVerticalPosition.center;
                    _result = null;
                  }),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _filename,
            enabled: !_busy,
            decoration: const InputDecoration(labelText: 'Output filename'),
          ),
          const SizedBox(height: 12),
          if (_busy) const LinearProgressIndicator(),
          if (_message != null)
            Text(
              _message!,
              style: TextStyle(
                color: _error ? Colors.red.shade700 : Colors.green.shade800,
              ),
            ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _busy || _input == null ? null : _preview,
            icon: const Icon(Icons.preview_outlined),
            label: const Text('Preview PDF with text'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy || _result == null ? null : _share,
            icon: const Icon(Icons.share_outlined),
            label: const Text('Share PDF with text'),
          ),
        ],
      ),
    );
  }
}

/// Exposed for tests: reads the page count of a PDF without the native channel.
Future<int> addTextPageCountFromBytes(Uint8List bytes) async {
  await pdfrxFlutterInitialize();
  final document = await PdfDocument.openData(bytes);
  try {
    return document.pages.length;
  } finally {
    await document.dispose();
  }
}
