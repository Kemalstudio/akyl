/// Порты «жизненных» функций: память, напоминания, экстренная помощь.
library;

/// То, что человек попросил запомнить: «ключи от гаража у Ахмеда».
class MemoryNote {
  const MemoryNote({required this.text, required this.at});

  final String text;
  final DateTime at;

  Map<String, Object> toJson() => {'text': text, 'at': at.toIso8601String()};

  static MemoryNote fromJson(Map<String, Object?> json) => MemoryNote(
    text: json['text'] as String,
    at: DateTime.parse(json['at'] as String),
  );
}

/// Записи памяти живут только на телефоне.
abstract class MemoryStore {
  Future<List<MemoryNote>> load();

  Future<void> save(List<MemoryNote> notes);
}

/// Напоминание: «выпить таблетку» каждый день в 9:00 или один раз.
class Reminder {
  const Reminder({
    required this.id,
    required this.text,
    required this.at,
    this.daily = false,
  });

  final int id;
  final String text;

  /// Ближайшее срабатывание.
  final DateTime at;

  /// Повторять каждый день в то же время.
  final bool daily;
}

/// Будильник Android: напоминание сработает, даже если приложение закрыто
/// и телефон перезагружали.
abstract class ReminderScheduler {
  Future<void> schedule(Reminder reminder);

  Future<void> cancel(int id);

  Future<List<Reminder>> list();
}
