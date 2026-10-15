import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

class PdfOutputPreview extends StatefulWidget {
  const PdfOutputPreview({
    super.key,
    required this.bytes,
    required this.name,
    required this.onSave,
    this.backLabel = 'Back to Split',
    this.passwordProvider,
  });
  final String backLabel;
  final PdfPasswordProvider? passwordProvider;
  final Uint8List bytes;
  final String name;
  final Future<String> Function() onSave;

  @override
  State<PdfOutputPreview> createState() => PdfOutputPreviewState();
}

class PdfOutputPreviewState extends State<PdfOutputPreview> {
  bool _saving = false;
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Preview PDF'),
      actions: [
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
            if (_saving) const LinearProgressIndicator(),
            if (_message != null)
              Semantics(liveRegion: true, child: Text(_message!)),
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
