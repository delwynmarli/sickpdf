import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/pdf_unlock_service.dart';
import 'pdf_output_preview.dart';

class UnlockPdfPage extends StatefulWidget {
  const UnlockPdfPage({super.key, this.service});
  final PdfUnlockService? service;
  @override
  State<UnlockPdfPage> createState() => _UnlockPdfPageState();
}

class _UnlockPdfPageState extends State<UnlockPdfPage> {
  late final _service = widget.service ?? PdfUnlockService();
  final _password = TextEditingController();
  final _filename = TextEditingController(text: 'document_unlocked.pdf');
  Uint8List? _result;
  String? _sourceName;
  String? _path;
  String? _message;
  bool _error = false;
  bool _busy = false;
  bool _hidden = true;

  void _status(String message, {bool error = false}) {
    if (mounted) setState(() { _message = message; _error = error; });
  }

  @override
  void dispose() {
    _password.clear();
    _password.dispose();
    _filename.dispose();
    _result = null;
    super.dispose();
  }

  Future<void> _pick() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final selection = await FilePicker.platform.pickFiles(
        allowMultiple: false, type: FileType.custom,
        allowedExtensions: ['pdf'], withData: false,
      );
      if (!mounted) return;
      if (selection == null) { _status('Selection cancelled.'); return; }
      final file = selection.files.single;
      if (file.path == null) throw const PdfUnlockException('The selected PDF cannot be accessed.');
      setState(() {
        _path = file.path;
        _sourceName = file.name;
        _result = null;
        _password.clear();
        _hidden = true;
        _filename.text = '${file.name.replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '')}_unlocked.pdf';
        _message = null;
      });
    } on PdfUnlockException catch (e) { _status(e.message, error: true); }
    catch (_) { _status('Could not select the PDF. Please try again.', error: true); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<bool> _generate() async {
    if (_path == null || _busy) return false;
    final validation = validateUnlockPassword(_password.text);
    if (validation != null) { _status(validation, error: true); return false; }
    if (_result != null) return true;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final result = await _service.unlock(_path!, _password.text);
      if (!mounted) return false;
      setState(() => _result = result);
      _status('Unlocked PDF verified. Ready to preview or save as a new file.');
      return true;
    } on PdfUnlockException catch (e) { _status(e.message, error: true); return false; }
    catch (_) { _status('Could not unlock the PDF. No file was exported.', error: true); return false; }
    finally { if (mounted) setState(() => _busy = false); }
  }

  String get _outputName {
    var name = _filename.text.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (name.isEmpty) name = 'document_unlocked.pdf';
    return name.toLowerCase().endsWith('.pdf') ? name : '$name.pdf';
  }

  Future<String> _save() async {
    if (_busy) return 'Please wait for the current operation.';
    if (!await _generate() || !mounted) return 'Could not generate the unlocked PDF.';
    setState(() => _busy = true);
    var message = '';
    var failed = false;
    try {
      final destination = await FilePicker.platform.saveFile(
        dialogTitle: 'Save unlocked PDF as a new file', fileName: _outputName,
        type: FileType.custom, allowedExtensions: ['pdf'], bytes: _result!,
      );
      message = destination == null || destination.trim().isEmpty
          ? 'Save cancelled. Your unlocked PDF is still ready to save.'
          : 'Unlocked PDF saved successfully.';
    } catch (_) { message = 'Save failed. Check the destination and available space, then try again.'; failed = true; }
    finally { if (mounted) setState(() => _busy = false); }
    _status(message, error: failed);
    return message;
  }

  Future<void> _preview() async {
    if (_busy || !await _generate() || !mounted) return;
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => PdfOutputPreview(bytes: _result!, name: _outputName, onSave: _save, backLabel: 'Back to Unlock'),
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Unlock PDF')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Remove the open password from a PDF privately on your device. The original stays unchanged.'),
      OutlinedButton.icon(onPressed: _busy ? null : _pick, icon: const Icon(Icons.upload_file), label: const Text('Select PDF')),
      if (_sourceName != null) Text(_sourceName!, maxLines: 2, overflow: TextOverflow.ellipsis),
      const SizedBox(height: 16),
      TextField(
        controller: _password, enabled: !_busy, obscureText: _hidden, autocorrect: false,
        enableSuggestions: false, enableIMEPersonalizedLearning: false,
        keyboardType: TextInputType.visiblePassword,
        onChanged: (_) => setState(() { _result = null; _message = null; }),
        decoration: InputDecoration(labelText: 'PDF password', suffixIcon: IconButton(
          tooltip: _hidden ? 'Show password' : 'Hide password', onPressed: _busy ? null : () => setState(() => _hidden = !_hidden),
          icon: Icon(_hidden ? Icons.visibility : Icons.visibility_off),
        )),
      ),
      const SizedBox(height: 8),
      const Text('This removes the password needed to open the document. It does not promise to remove owner permissions, DRM, or signatures.'),
      const SizedBox(height: 16),
      TextField(controller: _filename, enabled: !_busy, decoration: const InputDecoration(labelText: 'Output filename', isDense: true)),
      const SizedBox(height: 16),
      if (_busy) const LinearProgressIndicator(),
      if (_message != null) Semantics(liveRegion: true, child: Text(_message!, style: TextStyle(color: _error ? Colors.red.shade700 : Colors.green.shade800))),
      FilledButton.icon(onPressed: _busy || _path == null ? null : _preview, icon: const Icon(Icons.preview_outlined), label: const Text('Preview PDF')),
      OutlinedButton.icon(onPressed: _busy || _path == null ? null : _save, icon: const Icon(Icons.save_outlined), label: const Text('Save PDF')),
    ]),
  );
}
