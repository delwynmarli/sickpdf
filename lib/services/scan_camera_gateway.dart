import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:flutter/widgets.dart';

/// Why a camera operation could not be completed.
enum ScanCameraFailure {
  /// The user declined the camera permission.
  permissionDenied,

  /// The device has no camera, or it is in use by another app.
  unavailable,

  /// The camera could not be started.
  initializationFailed,

  /// The photo could not be taken.
  captureFailed,
}

/// Raised when the camera cannot be used.
class ScanCameraException implements Exception {
  const ScanCameraException(this.failure, this.message);

  final ScanCameraFailure failure;

  /// User-facing explanation of what went wrong.
  final String message;

  @override
  String toString() => message;
}

/// A camera session that the Scan Document screen drives.
///
/// The real implementation wraps the `camera` plugin. Tests substitute a
/// fake so the screen can be exercised without hardware.
abstract class ScanCameraGateway {
  /// Whether the camera is currently running and ready to take a picture.
  bool get isReady;

  /// The live preview for the running camera.
  ///
  /// Returns `null` when no camera is running, so the screen can show a
  /// placeholder instead of a broken preview.
  Widget? get preview;

  /// Aspect ratio to lay the preview out with, or `null` when it is unknown.
  ///
  /// The value is expressed in the orientation the preview widget expects:
  /// the raw sensor ratio is inverted in portrait, matching how
  /// `CameraPreview` sizes itself. A `null` result means the screen should
  /// fall back to a neutral frame instead of guessing.
  double? get previewAspectRatio;

  /// Opens the camera and starts the preview.
  ///
  /// Requests the camera permission when it has not been granted yet.
  /// Throws a [ScanCameraException] when the camera cannot be started.
  Future<void> open();

  /// Takes a photo and returns the encoded image bytes.
  ///
  /// The gateway owns the file the camera wrote and deletes it before it
  /// returns, so no temporary image is left behind.
  Future<Uint8List> takePicture();

  /// Releases the camera. Safe to call when no camera is running.
  Future<void> close();
}

/// The production camera gateway, backed by the `camera` plugin.
class PluginScanCameraGateway implements ScanCameraGateway {
  PluginScanCameraGateway();

  CameraController? _controller;

  @override
  bool get isReady => _controller?.value.isInitialized ?? false;

  @override
  Widget? get preview {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return null;
    return CameraPreview(controller);
  }

  @override
  double? get previewAspectRatio {
    final value = _controller?.value;
    if (value == null || !value.isInitialized) return null;

    // `previewSize` is reported in sensor coordinates, so portrait needs the
    // inverse. Landscape keeps the raw ratio. This mirrors the calculation
    // `CameraPreview` performs internally.
    final size = value.previewSize;
    if (size == null || size.width <= 0 || size.height <= 0) return null;
    final raw = size.width / size.height;
    if (!raw.isFinite || raw <= 0) return null;

    final orientation = value.lockedCaptureOrientation ?? value.deviceOrientation;
    final landscape = orientation == DeviceOrientation.landscapeLeft ||
        orientation == DeviceOrientation.landscapeRight;
    final ratio = landscape ? raw : 1 / raw;
    if (!ratio.isFinite || ratio <= 0) return null;
    return ratio;
  }

  @override
  Future<void> open() async {
    await close();

    final List<CameraDescription> cameras;
    try {
      cameras = await availableCameras();
    } on CameraException catch (error) {
      throw ScanCameraException(_mapFailure(error), _messageFor(error));
    } catch (_) {
      throw const ScanCameraException(
        ScanCameraFailure.unavailable,
        'The camera could not be opened on this device.',
      );
    }

    if (cameras.isEmpty) {
      throw const ScanCameraException(
        ScanCameraFailure.unavailable,
        'No camera was found on this device.',
      );
    }

    // Prefer the back camera: that is the one pointed at a document.
    final description = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    final controller = CameraController(
      description,
      ResolutionPreset.high,
      enableAudio: false,
    );
    _controller = controller;

    try {
      await controller.initialize();
    } on CameraException catch (error) {
      _controller = null;
      await controller.dispose();
      throw ScanCameraException(_mapFailure(error), _messageFor(error));
    } catch (_) {
      _controller = null;
      await controller.dispose();
      throw const ScanCameraException(
        ScanCameraFailure.initializationFailed,
        'The camera could not be started. Close other apps that use it and '
            'try again.',
      );
    }
  }

  @override
  Future<Uint8List> takePicture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      throw const ScanCameraException(
        ScanCameraFailure.initializationFailed,
        'The camera is not running. Open it and try again.',
      );
    }

    final XFile shot;
    try {
      shot = await controller.takePicture();
    } on CameraException catch (error) {
      throw ScanCameraException(_mapFailure(error), _messageFor(error));
    } catch (_) {
      throw const ScanCameraException(
        ScanCameraFailure.captureFailed,
        'The photo could not be taken. Try again.',
      );
    }

    try {
      final bytes = await shot.readAsBytes();
      if (bytes.isEmpty) {
        throw const ScanCameraException(
          ScanCameraFailure.captureFailed,
          'The photo was empty. Try again.',
        );
      }
      return bytes;
    } on ScanCameraException {
      rethrow;
    } catch (_) {
      throw const ScanCameraException(
        ScanCameraFailure.captureFailed,
        'The photo could not be read. Try again.',
      );
    } finally {
      // The camera writes into the app cache. The bytes now live in memory,
      // so the file is deleted straight away.
      await _deleteQuietly(shot.path);
    }
  }

  @override
  Future<void> close() async {
    final controller = _controller;
    _controller = null;
    if (controller == null) return;
    try {
      await controller.dispose();
    } catch (_) {
      // Disposing a controller that never initialized can throw. The camera
      // is released either way, so there is nothing to recover from.
    }
  }

  /// Deletes [path], ignoring any failure.
  ///
  /// A leftover file in the app cache is harmless.
  static Future<void> _deleteQuietly(String path) async {
    if (path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Nothing to do.
    }
  }

  /// Maps a plugin error code onto the failure the UI reacts to.
  static ScanCameraFailure _mapFailure(CameraException error) {
    switch (error.code) {
      case 'CameraAccessDenied':
      case 'CameraAccessDeniedWithoutPrompt':
      case 'CameraAccessRestricted':
        return ScanCameraFailure.permissionDenied;
      case 'cameraNotFound':
        return ScanCameraFailure.unavailable;
      default:
        return ScanCameraFailure.initializationFailed;
    }
  }

  /// Turns a plugin error into a message the user can act on.
  static String _messageFor(CameraException error) {
    switch (error.code) {
      case 'CameraAccessDenied':
      case 'CameraAccessDeniedWithoutPrompt':
      case 'CameraAccessRestricted':
        return 'sickPDF needs the camera to scan a document. Enable it in '
            'the app settings, then try again.';
      case 'cameraNotFound':
        return 'No camera was found on this device.';
      default:
        return 'The camera could not be started. Close other apps that use '
            'it and try again.';
    }
  }
}
