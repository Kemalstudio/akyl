import '../data/contacts/morphology.dart';
import '../domain/entities/contact.dart';
import '../domain/entities/dialog_context.dart';
import '../domain/entities/intent.dart';
import '../domain/entities/nlu_result.dart';
import '../domain/entities/skill_result.dart';
import '../domain/ports/contact_resolver.dart';
import '../domain/ports/phone.dart';
import '../domain/ports/skill.dart';
import 'contact_lookup.dart';

/// Звонок контакту (ТЗ, сценарии С1, С2, С5, С7).
///
/// При однозначном совпадении звонит сразу, без экрана подтверждения — в этом
/// весь смысл бюджета в 1 секунду (ТЗ, FR-6). Ошибочный звонок пользователь
/// видит и сбрасывает; ошибочную SMS вернуть нельзя, поэтому там правило другое.
class CallSkill implements Skill {
  CallSkill({
    required ContactResolver resolver,
    required Phone phone,
    RussianMorphology morphology = const RussianMorphology(),
    this.beforeCall,
  }) : _resolver = resolver,
       _phone = phone,
       _morphology = morphology;

  final ContactResolver _resolver;
  final Phone _phone;
  final RussianMorphology _morphology;
  final Future<void> Function(String response)? beforeCall;

  @override
  Intent get intent => Intent.call;

  @override
  Future<SkillResult> execute(NluResult result, DialogContext ctx) async {
    final spokenName = result.slot(Slot.contact);
    if (spokenName == null || spokenName.isEmpty) {
      return SkillResult.failed('Кому позвонить?');
    }

    final requestedType = _parsePhoneType(result.slot(Slot.phoneType));
    final speaker = result.slot(Slot.speaker) == 'true';

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
      LookupFound(match: final match) => await _placeCall(
        match,
        requestedType,
        speaker,
      ),
    };
  }

  Future<SkillResult> _placeCall(
    ContactMatch match,
    PhoneType? requested,
    bool speaker,
  ) async {
    final contact = match.contact;

    final PhoneNumber? number;
    if (requested != null) {
      number = contact.phoneOfType(requested);
      if (number == null) {
        // «У контакта X», а не «У X»: родительный падеж имени потребовал бы
        // ещё одной таблицы склонений ради одной строки — не стоит того.
        return SkillResult.failed(
          'У контакта ${contact.displayName} нет номера «${requested.spokenRu}»',
        );
      }
    } else {
      number = contact.primaryPhone;
      if (number == null) {
        return SkillResult.failed(
          'У контакта ${contact.displayName} нет номера',
        );
      }
    }

    if (!await _phone.hasPermissions()) {
      return SkillResult.failed('Нужно разрешение на звонки');
    }

    // Ответ повторяет всё, что ассистент понял: имя, номер и громкую связь.
    // Если он понял не так, человек услышит это раньше, чем пойдёт гудок.
    final parts = <String>['Звоню ${_morphology.dative(contact.displayName)}'];
    if (requested != null) parts.add(requested.spokenRu);
    if (speaker) parts.add('по громкой связи');
    final response = parts.join(', ');
    await beforeCall?.call('Хорошо. $response');
    await _phone.call(number.number, speaker: speaker);
    return SkillResult.done(
      response,
      contact: contact,
      alreadySpoken: beforeCall != null,
    );
  }

  /// «Какому Ахмеду: Ахмед Работа или Ахмед Брат?» (ТЗ, сценарий С5).
  String _askWhich(List<ContactMatch> matches) {
    final names = matches.map((m) => m.contact.displayName).toList();
    if (names.length == 2) {
      return 'Кому звонить: ${names[0]} или ${names[1]}?';
    }
    final head = names.sublist(0, names.length - 1).join(', ');
    return 'Кому звонить: $head или ${names.last}?';
  }

  PhoneType? _parsePhoneType(String? raw) {
    if (raw == null) return null;
    for (final t in PhoneType.values) {
      if (t.name == raw) return t;
    }
    return null;
  }
}
