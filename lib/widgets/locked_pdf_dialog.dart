import 'package:flutter/material.dart';

import '../services/pdf_open_service.dart';

/// Asks for the password of a locked PDF so it can be read in sickPDF.
///
/// This only unlocks the document for viewing. It never writes a copy, never
/// modifies the library file, and is not the Unlock PDF tool.
///
/// The password exists only in this dialog's controller and in the return
/// value. It is not stored in library metadata, not logged, and not copied to
/// the clipboard. [verify] is expected to throw [PdfOpenException] with
/// `wrongPassword` set when the password is rejected; any other
/// [PdfOpenException] is shown as a terminal error and the dialog stays open
/// so the user can cancel deliberately.
class LockedPdfDialog extends StatefulWidget {
  const LockedPdfDialog({
    super.key,
    required this.fileName,
    required this.verify,
  });

  /// Display name of the document, shown so the user knows what they are
  /// unlocking.
  final String fileName;

  /// Called with the typed password. Must complete normally when it is
  /// accepted, or throw [PdfOpenException] when it is not.
  final Future<void> Function(String password) verify;

  @override
  State<LockedPdfDialog> createState() => _LockedPdfDialogState();
}

class _LockedPdfDialogState extends State<LockedPdfDialog> {
  final _controller = TextEditingController();
  bool _hidden = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    // Drop the secret from memory as soon as the dialog goes away.
    _controller.clear();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final password = _controller.text;
    if (password.isEmpty) {
      setState(() => _error = 'Enter the PDF password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.verify(password);
      if (!mounted) return;
      Navigator.of(context).pop(password);
    } on PdfOpenException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
      });
      // A rejected password is worth another try, so the field is selected.
      if (error.wrongPassword) {
        _controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _controller.text.length,
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not open this document. It may be damaged.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Password required'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '"${widget.fileName}" is protected by a password. Enter it to '
            'read the document.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            enabled: !_busy,
            obscureText: _hidden,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            keyboardType: TextInputType.visiblePassword,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'PDF password',
              suffixIcon: IconButton(
                tooltip: _hidden ? 'Show password' : 'Hide password',
                onPressed: _busy
                    ? null
                    : () => setState(() => _hidden = !_hidden),
                icon: Icon(
                  _hidden ? Icons.visibility : Icons.visibility_off,
                ),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 18,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'The document is opened as it is. Nothing is saved or uploaded, '
            'and the password is not stored.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: const Text('Open'),
        ),
      ],
    );
  }
}

/// Shows [LockedPdfDialog] and returns the accepted password, or `null` when
/// the user cancelled.
Future<String?> showLockedPdfDialog({
  required BuildContext context,
  required String fileName,
  required Future<void> Function(String password) verify,
}) => showDialog<String>(
  context: context,
  barrierDismissible: false,
  builder: (_) => LockedPdfDialog(fileName: fileName, verify: verify),
);