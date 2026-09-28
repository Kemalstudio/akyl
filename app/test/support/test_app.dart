import 'dart:io';

import 'package:akyl/data/contacts/contact_index.dart';
import 'package:akyl/data/contacts/in_memory_contacts_source.dart';
import 'package:akyl/data/contacts/spoken_choice_resolver.dart';
import 'package:akyl/data/nlu/rule_based_nlu.dart';
import 'package:akyl/domain/dialog/dialog_machine.dart';
import 'package:akyl/presentation/assistant_controller.dart';
import 'package:akyl/presentation/theme/akyl_theme.dart';
import 'package:akyl/skills/call_skill.dart';
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
}) async {
  final p = phone ?? FakePhone();
  final index = ContactIndex(contacts ?? InMemoryContactsSource.demo());

  final machine = DialogMachine(
    nlu: RuleBasedNlu(),
    choiceResolver: const SpokenChoiceResolver(),
    skills: [
      CallSkill(resolver: index, phone: p),
      SmsSkill(resolver: index, phone: p),
    ],
  );

  final controller = AssistantController(
    machine: machine,
    resolver: index,
    tts: tts ?? FakeTts(),
    stt: stt ?? FakeStt(),
    phone: p,
  );
  await controller.init();
  return controller;
}

/// Оборачивает экран в тему приложения и фиксированный размер телефона.
///
/// Шрифт назначается явно: в приложении он системный, а системный шрифт
/// Android — Roboto. В тестовой среде «системного» шрифта нет, и без этой
/// строки весь текст на снимках превращается в прямоугольники.
Widget wrapForTest(Widget child, {Brightness brightness = Brightness.dark}) {
  final theme = brightness == Brightness.dark
      ? AkylTheme.dark()
      : AkylTheme.light();

  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: theme.copyWith(
      textTheme: theme.textTheme.apply(fontFamily: kTestFontFamily),
    ),
    home: child,
  );
}

/// Семейство, в которое загружаются настоящие шрифты для снимков.
const String kTestFontFamily = 'Roboto';

/// Типичный экран телефона среднего класса (ТЗ, раздел 3).
const Size kPhoneSurface = Size(390, 844);

Future<void> setPhoneSurface(WidgetTester tester) async {
  tester.view.physicalSize = kPhoneSurface * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Есть ли шрифты Flutter SDK на этой машине. Проверка синхронная: `skip:`
/// у теста вычисляется при сборке списка тестов, до setUpAll.
bool get materialFontsAvailable => _materialFontsDir() != null;

/// Подключает настоящие шрифты вместо тестовой заглушки.
///
/// Без этого golden-снимки получаются с чёрными прямоугольниками вместо букв и
/// проверить по ним вёрстку нельзя. Шрифты берутся из кэша Flutter SDK — он
/// есть и на машине разработчика, и на CI, поэтому файлы не тащатся в репозиторий.
Future<bool> loadRealFonts() async {
  final dir = _materialFontsDir();
  if (dir == null) return false;

  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final name in files) {
      final file = File('${dir.path}${Platform.pathSeparator}$name');
      if (!file.existsSync()) continue;
      loader.addFont(file.readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  }

  await load(kTestFontFamily, [
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
  ]);
  await load('MaterialIcons', ['materialicons-regular.otf']);
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
