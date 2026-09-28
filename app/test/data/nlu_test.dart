import 'package:akyl/data/nlu/rule_based_nlu.dart';
import 'package:akyl/domain/entities/contact.dart';
import 'package:akyl/domain/entities/dialog_context.dart';
import 'package:akyl/domain/entities/intent.dart';
import 'package:akyl/domain/entities/nlu_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final nlu = RuleBasedNlu();

  Future<NluResult> parse(String text, [DialogContext? ctx]) =>
      nlu.parse(text, ctx ?? DialogContext());

  group('Намерение CALL (ТЗ, FR-3)', () {
    test('простая команда', () async {
      final r = await parse('позвони маме');
      expect(r.intent, Intent.call);
      expect(r.slot(Slot.contact), 'маме');
      expect(r.isConfident, isTrue);
    });

    for (final verb in ['позвони', 'набери', 'вызови', 'звони', 'позвонить']) {
      test('глагол «$verb»', () async {
        expect((await parse('$verb ахмеду')).intent, Intent.call);
      });
    }

    test('тип номера после предлога', () async {
      final r = await parse('набери ахмеда на рабочий');
      expect(r.slot(Slot.contact), 'ахмеда');
      expect(r.slot(Slot.phoneType), PhoneType.work.name);
    });

    test('домашний номер', () async {
      final r = await parse('позвони ольге на домашний');
      expect(r.slot(Slot.phoneType), PhoneType.home.name);
      expect(r.slot(Slot.contact), 'ольге');
    });

    test('служебные слова не попадают в имя', () async {
      final r = await parse('позвони пожалуйста срочно маме');
      expect(r.slot(Slot.contact), 'маме');
    });

    test('глагол без имени — низкая уверенность, а не выдумка', () async {
      final r = await parse('позвони');
      expect(r.intent, Intent.call);
      expect(r.isConfident, isFalse);
      expect(r.slot(Slot.contact), isNull);
    });

    test('имя не в начале фразы командой не считается', () async {
      expect((await parse('мама позвонила')).intent, Intent.unknown);
    });
  });

  group('Намерение SMS (ТЗ, FR-3)', () {
    test('с разделителем «что»', () async {
      final r = await parse('напиши мерет что я опаздываю');
      expect(r.intent, Intent.sms);
      expect(r.slot(Slot.contact), 'мерет');
      expect(r.slot(Slot.message), 'я опаздываю');
    });

    test('без разделителя: первое слово — имя', () async {
      final r = await parse('напиши маме буду поздно');
      expect(r.slot(Slot.contact), 'маме');
      expect(r.slot(Slot.message), 'буду поздно');
    });

    test('слово «смс» служебное', () async {
      final r = await parse('отправь смс маме что я в пути');
      expect(r.slot(Slot.contact), 'маме');
      expect(r.slot(Slot.message), 'я в пути');
    });

    test('«скажи X что Y» тоже SMS', () async {
      final r = await parse('скажи ахмеду что встреча в пять');
      expect(r.intent, Intent.sms);
      expect(r.slot(Slot.message), 'встреча в пять');
    });

    test('без текста сообщения — не команда SMS', () async {
      expect((await parse('напиши маме')).intent, Intent.unknown);
    });
  });

  group('Контекст диалога (ТЗ, FR-8)', () {
    const mama = Contact(
      id: '1',
      displayName: 'Мама',
      phones: [PhoneNumber(number: '+1', type: PhoneType.mobile)],
    );

    test('«позвони ему ещё раз» берёт имя из контекста', () async {
      final ctx = DialogContext()..rememberContact(mama);

      final r = await parse('позвони ему еще раз', ctx);

      expect(r.slot(Slot.contact), 'Мама');
      expect(r.isConfident, isTrue);
    });

    test('без контекста местоимение не разворачивается', () async {
      final r = await parse('позвони ему еще раз');
      expect(r.intent, Intent.call);
      expect(r.slot(Slot.contact), isNull);
      expect(r.isConfident, isFalse);
    });

    test('«напиши ей что опаздываю» берёт имя из контекста', () async {
      final ctx = DialogContext()..rememberContact(mama);

      final r = await parse('напиши ей что опаздываю', ctx);

      expect(r.intent, Intent.sms);
      expect(r.slot(Slot.contact), 'Мама');
      expect(r.slot(Slot.message), 'опаздываю');
    });
  });

  group('CONFIRM и CANCEL', () {
    DialogContext withPending() => DialogContext()
      ..awaitConfirmation(
        const NluResult(intent: Intent.sms, confidence: 0.95),
      );

    for (final word in ['да', 'ага', 'давай', 'отправь', 'хорошо']) {
      test('«$word» подтверждает', () async {
        expect((await parse(word, withPending())).intent, Intent.confirm);
      });
    }

    test('«да всё верно» тоже подтверждает', () async {
      expect((await parse('да все верно', withPending())).intent, Intent.confirm);
    });

    test('новая команда подтверждением не считается', () async {
      final r = await parse('отправь маме что я в пути', withPending());
      expect(r.intent, Intent.sms);
    });

    test('без отложенного действия «да» ничего не значит', () async {
      expect((await parse('да')).intent, Intent.unknown);
    });

    for (final word in ['отмена', 'стоп', 'нет', 'забудь']) {
      test('«$word» отменяет', () async {
        expect((await parse(word, withPending())).intent, Intent.cancel);
      });
    }

    test('отмена работает и без контекста (ТЗ, FR-9)', () async {
      expect((await parse('отмена')).intent, Intent.cancel);
    });
  });

  group('SELECT', () {
    DialogContext withChoices() => DialogContext()
      ..offerChoices([
        const ContactMatch(
          contact: Contact(id: '1', displayName: 'Ахмед Брат', phones: []),
          score: 0.97,
          matchedVia: MatchKind.exact,
        ),
      ]);

    test('порядковое числительное', () async {
      final r = await parse('первому', withChoices());
      expect(r.intent, Intent.select);
      expect(r.slot(Slot.choice), 'первому');
    });

    test('имя из списка', () async {
      expect((await parse('брату', withChoices())).intent, Intent.select);
    });

    test('новая команда во время выбора остаётся командой', () async {
      expect((await parse('позвони маме', withChoices())).intent, Intent.call);
    });

    test('без предложенных вариантов выбора нет', () async {
      expect((await parse('первому')).intent, Intent.unknown);
    });
  });

  group('UNKNOWN (ТЗ, сценарий С8)', () {
    for (final phrase in [
      'какая сегодня погода',
      'включи музыку',
      'привет',
      '',
    ]) {
      test('«$phrase» не команда', () async {
        expect((await parse(phrase)).intent, Intent.unknown);
      });
    }
  });

  group('Устойчивость к шуму STT (ТЗ, раздел 6)', () {
    test('текст без пунктуации и в нижнем регистре', () async {
      final r = await parse('ПОЗВОНИ, МАМЕ!');
      expect(r.intent, Intent.call);
      expect(r.slot(Slot.contact), 'маме');
    });

    test('лишние пробелы', () async {
      expect((await parse('  позвони   маме  ')).slot(Slot.contact), 'маме');
    });
  });
}
