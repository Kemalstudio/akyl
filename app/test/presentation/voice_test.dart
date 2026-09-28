import 'package:akyl/domain/dialog/dialog_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/test_app.dart';

/// Голосовой путь: от нажатия на микрофон до выполненной команды.
void main() {
  group('Запись команды голосом', () {
    test('распознанная фраза выполняется', () async {
      final stt = FakeStt(scripted: 'позвони маме');
      final phone = FakePhone();
      final c = await buildTestController(stt: stt, phone: phone);

      await c.listen();

      expect(stt.startCount, 1);
      expect(phone.lastCall, '+99361000001');
      expect(c.history.first.text, 'позвони маме');
      expect(c.history.last.text, 'Звоню Маме');
      expect(c.listening, isFalse);
    });

    test('текст показывается во время речи (ТЗ, FR-2)', () async {
      final stt = FakeStt();
      final c = await buildTestController(stt: stt);

      final session = c.listen();
      await Future<void>.delayed(Duration.zero);

      expect(c.listening, isTrue);
      expect(c.state, DialogState.listening);

      stt.emitPartial('позвони');
      await Future<void>.delayed(Duration.zero);
      expect(c.partialText, 'позвони');

      stt.emitPartial('позвони маме');
      await Future<void>.delayed(Duration.zero);
      expect(c.partialText, 'позвони маме');

      stt.finish('позвони маме');
      await session;

      // После выполнения промежуточный текст убирается — он уже в истории.
      expect(c.partialText, isEmpty);
      expect(c.listening, isFalse);
    });

    test('тишина не создаёт запись в истории', () async {
      final stt = FakeStt(scripted: '');
      final c = await buildTestController(stt: stt);

      await c.listen();

      expect(c.history, isEmpty);
      expect(c.state, DialogState.idle);
      expect(c.listening, isFalse);
    });

    test('остановка записи ничего не выполняет', () async {
      final stt = FakeStt();
      final phone = FakePhone();
      final c = await buildTestController(stt: stt, phone: phone);

      final session = c.listen();
      await Future<void>.delayed(Duration.zero);
      stt.emitPartial('позвони маме');
      await c.stopListening();
      await session;

      expect(stt.stopped, isTrue);
      expect(phone.calls, isEmpty);
      expect(c.history, isEmpty);
      expect(c.state, DialogState.idle);
    });

    test('повторное нажатие во время записи ничего не ломает', () async {
      final stt = FakeStt();
      final c = await buildTestController(stt: stt);

      final session = c.listen();
      await Future<void>.delayed(Duration.zero);
      await c.listen();

      expect(stt.startCount, 1);

      stt.finish('');
      await session;
    });

    test('ассистент замолкает, когда начинает слушать', () async {
      final stt = FakeStt(scripted: 'позвони маме');
      final tts = FakeTts();
      final c = await buildTestController(stt: stt, tts: tts);

      await c.listen();

      // Иначе микрофон услышит собственный голос ассистента.
      expect(tts.stopCount, greaterThan(0));
    });
  });

  group('Когда распознавание недоступно', () {
    test('приложение запускается и предупреждает', () async {
      final c = await buildTestController(stt: FakeStt(failOnInit: true));

      expect(c.voiceAvailable, isFalse);
      expect(c.warning, contains('Голос недоступен'));
    });

    test('команду всё ещё можно набрать текстом', () async {
      final phone = FakePhone();
      final c = await buildTestController(
        stt: FakeStt(failOnInit: true),
        phone: phone,
      );

      await c.submit('позвони маме');

      expect(phone.lastCall, '+99361000001');
    });

    test('нажатие на микрофон не роняет приложение', () async {
      final c = await buildTestController(stt: FakeStt(failOnInit: true));

      await c.listen();

      expect(c.listening, isFalse);
      expect(c.warning, isNotNull);
    });
  });
}
