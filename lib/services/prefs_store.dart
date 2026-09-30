import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tiny key-value store. Values are JSON strings so every feature owns its
/// own schema and a bad value can simply be ignored.
abstract class PrefsStore {
  String? read(String key);
  Future<void> write(String key, String value);
}

/// Used in tests and as the default until the app injects the real store.
class MemoryPrefsStore implements PrefsStore {
  final Map<String, String> _data = {};

  @override
  String? read(String key) => _data[key];

  @override
  Future<void> write(String key, String value) async => _data[key] = value;
}

/// Survives app restarts (SharedPreferences under the hood).
class SharedPrefsStore implements PrefsStore {
  SharedPrefsStore(this._prefs);
  final SharedPreferences _prefs;

  @override
  String? read(String key) => _prefs.getString(key);

  @override
  Future<void> write(String key, String value) async {
    await _prefs.setString(key, value);
  }
}

final prefsStoreProvider = Provider<PrefsStore>((ref) => MemoryPrefsStore());
