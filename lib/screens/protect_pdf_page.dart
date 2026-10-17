import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/pdf_protect_service.dart';
import '../theme/app_theme.dart';
import '../widgets/tool_scaffold.dart';
import 'pdf_output_preview.dart';

class ProtectPdfPage extends StatefulWidget {
  const ProtectPdfPage({super.key, this.service});
  final PdfProtectService? service;

  @override
  State<ProtectPdfPage> createState() => _ProtectPdfPageState();
}

class _ProtectPdfPageState extends State<ProtectPdfPage> {
  late final _service = widget.service ?? PdfProtectService();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _filename = TextEditingController(text: 'document_protected.pdf');
  Uint8List? _source;
  Uint8List? _result;
  String? _sourceName;
  String? _message;
  bool _error = false;
  bool _busy = false;
  bool _hidden = true;

  void _status(String message, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _error = error;
    });
  }

  @override
  void dispose() {
    _password.clear();
    _confirmation.clear();
    _password.dispose();
    _confirmation.dispose();
    _filename.dispose();
    _source = null;
    _result = null;
    super.dispose();
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
      final file = selection.files.single;
      if (file.path == null) {
        throw const PdfProtectException('The selected PDF cannot be accessed.');
      }
      final source = await _service.load(file.path!);
      if (!mounted) return;
      setState(() {
        _source = source;
        _sourceName = file.name;
        _result = null;
        _password.clear();
        _confirmation.clear();
        _hidden = true;
        _filename.text =
            '${file.name.replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '')}_protected.pdf';
        _message = null;
      });
    } on PdfProtectException catch (error) {
      _status(error.message, error: true);
    } catch (_) {
      _status('Could not select the PDF. Please try again.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _invalidate(String _) {
    setState(() {
      _result = null;
      _message = null;
    });
  }

  Future<bool> _generate() async {
    if (_source == null || _busy) return false;
    final validation = validatePdfPassword(
      _password.text,
      _confirmation.text,
    );
    if (validation != null) {
      _status(validation, error: true);
      return false;
    }
    if (_result != null) return true;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final result = await _service.protect(
        _source!,
        _password.text,
        _confirmation.text,
      );
      if (!mounted) return false;
      setState(() => _result = result);
      _status('Encrypted PDF verified. Ready to preview or save as a new file.');
      return true;
    } on PdfProtectException catch (error) {
      _status(error.message, error: true);
      return false;
    } catch (_) {
      _status('Could not protect the PDF. No file was exported.', error: true);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _outputName {
    var name = _filename.text.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (name.isEmpty) name = 'document_protected.pdf';
    return name.toLowerCase().endsWith('.pdf') ? name : '$name.pdf';
  }

  Future<String> _save() async {
    if (_busy) return 'Please wait for the current operation.';
    if (!await _generate() || !mounted) {
      return 'Could not generate the protected PDF.';
    }
    setState(() => _busy = true);
    var message = '';
    var failed = false;
    try {
      final destination = await FilePicker.platform.saveFile(
        dialogTitle: 'Save protected PDF as a new file',
        fileName: _outputName,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        bytes: _result!,
      );
      message = destination == null || destination.trim().isEmpty
          ? 'Save cancelled. Your encrypted PDF is still ready to save.'
          : 'Encrypted PDF saved successfully.';
    } catch (_) {
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
    if (_busy || !await _generate() || !mounted) return;
    // Only encrypted bytes reach the shared viewer; password remains in memory.
    var supplied = false;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PdfOutputPreview(
          bytes: _result!,
          name: _outputName,
          onSave: _save,
          backLabel: 'Back to Protect',
          passwordProvider: () {
            if (supplied) return null;
            supplied = true;
            return _password.text;
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasSource = _source != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Protect PDF')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screen),
        children: [
          const ToolIntro(
            text:
                'Encrypt a PDF with a password. The original file stays unchanged.',
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.upload_file),
            label: const Text('Select PDF'),
          ),
          const SizedBox(height: AppSpacing.md),
          if (!hasSource)
            ToolEmptyState(
              icon: Icons.lock_outline,
              title: 'Select a PDF to protect',
              message: 'You will set a password on the next step.',
              onSelect: _busy ? null : _pick,
            )
          else ...[
            SelectedFileCard(
              name: _sourceName!,
              onReplace: _busy ? null : _pick,
            ),
            const SizedBox(height: AppSpacing.lg),
            ToolSection(
              title: 'Password',
              subtitle: 'AES-256 encryption is applied locally.',
              child: Column(
                children: [
                  for (final entry in [
                    (_password, 'Password'),
                    (_confirmation, 'Confirm password'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: TextField(
                        controller: entry.$1,
                        enabled: !_busy,
                        obscureText: _hidden,
                        autocorrect: false,
                        enableSuggestions: false,
                        enableIMEPersonalizedLearning: false,
                        keyboardType: TextInputType.visiblePassword,
                        onChanged: _invalidate,
                        decoration: InputDecoration(
                          labelText: entry.$2,
                          suffixIcon: IconButton(
                            tooltip: _hidden
                                ? 'Show passwords'
                                : 'Hide passwords',
                            onPressed: _busy
                                ? null
                                : () => setState(() => _hidden = !_hidden),
                            icon: Icon(
                              _hidden ? Icons.visibility : Icons.visibility_off,
                            ),
                          ),
                        ),
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Remember your password. Without it, the encrypted PDF '
                      'may not be recoverable.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            TextField(
              controller: _filename,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: 'Output filename'),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          if (_busy) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: AppSpacing.md),
          ],
          if (_message != null) ...[
            ToolStatus(message: _message!, isError: _error),
            const SizedBox(height: AppSpacing.md),
          ],
          FilledButton.icon(
            onPressed: _busy || !hasSource ? null : _preview,
            icon: const Icon(Icons.preview_outlined),
            label: const Text('Protect & Preview'),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: _busy || !hasSource ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save PDF'),
          ),
        ],
      ),
    );
  }
}
