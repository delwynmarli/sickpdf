import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/pdf_watermark_service.dart';
import '../services/pdf_split_service.dart';
import '../theme/app_theme.dart';
import '../widgets/tool_scaffold.dart';
import 'pdf_output_preview.dart';

class WatermarkPdfPage extends StatefulWidget {
  const WatermarkPdfPage({super.key, this.service});
  final PdfWatermarkService? service;

  @override
  State<WatermarkPdfPage> createState() => _WatermarkPdfPageState();
}

class _WatermarkPdfPageState extends State<WatermarkPdfPage> {
  late final _service = widget.service ?? PdfWatermarkService();
  final _text = TextEditingController();
  final _pagesText = TextEditingController();
  final _filename = TextEditingController(text: 'document_watermarked.pdf');
  Uint8List? _input;
  Uint8List? _result;
  String? _sourceName;
  int _pageCount = 0;
  String? _message;
  bool _error = false;
  bool _busy = false;
  double _size = 36;
  double _opacity = .25;
  WatermarkPosition _position = WatermarkPosition.center;
  WatermarkRotation _rotation = WatermarkRotation.diagonal;
  bool _allPages = true;
  final _pages = <int>{};

  @override
  void dispose() {
    _text.dispose();
    _pagesText.dispose();
    _filename.dispose();
    _input = null;
    _result = null;
    super.dispose();
  }

