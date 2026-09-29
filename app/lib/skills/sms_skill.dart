import '../domain/entities/contact.dart';
import '../domain/entities/dialog_context.dart';
import '../domain/entities/intent.dart';
import '../domain/entities/nlu_result.dart';
import '../domain/entities/skill_result.dart';
import '../domain/ports/contact_resolver.dart';
import '../domain/ports/phone.dart';
import '../domain/ports/skill.dart';
import 'contact_lookup.dart';

/// Отправка SMS (ТЗ, сценарии С3, С4).
///
/// Подтверждение обязательно всегда (ТЗ, FR-7): отправленное сообщение не
/// отзывается. Навык вызывается дважды — первый раз возвращает вопрос, второй
/// раз, уже из ожидающего подтверждения, отправляет.
class SmsSkill implements Skill {
  SmsSkill({required ContactResolver resolver, required Phone phone})
    : _resolver = resolver,
      _phone = phone;

  final ContactResolver _resolver;
  final Phone _phone;

  @override
  Intent get intent => Intent.sms;

  @override
  Future<SkillResult> execute(NluResult result, DialogContext ctx) async {
    final spokenName = result.slot(Slot.contact);
    final message = result.slot(Slot.message);

    if (message == null || message.isEmpty) {
      return SkillResult.failed('Что написать?');
    }
    if (spokenName == null || spokenName.isEmpty) {
      return SkillResult.failed('Кому написать?');
    }

    final lookup = await lookupContact(
      _resolver,
      spokenName,
      contactId: result.slot(Slot.contactId),
    );
    return switch (lookup) {
      LookupNotFound() => SkillResult.failed('Не нашёл контакт $spokenName'),
      LookupAmbiguous(matches: final matches) => SkillResult.needsChoice(
        _askWhich(matches),
        matches,
      ),
      LookupFound(match: final match) => await _confirmOrSend(
        match.contact,
        message,
        result,
        ctx,
      ),
    };
  }

  /// Та же самая NluResult, пришедшая второй раз из ctx.pendingAction, означает
  /// «пользователь сказал да» — DialogMachine передаёт сюда ровно тот объект,
  /// который сам же и отложил.
  Future<SkillResult> _confirmOrSend(
    Contact contact,
    String message,
    NluResult result,
    DialogContext ctx,
  ) async {
    // Номер проверяется до вопроса: бессмысленно спрашивать «отправить?»,
    // если отправлять всё равно некуда.
    final number = contact.primaryPhone;
    if (number == null) {
      return SkillResult.failed('У контакта ${contact.displayName} нет номера');
    }

    final confirmed = identical(ctx.pendingAction, result);
    if (!confirmed) {
      return SkillResult.needsConfirmation(
        'Отправить ${contact.displayName}: $message?',
        contact: contact,
      );
    }

    if (!await _phone.hasPermissions()) {
      return SkillResult.failed('Нужно разрешение на отправку SMS');
    }

    await _phone.sendSms(number: number.number, text: _forSending(message));
    return SkillResult.done('Отправлено', contact: contact);
  }

  /// STT отдаёт текст в нижнем регистре — первую букву возвращаем на место.
  String _forSending(String message) {
    if (message.isEmpty) return message;
    return message[0].toUpperCase() + message.substring(1);
  }

  String _askWhich(List<ContactMatch> matches) {
    final names = matches.map((m) => m.contact.displayName).toList();
    if (names.length == 2) {
      return 'Кому писать: ${names[0]} или ${names[1]}?';
    }
    final head = names.sublist(0, names.length - 1).join(', ');
    return 'Кому писать: $head или ${names.last}?';
  }
}
