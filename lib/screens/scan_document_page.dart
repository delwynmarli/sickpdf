import 'dart:developer' as developer;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/pdf_image_to_pdf_service.dart';
import '../services/scan_camera_gateway.dart';
import '../services/scan_document_service.dart';
import '../services/scan_service.dart';
import '../theme/app_theme.dart';
import '../widgets/tool_scaffold.dart';
import 'pdf_output_preview.dart';

/// Captures document pages with the camera and turns them into a PDF.
///
/// Everything happens on the device: the pages are cropped locally, the PDF
/// is built locally, and no scan is ever uploaded anywhere.
class ScanDocumentPage extends StatefulWidget {
  const ScanDocumentPage({super.key, this.service});

  /// Injectable service so widget tests can run without a camera.
  final ScanDocumentService? service;

  @override
  State<ScanDocumentPage> createState() => _ScanDocumentPageState();
}

class _ScanDocumentPageState extends State<ScanDocumentPage>
    with WidgetsBindingObserver {
  late final _service = widget.service ?? ScanDocumentService();
  final _pages = ScanPageList();
  final _filename = TextEditingController(text: 'scan.pdf');

  ImagePageSize _pageSize = ImagePageSize.a4;
  ImageMargin _margin = ImageMargin.small;

  Uint8List? _result;
  String? _message;
  bool _error = false;

  /// True while the camera is being opened or a photo is being taken.
  bool _capturing = false;

  /// True while the PDF is being built.
  bool _exporting = false;

  /// True while a page is being cropped.
  bool _cropping = false;

  /// True when the camera has been opened successfully.
  bool _cameraOpen = false;

  /// True when the camera could not be opened and the user should be told
  /// why.
  bool _cameraFailed = false;

  /// True when the camera was released because the app went to the
  /// background, so it should be reopened when the app comes back.
  ///
  /// The `camera` plugin does not handle lifecycle transitions itself (its
  /// README states this explicitly), and the native crop editor pauses the
  /// activity while it is open. Without this, returning from the crop editor
  /// would leave the preview dead.
  bool _restoreCameraOnResume = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _filename.dispose();
    // The camera holds a native resource, so it is released as soon as the
    // screen goes away.
    _service.closeCamera();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _releaseCameraForBackground();
      case AppLifecycleState.resumed:
        _restoreCameraAfterResume();
    }
  }

  /// Releases the camera when the app leaves the foreground.
  ///
  /// The controller is disposed rather than paused so another app (including
  /// the crop editor) can take the camera, and so no native resource is held
  /// while sickPDF is not visible.
  void _releaseCameraForBackground() {
    if (!_cameraOpen) return;
    _cameraOpen = false;
    _restoreCameraOnResume = true;
    if (mounted) setState(() {});
    _service.closeCamera();
  }

  /// Reopens the camera after the app returns to the foreground.
  ///
  /// This deliberately does not reuse [_openCamera], because that path owns
  /// the `_capturing` busy flag and would clear it while a capture or a crop
  /// is still in flight.
  Future<void> _restoreCameraAfterResume() async {
    if (!_restoreCameraOnResume) return;
    _restoreCameraOnResume = false;
    if (!mounted || _cameraOpen) return;
    try {
      await _service.openCamera();
      if (!mounted) return;
      setState(() {
        _cameraOpen = true;
        _cameraFailed = false;
      });
    } on ScanCameraException catch (exception) {
      if (!mounted) return;
      setState(() {
        _cameraOpen = false;
        _cameraFailed = true;
      });
      _status(exception.message, error: true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _cameraOpen = false;
        _cameraFailed = true;
      });
      _log('Camera resume', error);
      _status(
        'The camera could not be restarted. Tap Open camera to try again.',
        error: true,
      );
    }
  }

  /// Any edit invalidates the previously generated PDF so it is never stale.
  void _edit(void Function() action) {
    if (_exporting) return;
    setState(() {
      action();
      _result = null;
      _message = null;
    });
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
      name: 'sickpdf.scan',
    );
  }

  Future<void> _openCamera() async {
    if (_capturing) return;
    setState(() {
      _capturing = true;
      _cameraFailed = false;
    });
    try {
      await _service.openCamera();
      if (!mounted) return;
      setState(() => _cameraOpen = true);
    } on ScanCameraException catch (exception) {
      if (!mounted) return;
      setState(() {
        _cameraOpen = false;
        _cameraFailed = true;
      });
      _status(exception.message, error: true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _cameraOpen = false;
        _cameraFailed = true;
      });
      _log('Camera start', error);
      _status(
        'The camera could not be started. Close other apps that use it and '
        'try again.',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _capture() async {
    if (_capturing || _exporting) return;
    setState(() => _capturing = true);
    try {
      final result = await _service.capturePage();
      if (!mounted) return;
      setState(() {
        _pages.add(result.page);
        _result = null;
        _message = null;
      });
      if (result.needsManualCrop) {
        // The edges could not be found. Offer the manual crop editor so the
        // user can still trim the page.
        await _cropPage(result.page);
      } else {
        _status(
          'Page ${_pages.length} captured. Add more pages or export the PDF.',
        );
      }
    } on ScanCameraException catch (exception) {
      if (!mounted) return;
      _status(exception.message, error: true);
    } on ScanException catch (exception) {
      if (!mounted) return;
      _status(exception.message, error: true);
    } catch (error) {
      if (!mounted) return;
      _log('Capture', error);
      _status('The page could not be captured. Try again.', error: true);
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  /// Opens the crop editor for the page at [index].
  ///
  /// A cancelled crop leaves the page untouched.
  Future<void> _cropPage(ScanPage page) async {
    if (_cropping || _exporting) return;
    setState(() => _cropping = true);
    try {
      final cropped = await _service.cropPage(page);
      if (!mounted) return;
      if (cropped == null) {
        _status('Crop cancelled. The page was left as it was.');
        return;
      }
      final index = _pages.pages.indexOf(page);
      _edit(() {
        if (index >= 0) {
          _pages.replaceAt(index, cropped);
        }
      });
      _status('Page cropped.');
    } on ScanException catch (exception) {
      if (!mounted) return;
      _status(exception.message, error: true);
    } catch (error) {
      if (!mounted) return;
      _log('Crop', error);
      _status('The page could not be cropped. Try again.', error: true);
    } finally {
      if (mounted) setState(() => _cropping = false);
    }
  }

  /// Removes the page at [index].
  void _removePage(int index) {
    if (_exporting) return;
    setState(() {
      _pages.removeAt(index);
      _result = null;
      _message = null;
    });
    _status('Page removed.');
  }

  /// Retakes the page at [index]: the old page is dropped and a new capture
  /// replaces it in the same position.
  Future<void> _retakePage(int index) async {
    if (_capturing || _exporting) return;
    setState(() => _capturing = true);
    try {
      final result = await _service.capturePage();
      if (!mounted) return;
      setState(() {
        _pages.replaceAt(index, result.page);
        _result = null;
        _message = null;
      });
      if (result.needsManualCrop) {
        await _cropPage(result.page);
      } else {
        _status('Page ${index + 1} retaken.');
      }
    } on ScanCameraException catch (exception) {
      if (!mounted) return;
      _status(exception.message, error: true);
    } on ScanException catch (exception) {
      if (!mounted) return;
      _status(exception.message, error: true);
    } catch (error) {
      if (!mounted) return;
      _log('Retake', error);
      _status('The page could not be retaken. Try again.', error: true);
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  /// Builds the PDF. Returns the bytes, or null when the export failed.
  Future<Uint8List?> _generate() async {
    if (_result != null) return _result;
    if (_pages.isEmpty) {
      _status('Capture at least one page before exporting.', error: true);
      return null;
    }
    if (_exporting) return null;
    setState(() {
      _exporting = true;
      _message = null;
    });
    try {
      final bytes = await _service.exportPdf(
        _pages.pages,
        size: _pageSize,
        margin: _margin,
      );
      if (!mounted) return null;
      setState(() => _result = bytes);
      _status(
        'PDF created from ${_pages.length} page'
        '${_pages.length == 1 ? '' : 's'}. Preview or save it.',
      );
      return bytes;
    } on ScanException catch (exception) {
      if (!mounted) return null;
      _status(exception.message, error: true);
      return null;
    } catch (error) {
      if (!mounted) return null;
      _log('Export', error);
      _status(
        'Could not create the PDF from these pages. Try removing a page and '
        'try again.',
        error: true,
      );
      return null;
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  String get _outputName {
    var name = _filename.text.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (name.isEmpty) name = 'scan.pdf';
    return name.toLowerCase().endsWith('.pdf') ? name : '$name.pdf';
  }

  Future<String> _save() async {
    if (_exporting) return 'Please wait for the current operation.';
    final bytes = await _generate();
    if (bytes == null || !mounted) {
      // The export already reported why it failed. Do not replace that
      // specific reason with a generic one.
      return _message ?? 'Could not create the PDF.';
    }
    setState(() => _exporting = true);
    String message;
    var failed = false;
    try {
      final destination = await FilePicker.platform.saveFile(
        dialogTitle: 'Save scanned PDF',
        fileName: _outputName,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        bytes: bytes,
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
      if (mounted) setState(() => _exporting = false);
    }
    _status(message, error: failed);
    return message;
  }

  Future<void> _share() async {
    if (_exporting) return;
    final bytes = await _generate();
    if (bytes == null || !mounted) return;
    try {
      await const MethodChannel('sickpdf/share').invokeMethod<void>('share', {
        'bytes': bytes,
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
    if (_exporting) return;
    final bytes = await _generate();
    if (bytes == null || !mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PdfOutputPreview(
          bytes: bytes,
          name: _outputName,
          onSave: _save,
          backLabel: 'Back to Scan Document',
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
    final busy = _capturing || _exporting || _cropping;
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Document')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screen),
        children: [
          const ToolIntro(
            text:
                'Scan pages with the camera and save them as one PDF. Photos '
                'stay on this device and are never uploaded.',
          ),
          if (_cameraOpen)
            _CameraView(
              preview: _service.camera.preview,
              aspectRatio: _service.camera.previewAspectRatio,
              capturing: _capturing,
              onCapture: _capture,
            )
          else
            ToolEmptyState(
              icon: Icons.photo_camera_outlined,
              title: _cameraFailed
                  ? 'The camera is not available'
                  : 'Open the camera to start scanning',
              message: _cameraFailed
                  ? 'Check the camera permission in the app settings, then '
                      'try again.'
                  : 'sickPDF asks for the camera only while you are scanning.',
              onSelect: busy ? null : _openCamera,
              selectLabel: 'Open camera',
            ),
          const SizedBox(height: AppSpacing.md),
          if (_pages.isEmpty)
            const Text(
              'No pages captured yet.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            )
          else ...[
            Text(
              '${_pages.length} page${_pages.length == 1 ? '' : 's'} • '
              'one page per sheet, in the order below',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Drag the handle or use the arrows to reorder. Remove a page '
              'or retake it before exporting.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 8),
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: _pages.length,
              onReorderItem: (from, to) => _edit(() => _pages.move(from, to)),
              itemBuilder: (context, index) {
                final page = _pages.pages[index];
                return Card(
                  key: ValueKey('scan_page_$index'),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        _ScanThumbnail(bytes: page.bytes),
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
                                '${page.width} × ${page.height} px',
                                style: const TextStyle(fontSize: 12),
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    tooltip: 'Move page ${index + 1} up',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: busy || index == 0
                                        ? null
                                        : () => _edit(
                                            () => _pages.move(
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
                                    tooltip: 'Move page ${index + 1} down',
                                    visualDensity: VisualDensity.compact,
                                    onPressed:
                                        busy || index == _pages.length - 1
                                            ? null
                                            : () => _edit(
                                                () => _pages.move(
                                                  index,
                                                  index + 1,
                                                ),
                                              ),
                                    icon: const Icon(
                                      Icons.arrow_downward,
                                      size: 20,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Crop page ${index + 1}',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: busy
                                        ? null
                                        : () => _cropPage(page),
                                    icon: const Icon(Icons.crop, size: 20),
                                  ),
                                  IconButton(
                                    tooltip: 'Retake page ${index + 1}',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: busy
                                        ? null
                                        : () => _retakePage(index),
                                    icon: const Icon(
                                      Icons.refresh,
                                      size: 20,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove page ${index + 1}',
                          onPressed: busy ? null : () => _removePage(index),
                          icon: const Icon(Icons.close),
                        ),
                        ReorderableDragStartListener(
                          index: index,
                          enabled: !busy,
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
          ],
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<ImagePageSize>(
            initialValue: _pageSize,
            // The dropdown fills the field width so a long label can never
            // overflow on a narrow screen.
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Page size',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final size in ImagePageSize.values)
                DropdownMenuItem(value: size, child: Text(_pageSizeLabel(size))),
            ],
            onChanged: busy
                ? null
                : (value) => _edit(() => _pageSize = value ?? _pageSize),
          ),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<ImageMargin>(
            initialValue: _margin,
            isExpanded: true,
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
            onChanged: busy
                ? null
                : (value) => _edit(() => _margin = value ?? _margin),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _filename,
            enabled: !busy,
            decoration: const InputDecoration(
              labelText: 'Output filename',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() => _result = null),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            // The action stays disabled while a run is active, so a second
            // submission can never start.
            onPressed: busy || _pages.isEmpty ? null : _preview,
            icon: _exporting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.preview_outlined),
            label: Text(_exporting ? 'Working…' : 'Preview PDF'),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: busy || _pages.isEmpty ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save PDF'),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: busy || _pages.isEmpty ? null : _share,
            icon: const Icon(Icons.share_outlined),
            label: const Text('Share PDF'),
          ),
          if (busy) ...[
            const SizedBox(height: AppSpacing.md),
            const LinearProgressIndicator(),
          ],
          if (_message != null) ...[
            const SizedBox(height: AppSpacing.md),
            ToolStatus(message: _message!, isError: _error),
          ],
        ],
      ),
    );
  }
}

/// The live camera preview with its capture button.
class _CameraView extends StatelessWidget {
  const _CameraView({
    required this.preview,
    required this.capturing,
    required this.onCapture,
    this.aspectRatio,
  });

  final Widget? preview;
  final bool capturing;
  final VoidCallback onCapture;

  /// The camera's own preview ratio, or `null` when it is not known yet.
  final double? aspectRatio;

  /// Frame ratio used until the camera reports its own.
  ///
  /// Portrait sensor output is usually 3:4, so this is a reasonable neutral
  /// placeholder. It is only ever shown before the first real ratio arrives.
  static const double _fallbackAspectRatio = 3 / 4;

  /// Ratio to lay the frame out with.
  ///
  /// The camera reports the real sensor ratio, so the frame matches what the
  /// sensor produces instead of stretching it. Implausible values are
  /// ignored rather than allowed to collapse the layout.
  double get _effectiveAspectRatio {
    final ratio = aspectRatio;
    if (ratio == null || !ratio.isFinite || ratio <= 0) {
      return _fallbackAspectRatio;
    }
    // Guard against absurd values that would make the frame unusable.
    if (ratio < 0.2 || ratio > 5) return _fallbackAspectRatio;
    return ratio;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: AspectRatio(
            aspectRatio: _effectiveAspectRatio,
            child: preview ??
                Container(
                  color: AppColors.surfaceMuted,
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.photo_camera_outlined,
                    size: 34,
                    color: Colors.grey,
                  ),
                ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        FilledButton.icon(
          onPressed: capturing ? null : onCapture,
          icon: capturing
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.photo_camera_outlined),
          label: Text(capturing ? 'Capturing…' : 'Capture page'),
        ),
      ],
    );
  }
}

/// A small preview of one captured page.
class _ScanThumbnail extends StatelessWidget {
  const _ScanThumbnail({required this.bytes});

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
