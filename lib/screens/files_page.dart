import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../services/document_library.dart';
import '../services/document_share.dart';
import '../services/pdf_open_service.dart';
import '../theme/app_theme.dart';
import '../widgets/locked_pdf_dialog.dart';

/// Files tab: the sickPDF document library.
///
/// Documents are copies that sickPDF itself created or imported into its own
/// app-private storage, so the list survives closing the screen, force-stopping
/// the app, and rebooting the device. It never scans device storage, and
/// removing an entry never touches a file the user picked from elsewhere.
class FilesPage extends StatefulWidget {
  const FilesPage({
    super.key,
    this.library,
    this.share,
    this.pickPath,
    this.openService,
    this.viewerBuilder,
    bool? active,
    // ignore: prefer_initializing_formals
  }) : _active = active;

  final bool? _active;

  /// Whether this tab is visible. Defaults to visible.
  bool get active => _active ?? true;

  /// Injectable for tests; production uses the default persistent library.
  final DocumentLibraryApi? library;

  /// Injectable share implementation for tests.
  final DocumentShare? share;

  /// Injectable document-open/password check for tests.
  final PdfOpenApi? openService;

  /// Builds the viewer body for a document and the password to use (empty
  /// when the document is not locked).
  ///
  /// Injectable so widget tests can prove which password reached the viewer
  /// without depending on native PDF rendering. Production leaves it null and
  /// uses [`PdfViewer.file`].
  final Widget Function(LibraryDocument doc, String password)? viewerBuilder;

  /// Injectable file selection for tests. Returns the picked path, or `null`
  /// when the user cancelled.
  final Future<String?> Function()? pickPath;

  @override
  State<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends State<FilesPage> {
  late DocumentLibraryApi _library;
  late PdfOpenApi _openService;
  List<LibraryDocument>? _docs;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _library = widget.library ?? DocumentLibrary();
    _openService = widget.openService ?? const PdfOpenService();
    _refresh();
  }

  @override
  void didUpdateWidget(FilesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.library != null && widget.library != oldWidget.library) {
      _library = widget.library!;
    }
    if (widget.openService != null &&
        widget.openService != oldWidget.openService) {
      _openService = widget.openService!;
    }
    if (widget.active && !oldWidget.active) _refresh();
  }

  Future<void> _refresh() async {
    final docs = await _library.list();
    if (!mounted) return;
    setState(() => _docs = docs);
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<String?> _defaultPickPath() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: false,
    );
    return result?.files.single.path;
  }

  Future<void> _importFile() async {
    if (_busy) return;
    setState(() => _busy = true);
    var message = 'Import cancelled.';
    try {
      final path = await (widget.pickPath ?? _defaultPickPath)();
      if (path == null) {
        message = 'Import cancelled.';
      } else {
        final doc = await _library.addFromPath(path);
        message = 'Added "${doc.fileName}" to Files.';
      }
    } on LibraryException catch (error) {
      message = error.message;
    } catch (_) {
      message = 'Could not import the file. Please try again.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _refresh();
    _notify(message);
  }

  /// Opens a library document, asking for a password only when the document
  /// actually requires one.
  ///
  /// Nothing is written here: a password is used to read the existing library
  /// file and is discarded when the viewer closes. The library copy, its
  /// metadata, and the user's original file are all left untouched.
  Future<void> _open(LibraryDocument doc) async {
    if (!await _library.isAvailable(doc)) {
      await _handleMissing(doc);
      return;
    }
    if (!mounted) return;

    var password = '';
    try {
      final needsPassword = await _openService.requiresPassword(doc.storedPath);
      if (!mounted) return;
      if (needsPassword) {
        final entered = await showLockedPdfDialog(
          context: context,
          fileName: doc.fileName,
          verify: (candidate) =>
              _openService.verifyPassword(doc.storedPath, candidate),
        );
        // Cancelling closes the flow and returns to Files with no viewer and
        // no side effects.
        if (entered == null) return;
        password = entered;
      }
    } on PdfOpenException catch (error) {
      _notify(error.message);
      return;
    } catch (_) {
      _notify('Could not open this document. It may be damaged or unsupported.');
      return;
    }
    if (!mounted) return;
    await _showViewer(doc, password);
  }

  Future<void> _showViewer(LibraryDocument doc, String password) async {
    // A single-shot provider: pdfrx retries while it receives an answer, so
    // answering once with the verified password opens the document without
    // risking a retry loop on a document that changes under us.
    final provider = password.isEmpty ? null : pdfPasswordProviderFor(password);
    final custom = widget.viewerBuilder;
    final body = custom != null
        ? custom(doc, password)
        : PdfViewer.file(
            doc.storedPath,
            passwordProvider: provider,
            // The password was already verified, so the extra empty-password
            // attempt is skipped.
            firstAttemptByEmptyPassword: password.isEmpty,
            params: PdfViewerParams(
              errorBannerBuilder:
                  (context, error, stackTrace, documentRef) => const Center(
                    child: Text(
                      'This document could not be opened. It may have been '
                      'removed by the system.',
                      textAlign: TextAlign.center,
                    ),
                  ),
            ),
          );
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(doc.fileName)),
          body: body,
        ),
      ),
    );
  }

  /// A document whose stored copy disappeared is reported, never silently
  /// deleted from the library.
  Future<void> _handleMissing(LibraryDocument doc) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Document not found'),
        content: Text(
          '"${doc.fileName}" is no longer in sickPDF storage. It may have '
          'been removed by the system. You can remove the entry from Files.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove entry'),
          ),
        ],
      ),
    );
    if (remove != true) return;
    await _library.remove(doc);
    await _refresh();
    _notify('"${doc.fileName}" removed from Files.');
  }

  Future<void> _rename(LibraryDocument doc) async {
    final requested = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(currentName: doc.fileName),
    );
    if (requested == null || requested.trim().isEmpty) return;
    setState(() => _busy = true);
    var message = 'Rename cancelled.';
    try {
      final renamed = await _library.rename(doc, requested);
      message = renamed.fileName == doc.fileName
          ? 'The name did not change.'
          : 'Renamed to "${renamed.fileName}".';
    } on LibraryException catch (error) {
      message = error.message;
    } catch (_) {
      message = 'Could not rename this document.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _refresh();
    _notify(message);
  }

  Future<void> _share(LibraryDocument doc) async {
    setState(() => _busy = true);
    var message = 'Shared "${doc.fileName}".';
    try {
      final bytes = await _library.readBytes(doc);
      await (widget.share ?? shareDocumentBytes)(bytes, doc.fileName);
      message = 'Opening share options for "${doc.fileName}".';
    } on LibraryException catch (error) {
      message = error.message;
    } on DocumentShareException catch (error) {
      message = error.message;
    } catch (_) {
      message = 'Could not share this document.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    _notify(message);
  }

  Future<void> _delete(LibraryDocument doc) async {
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove document?'),
        content: Text(
          '"${doc.fileName}" will be removed from the sickPDF library. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _library.remove(doc);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _refresh();
    _notify('"${doc.fileName}" removed.');
  }

  String _formatSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
    return '$bytes B';
  }

  String _formatDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final docs = _docs;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Files'),
        actions: [
          IconButton(
            tooltip: 'Import a PDF into Files',
            onPressed: _busy ? null : _importFile,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: _busy && docs == null
          ? const Center(child: CircularProgressIndicator())
          : docs == null || docs.isEmpty
          ? _FilesEmptyState(onImport: _busy ? null : _importFile)
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screen,
                  AppSpacing.sm,
                  AppSpacing.screen,
                  AppSpacing.xxl,
                ),
                itemCount: docs.length + 1,
                separatorBuilder: (_, index) => index == 0
                    ? const SizedBox.shrink()
                    : Divider(height: 1, color: theme.colorScheme.outlineVariant),
                itemBuilder: (context, index) {
                  if (index == 0) return const _FilesPrivacyNote();
                  final doc = docs[index - 1];
                  return _FilesRow(
                    doc: doc,
                    busy: _busy,
                    detail:
                        '${_formatSize(doc.fileSize)} · '
                        '${_formatDate(doc.addedAt)}',
                    onOpen: () => _open(doc),
                    onRename: () => _rename(doc),
                    onShare: () => _share(doc),
                    onDelete: () => _delete(doc),
                  );
                },
              ),
            ),
    );
  }
}

