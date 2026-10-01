import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../domain/ports/life_ports.dart';

/// Заметки «запомни…» в JSON-файле внутри каталога приложения — как
/// история разговоров. Никуда не синхронизируются.
class FileMemoryStore implements MemoryStore {
  FileMemoryStore({this.fileName = 'memory.json'});

  final String fileName;

  /// Старые заметки вытесняются: это память о бытовом, а не архив.
  static const int keepLast = 300;

  File? _file;

  Future<File> _resolve() async {
    final cached = _file;
    if (cached != null) return cached;
    final dir = await getApplicationDocumentsDirectory();
    return _file = File('${dir.path}${Platform.pathSeparator}$fileName');
  }

  @override
  Future<List<MemoryNote>> load() async {
    try {
      final file = await _resolve();
      if (!await file.exists()) return [];
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List) return [];
      return raw.cast<Map<String, Object?>>().map(MemoryNote.fromJson).toList();
    } catch (_) {
      // Повреждённый файл не должен ронять помощника.
      return [];
    }
  }

  @override
  Future<void> save(List<MemoryNote> notes) async {
    final file = await _resolve();
    final kept = notes.length > keepLast
        ? notes.sublist(notes.length - keepLast)
        : notes;
    await file.writeAsString(jsonEncode([for (final n in kept) n.toJson()]));
  }
}
