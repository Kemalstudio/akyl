import 'package:flutter/foundation.dart';

/// Подсистемы в журнале голоса — те же теги видны в logcat.
enum VoiceTag {
  voice('VOICE'),
  wake('WAKE'),
  stt('STT'),
  llm('NLU'),
  tts('TTS'),
  action('ACTION'),
  audio('AUDIO'),
  background('BACKGROUND');

  const VoiceTag(this.label);
  final String label;
}

class VoiceLogEntry {
  const VoiceLogEntry(this.at, this.tag, this.message);
  final DateTime at;
  final VoiceTag tag;
  final String message;

  @override
  String toString() {
    String two(int v) => v.toString().padLeft(2, '0');
    final t =
        '${two(at.hour)}:${two(at.minute)}:${two(at.second)}.'
        '${at.millisecond.toString().padLeft(3, '0')}';
    return '$t [${tag.label}] $message';
  }
}

/// Журнал голосового конвейера: последние события для панели отладки.
///
/// Распознанные фразы сюда попадают — это журнал в памяти телефона, он не
/// пишется на диск и не покидает устройство. В logcat идут только события
/// без текста речи, чтобы чужое приложение с доступом к логам (adb, OEM)
/// не прочитало, что человек говорил.
class VoiceLog extends ChangeNotifier {
  VoiceLog({this.capacity = 200, this.echo = true});

  static final VoiceLog instance = VoiceLog();

  final int capacity;

  /// Печатать ли в logcat (тег flutter). И в релизе: без текста речи
  /// события нужны, чтобы разобраться с телефоном на подоконнике.
  final bool echo;

  final List<VoiceLogEntry> _entries = [];
  List<VoiceLogEntry> get entries => List.unmodifiable(_entries);

  /// [private] — текст речи: остаётся только в памяти.
  void add(VoiceTag tag, String message, {bool private = false}) {
    final entry = VoiceLogEntry(DateTime.now(), tag, message);
    _entries.add(entry);
    if (_entries.length > capacity) _entries.removeAt(0);
    if (echo && !private) debugPrint('[Akyl] $entry');
    notifyListeners();
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }
}
