import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:path_provider/path_provider.dart';

import '../theme/app_theme.dart';

/// Raised when the crop editor cannot be used.
class ScanCropException implements Exception {
  const ScanCropException(this.message);

  /// User-facing explanation of what went wrong.
  final String message;

  @override
  String toString() => message;
}

/// Opens the crop editor for a captured page.
///
/// The editor is the app's manual fallback when automatic edge detection
/// cannot find a document, and it is also how a user corrects a detection
/// that was close but not right.
abstract class ScanCropService {
  /// Opens the editor for the image in [bytes].
  ///
  /// Returns the cropped image bytes, or `null` when the user cancelled.
  /// Any temporary file the editor needs is created and removed by this
  /// method, so nothing is left behind.
  Future<Uint8List?> crop(Uint8List bytes);
}

/// The production crop editor, backed by the `image_cropper` plugin.
class PluginScanCropService implements ScanCropService {
  PluginScanCropService({ImageCropper? cropper, this.temporaryDirectory})
      : _cropper = cropper ?? ImageCropper();

  final ImageCropper _cropper;

  /// Folder used for the temporary image handed to the editor.
  ///
  /// Defaults to the app's own cache directory. Tests inject a temporary
  /// folder so they never touch the platform channel.
  final Directory? temporaryDirectory;

  @override
  Future<Uint8List?> crop(Uint8List bytes) async {
    if (bytes.isEmpty) {
      throw const ScanCropException(
        'The page image is no longer available. Capture the page again.',
      );
    }

    final File source = await _writeTemporary(bytes);
    try {
      final CroppedFile? result;
      try {
        result = await _cropper.cropImage(
          sourcePath: source.path,
          compressFormat: ImageCompressFormat.jpg,
          compressQuality: 90,
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: 'Crop page',
              toolbarColor: AppColors.teal,
              toolbarWidgetColor: Colors.white,
              activeControlsWidgetColor: AppColors.teal,
              lockAspectRatio: false,
              showCropGrid: true,
            ),
          ],
        );
      } catch (_) {
        throw const ScanCropException(
          'The crop editor could not be opened. Try again.',
        );
      }

      // The user closed the editor without saving.
      if (result == null) return null;

      final path = result.path;
      try {
        final cropped = await result.readAsBytes();
        if (cropped.isEmpty) {
          throw const ScanCropException(
            'The cropped page was empty. Try cropping the page again.',
          );
        }
        return cropped;
      } catch (error) {
        if (error is ScanCropException) rethrow;
        throw const ScanCropException(
          'The cropped page could not be read. Try cropping the page again.',
        );
      } finally {
        // The editor writes into the app cache. Remove it right away so a
        // cancelled or replaced crop does not pile up.
        await _deleteQuietly(path);
      }
    } finally {
      await _deleteQuietly(source.path);
    }
  }

  /// Writes [bytes] to a temporary file the editor can open.
  Future<File> _writeTemporary(Uint8List bytes) async {
    final Directory base = temporaryDirectory ?? await getTemporaryDirectory();
    final Directory directory = Directory(
      '${base.path}${Platform.pathSeparator}scans',
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final File file = File(
      '${directory.path}${Platform.pathSeparator}'
      'crop_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// Deletes [path], ignoring any failure.
  ///
  /// A leftover cache file is harmless, so this never throws.
  static Future<void> _deleteQuietly(String path) async {
    if (path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Nothing to do: the file stays in the app's own cache.
    }
  }
}
