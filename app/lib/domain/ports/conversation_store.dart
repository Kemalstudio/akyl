import '../entities/conversation.dart';

/// Хранилище истории разговоров (ТЗ, FR-10: только на устройстве).
abstract class ConversationStore {
  /// Свежие разговоры первыми.
  Future<List<Conversation>> load();

  Future<void> save(List<Conversation> conversations);

  Future<void> clear();
}
