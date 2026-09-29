import 'package:akyl/data/contacts/contact_index.dart';
import 'package:akyl/data/contacts/in_memory_contacts_source.dart';
import 'package:akyl/data/contacts/spoken_choice_resolver.dart';
import 'package:akyl/data/nlu/rule_based_nlu.dart';
import 'package:akyl/domain/dialog/dialog_machine.dart';
import 'dart:async';

import 'package:akyl/domain/entities/conversation.dart';
import 'package:akyl/domain/ports/device_control.dart';
import 'package:akyl/domain/ports/life_ports.dart';
import 'package:akyl/domain/ports/conversation_store.dart';
import 'package:akyl/domain/ports/device_info.dart';
import 'package:akyl/domain/ports/phone.dart';
import 'package:akyl/domain/ports/speech_to_text.dart';
import 'package:akyl/domain/ports/text_to_speech.dart';
import 'package:akyl/skills/call_skill.dart';
import 'package:akyl/skills/device_skills.dart';
import 'package:akyl/skills/life_skills.dart';
import 'package:akyl/skills/phone_control_skills.dart';
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
  int wakeStartCount = 0;
  bool stopped = false;
  bool disposed = false;

  @override
  Future<void> init() async {
    if (failOnInit) throw StateError('нет офлайн-движка');
    initialized = true;
  }

  @override
  Stream<String> partialResults() => _partial.stream;

  final _levels = StreamController<double>.broadcast();

  @override
  Stream<double> soundLevels() => _levels.stream;

  void emitLevel(double level) => _levels.add(level);

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
  Future<void> startWake() async {
    wakeStartCount++;
    await start();
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
  TestAssistant._(
    this.machine,
    this.phone,
    this.index,
    this.device,
    this.memory,
    this.reminders,
  );

  final DialogMachine machine;
  final FakePhone phone;
  final ContactIndex index;
  final FakeDeviceControl device;
  final FakeMemoryStore memory;
  final FakeReminders reminders;

  /// Часы тестов: 28 сентября 2026, 16:45.
  static DateTime now() => DateTime(2026, 9, 28, 16, 45);

  static Future<TestAssistant> build({
    InMemoryContactsSource? contacts,
    FakePhone? phone,
  }) async {
    final book = contacts ?? InMemoryContactsSource.demo();
    final p = phone ?? FakePhone();
    final device = FakeDeviceControl();
    final memory = FakeMemoryStore();
    final reminders = FakeReminders();
    final index = ContactIndex(book);
    await index.buildIndex();

    final machine = DialogMachine(
      nlu: RuleBasedNlu(),
      choiceResolver: const SpokenChoiceResolver(),
      skills: [
        CallSkill(resolver: index, phone: p),
        SmallTalkSkill(),
        SmsSkill(resolver: index, phone: p),
        // Часы зафиксированы: ответ про время должен быть проверяемым.
        TimeSkill(clock: () => DateTime(2026, 9, 28, 16, 45)),
        DateSkill(clock: () => DateTime(2026, 9, 28, 16, 45)),
        BatterySkill(device: FakeDeviceInfo()),
        AlarmSkill(device: device),
        TimerSkill(device: device),
        FlashlightSkill(device: device),
        VolumeSkill(device: device),
        ReadSmsSkill(device: device),
        RecentCallsSkill(device: device),
        OpenAppSkill(device: device),
        RememberSkill(store: memory, clock: now),
        RecallSkill(store: memory, clock: now),
        ForgetSkill(store: memory),
        LastCallSkill(resolver: index, device: device, clock: now),
        RemindSkill(scheduler: reminders, clock: now),
        ListRemindersSkill(scheduler: reminders, clock: now),
        CancelReminderSkill(scheduler: reminders),
        SosSkill(
          phone: p,
          device: device,
          relatives: () async => index.relatives,
        ),
      ],
    );
    return TestAssistant._(machine, p, index, device, memory, reminders);
  }

  Future<DialogTurn> say(String phrase) => machine.handle(phrase);
}

/// История в памяти: тест видит, что и когда сохранилось.
class FakeConversationStore implements ConversationStore {
  FakeConversationStore([List<Conversation>? initial]) : stored = initial ?? [];

  List<Conversation> stored;
  int saveCount = 0;
  bool cleared = false;

  @override
  Future<List<Conversation>> load() async => List.of(stored);

  @override
  Future<void> save(List<Conversation> conversations) async {
    stored = List.of(conversations);
    saveCount++;
  }

  @override
  Future<void> clear() async {
    stored = [];
    cleared = true;
  }
}

/// Телефон, который всегда отвечает одинаково.
class FakeDeviceInfo implements DeviceInfo {
  FakeDeviceInfo({this.level = 73, this.charging = false});

  final int? level;
  final bool charging;

  @override
  Future<int?> batteryLevel() async => level;

  @override
  Future<bool> isCharging() async => charging;
}

/// Телефон, которым «управляют» в тестах: запоминает, что его попросили.
class FakeDeviceControl implements DeviceControl {
  final List<String> actions = [];
  ({String from, String body})? sms = (from: 'Мама', body: 'Позвони мне');
  List<({String name, String type})> calls = [
    (name: 'Мама', type: 'missed'),
    (name: 'Ахмед', type: 'incoming'),
  ];

  @override
  Future<void> setAlarm(int hour, int minute) async =>
      actions.add('alarm $hour:$minute');

  @override
  Future<void> setTimer(int seconds) async => actions.add('timer $seconds');

  @override
  Future<void> setTorch(bool on) async => actions.add('torch $on');

  @override
  Future<void> changeVolume(String change) async =>
      actions.add('volume $change');

  @override
  Future<({String from, String body})?> lastSms() async => sms;

  @override
  Future<List<({String name, String type})>> recentCalls({
    int limit = 3,
  }) async => calls;

  ({DateTime at, String type})? lastCall;
  ({double lat, double lon})? place = (lat: 37.95, lon: 58.38);

  @override
  Future<({DateTime at, String type})?> lastCallWith(
    List<String> numbers,
  ) async => lastCall;

  @override
  Future<({double lat, double lon})?> location() async => place;

  @override
  Future<String?> openApp(String spokenName) async {
    actions.add('open $spokenName');
    return spokenName.startsWith('whatsapp') ? 'WhatsApp' : null;
  }
}

class FakeMemoryStore implements MemoryStore {
  List<MemoryNote> notes = [];

  @override
  Future<List<MemoryNote>> load() async => List.of(notes);

  @override
  Future<void> save(List<MemoryNote> list) async => notes = List.of(list);
}

class FakeReminders implements ReminderScheduler {
  final Map<int, Reminder> scheduled = {};

  @override
  Future<void> schedule(Reminder reminder) async =>
      scheduled[reminder.id] = reminder;

  @override
  Future<void> cancel(int id) async => scheduled.remove(id);

  @override
  Future<List<Reminder>> list() async =>
      scheduled.values.toList()..sort((a, b) => a.at.compareTo(b.at));
}
