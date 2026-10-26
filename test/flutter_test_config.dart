import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pdfrx/pdfrx.dart';

/// `flutter test` builds PDFium as a native code asset and records it in
/// `build/native_assets/<os>/native_assets.json`. `pdfium_dart` reads that file
/// only through `.dart_tool/native_assets.yaml`, which `dart run` and `dart
/// test` write but `flutter test` does not.
///
/// On Windows `flutter test` compensates by prepending
/// `build/native_assets/windows/` to `PATH`, so the bare `pdfium.dll` name
/// resolves. On Linux nothing compensates: the loader tries
/// `<flutter_tester>/lib/libpdfium.so`, which does not exist during a test run,
/// then fails to locate the native assets file, so every test that opened a PDF
/// failed on CI with "Failed to load PDFium module". Point the loader at the
/// library `flutter test` actually built.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  Pdfrx.pdfiumModulePath ??= _pdfiumFromNativeAssets();
  await testMain();
}

/// Absolute path of the PDFium library built for this test run, or `null` when
/// the platform already resolves it (Windows `PATH`, Dart's
/// `.dart_tool/native_assets.yaml`, or an explicit override).
String? _pdfiumFromNativeAssets() {
  final assetsFile = _findNativeAssetsFile();
  if (assetsFile == null) return null;
  try {
    final decoded = jsonDecode(assetsFile.readAsStringSync());
    if (decoded is! Map<String, Object?>) return null;
    final targets = decoded['native-assets'];
    if (targets is! Map<String, Object?>) return null;
    for (final target in targets.values) {
      if (target is! Map<String, Object?>) continue;
      final asset = target['package:pdfium_dart/libpdfium'];
      if (asset is! List<Object?> || asset.length != 2) continue;
      final path = asset[1];
      if (asset[0] == 'absolute' && path is String && File(path).existsSync()) {
        return path;
      }
    }
  } on FormatException {
    return null;
  } on FileSystemException {
    return null;
  }
  return null;
}

/// Walks up from the working directory looking for the file `flutter test`
/// wrote for this host OS.
File? _findNativeAssetsFile() {
  final separator = Platform.pathSeparator;
  final os = Platform.operatingSystem;
  final relative =
      'build${separator}native_assets${separator}$os'
      '${separator}native_assets.json';
  var directory = Directory.current;
  while (true) {
    final candidate = File('${directory.path}$separator$relative');
    if (candidate.existsSync()) return candidate;
    final parent = directory.parent;
    if (parent.path == directory.path) return null;
    directory = parent;
  }
}
