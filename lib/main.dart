import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'services/pdf_merge_service.dart';
import 'screens/split_pdf_page.dart';
import 'screens/organize_pdf_page.dart';
import 'screens/compress_pdf_page.dart';
import 'screens/rotate_pdf_page.dart';
import 'screens/protect_pdf_page.dart';
import 'screens/unlock_pdf_page.dart';
import 'screens/watermark_pdf_page.dart';
import 'screens/page_numbers_pdf_page.dart';
import 'screens/sign_pdf_page.dart';

const _navy = Color(0xFF0B172A);
const _navyLight = Color(0xFF14243D);
const _green = Color(0xFF45D483);
const _background = Color(0xFFF6F8FA);

void main() {
  runApp(const MyApp());
}

class MyApp extends SickPdfApp {
  const MyApp({super.key});
}

class SickPdfApp extends StatelessWidget {
  const SickPdfApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'sickPDF',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _green),
        scaffoldBackgroundColor: _background,
        useMaterial3: true,
        fontFamily: 'sans',
      ),
      home: const AppShell(),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [const HomePage(), const ToolsPage(), const SettingsPage()];

    return Scaffold(
      body: SafeArea(child: pages[_selectedIndex]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        backgroundColor: Colors.white,
        indicatorColor: _green.withValues(alpha: 0.18),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view),
            label: 'Tools',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
          sliver: SliverToBoxAdapter(child: _Header()),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
          sliver: SliverToBoxAdapter(
            child: Text(
              'Tools',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800, color: _navy),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          sliver: SliverGrid.count(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.25,
            children: const [
              ToolCard(
                icon: Icons.merge_type,
                title: 'Merge PDF',
                accent: true,
              ),
              ToolCard(icon: Icons.call_split, title: 'Split PDF'),
              ToolCard(icon: Icons.compress, title: 'Compress PDF'),
              ToolCard(icon: Icons.reorder, title: 'Organize PDF'),
              ToolCard(icon: Icons.rotate_right, title: 'Rotate PDF'),
              ToolCard(icon: Icons.lock_outline, title: 'Protect PDF'),
              ToolCard(icon: Icons.lock_open_outlined, title: 'Unlock PDF'),
              ToolCard(icon: Icons.water_drop_outlined, title: 'Watermark PDF'),
              ToolCard(icon: Icons.pin_outlined, title: 'Page Numbers PDF'),
              ToolCard(icon: Icons.image_outlined, title: 'Image to PDF'),
              ToolCard(icon: Icons.draw_outlined, title: 'Sign PDF'),
            ],
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 30, 20, 14),
          sliver: SliverToBoxAdapter(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent files',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800, color: _navy),
                ),
                Text(
                  '0 files',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
          sliver: SliverToBoxAdapter(child: _EmptyRecentFiles()),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _navy,
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _green,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.picture_as_pdf, color: _navy, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'sickPDF',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.lock_outline, size: 13, color: _green),
                    SizedBox(width: 5),
                    Text(
                      '100% OFFLINE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'Your files stay yours.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 25,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Simple PDF tools that work privately on your device.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.68),
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class ToolCard extends StatelessWidget {
  const ToolCard({
    super.key,
    required this.icon,
    required this.title,
    this.accent = false,
  });
  final IconData icon;
  final String title;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label:
          title == 'Merge PDF' ||
              title == 'Split PDF' ||
              title == 'Organize PDF' ||
              title == 'Compress PDF' ||
              title == 'Rotate PDF' ||
              title == 'Protect PDF' ||
              title == 'Unlock PDF' ||
              title == 'Watermark PDF' ||
              title == 'Page Numbers PDF' ||
              title == 'Sign PDF'
          ? title
          : '$title, coming soon',
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          if (title == 'Merge PDF') {
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const MergePdfPage()),
            );
            return;
          }
          if (title == 'Split PDF') {
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SplitPdfPage()),
            );
            return;
          }
          if (title == 'Compress PDF') {
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const CompressPdfPage()),
            );
            return;
          }
          if (title == 'Rotate PDF') {
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const RotatePdfPage()),
            );
            return;
          }
          if (title == 'Protect PDF') {
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ProtectPdfPage()),
            );
            return;
          }
          if (title == 'Unlock PDF') {
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const UnlockPdfPage()),
            );
            return;
          }
          if (title == 'Watermark PDF') {
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const WatermarkPdfPage()),
            );
            return;
          }
          if (title == 'Page Numbers PDF') {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const PageNumbersPdfPage(),
              ),
            );
            return;
          }
          if (title == 'Organize PDF') {
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const OrganizePdfPage()),
            );
            return;
          }
          if (title == 'Sign PDF') {
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SignPdfPage()),
            );
            return;
          }
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('$title is coming soon.')));
        },
        child: Ink(
          decoration: BoxDecoration(
            color: accent ? _navyLight : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: accent ? _navyLight : const Color(0xFFE8EDF2),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: accent ? _green : _navy, size: 27),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          color: accent ? Colors.white : _navy,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward,
                      size: 17,
                      color: accent ? _green : Colors.grey.shade500,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyRecentFiles extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8EDF2)),
      ),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: _green.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.folder_open_outlined,
              color: _navy,
              size: 25,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'No recent files',
            style: TextStyle(
              color: _navy,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Your processed PDFs will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class ToolsPage extends StatelessWidget {
  const ToolsPage({super.key});
  @override
  Widget build(BuildContext context) => const Center(
    child: Text(
      'Tools',
      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: _navy),
    ),
  );
}

