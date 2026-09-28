import '../entities/dialog_context.dart';
import '../entities/intent.dart';
import '../entities/nlu_result.dart';
import '../entities/skill_result.dart';

/// Навык = плагин: новая команда — новый класс, ядро не меняется (ТЗ, раздел 5).
abstract class Skill {
  Intent get intent;

  Future<SkillResult> execute(NluResult result, DialogContext ctx);
}
