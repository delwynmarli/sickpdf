import 'dart:developer' as developer;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/pdf_image_to_pdf_service.dart';
import 'pdf_output_preview.dart';

/// Editable, ordered list of images plus the layout options shared with
/// [PdfImageToPdfService]. Kept UI-free so it can be unit tested.
class ImageSelection {
  final List<PdfImageInput> _images = [];

  List<PdfImageInput> get images => List.unmodifiable(_images);
  int get length => _images.length;
  bool get isEmpty => _images.isEmpty;

  void addAll(Iterable<PdfImageInput> images) => _images.addAll(images);

  void removeAt(int index) {
    RangeError.checkValidIndex(index, _images);
    _images.removeAt(index);
  }

  void move(int from, int to) {
    RangeError.checkValidIndex(from, _images);
    RangeError.checkValidIndex(to, _images);
    _images.insert(to, _images.removeAt(from));
  }

  void clear() => _images.clear();
}

class ImagesToPdfPage extends StatefulWidget {
  const ImagesToPdfPage({super.key, this.service});

  /// Injectable service so widget tests can avoid the platform channel.
  final PdfImageToPdfService? service;

  @override
  State<ImagesToPdfPage> createState() => _ImagesToPdfPageState();
}

class _ImagesToPdfPageState extends State<ImagesToPdfPage> {
  late final _service = widget.service ?? PdfImageToPdfService();
  final _selection = ImageSelection();
  final _filename = TextEditingController(text: 'images_to_pdf.pdf');

  ImagePageSize _pageSize = ImagePageSize.a4;
  ImageMargin _margin = ImageMargin.small;
  ImageFit _fit = ImageFit.contain;

  Uint8List? _result;
  String? _message;
  bool _error = false;
  bool _busy = false;

  @override
  void dispose() {
    _filename.dispose();
    super.dispose();
  }