/// One library document with its actions.
class _FilesRow extends StatelessWidget {
  const _FilesRow({
    required this.doc,
    required this.busy,
    required this.detail,
    required this.onOpen,
    required this.onRename,
    required this.onShare,
    required this.onDelete,
  });

  final LibraryDocument doc;
  final bool busy;
  final String detail;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: 'Open ${doc.fileName}',
      child: InkWell(
        onTap: busy ? null : onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xxs,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            children: [
              Icon(
                Icons.picture_as_pdf_outlined,
                size: 22,
                color: theme.colorScheme.onSurface,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      detail,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_FilesAction>(
                tooltip: 'Actions for ${doc.fileName}',
                enabled: !busy,
                onSelected: (action) {
                  switch (action) {
                    case _FilesAction.rename:
                      onRename();
                    case _FilesAction.share:
                      onShare();
                    case _FilesAction.delete:
                      onDelete();
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _FilesAction.rename,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.drive_file_rename_outline),
                      title: Text('Rename'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _FilesAction.share,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.share_outlined),
                      title: Text('Share'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _FilesAction.delete,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_outline),
                      title: Text('Remove'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _FilesAction { rename, share, delete }

/// Asks for a new document name.
///
/// The dialog owns its [TextEditingController] so the controller outlives the
/// dialog's closing animation; disposing it from the caller would leave the
/// still-animating [TextField] pointing at a disposed controller.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.currentName});

  final String currentName;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final name = widget.currentName;
    _controller = TextEditingController(
      text: name.toLowerCase().endsWith('.pdf')
          ? name.substring(0, name.length - 4)
          : name,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename document'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      textCapitalization: TextCapitalization.sentences,
      decoration: const InputDecoration(
        labelText: 'Name',
        suffixText: '.pdf',
      ),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      TextButton(onPressed: _submit, child: const Text('Rename')),
    ],
  );
}

/// States where documents live, so the storage model is not a surprise.
class _FilesPrivacyNote extends StatelessWidget {
  const _FilesPrivacyNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.lock_outline,
            size: 14,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.xxs),
          Expanded(
            child: Text(
              'Stored only in sickPDF\'s private app storage. Uninstalling '
              'the app removes them.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilesEmptyState extends StatelessWidget {
  const _FilesEmptyState({required this.onImport});

  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.folder_open_outlined,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'No documents yet',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Import a PDF, or add a result from any sickPDF tool with '
              '"Add to Files". Documents stay in this list after you close the '
              'app.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.add),
              label: const Text('Import a PDF'),
            ),
          ],
        ),
      ),
    );
  }
}

