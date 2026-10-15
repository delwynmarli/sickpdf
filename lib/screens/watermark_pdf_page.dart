import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/pdf_watermark_service.dart';
import 'pdf_output_preview.dart';

class WatermarkPdfPage extends StatefulWidget {
  const WatermarkPdfPage({super.key, this.service});
  final PdfWatermarkService? service;
  @override
  State<WatermarkPdfPage> createState() => _WatermarkPdfPageState();
}

class _WatermarkPdfPageState extends State<WatermarkPdfPage> {
  late final _service = widget.service ?? PdfWatermarkService();
  final _text = TextEditingController();
  final _filename = TextEditingController(text: 'document_watermarked.pdf');
  Uint8List? _input;
  Uint8List? _result;
  String? _sourceName;
  String? _message;
  bool _error = false;
  bool _busy = false;
  double _size = 36;
  double _opacity = .25;
  WatermarkPosition _position = WatermarkPosition.center;
  WatermarkRotation _rotation = WatermarkRotation.diagonal;
  bool _allPages = true;
  final _pages = <int>{};

  @override
  void dispose() { _text.dispose(); _filename.dispose(); super.dispose(); }

  void _status(String value, {bool error = false}) => setState(() { _message = value; _error = error; });

  Future<void> _pick() async {
    if (_busy) return;
    try {
      final selection = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], withData: true);
      if (selection == null || !mounted) return;
      final file = selection.files.single;
      if (file.bytes == null || file.bytes!.isEmpty) throw const FormatException('The selected PDF cannot be accessed.');
      setState(() { _input = file.bytes; _sourceName = file.name; _filename.text = '${file.name.replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '')}_watermarked.pdf'; _result = null; _message = null; _pages.clear(); });
    } catch (error) { if (mounted) _status(error.toString().replaceFirst('FormatException: ', ''), error: true); }
  }

  PdfWatermarkOptions get _options => PdfWatermarkOptions(text: _text.text, fontSize: _size, opacity: _opacity, position: _position, rotation: _rotation, pages: _allPages ? null : _pages);

  Future<bool> _generate() async {
    if (_input == null) { _status('Select one PDF first.', error: true); return false; }
    final validation = validateWatermarkOptions(_options, 1);
    if (validation != null && validation != 'Select at least one valid page.') { _status(validation, error: true); return false; }
    if (!_allPages && _pages.isEmpty) { _status('Select at least one page.', error: true); return false; }
    setState(() => _busy = true);
    try { final output = await _service.apply(_input!, _options); if (!mounted) return false; setState(() => _result = output); return true; }
    catch (error) { if (mounted) _status(error.toString().replaceFirst('PdfWatermarkException: ', ''), error: true); return false; }
    finally { if (mounted) setState(() => _busy = false); }
  }

  String get _outputName { var name = _filename.text.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_'); if (name.isEmpty) name = 'document_watermarked.pdf'; return name.toLowerCase().endsWith('.pdf') ? name : '$name.pdf'; }

  Future<String> _save() async {
    if (!await _generate() || !mounted) return 'Could not generate the PDF.';
    try {
      final path = await FilePicker.platform.saveFile(dialogTitle: 'Save watermarked PDF as a new file', fileName: _outputName, type: FileType.custom, allowedExtensions: ['pdf'], bytes: _result!);
      final message = path == null || path.trim().isEmpty ? 'Save cancelled. Your PDF is still ready to save.' : 'PDF saved successfully.';
      _status(message); return message;
    } catch (_) { const message = 'Save failed. Check the destination and available space.'; _status(message, error: true); return message; }
  }

  Future<void> _preview() async { if (!await _generate() || !mounted) return; await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PdfOutputPreview(bytes: _result!, name: _outputName, onSave: _save, backLabel: 'Back to Watermark'))); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Watermark PDF')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Add a permanent text watermark locally. The original file stays unchanged.'),
      OutlinedButton.icon(onPressed: _busy ? null : _pick, icon: const Icon(Icons.upload_file), label: const Text('Select PDF')),
      if (_sourceName != null) Text(_sourceName!, overflow: TextOverflow.ellipsis),
      const SizedBox(height: 12),
      TextField(controller: _text, enabled: !_busy, decoration: const InputDecoration(labelText: 'Watermark text', border: OutlineInputBorder()), onChanged: (_) => setState(() => _result = null)),
      Text('Text size: ${_size.round()} pt'), Slider(value: _size, min: 8, max: 144, divisions: 34, onChanged: _busy ? null : (v) => setState(() { _size = v; _result = null; })),
      Text('Opacity: ${(_opacity * 100).round()}%'), Slider(value: _opacity, min: .05, max: 1, divisions: 19, onChanged: _busy ? null : (v) => setState(() { _opacity = v; _result = null; })),
      DropdownButtonFormField<WatermarkPosition>(initialValue: _position, decoration: const InputDecoration(labelText: 'Position'), items: const [DropdownMenuItem(value: WatermarkPosition.center, child: Text('Center')), DropdownMenuItem(value: WatermarkPosition.top, child: Text('Top')), DropdownMenuItem(value: WatermarkPosition.bottom, child: Text('Bottom'))], onChanged: _busy ? null : (v) => setState(() { _position = v!; _result = null; })),
      DropdownButtonFormField<WatermarkRotation>(initialValue: _rotation, decoration: const InputDecoration(labelText: 'Rotation'), items: const [DropdownMenuItem(value: WatermarkRotation.horizontal, child: Text('Horizontal')), DropdownMenuItem(value: WatermarkRotation.diagonal, child: Text('Diagonal'))], onChanged: _busy ? null : (v) => setState(() { _rotation = v!; _result = null; })),
      SwitchListTile(title: const Text('Apply to all pages'), value: _allPages, onChanged: _busy ? null : (v) => setState(() { _allPages = v; _result = null; })),
      if (!_allPages) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('Page selection is applied by page number. Enter pages below (for example: 1, 3, 5).')),
      if (!_allPages) TextField(keyboardType: TextInputType.text, decoration: const InputDecoration(labelText: 'Pages'), onChanged: (value) { final parsed = value.split(',').map((s) => int.tryParse(s.trim())).whereType<int>().where((p) => p > 0).map((p) => p - 1).toSet(); setState(() { _pages..clear()..addAll(parsed); _result = null; }); }),
      TextField(controller: _filename, enabled: !_busy, decoration: const InputDecoration(labelText: 'Output filename')),
      const SizedBox(height: 12),
      if (_busy) const LinearProgressIndicator(),
      if (_message != null) Text(_message!, style: TextStyle(color: _error ? Colors.red.shade700 : Colors.green.shade800)),
      const SizedBox(height: 8),
      FilledButton.icon(onPressed: _busy || _input == null ? null : _preview, icon: const Icon(Icons.preview_outlined), label: const Text('Preview watermark and export')),
    ]),
  );
}
