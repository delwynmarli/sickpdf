import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Persists the user's appearance preference locally.
///
/// Stored as a tiny JSON file in the app documents directory. Defaults to
/// light mode on first launch and whenever no valid preference exists.
/// No system-follow mode: the product default is explicit light theme.
class ThemePreferences {
  ThemePreferences();

  static const _fileName = 'appearance.json';

  File? _file;

  Future<File> _resolve() async {
    if (_file != null) return _file!;
    final dir = await getApplicationDocumentsDirectory();
    _file = File('${dir.path}${Platform.pathSeparator}$_fileName');
    return _file!;
  }

  /// Loads the saved theme mode. Returns [ThemeMode.light] when unset,
  /// missing, or unreadable.
  Future<ThemeMode> load() async {
    try {
      final file = await _resolve();
      if (!await file.exists()) return ThemeMode.light;
      final json = jsonDecode(await file.readAsString());
      final value = json['themeMode'] as String?;
      switch (value) {
        case 'dark':
          return ThemeMode.dark;
        case 'light':
        default:
          return ThemeMode.light;
      }
    } on FormatException {
      return ThemeMode.light;
    } on FileSystemException {
      return ThemeMode.light;
    }
  }

  /// Persists [mode]; ignores failures so a storage error never blocks the UI.
  Future<void> save(ThemeMode mode) async {
    try {
      final file = await _resolve();
      await file.writeAsString(
        jsonEncode({'themeMode': mode == ThemeMode.dark ? 'dark' : 'light'}),
        flush: true,
      );
    } on FileSystemException {
      // Preference will fall back to light on next launch.
    }
  }
}
