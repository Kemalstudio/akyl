import '../voice/wake_matcher.dart';

/// Обращение «Макс»: выделяет из услышанной фразы команду после имени.
///
/// Возвращает:
/// * `null` — обращения нет, фразу надо пропустить;
/// * `''` — прозвучало одно имя, команду надо дослушать;
/// * текст команды — «позвони маме».
///
/// Настраиваемый вариант — [WakeMatcher].
String? wakeCommand(String heard) => _default.match(heard.trim())?.command;

final _default = WakeMatcher();
