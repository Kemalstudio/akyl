import '../entities/dialog_context.dart';
import '../entities/nlu_result.dart';

/// Разбор фразы в намерение и слоты.
/// Этап 1 — RuleBasedNlu, этап 3 — MlNlu (своя модель, ТЗ раздел 6).
/// Интерфейс один, чтобы замена модели не трогала ядро (Strategy, ТЗ раздел 5).
abstract class Nlu {
  Future<void> init();

  /// Контекст нужен для «ему», «ещё раз», «да», «первому» (ТЗ, FR-8).
  Future<NluResult> parse(String text, DialogContext ctx);
}
