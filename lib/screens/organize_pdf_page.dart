import 'dart:async';
import 'dart:developer' as developer;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../services/pdf_organize_service.dart';
import '../services/pdf_split_service.dart';
import 'pdf_output_preview.dart';

class OrganizePdfPage extends StatefulWidget {
  const OrganizePdfPage({super.key});

  @override
  State<OrganizePdfPage> createState() => _OrganizePdfPageState();
}

class _OrganizePdfPageState extends State<OrganizePdfPage> {
  PdfOrganizeSession? _session;
  PdfPageOrder? _order;
  final _selected = <int>{};
  final _filename = TextEditingController(text: 'document_organized.pdf');
  String? _sourceName;
  Uint8List? _result;
  String? _message;
  bool _error = false;
  bool _busy = false;

  void _status(String message, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _error = error;
    });
  }

  void _log(String operation, Object error) {
    // No filenames, paths, document contents or exception messages in logs.
    developer.log(
      '$operation failed (${error.runtimeType}).',
      name: 'sickpdf.organize',
    );
  }

  Future<void> _close(PdfOrganizeSession? session) async {
    try {
      await session?.close();
    } catch (error) {
      _log('Document cleanup', error);
    }
  }

  @override
  void dispose() {
    _filename.dispose();
    unawaited(_close(_session));
    super.dispose();
  }

  void _edit(void Function() action) {
    if (_busy) return;
    setState(() {
      action();
      _result = null;
      _message = null;
    });
  }

  Future<void> _pick() async {
    if (_busy) return;
    setState(() => _busy = true);
    PdfOrganizeSession? opened;
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
        throw const FormatException('The selected PDF cannot be accessed.');
      }
      opened = await PdfOrganizeSession.open(file.path!);
      if (!mounted) {
        await _close(opened);
        return;
      }
      final previous = _session;
      setState(() {
        _session = opened;
        _order = PdfPageOrder(opened!.document.pages.length);
        _selected.clear();
        _sourceName = file.name;
        _filename.text =
            '${file.name.replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '')}_organized.pdf';
        _result = null;
        _message = null;
      });
      // Old thumbnail widgets unmount before the old document is disposed.
      await WidgetsBinding.instance.endOfFrame;
      await _close(previous);
    } catch (error) {
      _log('Selection', error);
      _status(
        pdfSplitLoadError(error).replaceAll('to split it', 'to organize it'),
        error: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    if (_busy || _selected.isEmpty) return;
    if (_selected.length == _order!.pages.length) {
      _status('Keep at least one page in the PDF.', error: true);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${_selected.length} pages?'),
        content: const Text(
          'The original file will not change. You can undo this removal before exporting.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    _edit(() {
      _order!.remove(_selected);
      _selected.clear();
    });
  }

  Future<bool> _generate() async {
    if (_session == null || _order == null) return false;
    if (_result != null) return true;
    setState(() => _busy = true);
    try {
      final bytes = await _session!.generate(_order!.pages);
      if (!mounted) return false;
      setState(() => _result = bytes);
      _status(
        'Organized PDF generated. Preview and save use the same document.',
      );
      return true;
    } catch (error) {
      _log('Generation', error);
      _status(
        'Could not generate the PDF. Try an unlocked, undamaged copy.',
        error: true,
      );
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
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
          backLabel: 'Back to Organize',
        ),
      ),
    );
  }

  String get _outputName {
    var name = _filename.text.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (name.isEmpty) name = 'document_organized.pdf';
    return name.toLowerCase().endsWith('.pdf') ? name : '$name.pdf';
  }

  Future<String> _save() async {
    if (_busy) return 'Please wait for the current operation.';
    if (!await _generate() || !mounted) return 'Could not generate the PDF.';
    setState(() => _busy = true);
    String message;
    var failed = false;
    try {
      final destination = await FilePicker.platform.saveFile(
        dialogTitle: 'Save organized PDF',
        fileName: _outputName,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        bytes: _result!,
      );
      message = destination == null || destination.trim().isEmpty
          ? 'Save cancelled. Your organized PDF is still ready to save.'
          : 'PDF saved successfully.';
    } catch (error) {
      _log('Save', error);
      message = 'Save failed. Check the destination and available space, then try again.';
      failed = true;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    _status(message, error: failed);
    return message;
  }

  @override
  Widget build(BuildContext context) {
    final pages = _order?.pages ?? <int>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Organize PDF')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Reorder and remove pages privately on your device.'),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pick,
              icon: const Icon(Icons.upload_file),
              label: const Text('Select PDF'),
            ),
            if (_sourceName != null)
              Text(
                '$_sourceName • ${pages.length} of ${_session!.document.pages.length} pages',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            if (pages.isNotEmpty) ...[
              const Text(
                'Drag the handle or use the arrows. Checked pages are selected for removal.',
                style: TextStyle(fontSize: 12),
              ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: _busy || _selected.isEmpty ? null : _remove,
                    icon: const Icon(Icons.delete_outline),
                    label: Text('Remove (${_selected.length})'),
                  ),
                  TextButton(
                    onPressed: _busy || !_order!.canUndo
                        ? null
                        : () => _edit(() {
                            _order!.undoRemoval();
                            _selected.clear();
                          }),
                    child: const Text('Undo removal'),
                  ),
                ],
              ),
            ],
            Expanded(
              child: pages.isEmpty
                  ? const Center(
                      child: Text('Select one PDF to organize its pages.'),
                    )
                  : ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      scrollCacheExtent: const ScrollCacheExtent.pixels(0),
                      itemCount: pages.length,
                      onReorderItem: (from, to) =>
                          _edit(() => _order!.move(from, to)),
                      itemBuilder: (context, index) {
                        final source = pages[index];
                        final selected = _selected.contains(source);
                        return Card(
                          key: ValueKey((_session, source)),
                          color: selected
                              ? const Color(0xFFDDF5E7)
                              : Colors.white,
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Row(
                              children: [
                                Checkbox(
                                  value: selected,
                                  semanticLabel:
                                      'Select output page ${index + 1} for removal',
                                  onChanged: _busy
                                      ? null
                                      : (value) => setState(() {
                                          value!
                                              ? _selected.add(source)
                                              : _selected.remove(source);
                                        }),
                                ),
                                _PageThumbnail(
                                  session: _session!,
                                  source: source,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Page ${index + 1}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text('Original ${source + 1}'),
                                      Row(
                                        children: [
                                          IconButton(
                                            tooltip:
                                                'Move page ${index + 1} up',
                                            visualDensity:
                                                VisualDensity.compact,
                                            onPressed: _busy || index == 0
                                                ? null
                                                : () => _edit(
                                                    () => _order!.move(
                                                      index,
                                                      index - 1,
                                                    ),
                                                  ),
                                            icon: const Icon(
                                              Icons.arrow_upward,
                                              size: 20,
                                            ),
                                          ),
                                          IconButton(
                                            tooltip:
                                                'Move page ${index + 1} down',
                                            visualDensity:
                                                VisualDensity.compact,
                                            onPressed:
                                                _busy ||
                                                    index == pages.length - 1
                                                ? null
                                                : () => _edit(
                                                    () => _order!.move(
                                                      index,
                                                      index + 1,
                                                    ),
                                                  ),
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
                                ReorderableDragStartListener(
                                  index: index,
                                  enabled: !_busy,
                                  child: const Padding(
                                    padding: EdgeInsets.all(12),
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
            if (_busy) const LinearProgressIndicator(),
            if (_message != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  _message!,
                  style: TextStyle(
                    color: _error ? Colors.red.shade700 : Colors.green.shade800,
                  ),
                ),
              ),
            TextField(
              controller: _filename,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Output filename',
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy || pages.isEmpty ? null : _preview,
                    icon: const Icon(Icons.preview_outlined),
                    label: const Text('Preview PDF'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy || pages.isEmpty ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save PDF'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Only visible rows hold images. Each image is at most 160px on its long side;
/// the session serializes rendering, and unmounted rows release native images.
class _PageThumbnail extends StatefulWidget {
  const _PageThumbnail({required this.session, required this.source});
  final PdfOrganizeSession session;
  final int source;
  @override
  State<_PageThumbnail> createState() => _PageThumbnailState();
}

class _PageThumbnailState extends State<_PageThumbnail> {
  ui.Image? _image;
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final image = await widget.session.thumbnail(widget.source);
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() => _image = image);
    } catch (error) {
      developer.log(
        'Thumbnail failed (${error.runtimeType}).',
        name: 'sickpdf.organize',
      );
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 64,
    height: 88,
    child: _failed
        ? Tooltip(
            message: 'Thumbnail unavailable. Tap to retry; the page is still included.',
            child: IconButton(
              onPressed: _load,
              icon: const Icon(Icons.broken_image_outlined),
            ),
          )
        : _image == null
        ? const Center(
            child: SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        : RawImage(image: _image, fit: BoxFit.contain),
  );
}
