import 'package:flutter/services.dart';

/// Sharing a document through Android's share sheet.
///
/// The bytes are written to the app's own cache directory and handed to other
/// apps through the existing `sickpdf/share` channel and its FileProvider.
/// The library copy is never moved or modified, and no network is involved.
typedef DocumentShare = Future<void> Function(
  List<int> bytes,
  String fileName,
);

/// A share attempt that the user needs to know about.
class DocumentShareException implements Exception {
  const DocumentShareException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Default share implementation: the platform channel in
/// [`MainActivity.kt`](android/app/src/main/kotlin/com/sickpdf/sickpdf/MainActivity.kt).
Future<void> shareDocumentBytes(List<int> bytes, String fileName) async {
  if (bytes.isEmpty) {
    throw const DocumentShareException('There is nothing to share.');
  }
  try {
    await const MethodChannel('sickpdf/share').invokeMethod<void>('share', {
      'bytes': bytes,
      'fileName': fileName,
    });
  } on MissingPluginException {
    throw const DocumentShareException('Sharing is supported on Android only.');
  } on PlatformException {
    throw const DocumentShareException('Could not share this document.');
  }
}
