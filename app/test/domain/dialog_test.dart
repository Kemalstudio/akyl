import 'package:akyl/domain/dialog/dialog_state.dart';
import 'package:akyl/domain/entities/contact.dart';
import 'package:akyl/domain/entities/dialog_context.dart';
import 'package:akyl/domain/entities/intent.dart';
import 'package:akyl/domain/entities/nlu_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const mama = Contact(
    id: '1',
    displayName: 'Мама',
    phones: [PhoneNumber(number: '+1', type: PhoneType.mobile)],
  );

  group('Контекст живёт 60 секунд (ТЗ, FR-8)', () {
    /// Часы, которыми управляет тест: ждать минуту в тестах нельзя.
    late DateTime now;
    DialogContext build() => DialogContext(clock: () => now);

    setUp(() => now = DateTime(2026, 9, 28, 12, 0, 0));

    test('сразу после команды контакт доступен', () {
      final ctx = build()..rememberContact(mama);
      expect(ctx.lastContact, mama);
      expect(ctx.isAlive, isTrue);
    });

    test('через 59 секунд ещё доступен', () {
      final ctx = build()..rememberContact(mama);
      now = now.add(const Duration(seconds: 59));
      expect(ctx.lastContact, mama);
    });

    test('через 61 секунду контекст истёк', () {
      final ctx = build()..rememberContact(mama);
      now = now.add(const Duration(seconds: 61));
      expect(ctx.lastContact, isNull);
      expect(ctx.isAlive, isFalse);
    });

    test('истёкшее подтверждение не сработает', () {
      final ctx = build()
        ..awaitConfirmation(const NluResult(intent: Intent.sms, confidence: 0.95));
      now = now.add(const Duration(seconds: 61));
      expect(ctx.pendingAction, isNull);
    });

    test('истёкшие варианты выбора исчезают', () {
      final ctx = build()
        ..offerChoices([
          const ContactMatch(contact: mama, score: 1, matchedVia: MatchKind.exact),
        ]);
      now = now.add(const Duration(seconds: 61));
      expect(ctx.choices, isEmpty);
    });

    test('новая команда продлевает контекст', () {
      final ctx = build()..rememberContact(mama);
      now = now.add(const Duration(seconds: 50));
      ctx.rememberContact(mama);
      now = now.add(const Duration(seconds: 50));
      expect(ctx.lastContact, mama);
    });

    test('reset очищает всё', () {
      final ctx = build()
        ..rememberContact(mama)
        ..awaitConfirmation(const NluResult(intent: Intent.sms, confidence: 0.9))
        ..reset();
      expect(ctx.lastContact, isNull);
      expect(ctx.pendingAction, isNull);
      expect(ctx.isAlive, isFalse);
    });

    test('clearPending не забывает собеседника', () {
      final ctx = build()
        ..rememberContact(mama)
        ..awaitConfirmation(const NluResult(intent: Intent.sms, confidence: 0.9))
        ..clearPending();
      expect(ctx.pendingAction, isNull);
      expect(ctx.lastContact, mama); // «позвони ему ещё раз» должно работать
    });
  });

  group('Конечный автомат (ТЗ, раздел 5)', () {
    test('обычный путь команды', () {
      expect(DialogState.idle.canGoTo(DialogState.listening), isTrue);
      expect(DialogState.listening.canGoTo(DialogState.processing), isTrue);
      expect(DialogState.processing.canGoTo(DialogState.executing), isTrue);
      expect(DialogState.executing.canGoTo(DialogState.idle), isTrue);
    });

    test('путь с уточнением', () {
      expect(DialogState.executing.canGoTo(DialogState.awaitingChoice), isTrue);
      expect(DialogState.awaitingChoice.canGoTo(DialogState.processing), isTrue);
    });

    test('недопустимые переходы закрыты', () {
      expect(DialogState.idle.canGoTo(DialogState.executing), isFalse);
      expect(DialogState.listening.canGoTo(DialogState.executing), isFalse);
      expect(DialogState.executing.canGoTo(DialogState.listening), isFalse);
    });

    test('состояния ожидания ответа помечены', () {
      expect(DialogState.awaitingConfirmation.isAwaiting, isTrue);
      expect(DialogState.awaitingChoice.isAwaiting, isTrue);
      expect(DialogState.processing.isAwaiting, isFalse);
    });
  });

  group('Порог уверенности (ТЗ, FR-6)', () {
    test('0.85 и выше — действуем', () {
      expect(const NluResult(intent: Intent.call, confidence: 0.85).isConfident,
          isTrue);
    });

    test('ниже 0.85 — уточняем', () {
      expect(const NluResult(intent: Intent.call, confidence: 0.84).isConfident,
          isFalse);
    });
  });
}
