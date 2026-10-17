import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../services/pdf_organize_service.dart';
import '../services/pdf_rotate_service.dart';
import '../services/pdf_split_service.dart';
import '../theme/app_theme.dart';
import '../widgets/tool_scaffold.dart';
import 'pdf_output_preview.dart';

class RotatePdfPage extends StatefulWidget {
  const RotatePdfPage({super.key});
  @override
  State<RotatePdfPage> createState() => _RotatePdfPageState();
}

class _RotatePdfPageState extends State<RotatePdfPage> {
  PdfOrganizeSession? _session;
  PdfPageRotations? _rotations;
  final _selected = <int>{};
  final _filename = TextEditingController(text: 'document_rotated.pdf');
  Uint8List? _result;
  String? _sourceName;
  String? _message;
  bool _error = false;
  bool _busy = false;

  void _status(String message, {bool error = false}) {
    if (mounted) {
      setState(() {
        _message = message;
        _error = error;
      });
    }
  }

  Future<void> _close(PdfOrganizeSession? session) async {
    try {
      await session?.close();
    } catch (_) {
      /* Best effort cleanup. */
    }
  }

  @override
  void dispose() {
    _filename.dispose();
    unawaited(_close(_session));
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
        throw const FormatException('The selected PDF cannot be accessed.');
      }
      final opened = await PdfOrganizeSession.open(file.path!);
      if (!mounted) {
        await _close(opened);
        return;
      }
      final previous = _session;
      setState(() {
        _session = opened;
        _rotations = PdfPageRotations(opened.document.pages.length);
        _selected.clear();
        _sourceName = file.name;
        _filename.text =
            '${file.name.replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '')}_rotated.pdf';
        _result = null;
        _message = null;
      });
      await WidgetsBinding.instance.endOfFrame;
      await _close(previous);
    } catch (error) {
      _status(
        pdfSplitLoadError(error).replaceAll('to split it', 'to rotate it'),
        error: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _rotate(int delta) {
    if (_busy || _selected.isEmpty) return;
    setState(() {
      _rotations!.rotate(_selected, delta);
      _result = null;
      _message = null;
    });
  }

  Future<bool> _generate() async {
    if (_session == null) return false;
    if (_result != null) return true;
    setState(() => _busy = true);
    try {
      final bytes = await generateRotatedPdf(
        _session!.document,
        _rotations!.turns,
      );
      if (!mounted) return false;
      setState(() => _result = bytes);
      return true;
    } catch (_) {
      _status(
        'Could not generate the PDF. Try an unlocked, undamaged copy.',
        error: true,
      );
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _outputName {
    var name = _filename.text.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (name.isEmpty) name = 'document_rotated.pdf';
    return name.toLowerCase().endsWith('.pdf') ? name : '$name.pdf';
  }

  Future<String> _save() async {
    if (_busy) return 'Please wait for the current operation.';
    if (!await _generate() || !mounted) return 'Could not generate the PDF.';
    setState(() => _busy = true);
    var message = '';
    var failed = false;
    try {
      final destination = await FilePicker.platform.saveFile(
        dialogTitle: 'Save rotated PDF as a new file',
        fileName: _outputName,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        bytes: _result!,
      );
      message = destination == null || destination.trim().isEmpty
          ? 'Save cancelled. Your rotated PDF is still ready to save.'
          : 'PDF saved successfully.';
    } catch (_) {
      message = 'Save failed. Check the destination and available space, then try again.';
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
          backLabel: 'Back to Rotate',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = _rotations?.turns.length ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Rotate PDF')),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.screen),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ToolIntro(
              text:
                  'Rotate selected pages by 90°. The original stays unchanged.',
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pick,
              icon: const Icon(Icons.upload_file),
              label: const Text('Select PDF'),
            ),
            if (_sourceName != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  '$_sourceName • $count pages',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (count > 0) ...[
              const SizedBox(height: AppSpacing.xs),
              Text('${_selected.length} pages selected'),
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(
                            () => _selected.addAll(
                              List.generate(count, (i) => i),
                            ),
                          ),
                    child: const Text('Select all'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => setState(_selected.clear),
                    child: const Text('Deselect all'),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: _busy || _selected.isEmpty
                        ? null
                        : () => _rotate(-1),
                    icon: const Icon(Icons.rotate_left),
                    label: const Text('90° counterclockwise'),
                  ),
                  TextButton.icon(
                    onPressed: _busy || _selected.isEmpty
                        ? null
                        : () => _rotate(1),
                    icon: const Icon(Icons.rotate_right),
                    label: const Text('90° clockwise'),
                  ),
                ],
              ),
              const Text(
                'Applies to selected pages. Select all to rotate every page.',
              ),
            ],
            Expanded(
              child: count == 0
                  ? const Center(
                      child: Text('Select one PDF to rotate its pages.'),
                    )
                  : ListView.builder(
                      scrollCacheExtent: const ScrollCacheExtent.pixels(0),
                      itemCount: count,
                      itemBuilder: (context, index) => Card(
                        key: ValueKey((_session, index)),
                        color: _selected.contains(index)
                            ? const Color(0xFFDDF5E7)
                            : Colors.white,
                        child: Row(
                          children: [
                            Checkbox(
                              value: _selected.contains(index),
                              semanticLabel: 'Select page ${index + 1}',
                              onChanged: _busy
                                  ? null
                                  : (value) => setState(() {
                                      value!
                                          ? _selected.add(index)
                                          : _selected.remove(index);
                                    }),
                            ),
                            RotatedBox(
                              quarterTurns: _rotations!.turns[index],
                              child: _RotateThumbnail(
                                session: _session!,
                                index: index,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Page ${index + 1} • +${_rotations!.turns[index] * 90}°',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
            if (_busy) ...[
              const SizedBox(height: AppSpacing.xs),
              const LinearProgressIndicator(),
            ],
            if (_message != null) ...[
              const SizedBox(height: AppSpacing.xs),
              ToolStatus(message: _message!, isError: _error),
            ],
            const SizedBox(height: AppSpacing.xs),
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
                    onPressed: _busy || count == 0 ? null : _preview,
                    icon: const Icon(Icons.preview_outlined),
                    label: const Text('Preview PDF'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy || count == 0 ? null : _save,
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

/// Visible rows only; session serializes renders, capped at 160px long edge.
class _RotateThumbnail extends StatefulWidget {
  const _RotateThumbnail({required this.session, required this.index});
  final PdfOrganizeSession session;
  final int index;
  @override
  State<_RotateThumbnail> createState() => _RotateThumbnailState();
}

class _RotateThumbnailState extends State<_RotateThumbnail> {
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
      final image = await widget.session.thumbnail(widget.index);
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() => _image = image);
    } catch (_) {
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
        ? IconButton(
            tooltip: 'Thumbnail unavailable. Retry',
            onPressed: _load,
            icon: const Icon(Icons.broken_image_outlined),
          )
        : _image == null
        ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
        : RawImage(image: _image, fit: BoxFit.contain),
  );
}
