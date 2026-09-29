import 'dart:io';

import 'package:akyl/data/contacts/contact_index.dart';
import 'package:akyl/data/contacts/in_memory_contacts_source.dart';
import 'package:akyl/data/contacts/spoken_choice_resolver.dart';
import 'package:akyl/data/nlu/rule_based_nlu.dart';
import 'package:akyl/domain/dialog/dialog_machine.dart';
import 'package:akyl/presentation/assistant_controller.dart';
import 'package:akyl/presentation/theme/akyl_theme.dart';
import 'package:akyl/skills/call_skill.dart';
import 'package:akyl/skills/device_skills.dart';
import 'package:akyl/skills/sms_skill.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

/// Собранный контроллер поверх поддельного телефона — для тестов экрана.
Future<AssistantController> buildTestController({
  InMemoryContactsSource? contacts,
  FakePhone? phone,
  FakeTts? tts,
  FakeStt? stt,
  FakeConversationStore? store,
  bool wakeWord = false,
  bool simpleMode = false,
}) async {
  final p = phone ?? FakePhone();
  final index = ContactIndex(contacts ?? InMemoryContactsSource.demo());

  final machine = DialogMachine(
    nlu: RuleBasedNlu(),
    choiceResolver: const SpokenChoiceResolver(),
    skills: [
      CallSkill(resolver: index, phone: p),
      SmsSkill(resolver: index, phone: p),
      TimeSkill(clock: () => DateTime(2026, 9, 28, 16, 45)),
      SmallTalkSkill(),
      DateSkill(clock: () => DateTime(2026, 9, 28, 16, 45)),
      BatterySkill(device: FakeDeviceInfo()),
    ],
  );

  final controller = AssistantController(
    machine: machine,
    resolver: index,
    tts: tts ?? FakeTts(),
    stt: stt ?? FakeStt(),
    phone: p,
    store: store ?? FakeConversationStore(),
    wakeWordEnabled: wakeWord,
    simpleMode: simpleMode,
  );
  await controller.init();
  return controller;
}

/// Оборачивает экран в тему приложения и фиксированный размер телефона.
///
/// Шрифт не подменяется: Nunito лежит в ассетах и грузится в тест как есть,
/// поэтому снимки показывают ровно ту типографику, что и приложение.
Widget wrapForTest(Widget child, {Brightness brightness = Brightness.dark}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: brightness == Brightness.dark ? AkylTheme.dark() : AkylTheme.light(),
    home: child,
  );
}

/// Типичный экран телефона среднего класса (ТЗ, раздел 3).
const Size kPhoneSurface = Size(390, 844);

Future<void> setPhoneSurface(WidgetTester tester) async {
  tester.view.physicalSize = kPhoneSurface * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Есть ли шрифт значков Flutter SDK на этой машине. Проверка синхронная:
/// `skip:` у теста вычисляется при сборке списка тестов, до setUpAll.
bool get materialFontsAvailable => _materialFontsDir() != null;

/// Подключает настоящие шрифты вместо тестовой заглушки.
///
/// Без этого golden-снимки получаются с чёрными прямоугольниками вместо букв.
/// Nunito берётся из ассетов приложения — он и так едет в APK. Шрифт значков
/// Material в ассетах не лежит, поэтому его приходится брать из кэша Flutter
/// SDK: он есть и на машине разработчика, и на CI.
Future<bool> loadRealFonts() async {
  final nunito = FontLoader(AkylTheme.fontFamily);
  for (final weight in const [300, 400, 500, 600, 700, 800]) {
    nunito.addFont(rootBundle.load('assets/fonts/Nunito-$weight.ttf'));
  }
  await nunito.load();

  // Значки Lucide приезжают шрифтом из пакета, он есть в ассетах.
  final lucide = FontLoader('packages/lucide_icons_flutter/Lucide');
  lucide.addFont(
    rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
  );
  await lucide.load();

  final dir = _materialFontsDir();
  if (dir == null) return false;

  final icons = FontLoader('MaterialIcons');
  final file = File(
    '${dir.path}${Platform.pathSeparator}materialicons-regular.otf',
  );
  if (!file.existsSync()) return false;
  icons.addFont(file.readAsBytes().then(ByteData.sublistView));
  await icons.load();
  return true;
}

/// bin/cache/dart-sdk/bin/dart -> bin/cache/artifacts/material_fonts
Directory? _materialFontsDir() {
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 6; i++) {
    final candidate = Directory(
      '${dir.path}${Platform.pathSeparator}artifacts'
      '${Platform.pathSeparator}material_fonts',
    );
    if (candidate.existsSync()) return candidate;
    if (dir.parent.path == dir.path) break;
    dir = dir.parent;
  }
  return null;
}
