import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/ports/contact_alias_store.dart';

class PreferencesAliasStore implements ContactAliasStore {
  final _preferences = SharedPreferencesAsync();
  static const _key = 'contact_relationships_v1';

  @override
  Future<Map<String, String>> load() async {
    final raw = await _preferences.getString(_key);
    if (raw == null) return {};
    try {
      return Map<String, String>.from(jsonDecode(raw) as Map);
    } on FormatException {
      return {};
    } on TypeError {
      return {};
    }
  }

  @override
  Future<void> save(Map<String, String> aliases) =>
      _preferences.setString(_key, jsonEncode(aliases));
}
