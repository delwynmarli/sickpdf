import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import '../services/pdf_sign_service.dart';
import '../widgets/signature_pad.dart';
import 'pdf_output_preview.dart';

class SignPdfPage extends StatefulWidget {
  const SignPdfPage({super.key, this.service, this.pageCountLoader});

  final PdfSignService? service;

  /// Injectable page-count reader so tests can avoid loading a real PDF.
  final Future<int> Function(Uint8List bytes, String? password)? pageCountLoader;

  @override
  State<SignPdfPage> createState() => _SignPdfPageState();
}

class _SignPdfPageState extends State<SignPdfPage> {
  late final _service = widget.service ?? PdfSignService();
  final _padController = SignaturePadController();
  final _filename = TextEditingController(text: 'document_signed.pdf');

  Uint8List? _input;
  Uint8List? _signaturePng;
  Uint8List? _result;
  String? _sourceName;
  String? _message;
  bool _error = false;
  bool _busy = false;

  int _pageCount = 0;
  int _pageIndex = 0;
  SignaturePosition _position = SignaturePosition.bottomRight;
  double _width = 0.30;
  double _height = 0.12;
  double _margin = 0.04;
  double _opacity = 1.0;

  @override
  void dispose() {
    _filename.dispose();
    _padController.dispose();
    super.dispose();
  }

  void _status(String value, {bool error = false}) =>
      setState(() {
        _message = value;
        _error = error;
      });

  Future<int> _loadPageCount(Uint8List bytes) async {
    if (widget.pageCountLoader != null) {
      return widget.pageCountLoader!(bytes, null);
    }
    await pdfrxFlutterInitialize();
    final document = await PdfDocument.openData(bytes);
    try {
      return document.pages.length;
    } finally {
      await document.dispose();
    }
  }