  void _status(String message, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _error = error;
    });
  }

  void _log(String operation, Object error) {
    // No filenames, paths or image contents in logs.
    developer.log(
      '$operation failed (${error.runtimeType}).',
      name: 'sickpdf.images',
    );
  }

  /// Any edit invalidates the previously generated PDF so it is never stale.
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
    try {
      final selection = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png'],
        withData: true,
      );
      if (!mounted) return;
      if (selection == null) {
        _status('Selection cancelled.');
        return;
      }
      final valid = <PdfImageInput>[];
      for (final file in selection.files) {
        final bytes = file.bytes;
        if (bytes == null || bytes.isEmpty) continue;
        valid.add(PdfImageInput(name: file.name, bytes: bytes));
      }
      if (valid.isEmpty) {
        _edit(() {}); // clear stale result
        _status(
          'The selected images could not be read. Choose JPEG or PNG files and try again.',
          error: true,
        );
        return;
      }
      _edit(() => _selection.addAll(valid));
      _status(
        'Added ${valid.length} image${valid.length == 1 ? '' : 's'}. '
        'Reorder or remove before converting.',
      );
    } catch (error) {
      _log('Selection', error);
      _status('Could not open the file picker. Please try again.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _generate() async {
    if (_result != null) return true;
    if (_selection.isEmpty) {
      _status('Select at least one image to convert.', error: true);
      return false;
    }
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      final bytes = await _service.convert(
        images: _selection.images,
        size: _pageSize,
        margin: _margin,
        fit: _fit,
      );
      if (!mounted) return false;
      setState(() => _result = bytes);
      _status(
        'PDF created from ${_selection.length} image'
        '${_selection.length == 1 ? '' : 's'}. Preview or save it.',
      );
      return true;
    } on PdfImageToPdfException catch (error) {
      _status(error.message, error: true);
      return false;
    } catch (error) {
      _log('Conversion', error);
      _status(
        'Could not create the PDF from these images. Try removing the affected image.',
        error: true,
      );
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _outputName {
    var name = _filename.text.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (name.isEmpty) name = 'images_to_pdf.pdf';
    return name.toLowerCase().endsWith('.pdf') ? name : '$name.pdf';
  }

  Future<String> _save() async {
    if (_busy) return 'Please wait for the current operation.';
    if (!await _generate() || !mounted) return 'Could not create the PDF.';
    setState(() => _busy = true);
    String message;
    var failed = false;
    try {
      final destination = await FilePicker.platform.saveFile(
        dialogTitle: 'Save PDF from images',
        fileName: _outputName,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        bytes: _result!,
      );
      message = destination == null || destination.trim().isEmpty
          ? 'Save cancelled. Your PDF is still ready to save.'
          : 'PDF saved successfully.';
    } catch (error) {
      _log('Save', error);
      message =
          'Save failed. Check the destination and available space, then try again.';
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
    } catch (error) {
      _log('Share', error);
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
          backLabel: 'Back to Image to PDF',
        ),
      ),
    );
  }

  String _pageSizeLabel(ImagePageSize size) {
    switch (size) {
      case ImagePageSize.a4:
        return 'A4 page';
      case ImagePageSize.original:
        return 'Original image proportions';
      case ImagePageSize.letter:
        return 'US Letter page';
      case ImagePageSize.square:
        return 'Square page';
    }
  }

  String _fitLabel(ImageFit fit) {
    switch (fit) {
      case ImageFit.contain:
        return 'Contain (no crop)';
      case ImageFit.cover:
        return 'Cover (fills page)';
      case ImageFit.stretch:
        return 'Stretch to page';
    }
  }

  String _marginLabel(ImageMargin margin) {
    switch (margin) {
      case ImageMargin.none:
        return 'No margin';
      case ImageMargin.small:
        return 'Small margin';
      case ImageMargin.medium:
        return 'Medium margin';
      case ImageMargin.large:
        return 'Large margin';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Image to PDF')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          const Text(
            'Turn photos and images into a PDF privately on your device. The original images are never changed.',
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('Select images'),
          ),
          const SizedBox(height: 12),
          if (_selection.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'No images selected yet.\nChoose one or more JPEG or PNG files.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          else ...[
            Text(
              '${_selection.length} image${_selection.length == 1 ? '' : 's'} • '
              'one image per page, in the order below',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Drag the handle or use the arrows to reorder. Remove images before converting.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 8),
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: _selection.length,
              onReorderItem: (from, to) => _edit(() => _selection.move(from, to)),
              itemBuilder: (context, index) {
                final image = _selection.images[index];
                return Card(
                  key: ValueKey('${index}_${image.name}'),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        _ImageThumbnail(bytes: image.bytes),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Page ${index + 1}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                image.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    tooltip: 'Move image ${index + 1} up',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: _busy || index == 0
                                        ? null
                                        : () => _edit(
                                            () => _selection.move(
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
                                    tooltip: 'Move image ${index + 1} down',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: _busy ||
                                            index == _selection.length - 1
                                        ? null
                                        : () => _edit(
                                            () => _selection.move(
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
                        IconButton(
                          tooltip: 'Remove ${image.name}',
                          onPressed: _busy
                              ? null
                              : () => _edit(() => _selection.removeAt(index)),
                          icon: const Icon(Icons.close),
                        ),
                        ReorderableDragStartListener(
                          index: index,
                          enabled: !_busy,
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(Icons.drag_handle),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<ImagePageSize>(
              initialValue: _pageSize,
              decoration: const InputDecoration(
                labelText: 'Page size',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final size in ImagePageSize.values)
                  DropdownMenuItem(value: size, child: Text(_pageSizeLabel(size))),
              ],
              onChanged: _busy
                  ? null
                  : (value) => _edit(() => _pageSize = value ?? _pageSize),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ImageMargin>(
              initialValue: _margin,
              decoration: const InputDecoration(
                labelText: 'Margin',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final margin in ImageMargin.values)
                  DropdownMenuItem(
                    value: margin,
                    child: Text(_marginLabel(margin)),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (value) => _edit(() => _margin = value ?? _margin),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ImageFit>(
              initialValue: _fit,
              decoration: const InputDecoration(
                labelText: 'Image fitting',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final fit in ImageFit.values)
                  DropdownMenuItem(value: fit, child: Text(_fitLabel(fit))),
              ],
              onChanged: _busy
                  ? null
                  : (value) => _edit(() => _fit = value ?? _fit),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _filename,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Output filename',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() => _result = null),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy || _selection.isEmpty ? null : _preview,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.preview_outlined),
              label: Text(_busy ? 'Working…' : 'Preview PDF'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy || _selection.isEmpty ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save PDF'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy || _selection.isEmpty ? null : _share,
              icon: const Icon(Icons.share_outlined),
              label: const Text('Share PDF'),
            ),
          ],
          if (_busy) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
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
        ],
      ),
    );
  }
}

class _ImageThumbnail extends StatelessWidget {
  const _ImageThumbnail({required this.bytes});
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 56,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          bytes,
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) => Container(
            color: const Color(0xFFE8EDF2),
            alignment: Alignment.center,
            child: const Icon(Icons.broken_image_outlined, size: 22),
          ),
        ),
      ),
    );
  }
}
