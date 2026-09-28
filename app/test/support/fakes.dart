import 'package:akyl/data/contacts/contact_index.dart';
import 'package:akyl/data/contacts/in_memory_contacts_source.dart';
import 'package:akyl/data/contacts/spoken_choice_resolver.dart';
import 'package:akyl/data/nlu/rule_based_nlu.dart';
import 'package:akyl/domain/dialog/dialog_machine.dart';
import 'package:akyl/domain/ports/phone.dart';
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
  Future<void> stop() async {}
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
