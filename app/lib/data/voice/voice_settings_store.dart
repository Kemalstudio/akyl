import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/voice/voice_print.dart';
import '../../domain/voice/voice_settings.dart';

/// Где хранятся настройки голоса.
abstract class VoiceSettingsStore {
  VoiceSettings load();
  Future<void> save(VoiceSettings settings);

  /// Образцы «Макс» голосом человека. Хранятся отпечатки MFCC, а не запись
  /// голоса, и только на телефоне.
  WakeVoice? loadVoice();
  Future<void> saveVoice(WakeVoice? voice);
}

class PreferencesVoiceSettingsStore implements VoiceSettingsStore {
  PreferencesVoiceSettingsStore(this._prefs);

  final SharedPreferences _prefs;

  static const _key = 'voice.settings.v1';
  static const _voiceKey = 'voice.print.v1';

  /// Флаг старой версии: «откликаться на Макс» в открытом приложении.
  static const _legacyWake = 'wake_word_in_app';

  @override
  VoiceSettings load() {
    final raw = _prefs.getString(_key);
    if (raw != null) {
      try {
        final map = jsonDecode(raw);
        if (map is Map<String, Object?>) return VoiceSettings.fromMap(map);
      } on FormatException {
        // Испорченная запись — начинаем с умолчаний, а не падаем.
      }
    }
    return VoiceSettings(wakeEnabled: _prefs.getBool(_legacyWake) ?? false);
  }

  @override
  Future<void> save(VoiceSettings settings) =>
      _prefs.setString(_key, jsonEncode(settings.toMap()));

  @override
  WakeVoice? loadVoice() {
    final raw = _prefs.getString(_voiceKey);
    if (raw == null) return null;
    try {
      return WakeVoice.fromJson(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> saveVoice(WakeVoice? voice) async {
    if (voice == null) {
      await _prefs.remove(_voiceKey);
    } else {
      await _prefs.setString(_voiceKey, jsonEncode(voice.toJson()));
    }
  }
}

/// Для тестов: настройки живут в памяти.
class MemoryVoiceSettingsStore implements VoiceSettingsStore {
  MemoryVoiceSettingsStore([this.value = const VoiceSettings()]);

  VoiceSettings value;
  int saves = 0;

  @override
  VoiceSettings load() => value;

  @override
  Future<void> save(VoiceSettings settings) async {
    value = settings;
    saves++;
  }

  WakeVoice? voice;

  @override
  WakeVoice? loadVoice() => voice;

  @override
  Future<void> saveVoice(WakeVoice? voice) async => this.voice = voice;
}