  void _status(String value, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _message = value;
      _error = error;
    });
  }

  Future<void> _pick() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final selection = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );
      if (!mounted) return;
      if (selection == null) {
        _status('Selection cancelled.');
        return;
      }
      final file = selection.files.single;
      if (file.bytes == null || file.bytes!.isEmpty) {
        throw const FormatException('The selected PDF cannot be accessed.');
      }
      var count = 0;
      if (file.path != null) {
        try {
          count = await PdfSplitService().pageCount(file.path!);
        } on FormatException {
          count = 0;
        }
      }
      if (!mounted) return;
      setState(() {
        _input = file.bytes;
        _sourceName = file.name;
        _pageCount = count;
        _filename.text =
            '${file.name.replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '')}_watermarked.pdf';
        _result = null;
        _message = null;
        _pages.clear();
        _pagesText.clear();
      });
    } catch (error) {
      if (mounted) {
        _status(
          pdfSplitLoadError(error).replaceAll('to split it', 'to watermark it'),
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  PdfWatermarkOptions get _options => PdfWatermarkOptions(
    text: _text.text,
    fontSize: _size,
    opacity: _opacity,
    position: _position,
    rotation: _rotation,
    pages: _allPages ? null : _pages,
  );

  Future<bool> _generate() async {
    if (_input == null) {
      _status('Select one PDF first.', error: true);
      return false;
    }
    if (_result != null) return true;
    final validation = validateWatermarkOptions(_options, _pageCount);
    if (validation != null &&
        validation != 'Select at least one valid page.') {
      _status(validation, error: true);
      return false;
    }
    if (!_allPages && _pages.isEmpty) {
      _status('Select at least one page.', error: true);
      return false;
    }
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final output = await _service.apply(_input!, _options);
      if (!mounted) return false;
      setState(() => _result = output);
      return true;
    } on PdfWatermarkException catch (error) {
      _status(error.message, error: true);
      return false;
    } catch (error) {
      _status(
        'Could not add the watermark. Try an unlocked, undamaged PDF.',
        error: true,
      );
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _outputName {
    var name = _filename.text.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (name.isEmpty) name = 'document_watermarked.pdf';
    return name.toLowerCase().endsWith('.pdf') ? name : '$name.pdf';
  }

  Future<String> _save() async {
    if (_busy) return 'Please wait for the current operation.';
    if (!await _generate() || !mounted) {
      return 'Could not generate the PDF.';
    }
    setState(() => _busy = true);
    var message = '';
    var failed = false;
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save watermarked PDF as a new file',
        fileName: _outputName,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        bytes: _result!,
      );
      message = path == null || path.trim().isEmpty
          ? 'Save cancelled. Your PDF is still ready to save.'
          : 'PDF saved successfully.';
    } catch (_) {
      message = 'Save failed. Check the destination and available space.';
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
          backLabel: 'Back to Watermark',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasFile = _input != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Watermark PDF')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screen),
        children: [
          const ToolIntro(
            text:
                'Add a permanent text watermark. The original file stays unchanged.',
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.upload_file),
            label: const Text('Select PDF'),
          ),
          const SizedBox(height: AppSpacing.md),
          if (!hasFile)
            ToolEmptyState(
              icon: Icons.water_drop_outlined,
              title: 'Select a PDF to watermark',
              message: 'Then type the watermark text and choose a style.',
              onSelect: _busy ? null : _pick,
            )
          else ...[
            SelectedFileCard(
              name: _sourceName!,
              detail: _pageCount > 0 ? '$_pageCount pages' : null,
              onReplace: _busy ? null : _pick,
            ),
            const SizedBox(height: AppSpacing.lg),
            ToolSection(
              title: 'Watermark',
              subtitle: 'Required. Keep it short for best results.',
              child: TextField(
                controller: _text,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'Watermark text',
                  hintText: 'e.g. CONFIDENTIAL',
                ),
                onChanged: (_) => setState(() => _result = null),
              ),
            ),
            ToolSection(
              title: 'Style',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _LabeledSlider(
                    label: 'Text size',
                    value: '${_size.round()} pt',
                    slider: Slider(
                      value: _size,
                      min: 8,
                      max: 144,
                      divisions: 34,
                      semanticFormatterCallback: (v) => '${v.round()} points',
                      onChanged: _busy
                          ? null
                          : (v) => setState(() {
                              _size = v;
                              _result = null;
                            }),
                    ),
                  ),
                  _LabeledSlider(
                    label: 'Opacity',
                    value: '${(_opacity * 100).round()}%',
                    slider: Slider(
                      value: _opacity,
                      min: .05,
                      max: 1,
                      divisions: 19,
                      semanticFormatterCallback: (v) =>
                          '${(v * 100).round()} percent',
                      onChanged: _busy
                          ? null
                          : (v) => setState(() {
                              _opacity = v;
                              _result = null;
                            }),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  DropdownButtonFormField<WatermarkPosition>(
                    initialValue: _position,
                    decoration: const InputDecoration(labelText: 'Position'),
                    items: const [
                      DropdownMenuItem(
                        value: WatermarkPosition.center,
                        child: Text('Center'),
                      ),
                      DropdownMenuItem(
                        value: WatermarkPosition.top,
                        child: Text('Top'),
                      ),
                      DropdownMenuItem(
                        value: WatermarkPosition.bottom,
                        child: Text('Bottom'),
                      ),
                    ],
                    onChanged: _busy
                        ? null
                        : (v) => setState(() {
                            _position = v!;
                            _result = null;
                          }),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  DropdownButtonFormField<WatermarkRotation>(
                    initialValue: _rotation,
                    decoration: const InputDecoration(labelText: 'Rotation'),
                    items: const [
                      DropdownMenuItem(
                        value: WatermarkRotation.horizontal,
                        child: Text('Horizontal'),
                      ),
                      DropdownMenuItem(
                        value: WatermarkRotation.diagonal,
                        child: Text('Diagonal'),
                      ),
                    ],
                    onChanged: _busy
                        ? null
                        : (v) => setState(() {
                            _rotation = v!;
                            _result = null;
                          }),
                  ),
                ],
              ),
            ),
            ToolSection(
              title: 'Pages',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Apply to all pages'),
                    value: _allPages,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() {
                            _allPages = v;
                            _result = null;
                          }),
                  ),
                  if (!_allPages)
                    TextField(
                      controller: _pagesText,
                      enabled: !_busy,
                      keyboardType: TextInputType.text,
                      decoration: const InputDecoration(
                        labelText: 'Pages',
                        helperText: 'Comma separated, e.g. 1, 3, 5',
                      ),
                      onChanged: (value) {
                        final parsed = value
                            .split(',')
                            .map((s) => int.tryParse(s.trim()))
                            .whereType<int>()
                            .where((p) => p > 0 && (_pageCount == 0 || p <= _pageCount))
                            .map((p) => p - 1)
                            .toSet();
                        setState(() {
                          _pages
                            ..clear()
                            ..addAll(parsed);
                          _result = null;
                        });
                      },
                    ),
                ],
              ),
            ),
            TextField(
              controller: _filename,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: 'Output filename'),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          if (_busy) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: AppSpacing.md),
          ],
          if (_message != null) ...[
            ToolStatus(message: _message!, isError: _error),
            const SizedBox(height: AppSpacing.md),
          ],
          FilledButton.icon(
            onPressed: _busy || !hasFile ? null : _preview,
            icon: const Icon(Icons.preview_outlined),
            label: const Text('Preview & Save'),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'The watermark is not yet applied until you preview or save.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.label,
    required this.value,
    required this.slider,
  });

  final String label;
  final String value;
  final Widget slider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: theme.textTheme.bodyMedium),
            Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        slider,
      ],
    );
  }
}
