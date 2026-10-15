import 'dart:developer' as developer;
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/pdf_compress_service.dart';
import '../services/pdf_split_service.dart';
import 'pdf_output_preview.dart';

class CompressPdfPage extends StatefulWidget {
  const CompressPdfPage({super.key});

  @override
  State<CompressPdfPage> createState() => _CompressPdfPageState();
}

class _CompressPdfPageState extends State<CompressPdfPage> {
  final _service = PdfCompressService();
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
            : 'This PDF is already optimized, or no smaller output could be produced with the selected settings. Preview and Save now use the unchanged original.',
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
      message = 'Save failed. Choose a different destination and check available space.';
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
    return Scaffold(
      appBar: AppBar(title: const Text('Compress PDF')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Optimize a PDF privately on your device. The original stays unchanged.',
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.upload_file),
            label: const Text('Select PDF'),
          ),
          if (_name != null)
            Text(
              '$_name\nOriginal: ${formatPdfSize(_size!)} ($_size bytes) • $_pages pages',
            ),
          const SizedBox(height: 16),
          const Text(
            'Compression preset',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const Text(
            'Text and vector objects are not rasterized. Medium and High recompress eligible opaque RGB/grayscale images; transparency, images inside forms, tagged images and unusual color spaces are skipped. Already optimized PDFs may not shrink.',
          ),
          const Text(
            'Up to 64 MiB input. Digitally signed PDFs should not be optimized: rewriting invalidates signatures.',
          ),
          DropdownButton<PdfCompressionMode>(
            value: _mode,
            isExpanded: true,
            items: const [
              DropdownMenuItem(
                value: PdfCompressionMode.lossless,
                child: Text('Low — lossless, images unchanged'),
              ),
              DropdownMenuItem(
                value: PdfCompressionMode.medium,
                child: Text('Medium — 150 dpi, JPEG quality 80'),
              ),
              DropdownMenuItem(
                value: PdfCompressionMode.high,
                child: Text('High — 100 dpi, JPEG quality 55'),
              ),
            ],
            onChanged: _busy
                ? null
                : (mode) => setState(() {
                    _mode = mode!;
                    _result = null;
                    _message = null;
                  }),
          ),
          const Text(
            'Medium/High may soften images and introduce JPEG artifacts. Preview before saving. Resolution targets apply where images are oversized.',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy || _path == null ? null : _compress,
            icon: const Icon(Icons.compress),
            label: const Text('Compress PDF'),
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
          if (result != null) ...[
            const SizedBox(height: 16),
            Text(
              'Original: ${formatPdfSize(result.originalSize)} (${result.originalSize} bytes)\nOutput: ${formatPdfSize(result.outputSize)} (${result.outputSize} bytes)\nBytes saved: ${result.bytesSaved}\nReduction: ${result.reductionPercent.toStringAsFixed(2)}%',
            ),
            Text('Images recompressed in candidate: ${result.imagesChanged}'),
            Text(
              'Validated candidate: ${result.candidateSize} bytes; retained ${result.retainedOriginal ? "original" : "candidate"}.',
            ),
            Text(
              'Processing: ${result.diagnostics.entries.map((e) => "${e.key}: ${e.value}").join(", ")}',
            ),
            TextField(
              controller: _filename,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: 'Output filename'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _preview,
              icon: const Icon(Icons.preview_outlined),
              label: const Text('Preview PDF'),
            ),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save PDF'),
            ),
          ],
        ],
      ),
    );
  }
}
