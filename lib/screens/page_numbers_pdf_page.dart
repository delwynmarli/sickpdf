import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/pdf_page_numbers_service.dart';
import '../services/pdf_split_service.dart';
import 'pdf_output_preview.dart';

class PageNumbersPdfPage extends StatefulWidget {
  const PageNumbersPdfPage({super.key, this.service});
  final PdfPageNumbersService? service;
  @override
  State<PageNumbersPdfPage> createState() => _PageNumbersPdfPageState();
}

class _PageNumbersPdfPageState extends State<PageNumbersPdfPage> {
  late final _service = widget.service ?? PdfPageNumbersService();

  final _start = TextEditingController(text: '1');
  final _first = TextEditingController(text: '1');
  final _last = TextEditingController();
  final _filename = TextEditingController(text: 'document_numbered.pdf');

  Uint8List? _input;
  Uint8List? _result;
  String? _sourceName;
  String? _message;
  bool _error = false;
  bool _busy = false;
  int _pageCount = 0;
  double _fontSize = 12;
  int _color = 0xFF000000;

  PageNumberFormat _format = PageNumberFormat.plain;
  PageNumberPosition _position = PageNumberPosition.bottomCenter;

  static const _palette = <int, String>{
    0xFF000000: 'Black',
    0xFF37474F: 'Slate',
    0xFFD32F2F: 'Red',
    0xFF1565C0: 'Blue',
    0xFF2E7D32: 'Green',
  };

  @override
  void dispose() {
    _start.dispose();
    _first.dispose();
    _last.dispose();
    _filename.dispose();
    super.dispose();
  }

  void _status(String value, {bool error = false}) =>
      setState(() {
        _message = value;
        _error = error;
      });

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
      var count = 0;
      if (file.path != null) {
        count = await PdfSplitService().pageCount(file.path!);
        if (!mounted) return;
      }
      setState(() {
        _input = file.bytes;
        _sourceName = file.name;
        _pageCount = count;
        _result = null;
        _message = null;
        _first.text = '1';
        _last.text = count > 0 ? '$count' : '';
        _filename.text =
            '${file.name.replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '')}_numbered.pdf';
      });
    } catch (error) {
      _status(pdfSplitLoadError(error).replaceAll('to split it', 'to number it'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  PdfPageNumbersOptions? _options() {
    final start = int.tryParse(_start.text.trim());
    final first = int.tryParse(_first.text.trim());
    final last = int.tryParse(_last.text.trim());
    if (start == null) {
      _status('Enter a whole starting number.', error: true);
      return null;
    }
    if (first == null || last == null) {
      _status('Enter whole numbers for the first and last pages.', error: true);
      return null;
    }
    return PdfPageNumbersOptions(
      format: _format,
      position: _position,
      startNumber: start,
      firstPage: first,
      lastPage: last,
      fontSize: _fontSize,
      color: _color,
    );
  }

  Future<bool> _generate() async {
    if (_input == null) {
      _status('Select one PDF first.', error: true);
      return false;
    }
    if (_result != null) return true;
    final options = _options();
    if (options == null) return false;
    final validation = validatePageNumberOptions(
      options,
      _pageCount > 0 ? _pageCount : options.lastPage,
    );
    if (validation != null) {
      _status(validation, error: true);
      return false;
    }
    setState(() => _busy = true);
    try {
      final output = await _service.apply(_input!, options);
      if (!mounted) return false;
      setState(() => _result = output);
      return true;
    } catch (error) {
      _status(
        error.toString().replaceFirst('PdfPageNumbersException: ', ''),
        error: true,
      );
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _outputName {
    var name = _filename.text.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (name.isEmpty) name = 'document_numbered.pdf';
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
        dialogTitle: 'Save numbered PDF as a new file',
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

  Future<void> _preview() async {
    if (_busy || !await _generate() || !mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PdfOutputPreview(
          bytes: _result!,
          name: _outputName,
          onSave: _save,
          backLabel: 'Back to Page Numbers',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Page Numbers PDF')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Add page numbers locally. The original file stays unchanged.',
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.upload_file),
            label: const Text('Select PDF'),
          ),
          if (_sourceName != null)
            Text(
              _pageCount > 0 ? '$_sourceName • $_pageCount pages' : _sourceName!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 12),
          DropdownButtonFormField<PageNumberFormat>(
            initialValue: _format,
            decoration: const InputDecoration(labelText: 'Format'),
            items: const [
              DropdownMenuItem(
                value: PageNumberFormat.plain,
                child: Text('1, 2, 3'),
              ),
              DropdownMenuItem(
                value: PageNumberFormat.page,
                child: Text('Page 1'),
              ),
              DropdownMenuItem(
                value: PageNumberFormat.pageOfN,
                child: Text('Page 1 of N'),
              ),
            ],
            onChanged: _busy
                ? null
                : (v) => setState(() {
                    _format = v!;
                    _result = null;
                  }),
          ),
          DropdownButtonFormField<PageNumberPosition>(
            initialValue: _position,
            decoration: const InputDecoration(labelText: 'Position'),
            items: const [
              DropdownMenuItem(
                value: PageNumberPosition.bottomLeft,
                child: Text('Bottom left'),
              ),
              DropdownMenuItem(
                value: PageNumberPosition.bottomCenter,
                child: Text('Bottom center'),
              ),
              DropdownMenuItem(
                value: PageNumberPosition.bottomRight,
                child: Text('Bottom right'),
              ),
              DropdownMenuItem(
                value: PageNumberPosition.topLeft,
                child: Text('Top left'),
              ),
              DropdownMenuItem(
                value: PageNumberPosition.topCenter,
                child: Text('Top center'),
              ),
              DropdownMenuItem(
                value: PageNumberPosition.topRight,
                child: Text('Top right'),
              ),
            ],
            onChanged: _busy
                ? null
                : (v) => setState(() {
                    _position = v!;
                    _result = null;
                  }),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _start,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Start number',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() => _result = null),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _first,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'First page',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() => _result = null),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _last,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Last page',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() => _result = null),
                ),
              ),
            ],
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
                : (v) => setState(() {
                    _fontSize = v;
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
                : (v) => setState(() {
                    _color = v!;
                    _result = null;
                  }),
          ),
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
            label: const Text('Preview numbered PDF'),
          ),
        ],
      ),
    );
  }
}