  Future<void> _pick() async {
    if (_busy) return;
    try {
      final selection = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );
      if (selection == null || !mounted) return;
      final file = selection.files.single;
      if (file.bytes == null || file.bytes!.isEmpty) {
        throw const FormatException('The selected PDF cannot be accessed.');
      }
      final bytes = file.bytes!;
      int pageCount;
      try {
        pageCount = await _loadPageCount(bytes);
      } on PdfPasswordException {
        throw const FormatException(
          'This PDF is password-protected. Unlock it first with the Unlock PDF tool.',
        );
      } catch (error) {
        if (error is FormatException) rethrow;
        throw const FormatException(
          'Could not open this PDF. It may be damaged or unsupported.',
        );
      }
      if (!mounted) return;
      if (pageCount <= 0) {
        throw const FormatException('This PDF has no pages.');
      }
      setState(() {
        _input = bytes;
        _sourceName = file.name;
        _pageCount = pageCount;
        _pageIndex = 0;
        _filename.text =
            '${file.name.replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '')}_signed.pdf';
        _result = null;
        _message = null;
      });
    } catch (error) {
      if (mounted) {
        _status(error.toString().replaceFirst('FormatException: ', ''), error: true);
      }
    }
  }

  PdfSignOptions _options(Uint8List signature) => PdfSignOptions(
    signaturePng: signature,
    pageIndex: _pageIndex,
    position: _position,
    widthFraction: _width,
    heightFraction: _height,
    offsetXFraction: _margin,
    offsetYFraction: _margin,
    opacity: _opacity,
  );

  /// Captures the current signature and validates the whole request.
  Future<PdfSignOptions?> _validatedOptions() async {
    if (_input == null) {
      _status('Select one PDF first.', error: true);
      return null;
    }
    final signature = _signaturePng ?? await _padController.exportPng();
    if (signature == null || signature.isEmpty) {
      _status('Draw your signature before continuing.', error: true);
      return null;
    }
    final options = _options(signature);
    final validation = validateSignOptions(options, _pageCount);
    if (validation != null) {
      _status(validation, error: true);
      return null;
    }
    return options;
  }

  Future<bool> _generate() async {
    if (_busy) return false;
    final options = await _validatedOptions();
    if (options == null || !mounted) return false;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final output = await _service.apply(_input!, options);
      if (!mounted) return false;
      setState(() {
        _signaturePng = options.signaturePng;
        _result = output;
      });
      return true;
    } catch (error) {
      if (mounted) {
        _status(
          error.toString().replaceFirst('PdfSignException: ', ''),
          error: true,
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _outputName {
    var name = _filename.text.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (name.isEmpty) name = 'document_signed.pdf';
    return name.toLowerCase().endsWith('.pdf') ? name : '$name.pdf';
  }

  Future<String> _save() async {
    if (!await _generate() || !mounted) return 'Could not generate the PDF.';
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save signed PDF as a new file',
        fileName: _outputName,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        bytes: _result!,
      );
      final message = path == null || path.trim().isEmpty
          ? 'Save cancelled. Your PDF is still ready to save.'
          : 'PDF saved successfully.';
      _status(message);
      return message;
    } catch (_) {
      const message = 'Save failed. Check the destination and available space.';
      _status(message, error: true);
      return message;
    }
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
    } catch (_) {
      _status('Could not share this PDF.', error: true);
    }
  }

  Future<void> _preview() async {
    if (!await _generate() || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PdfOutputPreview(
          bytes: _result!,
          name: _outputName,
          onSave: _save,
          backLabel: 'Back to Sign',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign PDF')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Draw a signature and place it on one page. Everything stays on your device.',
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.upload_file),
            label: const Text('Select PDF'),
          ),
          if (_sourceName != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_sourceName!, overflow: TextOverflow.ellipsis),
            ),
          const SizedBox(height: 12),
          const Text(
            'Draw your signature',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          SignaturePad(controller: _padController),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _busy || _input == null
                  ? null
                  : () {
                      _padController.clear();
                      setState(() {
                        _signaturePng = null;
                        _result = null;
                        _message = null;
                      });
                    },
              icon: const Icon(Icons.cleaning_services_outlined, size: 18),
              label: const Text('Clear signature'),
            ),
          ),
          if (_pageCount > 0) ...[
            const SizedBox(height: 4),
            DropdownButtonFormField<int>(
              initialValue: _pageIndex,
              decoration: const InputDecoration(
                labelText: 'Target page',
                border: OutlineInputBorder(),
              ),
              items: [
                for (var i = 0; i < _pageCount; i++)
                  DropdownMenuItem(value: i, child: Text('Page ${i + 1}')),
              ],
              onChanged: _busy
                  ? null
                  : (value) => setState(() {
                      _pageIndex = value ?? 0;
                      _result = null;
                    }),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<SignaturePosition>(
              initialValue: _position,
              decoration: const InputDecoration(
                labelText: 'Placement',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: SignaturePosition.bottomRight,
                  child: Text('Bottom right'),
                ),
                DropdownMenuItem(
                  value: SignaturePosition.bottomLeft,
                  child: Text('Bottom left'),
                ),
                DropdownMenuItem(
                  value: SignaturePosition.bottomCenter,
                  child: Text('Bottom center'),
                ),
                DropdownMenuItem(
                  value: SignaturePosition.topRight,
                  child: Text('Top right'),
                ),
                DropdownMenuItem(
                  value: SignaturePosition.topLeft,
                  child: Text('Top left'),
                ),
                DropdownMenuItem(
                  value: SignaturePosition.center,
                  child: Text('Center'),
                ),
              ],
              onChanged: _busy
                  ? null
                  : (value) => setState(() {
                      _position = value ?? SignaturePosition.bottomRight;
                      _result = null;
                    }),
            ),
            Text('Width: ${(_width * 100).round()}% of page'),
            Slider(
              value: _width,
              min: 0.05,
              max: 0.9,
              divisions: 17,
              onChanged: _busy
                  ? null
                  : (v) => setState(() {
                      _width = v;
                      _result = null;
                    }),
            ),
            Text('Height: ${(_height * 100).round()}% of page'),
            Slider(
              value: _height,
              min: 0.03,
              max: 0.5,
              divisions: 47,
              onChanged: _busy
                  ? null
                  : (v) => setState(() {
                      _height = v;
                      _result = null;
                    }),
            ),
            Text('Margin from edge: ${(_margin * 100).round()}%'),
            Slider(
              value: _margin,
              min: 0,
              max: 0.3,
              divisions: 30,
              onChanged: _busy
                  ? null
                  : (v) => setState(() {
                      _margin = v;
                      _result = null;
                    }),
            ),
            Text('Opacity: ${(_opacity * 100).round()}%'),
            Slider(
              value: _opacity,
              min: 0.1,
              max: 1,
              divisions: 18,
              onChanged: _busy
                  ? null
                  : (v) => setState(() {
                      _opacity = v;
                      _result = null;
                    }),
            ),
          ],
          TextField(
            controller: _filename,
            enabled: !_busy,
            decoration: const InputDecoration(labelText: 'Output filename'),
          ),
          const SizedBox(height: 12),
          if (_busy) const LinearProgressIndicator(),
          if (_message != null)
            Text(
              _message!,
              style: TextStyle(
                color: _error ? Colors.red.shade700 : Colors.green.shade800,
              ),
            ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _busy || _input == null ? null : _preview,
            icon: const Icon(Icons.preview_outlined),
            label: const Text('Preview signed PDF'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy || _result == null ? null : _share,
            icon: const Icon(Icons.share_outlined),
            label: const Text('Share signed PDF'),
          ),
        ],
      ),
    );
  }
}

/// Exposed for tests: reads the page count of a PDF without the native channel.
Future<int> signPageCountFromBytes(Uint8List bytes) async {
  await pdfrxFlutterInitialize();
  final document = await PdfDocument.openData(bytes);
  try {
    return document.pages.length;
  } finally {
    await document.dispose();
  }
}
