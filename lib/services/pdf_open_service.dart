import 'dart:io';

import 'package:pdfrx/pdfrx.dart';

/// Shown when a supplied password is rejected.
///
/// Kept in one place so the dialog and the tests cannot drift apart. It never
/// contains the password itself.
const String pdfWrongPasswordMessage =
    'The password is incorrect. Check it and try again.';

/// A controlled failure while opening a library document.
///
/// [wrongPassword] separates "the password was rejected" from every other
/// failure, so the UI can keep the prompt open only when retrying can help.
/// [message] is plain English and never contains the password, a file path, or
/// document content.
class PdfOpenException implements Exception {
  const PdfOpenException(this.message, {this.wrongPassword = false});

  final String message;
  final bool wrongPassword;

  @override
  String toString() => message;
}

/// What the Files screen needs in order to open a document safely.
///
/// [PdfOpenService] is the real implementation; widget tests substitute a fake
/// so no native PDF engine is required.
abstract class PdfOpenApi {
  /// True when the document cannot be opened without a user password.
  ///
  /// Throws [PdfOpenException] when the file is missing, empty, damaged, or
  /// unreadable — none of which are password problems.
  Future<bool> requiresPassword(String path);

  /// Opens the document with [password] to prove it is correct.
  ///
  /// Completes normally when the password works. Throws [PdfOpenException]
  /// with [PdfOpenException.wrongPassword] set when it is rejected.
  Future<void> verifyPassword(String path, String password);
}

/// Supplies a known-good password to pdfrx exactly once.
///
/// pdfrx re-invokes a password provider each time an open attempt fails, so a
/// provider that always answers with the same password would loop forever if
/// that password were wrong. Answering once and then returning `null` bounds
/// the sequence: pdfrx either opens the document or gives up with
/// `PdfPasswordException`.
///
/// The password lives only inside this closure, which the caller drops when the
/// viewer route closes. It is never written to disk, the library index, a log,
/// or the clipboard.
PdfPasswordProvider pdfPasswordProviderFor(String password) {
  var answered = false;
  return () {
    if (answered) return null;
    answered = true;
    return password;
  };
}

/// Detects whether an opened document still needs a password.
///
/// Derived from the installed pdfrx 2.6.5 API, not guessed:
/// - `PdfDocument.openFile` accepts `passwordProvider` and
///   `firstAttemptByEmptyPassword`.
/// - With `firstAttemptByEmptyPassword: true` and a provider that returns
///   `null`, pdfrx makes exactly one attempt with an empty password and then
///   throws `PdfPasswordException`.
///
/// That single probe distinguishes "needs a user password" from "opens
/// normally" without parsing encryption dictionaries by hand. A document that
/// only carries owner permissions opens normally and therefore never prompts,
/// which is correct: it is readable as-is.
///
/// pdfium reports a missing password through error code 4
/// (`FPDF_ERR_PASSWORD`), the same convention [`pdfSplitLoadError`] already
/// uses, so that code is treated as a password requirement too.
///
/// This is not the Unlock PDF tool: nothing is decrypted to disk, nothing is
/// copied, and the library file is only read.
class PdfOpenService implements PdfOpenApi {
  const PdfOpenService();

  /// pdfium error code for a missing or wrong password.
  static const _passwordErrorCode = 4;

  @override
  Future<bool> requiresPassword(String path) async {
    await _ensureReadable(path);
    PdfDocument? document;
    try {
      await pdfrxFlutterInitialize();
      document = await PdfDocument.openFile(
        path,
        // Returning null allows only the empty-password attempt, so a locked
        // document raises PdfPasswordException instead of retrying forever.
        passwordProvider: () => null,
        firstAttemptByEmptyPassword: true,
      );
      if (document.pages.isEmpty) {
        throw const PdfOpenException('This PDF has no pages.');
      }
      return false;
    } on PdfPasswordException {
      return true;
    } on PdfException catch (error) {
      if (error.errorCode == _passwordErrorCode) return true;
      throw const PdfOpenException(
        'This PDF is damaged or uses an unsupported format.',
      );
    } on FileSystemException {
      throw const PdfOpenException(
        'This document is no longer available. It may have been removed by the '
        'system.',
      );
    } catch (_) {
      throw const PdfOpenException(
        'Could not open this document. It may be damaged or unsupported.',
      );
    } finally {
      // The probe is never displayed, so it is released on every path.
      await document?.dispose();
    }
  }

  @override
  Future<void> verifyPassword(String path, String password) async {
    if (password.isEmpty) {
      throw const PdfOpenException(
        'Enter the PDF password.',
        wrongPassword: true,
      );
    }
    await _ensureReadable(path);
    PdfDocument? document;
    try {
      await pdfrxFlutterInitialize();
      // firstAttemptByEmptyPassword is false so the only attempt uses the
      // password the user typed; answering once keeps the retry sequence
      // finite.
      document = await PdfDocument.openFile(
        path,
        passwordProvider: pdfPasswordProviderFor(password),
        firstAttemptByEmptyPassword: false,
      );
      if (document.pages.isEmpty) {
        throw const PdfOpenException('This PDF has no pages.');
      }
    } on PdfPasswordException {
      throw const PdfOpenException(
        pdfWrongPasswordMessage,
        wrongPassword: true,
      );
    } on PdfException catch (error) {
      if (error.errorCode == _passwordErrorCode) {
        throw const PdfOpenException(
          pdfWrongPasswordMessage,
          wrongPassword: true,
        );
      }
      throw const PdfOpenException(
        'The password was accepted, but this PDF could not be read. It may be '
        'damaged or unsupported.',
      );
    } on FileSystemException {
      throw const PdfOpenException(
        'This document is no longer available. It may have been removed by the '
        'system.',
      );
    } catch (_) {
      throw const PdfOpenException(
        'Could not open this document. It may be damaged or unsupported.',
      );
    } finally {
      await document?.dispose();
    }
  }

  /// Rejects a missing or empty file before the PDF engine is involved, so the
  /// user gets a specific message instead of a generic parse failure.
  Future<void> _ensureReadable(String path) async {
    FileStat stat;
    try {
      stat = await File(path).stat();
    } on FileSystemException {
      throw const PdfOpenException(
        'This document is no longer available. It may have been removed by the '
        'system.',
      );
    }
    if (stat.type == FileSystemEntityType.notFound) {
      throw const PdfOpenException(
        'This document is no longer available. It may have been removed by the '
        'system.',
      );
    }
    if (stat.size == 0) {
      throw const PdfOpenException(
        'This document is empty and cannot be opened.',
      );
    }
  }
}