import 'dart:async';

import 'package:akyl/presentation/widgets/glass_background.dart';
import 'package:akyl/presentation/widgets/typewriter_text.dart';

/// Общая настройка всех тестов: фон главного экрана стоит на месте, иначе
/// `pumpAndSettle` ждал бы конца бесконечной анимации.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  GlassBackground.animate = false;
  // Печать по буквам и бегущие подсказки держат таймеры — в тестах
  // текст появляется сразу.
  TypewriterText.enabled = false;
  await testMain();
}