class MergePdfPage extends StatefulWidget {
  const MergePdfPage({super.key});

  @override
  State<MergePdfPage> createState() => _MergePdfPageState();
}

class _MergePdfPageState extends State<MergePdfPage> {
  final _mergeService = PdfMergeService();
  final List<PlatformFile> _files = [];
  bool _isBusy = false;
  Uint8List? _mergedPdf;
  String? _statusMessage;
  bool _statusIsError = false;

  Future<void> _pickFiles() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: false,
      );
      if (!mounted || result == null) return;
      final validFiles = result.files
          .where((file) => file.path != null)
          .toList();
      setState(() {
        for (final file in validFiles) {
          if (!_files.any((existing) => existing.path == file.path)) {
            _mergedPdf = null;
            _statusMessage = null;
            _files.add(file);
          }
        }
      });
      if (validFiles.isEmpty && result.files.isNotEmpty) {
        _setStatus(
          'The selected files could not be accessed. Please try again.',
        );
      }
    } catch (error) {
      developer.log(
        'File selection failed (${error.runtimeType}).',
        name: 'sickpdf.merge',
      );
      if (mounted) {
        _setStatus('Could not open the file picker. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _mergeFiles() async {
    if (_isBusy) return;
    if (_files.length < 2) {
      _setStatus('Select at least two PDF files before merging.');
      return;
    }

    setState(() {
      _isBusy = true;
      _mergedPdf = null;
      _statusMessage = null;
    });
    final temporaryPath =
        '${Directory.systemTemp.path}${Platform.pathSeparator}sickpdf_${DateTime.now().microsecondsSinceEpoch}.pdf';
    try {
      final bytes = await _mergeService.merge(
        inputPaths: _files.map((file) => file.path!).toList(),
        outputPath: temporaryPath,
      );
      if (!mounted) return;
      setState(() => _mergedPdf = bytes);
      developer.log(
        'Merge completed: ${bytes.length} bytes.',
        name: 'sickpdf.merge',
      );
      _setStatus(
        'PDFs merged successfully',
        secondary: 'Your merged PDF is ready to preview or save.',
        isError: false,
      );
    } catch (error, stackTrace) {
      developer.log(
        'Merge failed.',
        name: 'sickpdf.merge',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        _setStatus(
          'Merge failed: ${error.toString().replaceFirst('Exception: ', '')}',
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _savePdf() async {
    if (_isBusy || _mergedPdf == null || _mergedPdf!.isEmpty) return;
    setState(() => _isBusy = true);
    try {
      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save merged PDF',
        fileName: 'merged_document.pdf',
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        bytes: _mergedPdf,
      );
      if (!mounted) return;
      if (outputPath == null || outputPath.trim().isEmpty) {
        _setStatus('Save cancelled. Your merged PDF is still ready to save.');
        return;
      }
      _setStatus('PDF saved successfully', isError: false);
    } catch (error, stackTrace) {
      developer.log(
        'Save failed.',
        name: 'sickpdf.merge',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        _setStatus(
          'Save failed: ${error.toString().replaceFirst('Exception: ', '')}',
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _setStatus(String message, {String? secondary, bool isError = true}) {
    if (!mounted) return;
    setState(() {
      _statusMessage = secondary == null ? message : '$message\n$secondary';
      _statusIsError = isError;
    });
  }

  Future<void> _openPreview() async {
    final bytes = _mergedPdf;
    if (bytes == null || bytes.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PreviewPdfPage(bytes: bytes, onSave: _savePdf),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Merge PDF'),
        foregroundColor: _navy,
        backgroundColor: _background,
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Combine PDFs privately on your device.',
              style: TextStyle(color: _navy, fontSize: 16),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: _isBusy ? null : _pickFiles,
              icon: const Icon(Icons.add),
              label: const Text('Select PDF files'),
            ),
            const SizedBox(height: 12),
            if (_files.isNotEmpty) ...[
              const Text(
                'Reorder your PDFs before merging',
                style: TextStyle(color: _navy, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              const Text(
                'Drag and drop files to change their order. The merged PDF will follow the order shown below.',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 10),
            ],
            Expanded(
              child: _files.isEmpty
                  ? const Center(
                      child: Text(
                        'No PDFs selected yet.\nChoose two or more files to begin.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ReorderableListView.builder(
                      itemCount: _files.length,
                      onReorderItem: (oldIndex, newIndex) {
                        if (_isBusy || oldIndex == newIndex) return;
                        setState(() {
                          _mergedPdf = null;
                          _statusMessage = null;
                          final file = _files.removeAt(oldIndex);
                          _files.insert(newIndex, file);
                        });
                      },
                      itemBuilder: (context, index) {
                        final file = _files[index];
                        return Card(
                          key: ValueKey(file.path),
                          child: ListTile(
                            leading: const Icon(
                              Icons.picture_as_pdf,
                              color: _navy,
                            ),
                            title: Text(
                              file.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text('File ${index + 1}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.drag_handle,
                                  color: Colors.grey,
                                ),
                                IconButton(
                                  tooltip: 'Remove ${file.name}',
                                  onPressed: _isBusy
                                      ? null
                                      : () => setState(() {
                                          _mergedPdf = null;
                                          _statusMessage = null;
                                          _files.removeAt(index);
                                        }),
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            if (_statusMessage != null) ...[
              _InlineStatus(message: _statusMessage!, isError: _statusIsError),
              const SizedBox(height: 10),
            ],
            if (_mergedPdf != null) ...[
              OutlinedButton.icon(
                onPressed: _isBusy ? null : _openPreview,
                icon: const Icon(Icons.preview_outlined),
                label: const Text('Preview PDF'),
              ),
              const SizedBox(height: 10),
            ],
            FilledButton.icon(
              onPressed: _isBusy || _files.length < 2 ? null : _mergeFiles,
              icon: _isBusy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.merge_type),
              label: Text(_isBusy ? 'Processing...' : 'Merge PDF'),
              style: FilledButton.styleFrom(
                backgroundColor: _navy,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _isBusy || _mergedPdf == null ? null : _savePdf,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save PDF'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineStatus extends StatelessWidget {
  const _InlineStatus({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final lines = message.split('\n');
    final color = isError ? Colors.red.shade700 : Colors.green.shade800;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: (isError ? Colors.red : _green).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (isError ? Colors.red : _green).withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: lines.first,
                    style: TextStyle(color: color, fontWeight: FontWeight.w700),
                  ),
                  if (lines.length > 1)
                    TextSpan(
                      text: '\n${lines.skip(1).join('\n')}',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 13,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PreviewPdfPage extends StatelessWidget {
  const PreviewPdfPage({super.key, required this.bytes, required this.onSave});

  final Uint8List bytes;
  final Future<void> Function() onSave;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Preview PDF'),
        foregroundColor: _navy,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: onSave,
              icon: const Icon(Icons.save_outlined, size: 18),
              label: const Text('Save PDF'),
              style: FilledButton.styleFrom(
                backgroundColor: _navy,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
      body: PdfViewer.data(
        bytes,
        sourceName: 'merged_document.pdf',
        params: const PdfViewerParams(),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back to Merge'),
          ),
        ),
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) => const Center(
    child: Text(
      'Settings',
      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: _navy),
    ),
  );
}
