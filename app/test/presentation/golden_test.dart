import 'package:akyl/data/contacts/in_memory_contacts_source.dart';
import 'package:akyl/presentation/screens/assistant_settings.dart';
import 'package:akyl/presentation/screens/home_screen.dart';
import 'package:akyl/presentation/screens/voice_settings_screen.dart';
import 'package:akyl/presentation/voice_manager.dart';
import 'package:akyl/presentation/screens/welcome_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/test_app.dart';

/// Снимки экранов. Обновляются командой:
///
///     flutter test --update-goldens test/presentation/golden_test.dart
///
/// Ловят то, чего не видит ни один unit-тест: съехавшую вёрстку, потерянный
/// контраст, обрезанный текст. Шрифты берутся из кэша Flutter SDK; если его
/// нет, тесты пропускаются, а не падают.
void main() {
  final fonts = materialFontsAvailable;

  setUpAll(() async {
    if (fonts) await loadRealFonts();
  });

  Future<void> snapshot(
    WidgetTester tester,
    Widget screen,
    String name, {
    Brightness brightness = Brightness.dark,
    bool settle = true,
    Duration wait = const Duration(milliseconds: 350),
  }) async {
    await setPhoneSurface(tester);
    await tester.pumpWidget(wrapForTest(screen, brightness: brightness));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      // Пока идёт запись, кольцо вокруг кнопки пульсирует без конца —
      // pumpAndSettle такого не дождётся. Останавливаем кадр вручную.
      await tester.pump(wait);
    }
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  testWidgets('Экран входа', (tester) async {
    final controller = await buildTestController(
      phone: FakePhone(permissionsGranted: false),
    );
    await snapshot(
      tester,
      WelcomeScreen(controller: controller, onReady: () {}),
      'welcome',
    );
  }, skip: !fonts);

  testWidgets('Пустой разговор', (tester) async {
    final controller = await buildTestController();
    await snapshot(tester, HomeScreen(controller: controller), 'home_empty');
  }, skip: !fonts);

  testWidgets('Пустой разговор, светлая тема', (tester) async {
    final controller = await buildTestController();
    await snapshot(
      tester,
      HomeScreen(controller: controller),
      'home_empty_light',
      brightness: Brightness.light,
    );
  }, skip: !fonts);

  testWidgets('Разговор: звонок, уточнение, SMS', (tester) async {
    final controller = await buildTestController(
      contacts: InMemoryContactsSource.twoAhmeds(),
    );
    await controller.submit('позвони маме');
    await controller.submit('позвони ахмеду');
    await controller.submit('брату');

    await snapshot(tester, HomeScreen(controller: controller), 'home_dialog');
  }, skip: !fonts);

  testWidgets('Ожидание подтверждения SMS', (tester) async {
    final controller = await buildTestController();
    await controller.submit('напиши мерет что я опаздываю');

    await snapshot(tester, HomeScreen(controller: controller), 'home_confirm');
  }, skip: !fonts);

  testWidgets('Настройки помощника', (tester) async {
    final controller = await buildTestController();
    await snapshot(
      tester,
      AssistantSettings(controller: controller),
      'settings',
    );
  }, skip: !fonts);

  testWidgets('Простой режим для родителей', (tester) async {
    final controller = await buildTestController(simpleMode: true);
    await controller.rememberRelationship('мама', '1');
    await controller.rememberRelationship('брат', '3');
    await snapshot(tester, HomeScreen(controller: controller), 'home_simple');
  }, skip: !fonts);

  testWidgets('Голос и обращение', (tester) async {
    final controller = await buildTestController(
      pipeline: FakePipeline(),
      settings: const VoiceSettings(wakeEnabled: true, background: true),
    );
    await snapshot(
      tester,
      VoiceSettingsScreen(voice: controller.voice),
      'voice_settings',
      settle: false,
      wait: const Duration(milliseconds: 1500),
    );
    // Таймер «микрофон стабилен» живёт 20 с — освобождаем голос сами.
    controller.dispose();
    await tester.pump(const Duration(seconds: 1));
  }, skip: !fonts);

  testWidgets('Обращение включается одним касанием', (tester) async {
    final controller = await buildTestController(pipeline: FakePipeline());
    await snapshot(tester, HomeScreen(controller: controller), 'home_wake_off');
  }, skip: !fonts);
}
