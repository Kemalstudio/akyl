import 'package:akyl/data/contacts/contact_index.dart';
import 'package:akyl/data/contacts/in_memory_contacts_source.dart';
import 'package:akyl/data/contacts/spoken_choice_resolver.dart';
import 'package:akyl/data/nlu/rule_based_nlu.dart';
import 'package:akyl/domain/dialog/dialog_machine.dart';
import 'dart:async';

import 'package:akyl/domain/ports/phone.dart';
import 'package:akyl/domain/ports/speech_to_text.dart';
import 'package:akyl/domain/ports/text_to_speech.dart';
import 'package:akyl/skills/call_skill.dart';
import 'package:akyl/skills/sms_skill.dart';

/// Телефон, который ничего не делает, но помнит, о чём его просили.
class FakePhone implements Phone {
  FakePhone({this.permissionsGranted = true});

  bool permissionsGranted;

  final List<String> calls = [];
  final List<({String number, String text})> sentSms = [];

  /// Была ли включена громкая связь на последнем звонке.
  bool lastCallOnSpeaker = false;

  String? get lastCall => calls.isEmpty ? null : calls.last;

  @override
  Future<bool> hasPermissions() async => permissionsGranted;

  @override
  Future<bool> requestPermissions() async => permissionsGranted;

  @override
  Future<void> call(String number, {bool speaker = false}) async {
    calls.add(number);
    lastCallOnSpeaker = speaker;
  }

  @override
  Future<void> sendSms({required String number, required String text}) async =>
      sentSms.add((number: number, text: text));
}

/// Микрофон, которым управляет тест: [emitPartial] печатает текст «по слогам»,
/// [finish] закрывает фразу — как это делает настоящий движок.
class FakeStt implements SpeechToText {
  FakeStt({this.failOnInit = false, this.scripted});

  /// Движок не запускается — проверка, что приложение это переживает.
  final bool failOnInit;

  /// Что «услышать» автоматически при start(). null — тест управляет вручную.
  final String? scripted;

  final _partial = StreamController<String>.broadcast();

  /// Как и в настоящей реализации, ожидание переживает своё завершение:
  /// результат может прийти раньше, чем его спросят.
  Completer<String>? _pending;
  bool _active = false;

  bool initialized = false;
  int startCount = 0;
  bool stopped = false;
  bool disposed = false;

  @override
  Future<void> init() async {
    if (failOnInit) throw StateError('нет офлайн-движка');
    initialized = true;
  }

  @override
  Stream<String> partialResults() => _partial.stream;

  @override
  Future<void> start() async {
    if (_active) return;
    startCount++;
    _active = true;
    _pending = Completer<String>();
    final text = scripted;
    if (text != null) {
      emitPartial(text);
      finish(text);
    }
  }

  @override
  Future<String> finalResult() => _pending?.future ?? Future.value('');

  @override
  Future<void> stop() async {
    stopped = true;
    finish('');
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    if (!_partial.isClosed) await _partial.close();
  }

  void emitPartial(String text) {
    if (!_partial.isClosed) _partial.add(text);
  }

  void finish(String text) {
    _active = false;
    final pending = _pending;
    if (pending == null || pending.isCompleted) return;
    pending.complete(text);
  }
}

class FakeTts implements TextToSpeech {
  final List<String> spoken = [];
  bool _enabled = true;

  @override
  bool get enabled => _enabled;

  @override
  set enabled(bool value) => _enabled = value;

  @override
  Future<void> init() async {}

  @override
  Future<void> speak(String text) async {
    if (_enabled) spoken.add(text);
  }

  @override
  Future<void> stop() async => stopCount++;

  int stopCount = 0;
}

/// Собранный ассистент этапа 1 — всё настоящее, кроме телефона.
class TestAssistant {
  TestAssistant._(this.machine, this.phone, this.index);

  final DialogMachine machine;
  final FakePhone phone;
  final ContactIndex index;

  static Future<TestAssistant> build({
    InMemoryContactsSource? contacts,
    FakePhone? phone,
  }) async {
    final book = contacts ?? InMemoryContactsSource.demo();
    final p = phone ?? FakePhone();
    final index = ContactIndex(book);
    await index.buildIndex();

    final machine = DialogMachine(
      nlu: RuleBasedNlu(),
      choiceResolver: const SpokenChoiceResolver(),
      skills: [
        CallSkill(resolver: index, phone: p),
        SmsSkill(resolver: index, phone: p),
      ],
    );
    return TestAssistant._(machine, p, index);
  }

  Future<DialogTurn> say(String phrase) => machine.handle(phrase);
}
