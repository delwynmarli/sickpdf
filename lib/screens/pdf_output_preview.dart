import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../services/document_library.dart';

/// Shared output preview for processed PDFs.
///
/// In addition to saving via the system file picker, offers "Add to Files"
/// which copies the output into sickPDF's app-managed document library so it
/// appears on the Files tab. The original source file is never modified.
class PdfOutputPreview extends StatefulWidget {
  const PdfOutputPreview({
    super.key,
    required this.bytes,
    required this.name,
    required this.onSave,
    this.backLabel = 'Back to Split',
    this.passwordProvider,
    this.addToLibrary,
  });
  final String backLabel;
  final PdfPasswordProvider? passwordProvider;
  final Uint8List bytes;
  final String name;
  final Future<String> Function() onSave;

  /// When provided, overrides how the output is stored in the app-managed
  /// library (used by tests to avoid platform channels).
  final Future<void> Function(Uint8List bytes, String name)? addToLibrary;

  @override
  State<PdfOutputPreview> createState() => PdfOutputPreviewState();
}

class PdfOutputPreviewState extends State<PdfOutputPreview> {
  bool _saving = false;
  bool _adding = false;
  String? _message;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final message = await widget.onSave();
    if (!mounted) return;
    setState(() {
      _saving = false;
      _message = message;
    });
  }

  Future<void> _addToFiles() async {
    if (_adding) return;
    setState(() {
      _adding = true;
      _message = null;
    });
    try {
      final add = widget.addToLibrary;
      if (add != null) {
        await add(widget.bytes, widget.name);
        if (!mounted) return;
        setState(
          () => _message = 'Added to Files. Find it under the Files tab.',
        );
      } else {
        // Production path: store into the app-managed library directly and
        // report the name it actually got, which may carry a collision suffix.
        final doc = await DocumentLibrary().addFromBytes(
          widget.bytes,
          displayName: widget.name,
        );
        if (!mounted) return;
        setState(
          () => _message =
              'Added "${doc.fileName}" to Files. Find it under the Files tab.',
        );
      }
    } on LibraryException catch (error) {
      if (!mounted) return;
      setState(() => _message = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _message = 'Could not add the document to Files.');
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Preview PDF'),
      actions: [
        TextButton.icon(
          onPressed: _adding || _saving ? null : _addToFiles,
          icon: _adding
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.create_new_folder_outlined),
          label: const Text('Add to Files'),
        ),
        TextButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Save PDF'),
        ),
      ],
    ),
    // PdfViewer owns and disposes its document reference when unmounted.
    body: PdfViewer.data(
      widget.bytes,
      sourceName: widget.name,
      passwordProvider: widget.passwordProvider,
      params: PdfViewerParams(
        errorBannerBuilder: (context, error, stackTrace, documentRef) =>
            const Center(
              child: Text(
                'Preview unavailable. Go back and try again, or save the PDF.',
              ),
            ),
      ),
    ),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_saving || _adding) const LinearProgressIndicator(),
            if (_message != null)
              Semantics(
                liveRegion: true,
                child: Text(_message!),
              ),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(widget.backLabel),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Convenience helper: copies [bytes] into the app-managed library under
/// [name] and returns the stored record.
Future<LibraryDocument> addBytesToLibrary(
  Uint8List bytes,
  String name, {
  DocumentLibrary? library,
}) async {
  final lib = library ?? DocumentLibrary();
  return lib.addFromBytes(bytes, displayName: name);
}
