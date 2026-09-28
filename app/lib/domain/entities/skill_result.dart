import 'contact.dart';

/// Что навык сделал и что нужно сказать пользователю.
class SkillResult {
  const SkillResult({
    required this.status,
    required this.spokenResponse,
    this.contact,
    this.choices = const [],
  });

  final SkillStatus status;

  /// Текст для TTS и для чата на экране (ТЗ, FR-10, FR-11).
  final String spokenResponse;

  /// Контакт, с которым работали — уходит в контекст диалога.
  final Contact? contact;

  /// Варианты для уточнения, если status == needsChoice.
  final List<ContactMatch> choices;

  factory SkillResult.done(String response, {Contact? contact}) =>
      SkillResult(
        status: SkillStatus.done,
        spokenResponse: response,
        contact: contact,
      );

  factory SkillResult.needsConfirmation(String response, {Contact? contact}) =>
      SkillResult(
        status: SkillStatus.needsConfirmation,
        spokenResponse: response,
        contact: contact,
      );

  factory SkillResult.needsChoice(
    String response,
    List<ContactMatch> choices,
  ) =>
      SkillResult(
        status: SkillStatus.needsChoice,
        spokenResponse: response,
        choices: choices,
      );

  factory SkillResult.failed(String response) => SkillResult(
        status: SkillStatus.failed,
        spokenResponse: response,
      );

  @override
  String toString() => 'SkillResult($status, "$spokenResponse")';
}

enum SkillStatus {
  /// команда выполнена
  done,

  /// нужно «да» или кнопка — SMS никогда не уходит без этого (ТЗ, FR-7)
  needsConfirmation,

  /// несколько контактов подошли, нужен выбор (ТЗ, сценарий С5)
  needsChoice,

  /// выполнить не удалось
  failed,
}
