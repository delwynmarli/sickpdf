import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/pdf_merge_service.dart';
import '../theme/app_theme.dart';
import '../widgets/tool_scaffold.dart';
import 'pdf_output_preview.dart';

class MergePdfPage extends StatefulWidget {
  const MergePdfPage({super.key, this.service});

  /// Injectable service so widget tests can avoid the platform channel.
  final PdfMergeService? service;

  @override
  State<MergePdfPage> createState() => _MergePdfPageState();
}

class _MergePdfPageState extends State<MergePdfPage> {
  late final _mergeService = widget.service ?? PdfMergeService();
  final List<PlatformFile> _files = [];
  bool _isBusy = false;
  Uint8List? _mergedPdf;
  String? _statusMessage;
  bool _statusIsError = false;

  @override
  void dispose() {
    // Bytes are GC-managed; drop the reference eagerly.
    _mergedPdf = null;
    super.dispose();
  }

  void _setStatus(String message, {bool isError = true}) {
    if (!mounted) return;
    setState(() {
      _statusMessage = message;
      _statusIsError = isError;
    });
  }

  Future<void> _pickFiles() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: false,
      );
      if (!mounted || result == null) return;
      final validFiles = result.files
          .where((file) => file.path != null)
          .toList();
      setState(() {
        for (final file in validFiles) {
          if (!_files.any((existing) => existing.path == file.path)) {
            _mergedPdf = null;
            _statusMessage = null;
            _files.add(file);
          }
        }
      });
      if (validFiles.isEmpty && result.files.isNotEmpty) {
        _setStatus(
          'The selected files could not be accessed. Please try again.',
        );
      }
    } catch (error) {
      developer.log(
        'File selection failed (${error.runtimeType}).',
        name: 'sickpdf.merge',
      );
      if (mounted) {
        _setStatus('Could not open the file picker. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _mergeFiles() async {
    if (_isBusy) return;
    if (_files.length < 2) {
      _setStatus('Select at least two PDF files before merging.');
      return;
    }

    setState(() {
      _isBusy = true;
      _mergedPdf = null;
      _statusMessage = null;
    });
    try {
      final bytes = await _mergeService.merge(
        inputPaths: _files.map((file) => file.path!).toList(),
      );
      if (!mounted) return;
      setState(() => _mergedPdf = bytes);
      developer.log(
        'Merge completed: ${bytes.length} bytes.',
        name: 'sickpdf.merge',
      );
      _setStatus(
        'PDFs merged successfully. Preview or save the result.',
        isError: false,
      );
    } catch (error, stackTrace) {
      developer.log(
        'Merge failed.',
        name: 'sickpdf.merge',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        _setStatus(
          'Merge failed: ${error.toString().replaceFirst('Exception: ', '')}',
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  String get _outputName => 'merged_document.pdf';

  Future<String> _save() async {
    final bytes = _mergedPdf;
    if (_isBusy || bytes == null || bytes.isEmpty) {
      return 'No merged PDF is ready to save.';
    }
    setState(() => _isBusy = true);
    var message = 'Save cancelled. Your merged PDF is still ready to save.';
    var failed = false;
    try {
      final destination = await FilePicker.platform.saveFile(
        dialogTitle: 'Save merged PDF',
        fileName: _outputName,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        bytes: bytes,
      );
      if (destination != null && destination.trim().isNotEmpty) {
        message = 'PDF saved successfully.';
      }
    } catch (error, stackTrace) {
      developer.log(
        'Save failed.',
        name: 'sickpdf.merge',
        error: error,
        stackTrace: stackTrace,
      );
      message =
          'Save failed. Choose a different destination and check available space.';
      failed = true;
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
    _setStatus(message, isError: failed);
    return message;
  }

  Future<void> _openPreview() async {
    final bytes = _mergedPdf;
    if (bytes == null || bytes.isEmpty) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PdfOutputPreview(
          bytes: bytes,
          name: _outputName,
          onSave: _save,
          backLabel: 'Back to Merge',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canMerge = !_isBusy && _files.length >= 2;
    return Scaffold(
      appBar: AppBar(title: const Text('Merge PDF')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screen),
        children: [
          const ToolIntro(
            text:
                'Combine several PDFs into one file. Everything stays on your device and the original files are never changed.',
          ),
          OutlinedButton.icon(
            onPressed: _isBusy ? null : _pickFiles,
            icon: const Icon(Icons.add),
            label: const Text('Select PDF files'),
          ),
          const SizedBox(height: AppSpacing.xl),
          if (_files.isEmpty)
            ToolEmptyState(
              icon: Icons.merge_type,
              title: 'No PDFs selected yet',
              message: 'Choose two or more PDFs to combine them.',
              onSelect: _isBusy ? null : _pickFiles,
            )
          else ...[
            ToolSection(
              title: 'Order (${_files.length} files)',
              subtitle:
                  'Drag the handle or use the arrows to reorder. The merged PDF follows this order.',
              child: ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: _files.length,
                onReorderItem: (oldIndex, newIndex) {
                  if (_isBusy || oldIndex == newIndex) return;
                  setState(() {
                    _mergedPdf = null;
                    _statusMessage = null;
                    final file = _files.removeAt(oldIndex);
                    _files.insert(newIndex, file);
                  });
                },
                itemBuilder: (context, index) {
                  final file = _files[index];
                  return Card(
                    key: ValueKey(file.path),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xs),
                      child: Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.xs,
                            ),
                            child: Icon(
                              Icons.picture_as_pdf_outlined,
                              size: 22,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  file.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  'Position ${index + 1}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color:
                                        theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                Row(
                                  children: [
                                    IconButton(
                                      tooltip: 'Move ${file.name} up',
                                      visualDensity: VisualDensity.compact,
                                      onPressed: _isBusy || index == 0
                                          ? null
                                          : () => setState(() {
                                              _mergedPdf = null;
                                              _statusMessage = null;
                                              final item = _files.removeAt(
                                                index,
                                              );
                                              _files.insert(index - 1, item);
                                            }),
                                      icon: const Icon(
                                        Icons.arrow_upward,
                                        size: 20,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Move ${file.name} down',
                                      visualDensity: VisualDensity.compact,
                                      onPressed:
                                          _isBusy ||
                                              index == _files.length - 1
                                          ? null
                                          : () => setState(() {
                                              _mergedPdf = null;
                                              _statusMessage = null;
                                              final item = _files.removeAt(
                                                index,
                                              );
                                              _files.insert(index + 1, item);
                                            }),
                                      icon: const Icon(
                                        Icons.arrow_downward,
                                        size: 20,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Remove ${file.name}',
                            onPressed: _isBusy
                                ? null
                                : () => setState(() {
                                    _mergedPdf = null;
                                    _statusMessage = null;
                                    _files.removeAt(index);
                                  }),
                            icon: const Icon(Icons.close),
                          ),
                          ReorderableDragStartListener(
                            index: index,
                            enabled: !_isBusy,
                            child: const Padding(
                              padding: EdgeInsets.all(AppSpacing.sm),
                              child: Icon(Icons.drag_handle),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          if (_statusMessage != null) ...[
            ToolStatus(message: _statusMessage!, isError: _statusIsError),
            const SizedBox(height: AppSpacing.xl),
          ],
          if (_isBusy) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: AppSpacing.xl),
          ],
          FilledButton.icon(
            onPressed: canMerge ? _mergeFiles : null,
            icon: const Icon(Icons.merge_type),
            label: Text(_isBusy ? 'Processing…' : 'Merge PDF'),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isBusy || _mergedPdf == null
                      ? null
                      : _openPreview,
                  icon: const Icon(Icons.preview_outlined),
                  label: const Text('Preview'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isBusy || _mergedPdf == null ? null : _save,
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
