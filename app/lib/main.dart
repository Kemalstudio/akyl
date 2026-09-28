import 'package:flutter/material.dart';

import 'data/contacts/contact_index.dart';
import 'data/contacts/device_contacts_source.dart';
import 'data/contacts/spoken_choice_resolver.dart';
import 'data/nlu/rule_based_nlu.dart';
import 'data/phone/phone_bridge.dart';
import 'data/stt/device_speech_stt.dart';
import 'data/tts/system_tts.dart';
import 'domain/dialog/dialog_machine.dart';
import 'presentation/assistant_controller.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/screens/welcome_screen.dart';
import 'presentation/theme/akyl_motion.dart';
import 'presentation/theme/akyl_theme.dart';
import 'presentation/widgets/akyl_mark.dart';
import 'skills/call_skill.dart';
import 'skills/sms_skill.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(AkylApp(controller: buildController()));
}

/// Сборка зависимостей в одном месте: заменить RuleBasedNlu на MlNlu (этап 3)
/// или ManualTextStt на TOneStt (этап 2) — это правка здесь, а не в ядре
/// (ТЗ, раздел 5: Strategy).
AssistantController buildController() {
  const phone = PhoneBridge();
  final resolver = ContactIndex(const DeviceContactsSource());

  final machine = DialogMachine(
    nlu: RuleBasedNlu(),
    choiceResolver: const SpokenChoiceResolver(),
    skills: [
      CallSkill(resolver: resolver, phone: phone),
      SmsSkill(resolver: resolver, phone: phone),
    ],
  );

  return AssistantController(
    machine: machine,
    resolver: resolver,
    tts: SystemTts(),
    stt: DeviceSpeechStt(),
    phone: phone,
  );
}

class AkylApp extends StatelessWidget {
  const AkylApp({super.key, required this.controller});

  final AssistantController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Akyl',
      debugShowCheckedModeBanner: false,
      theme: AkylTheme.light(),
      darkTheme: AkylTheme.dark(),
      // Тёмная тема по умолчанию: ассистентом пользуются на ходу и часто
      // в темноте, а заставка Android тоже тёмная — светлая вспышка между
      // ними выглядела бы сбоем.
      themeMode: ThemeMode.dark,
      home: AkylRoot(controller: controller),
    );
  }
}

/// Решает, показать приветствие или сразу разговор.
class AkylRoot extends StatefulWidget {
  const AkylRoot({super.key, required this.controller});

  final AssistantController controller;

  @override
  State<AkylRoot> createState() => _AkylRootState();
}

class _AkylRootState extends State<AkylRoot> {
  /// Пользователь прошёл экран входа в этом запуске.
  bool _passedWelcome = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    widget.controller.init();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;

    // Пока идёт проверка разрешений, держим тот же кадр, что и заставка
    // Android: знак на фирменном фоне. Переход не должен мигать.
    final Widget screen;
    if (!controller.ready) {
      screen = const _SplashHold(key: ValueKey('splash'));
    } else if (controller.permissionsGranted || _passedWelcome) {
      screen = HomeScreen(key: const ValueKey('home'), controller: controller);
    } else {
      screen = WelcomeScreen(
        key: const ValueKey('welcome'),
        controller: controller,
        onReady: () => setState(() => _passedWelcome = true),
      );
    }

    // Экран не подменяется кадром: уходящий гаснет, приходящий проявляется
    // и чуть приближается. Заставка Android, знак и первый экран читаются
    // как одно непрерывное движение.
    return AnimatedSwitcher(
      duration: AkylMotion.slow,
      switchInCurve: AkylMotion.enter,
      switchOutCurve: AkylMotion.exit,
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.985, end: 1).animate(animation),
          child: child,
        ),
      ),
      child: screen,
    );
  }
}

class _SplashHold extends StatelessWidget {
  const _SplashHold({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FadeSlideIn(
          duration: AkylMotion.slow,
          offset: 0,
          child: AkylMark(size: 64, color: context.akyl.textPrimary),
        ),
      ),
    );
  }
}
