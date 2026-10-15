import 'dart:io';

import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

String? validateUnlockPassword(String password) =>
    password.isEmpty ? 'Enter the PDF password.' : null;

class PdfUnlockException implements Exception {
  const PdfUnlockException(this.message);
  final String message;
  @override
  String toString() => message;
}

class PdfUnlockService {
  static const _channel = MethodChannel('sickpdf/unlock');

  Future<Uint8List> unlock(String path, String password) async {
    final validation = validateUnlockPassword(password);
    if (validation != null) throw PdfUnlockException(validation);
    Uint8List source;
    try {
      source = await File(path).readAsBytes();
      if (source.isEmpty) throw const PdfUnlockException('This PDF is empty.');
    } on PdfUnlockException {
      rethrow;
    } on FileSystemException {
      throw const PdfUnlockException('Could not read the selected PDF.');
    }

    try {
      await pdfrxFlutterInitialize();
      var passwordAttempted = false;
      final input = await PdfDocument.openData(
        source,
        passwordProvider: () {
          if (passwordAttempted) return null;
          passwordAttempted = true;
          return password;
        },
      );
      try {
        if (!input.isEncrypted) {
          throw const PdfUnlockException(
            'This PDF is already unlocked and does not require a password.',
          );
        }
        if (input.pages.isEmpty) {
          throw const PdfUnlockException('This PDF has no pages.');
        }
      } finally {
        await input.dispose();
      }

      final result = await _channel.invokeMethod<Uint8List>('unlock', {
        'bytes': source,
        'password': password,
      });
      if (result == null || result.isEmpty) {
        throw const PdfUnlockException('The PDF engine returned no output.');
      }
      await verifyUnlockedPdf(result);
      return result;
    } on PdfUnlockException {
      rethrow;
    } on PdfPasswordException {
      throw const PdfUnlockException(
        'The password is incorrect. Check it and try again.',
      );
    } on MissingPluginException {
      throw const PdfUnlockException('Unlock PDF is supported on Android only.');
    } on PlatformException catch (error) {
      throw PdfUnlockException(
        error.code == 'wrong_password'
            ? 'The password is incorrect. Check it and try again.'
            : error.code == 'too_large'
            ? 'Not enough memory. Try a smaller PDF.'
            : 'Could not unlock this PDF. It may be damaged, signed, or unsupported.',
      );
    } catch (_) {
      throw const PdfUnlockException(
        'Could not unlock this PDF. It may be damaged or unsupported.',
      );
    }
  }
}

Future<void> verifyUnlockedPdf(Uint8List bytes) async {
  await pdfrxFlutterInitialize();
  final document = await PdfDocument.openData(bytes, passwordProvider: () => null);
  try {
    if (document.isEncrypted || document.pages.isEmpty) {
      throw const PdfUnlockException('Unlock verification failed. No file was exported.');
    }
    final image = await document.pages.first.render(width: 32, height: 32);
    image?.dispose();
  } finally {
    await document.dispose();
  }
}
