import 'dart:io';

import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

/// Printable ASCII avoids reader-dependent Unicode normalization/truncation.
String? validatePdfPassword(String password, String confirmation) {
  if (password.trim().isEmpty) return 'Enter a password.';
  if (password.length > 127 ||
      password.codeUnits.any((unit) => unit < 32 || unit > 126)) {
    return 'Use 1–127 printable English letters, numbers, spaces or symbols.';
  }
  if (password != confirmation) return 'Passwords do not match.';
  return null;
}

class PdfProtectException implements Exception {
  const PdfProtectException(this.message);
  final String message;
  @override
  String toString() => message;
}

class PdfProtectService {
  static const _channel = MethodChannel('sickpdf/protect');

  /// Snapshot once: subsequent processing never reads or writes the source path.
  Future<Uint8List> load(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      if (bytes.isEmpty) {
        throw const PdfProtectException(
          'This PDF is empty. Select another file.',
        );
      }
      await pdfrxFlutterInitialize();
      final document = await PdfDocument.openData(
        bytes,
        passwordProvider: () => null,
      );
      try {
        if (document.isEncrypted) {
          throw const PdfProtectException(
            'This PDF is already encrypted. Select an unlocked, unencrypted copy.',
          );
        }
        if (document.pages.isEmpty) {
          throw const PdfProtectException('This PDF has no pages.');
        }
      } finally {
        await document.dispose();
      }
      return bytes;
    } on PdfProtectException {
      rethrow;
    } on PdfPasswordException {
      throw const PdfProtectException(
        'This PDF requires a password. Select an unlocked, unencrypted copy.',
      );
    } on FileSystemException {
      throw const PdfProtectException(
        'Could not read the PDF. Select an accessible local copy.',
      );
    } catch (_) {
      throw const PdfProtectException(
        'Could not open this PDF. It may be damaged or unsupported.',
      );
    }
  }

  Future<Uint8List> protect(
    Uint8List source,
    String password,
    String confirmation,
  ) async {
    final validation = validatePdfPassword(password, confirmation);
    if (validation != null) throw PdfProtectException(validation);
    try {
      final bytes = await _channel.invokeMethod<Uint8List>('protect', {
        'bytes': source,
        'password': password,
      });
      if (bytes == null || bytes.isEmpty) {
        throw const PdfProtectException(
          'The PDF engine returned no protected output.',
        );
      }
      await verifyProtectedPdf(bytes, password);
      return bytes;
    } on PdfProtectException {
      rethrow;
    } on MissingPluginException {
      throw const PdfProtectException(
        'Protect PDF is currently supported on Android only.',
      );
    } on PlatformException catch (error) {
      throw PdfProtectException(
        error.code == 'too_large' ? 'Not enough memory. Try a smaller PDF.' : 'Could not protect this PDF. Use an unlocked, undamaged, unsigned copy.',
      );
    } catch (_) {
      throw const PdfProtectException(
        'Protection verification failed. No file was exported.',
      );
    }
  }
}

/// Independent verification with PDFium, not the PDFBox writer.
Future<void> verifyProtectedPdf(Uint8List bytes, String password) async {
  await pdfrxFlutterInitialize();
  var attempts = 0;
  final opened = await PdfDocument.openData(
    bytes,
    passwordProvider: () => attempts++ == 0 ? password : null,
  );
  try {
    if (!opened.isEncrypted || opened.pages.isEmpty) {
      throw const PdfProtectException(
        'Protection verification failed. No file was exported.',
      );
    }
    // Exercise content decryption as well as opening the page tree.
    final image = await opened.pages.first.render(width: 32, height: 32);
    if (image == null) {
      throw const PdfProtectException(
        'Could not verify the protected PDF content.',
      );
    }
    image.dispose();
  } finally {
    await opened.dispose();
  }
  final wrongPassword =
      '${password.startsWith('!') ? '#' : '!'}${password.substring(1)}';
  for (final candidate in ['', wrongPassword]) {
    var supplied = false;
    try {
      final unexpected = await PdfDocument.openData(
        bytes,
        passwordProvider: () {
          if (supplied || candidate.isEmpty) return null;
          supplied = true;
          return candidate;
        },
      );
      await unexpected.dispose();
    } on PdfPasswordException {
      continue;
    }
    throw const PdfProtectException(
      'The output did not enforce the password. No file was exported.',
    );
  }
}
