import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../domain/entities/conversation.dart';
import '../../domain/ports/conversation_store.dart';

/// История разговоров в одном JSON-файле внутри каталога приложения.
///
/// Почему файл, а не база: разговоров у голосового ассистента десятки, а не
/// десятки тысяч, и они всегда читаются целиком — для боковой панели нужен
/// сразу весь список. База здесь добавила бы зависимость и схему, не дав
/// ничего взамен.
///
/// Каталог приложения не виден другим программам и удаляется вместе с ним.
/// История никуда не синхронизируется (ТЗ, раздел 3: приватность).
class FileConversationStore implements ConversationStore {
  FileConversationStore({this.fileName = 'conversations.json'});

  final String fileName;

  /// Сколько разговоров хранить. Старые вытесняются: история ассистента
  /// нужна за последние дни, а не за всё время.
  static const int keepLast = 100;

  File? _file;

  Future<File> _resolve() async {
    final cached = _file;
    if (cached != null) return cached;
    final dir = await getApplicationDocumentsDirectory();
    return _file = File('${dir.path}${Platform.pathSeparator}$fileName');
  }

  @override
  Future<List<Conversation>> load() async {
    try {
      final file = await _resolve();
      if (!await file.exists()) return [];

      final raw = jsonDecode(await file.readAsString());
      if (raw is! List) return [];

      final list = raw
          .cast<Map<String, Object?>>()
          .map(Conversation.fromJson)
          .toList();
      // Свежие сверху — в таком порядке их и показывает панель.
      list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return list;
    } catch (_) {
      // Повреждённый файл не должен мешать запуску: история — не то, ради
      // чего человек открыл ассистента.
      return [];
    }
  }

  @override
  Future<void> save(List<Conversation> conversations) async {
    try {
      final file = await _resolve();
      final kept = conversations.take(keepLast).toList();
      await file.writeAsString(
        jsonEncode(kept.map((c) => c.toJson()).toList()),
        flush: true,
      );
    } catch (_) {
      // Не смогли записать — разговор всё равно продолжается.
    }
  }

  @override
  Future<void> clear() async {
    try {
      final file = await _resolve();
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Нечего чистить.
    }
  }
}
