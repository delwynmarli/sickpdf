import 'dart:developer' as developer;
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/pdf_compress_service.dart';
import '../services/pdf_split_service.dart';
import '../theme/app_theme.dart';
import '../widgets/tool_scaffold.dart';
import 'pdf_output_preview.dart';

class CompressPdfPage extends StatefulWidget {
  const CompressPdfPage({super.key, this.service});

  /// Injectable service so widget tests can bypass the platform channel.
  final PdfCompressService? service;

  @override
  State<CompressPdfPage> createState() => _CompressPdfPageState();
}

class _CompressPdfPageState extends State<CompressPdfPage> {
  late final _service = widget.service ?? PdfCompressService();
  PdfCompressionMode _mode = PdfCompressionMode.medium;
  final _filename = TextEditingController(text: 'document_compressed.pdf');
  String? _path;
  String? _name;
  int? _size;
  int? _pages;
  PdfCompressionResult? _result;
  bool _busy = false;
  bool _error = false;
  String? _message;

  @override
  void dispose() {
    _filename.dispose();
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

  void _log(String operation, Object error) => developer.log(
    '$operation failed (${error.runtimeType}).',
    name: 'sickpdf.compress',
  );

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
        throw const FormatException('The selected PDF cannot be accessed.');
      }
      final pages = await _service.pageCount(file.path!);
      final size = await File(file.path!).length();
      if (!mounted) return;
      setState(() {
        _path = file.path;
        _name = file.name;
        _size = size;
        _pages = pages;
        _result = null;
        _message = null;
        _filename.text =
            '${file.name.replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '')}_compressed.pdf';
      });
    } catch (error) {
      _log('Selection', error);
      _status(
        pdfSplitLoadError(error).replaceAll('to split it', 'to compress it'),
        error: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _compress() async {
    if (_busy || _path == null) return;
    setState(() {
      _busy = true;
      _result = null;
      _message = 'Optimizing PDF locally…';
      _error = false;
    });
    try {
      final result = await _service.compress(_path!, mode: _mode);
      if (!mounted) return;
      setState(() => _result = result);
      _status(
        result.reduced
            ? 'Compression produced a smaller PDF. Preview before saving.'
            : 'This PDF is already optimized, so no smaller output was produced. Preview and Save use the unchanged original.',
      );
    } catch (error) {
      _log('Compression', error);
      _status(
        'Could not optimize this PDF. Try an unlocked, undamaged copy with sufficient free memory.',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _outputName {
    var name = _filename.text.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (name.isEmpty) name = 'document_compressed.pdf';
    return name.toLowerCase().endsWith('.pdf') ? name : '$name.pdf';
  }

  Future<String> _save() async {
    if (_busy || _result == null) return 'No output is ready to save.';
    setState(() => _busy = true);
    var message = 'Save cancelled. Your generated PDF is still ready to save.';
    var failed = false;
    try {
      final destination = await FilePicker.platform.saveFile(
        dialogTitle: 'Save compressed PDF',
        fileName: _outputName,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        bytes: _result!.bytes,
      );
      if (destination != null && destination.trim().isNotEmpty) {
        // Mobile picker writes the supplied bytes. Desktop pickers only return
        // a path; perform and await the actual write there.
        if (!Platform.isAndroid && !Platform.isIOS) {
          if (File(destination).absolute.path == File(_path!).absolute.path) {
            throw const FileSystemException(
              'The original must not be overwritten.',
            );
          }
          await File(destination).writeAsBytes(_result!.bytes, flush: true);
        }
        message = 'PDF saved successfully.';
      }
    } catch (error) {
      _log('Save', error);
      message =
          'Save failed. Choose a different destination and check available space.';
      failed = true;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    _status(message, error: failed);
    return message;
  }

  Future<void> _preview() async {
    if (_busy || _result == null) return;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => PdfOutputPreview(
            bytes: _result!.bytes,
            name: _outputName,
            onSave: _save,
            backLabel: 'Back to Compress',
          ),
        ),
      );
    } catch (error) {
      _log('Preview', error);
      _status(
        'Preview failed. You can still try saving the generated PDF.',
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final hasFile = _path != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Compress PDF')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screen),
        children: [
          const ToolIntro(
            text:
                'Reduce file size while keeping the original PDF. Text and vector content are never rasterized.',
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
              detail: '${formatPdfSize(_size!)} • $_pages pages',
              onReplace: _busy ? null : _pick,
            )
          else
            ToolEmptyState(
              icon: Icons.compress,
              title: 'Select one PDF to begin',
              message: 'Already optimized PDFs may not shrink further.',
              onSelect: _busy ? null : _pick,
            ),
          const SizedBox(height: AppSpacing.lg),
          ToolSection(
            title: 'Compression level',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final mode in PdfCompressionMode.values)
                  RadioListTile<PdfCompressionMode>(
                    value: mode,
                    // ignore: deprecated_member_use
                    groupValue: _mode,
                    // ignore: deprecated_member_use
                    onChanged: _busy
                        ? null
                        : (value) => setState(() {
                            _mode = value!;
                            _result = null;
                            _message = null;
                          }),
                    contentPadding: EdgeInsets.zero,
                    title: Text(_modeTitle(mode)),
                    subtitle: Text(_modeSubtitle(mode)),
                  ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Medium and High recompress eligible images and may soften them. Preview before saving.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (_busy) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: AppSpacing.md),
          ],
          if (_message != null) ...[
            ToolStatus(message: _message!, isError: _error),
            const SizedBox(height: AppSpacing.md),
          ],
          FilledButton.icon(
            onPressed: _busy || !hasFile ? null : _compress,
            icon: const Icon(Icons.compress),
            label: Text(_busy ? 'Optimizing…' : 'Compress PDF'),
          ),
          if (result != null) ...[
            const SizedBox(height: AppSpacing.lg),
            ToolSection(
              title: 'Result',
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ResultRow(
                        label: 'Original',
                        value: formatPdfSize(result.originalSize),
                      ),
                      _ResultRow(
                        label: 'Output',
                        value: formatPdfSize(result.outputSize),
                      ),
                      _ResultRow(
                        label: 'Saved',
                        value:
                            '${formatPdfSize(result.bytesSaved)} '
                            '(${result.reductionPercent.clamp(0, 100).toStringAsFixed(1)}%)',
                      ),
                    ],
                  ),
                ),
              ),
            ),
            TextField(
              controller: _filename,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: 'Output filename'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _preview,
                    icon: const Icon(Icons.preview_outlined),
                    label: const Text('Preview'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save PDF'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _modeTitle(PdfCompressionMode mode) {
    switch (mode) {
      case PdfCompressionMode.lossless:
        return 'Low — lossless';
      case PdfCompressionMode.medium:
        return 'Medium — recommended';
      case PdfCompressionMode.high:
        return 'High — smallest file';
    }
  }

  String _modeSubtitle(PdfCompressionMode mode) {
    switch (mode) {
      case PdfCompressionMode.lossless:
        return 'Images stay unchanged. Safest option.';
      case PdfCompressionMode.medium:
        return '150 dpi, JPEG quality 80.';
      case PdfCompressionMode.high:
        return '100 dpi, JPEG quality 55. Most aggressive.';
    }
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
