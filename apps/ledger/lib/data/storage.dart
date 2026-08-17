import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A key/value document store.
///
/// Everything above this line is plain Dart, so the whole app can be tested
/// against [MemoryStorage] with no plugins and no platform channels. Moving
/// to sqflite, drift or a network backend means writing one more subclass
/// and changing one registration in main().
abstract class Storage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);

  Future<Map<String, Object?>?> readJson(String key) async {
    final raw = await read(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw) as Map<String, Object?>;
    } on FormatException {
      // Corrupt data is treated as absent rather than crashing on launch —
      // a user who cannot open the app cannot recover their data either.
      return null;
    }
  }

  Future<void> writeJson(String key, Map<String, Object?> value) =>
      write(key, jsonEncode(value));
}

class MemoryStorage extends Storage {
  MemoryStorage([Map<String, String>? seed]) : _values = {...?seed};

  final Map<String, String> _values;

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}

class PrefsStorage extends Storage {
  PrefsStorage(this._prefs);

  static Future<PrefsStorage> open() async =>
      PrefsStorage(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  @override
  Future<String?> read(String key) async => _prefs.getString(key);

  @override
  Future<void> write(String key, String value) async =>
      _prefs.setString(key, value);

  @override
  Future<void> delete(String key) async => _prefs.remove(key);
}
