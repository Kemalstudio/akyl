import 'skill_result.dart';

/// Одна реплика в разговоре (ТЗ, FR-10).
class ChatMessage {
  const ChatMessage({
    required this.text,
    required this.fromUser,
    required this.at,
    this.status,
  });

  final String text;
  final bool fromUser;
  final DateTime at;

  /// Чем закончился ход ассистента — по нему экран выбирает акцент.
  final SkillStatus? status;

  Map<String, Object?> toJson() => {
    'text': text,
    'fromUser': fromUser,
    'at': at.toIso8601String(),
    if (status != null) 'status': status!.name,
  };

  factory ChatMessage.fromJson(Map<String, Object?> json) => ChatMessage(
    text: json['text'] as String? ?? '',
    fromUser: json['fromUser'] as bool? ?? false,
    at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime.now(),
    status: _statusFrom(json['status'] as String?),
  );

  static SkillStatus? _statusFrom(String? name) {
    if (name == null) return null;
    for (final s in SkillStatus.values) {
      if (s.name == name) return s;
    }
    return null;
  }
}

/// Разговор целиком: то, что в боковой панели одна строка.
class Conversation {
  Conversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    List<ChatMessage>? messages,
  }) : messages = messages ?? [];

  final String id;

  /// Заголовок придумывается по первой команде, а не по её тексту.
  String title;

  final DateTime createdAt;
  DateTime updatedAt;

  final List<ChatMessage> messages;

  bool get isEmpty => messages.isEmpty;

  /// Новый пустой разговор. Идентификатор — время создания: разговоры
  /// сортируются по нему и без отдельного счётчика.
  factory Conversation.fresh({DateTime? now}) {
    final at = now ?? DateTime.now();
    return Conversation(
      id: at.microsecondsSinceEpoch.toString(),
      title: 'Новый разговор',
      createdAt: at,
      updatedAt: at,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'messages': messages.map((m) => m.toJson()).toList(),
  };

  factory Conversation.fromJson(Map<String, Object?> json) {
    final raw = (json['messages'] as List<Object?>? ?? const [])
        .cast<Map<String, Object?>>();
    final created =
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now();
    return Conversation(
      id: json['id'] as String? ?? created.microsecondsSinceEpoch.toString(),
      title: json['title'] as String? ?? 'Разговор',
      createdAt: created,
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? created,
      messages: raw.map(ChatMessage.fromJson).toList(),
    );
  }
}
