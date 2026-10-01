import '../entities/intent.dart';
import '../entities/nlu_result.dart';

/// Заголовок разговора из разобранной команды.
///
/// Заголовок описывает **что человек хотел**, а не повторяет сказанное:
/// «позвони пожалуйста маме по громкой связи» превращается в «Звонок: Мама».
/// Для этого не нужна языковая модель — намерение и слоты уже разобраны,
/// а это и есть смысл фразы.
///
/// Там, где ассистент не понял команду, взять смысл неоткуда, и заголовком
/// становится сама фраза: честнее показать её, чем выдумать тему.
class ConversationTitler {
  const ConversationTitler();

  /// Сколько символов заголовка помещается в строку боковой панели.
  static const int maxLength = 38;

  String titleFor(NluResult result, String spokenText) {
    final title = switch (result.intent) {
      Intent.call => _withTarget('Звонок', result),
      Intent.sms => _withTarget('Сообщение', result),
      Intent.time => 'Который час',
      Intent.date => 'Какое сегодня число',
      Intent.battery => 'Заряд батареи',
      Intent.smallTalk => 'Разговор с помощником',
      Intent.alarm => 'Будильник',
      Intent.timer => 'Таймер',
      Intent.flashlight => 'Фонарик',
      Intent.volume => 'Громкость',
      Intent.readSms => 'Последнее сообщение',
      Intent.recentCalls => 'Кто звонил',
      Intent.openApp => 'Открыть приложение',
      Intent.remember => 'Заметка',
      Intent.recall || Intent.forget => 'Память',
      Intent.lastCall => _withTarget('Когда звонили', result),
      Intent.remind ||
      Intent.listReminders ||
      Intent.cancelReminder => 'Напоминание',
      Intent.sos => 'SOS',
      Intent.calculate => 'Калькулятор',
      Intent.media => 'Музыка',
      Intent.needsInternet => 'Нужен интернет',
      // Эти намерения не начинают разговор — они отвечают на вопрос
      // ассистента, и заголовок к этому моменту уже есть.
      Intent.confirm ||
      Intent.cancel ||
      Intent.select ||
      Intent.repeat ||
      Intent.correct => null,
      Intent.unknown => null,
    };

    return _trim(title ?? _fromSpokenText(spokenText));
  }

  /// «Звонок: Мама», «Сообщение: Мерет».
  String _withTarget(String action, NluResult result) {
    final contact = result.slot(Slot.contact);
    if (contact == null || contact.isEmpty) return action;
    return '$action: ${_capitalize(contact)}';
  }

  /// Непонятая команда: показываем начало фразы.
  String _fromSpokenText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return 'Новый разговор';
    return _capitalize(trimmed);
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  /// Обрезка по границе слова: «Сообщение: Ахмед Рабо…» читается хуже,
  /// чем «Сообщение: Ахмед…».
  String _trim(String s) {
    if (s.length <= maxLength) return s;
    final cut = s.substring(0, maxLength);
    final lastSpace = cut.lastIndexOf(' ');
    final base = lastSpace > maxLength ~/ 2 ? cut.substring(0, lastSpace) : cut;
    return '$base…';
  }
}
