import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/document_share.dart';
import '../services/pdf_ocr_service.dart';
import '../theme/app_theme.dart';
import '../widgets/tool_scaffold.dart';

/// Shows recognized text before anything is written to disk.
///
/// Nothing is saved automatically: the text exists only in memory until the
/// user presses **Save TXT**. Leaving with **Back** or **Cancel** discards it,
/// so a cancelled run never leaves an output file behind.
class OcrResultPage extends StatefulWidget {
  const OcrResultPage({
    super.key,
    required this.result,
    required this.sourceName,
    required this.outputName,
    this.saveFile,
    this.copyText,
    this.share,
  });

  /// The extraction result shown to the user.
  final PdfOcrResult result;

  /// Name of the PDF the text came from.
  final String sourceName;

  /// File name offered when saving.
  final String outputName;

  /// Injectable save implementation. Returns the path or name that was
  /// actually written, or `null` when the user cancelled.
  final Future<String?> Function(String fileName, Uint8List bytes)? saveFile;

  /// Injectable clipboard writer, so copy can be asserted in tests.
  final Future<void> Function(String text)? copyText;

  /// Injectable share implementation.
  final DocumentShare? share;

  @override
  State<OcrResultPage> createState() => _OcrResultPageState();
}

class _OcrResultPageState extends State<OcrResultPage> {
  late final TextEditingController _controller;
  bool _busy = false;
  String? _message;
  bool _error = false;

  /// True once the text has been saved, so Back can explain what happens.
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.result.text);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Current text, including the user's edits.
  String get _text => _controller.text;

  void _status(String message, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _error = error;
    });
  }

  Future<void> _copy() async {
    if (_busy) return;
    if (_text.trim().isEmpty) {
      _status('There is no text to copy.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final copy = widget.copyText;
      if (copy != null) {
        await copy(_text);
      } else {
        await Clipboard.setData(ClipboardData(text: _text));
      }
      _status('Text copied to the clipboard.');
    } catch (_) {
      _status('Could not copy the text.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    if (_busy) return;
    if (_text.trim().isEmpty) {
      _status('There is no text to share.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final share = widget.share ?? shareDocumentBytes;
      await share(
        Uint8List.fromList(_utf8Bytes(_text)),
        widget.outputName,
      );
      _status('Opening share options…');
    } on DocumentShareException catch (error) {
      _status(error.message, error: true);
    } catch (_) {
      _status('Could not share this text file.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    if (_text.trim().isEmpty) {
      _status('There is no text to save.', error: true);
      return;
    }
    setState(() => _busy = true);
    var message = 'Save cancelled. The text is still here.';
    var failed = false;
    try {
      final bytes = Uint8List.fromList(_utf8Bytes(_text));
      final save = widget.saveFile ?? _saveWithPicker;
      final written = await save(widget.outputName, bytes);
      if (written == null || written.trim().isEmpty) {
        message = 'Save cancelled. The text is still here.';
      } else {
        _saved = true;
        message = 'Saved "${_fileNameOf(written)}".';
      }
    } on DocumentSaveException catch (error) {
      message = error.message;
      failed = true;
    } catch (_) {
      message =
          'Save failed. Choose a different destination and check available '
          'space.';
      failed = true;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    _status(message, error: failed);
  }

  /// Writes through the system save dialog, matching the other tools.
  Future<String?> _saveWithPicker(String fileName, Uint8List bytes) async {
    final String? destination;
    try {
      destination = await FilePicker.platform.saveFile(
        dialogTitle: 'Save extracted text',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['txt'],
        bytes: bytes,
      );
    } catch (_) {
      throw const DocumentSaveException(
        'Save failed. Choose a different destination and check available '
        'space.',
      );
    }
    if (destination == null || destination.trim().isEmpty) return null;
    // The mobile picker writes the supplied bytes. Desktop pickers only
    // return a path, so the file is written there.
    if (!Platform.isAndroid && !Platform.isIOS) {
      try {
        final file = File(destination);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes, flush: true);
      } catch (_) {
        throw const DocumentSaveException(
          'Save failed. Choose a different destination and check available '
          'space.',
        );
      }
    }
    return destination;
  }

  /// Asks before discarding text that was never saved.
  Future<void> _confirmDiscard() async {
    if (_saved || _text.trim().isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard the text?'),
        content: const Text(
          'The recognized text has not been saved. Going back discards it and '
          'no file is created.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard != true || !mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = widget.result;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _confirmDiscard();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('OCR result'),
          leading: IconButton(
            tooltip: 'Back',
            onPressed: _busy ? null : _confirmDiscard,
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(AppSpacing.screen),
          children: [
            _OcrResultSummary(
              sourceName: widget.sourceName,
              pageCount: result.pageCount,
              processedPages: result.processedPages,
              outputName: widget.outputName,
            ),
            if (result.failures.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              ToolStatus(
                message:
                    '${result.failures.length} '
                    '${result.failures.length == 1 ? 'page' : 'pages'} could '
                    'not be read: '
                    '${result.failures.map((failure) => 'page ${failure.pageNumber}').join(', ')}.',
                isError: false,
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            ToolSection(
              title: 'Recognized text',
              subtitle: 'You can edit the text before saving it.',
              child: TextField(
                controller: _controller,
                minLines: 12,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                  height: 1.45,
                ),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                  hintText: 'Recognized text appears here.',
                ),
              ),
            ),
            if (_message != null) ...[
              ToolStatus(message: _message!, isError: _error),
              const SizedBox(height: AppSpacing.md),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _copy,
                    icon: const Icon(Icons.copy_all_outlined),
                    label: const Text('Copy Text'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _share,
                    icon: const Icon(Icons.share_outlined),
                    label: const Text('Share'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save TXT'),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(
              onPressed: _busy ? null : _confirmDiscard,
              child: const Text('Cancel'),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Nothing is written to your device until you press Save TXT.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Source document, page counts, and the name the text will be saved under.
class _OcrResultSummary extends StatelessWidget {
  const _OcrResultSummary({
    required this.sourceName,
    required this.pageCount,
    required this.processedPages,
    required this.outputName,
  });

  final String sourceName;
  final int pageCount;
  final int processedPages;
  final String outputName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detail = processedPages == 0
        ? 'No text recognized in $pageCount '
              '${pageCount == 1 ? 'page' : 'pages'}.'
        : '$processedPages of $pageCount '
              '${pageCount == 1 ? 'page' : 'pages'} produced text.';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.picture_as_pdf_outlined,
                  size: 20,
                  color: theme.colorScheme.onSurface,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    sourceName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              detail,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Will be saved as $outputName',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A save attempt that the user needs to know about.
class DocumentSaveException implements Exception {
  const DocumentSaveException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Last path segment of a saved destination, so the confirmation names the
/// file that was actually written rather than the requested one.
String _fileNameOf(String destination) {
  final normalized = destination.replaceAll(r'\', '/');
  final trimmed = normalized.endsWith('/')
      ? normalized.substring(0, normalized.length - 1)
      : normalized;
  final slash = trimmed.lastIndexOf('/');
  final name = slash >= 0 ? trimmed.substring(slash + 1) : trimmed;
  return name.isEmpty ? destination : name;
}

/// UTF-8 bytes for the text as it currently stands, including any edits.
List<int> _utf8Bytes(String text) => utf8.encode(text);
