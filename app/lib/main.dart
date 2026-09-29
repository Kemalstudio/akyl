import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/contacts/contact_index.dart';
import 'data/contacts/preferences_alias_store.dart';
import 'data/phone/hands_free_bridge.dart';
import 'data/contacts/device_contacts_source.dart';
import 'data/contacts/spoken_choice_resolver.dart';
import 'data/history/file_conversation_store.dart';
import 'data/nlu/rule_based_nlu.dart';
import 'data/history/file_memory_store.dart';
import 'data/phone/care_bridge.dart';
import 'data/phone/device_control_bridge.dart';
import 'data/phone/device_info_bridge.dart';
import 'data/phone/phone_bridge.dart';
import 'data/stt/device_speech_stt.dart';
import 'data/stt/tone_stt.dart';
import 'data/tts/system_tts.dart';
import 'domain/dialog/dialog_machine.dart';
import 'presentation/assistant_controller.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/screens/welcome_screen.dart';
import 'presentation/theme/akyl_motion.dart';
import 'presentation/theme/akyl_theme.dart';
import 'presentation/widgets/akyl_mark.dart';
import 'skills/call_skill.dart';
import 'skills/device_skills.dart';
import 'skills/life_skills.dart';
import 'skills/phone_control_skills.dart';
import 'skills/sms_skill.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(AkylApp(controller: buildController(prefs)));
}

const _wakeWordKey = 'wake_word_in_app';
const _simpleModeKey = 'simple_mode';

/// Сборка зависимостей в одном месте: заменить RuleBasedNlu на MlNlu (этап 3)
/// или ManualTextStt на TOneStt (этап 2) — это правка здесь, а не в ядре
/// (ТЗ, раздел 5: Strategy).
AssistantController buildController(SharedPreferences prefs) {
  const phone = PhoneBridge();
  const control = DeviceControlBridge();
  const care = CareBridge();
  final memory = FileMemoryStore();
  final tts = SystemTts();
  final resolver = ContactIndex(
    const DeviceContactsSource(),
    aliasStore: PreferencesAliasStore(),
  );

  final machine = DialogMachine(
    nlu: RuleBasedNlu(),
    choiceResolver: const SpokenChoiceResolver(),
    skills: [
      CallSkill(resolver: resolver, phone: phone, beforeCall: tts.speak),
      SmsSkill(resolver: resolver, phone: phone),
      TimeSkill(),
      SmallTalkSkill(),
      DateSkill(),
      BatterySkill(device: const DeviceInfoBridge()),
      AlarmSkill(device: control),
      TimerSkill(device: control),
      FlashlightSkill(device: control),
      VolumeSkill(device: control),
      ReadSmsSkill(device: control),
      RecentCallsSkill(device: control),
      OpenAppSkill(device: control),
      RememberSkill(store: memory),
      RecallSkill(store: memory),
      ForgetSkill(store: memory),
      LastCallSkill(resolver: resolver, device: control),
      RemindSkill(scheduler: care),
      ListRemindersSkill(scheduler: care),
      CancelReminderSkill(scheduler: care),
      SosSkill(
        phone: phone,
        device: control,
        relatives: () async => resolver.relatives,
      ),
    ],
  );

  return AssistantController(
    machine: machine,
    resolver: resolver,
    tts: tts,
    // Своя T-one в процессе приложения; если не поднялась — системное
    // распознавание Android.
    stt: FallbackStt(ToneStt(), DeviceSpeechStt()),
    phone: phone,
    store: FileConversationStore(),
    handsFree: HandsFreeBridge(),
    // Микрофон включается только после явного выбора пользователя.
    wakeWordEnabled: prefs.getBool(_wakeWordKey) ?? false,
    onWakeWordChanged: (value) => prefs.setBool(_wakeWordKey, value),
    care: care,
    simpleMode: prefs.getBool(_simpleModeKey) ?? false,
    onSimpleModeChanged: (value) => prefs.setBool(_simpleModeKey, value),
  );
}

class AkylApp extends StatelessWidget {
  const AkylApp({super.key, required this.controller});

  final AssistantController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AkylWordmark.appName,
      // Простой режим: всё на пятую часть крупнее — для родителей и тех,
      // кому мелкий текст трудно читать.
      builder: (context, child) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          if (!controller.simpleMode) return child!;
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(
              textScaler: TextScaler.linear(media.textScaler.scale(1) * 1.2),
            ),
            child: child!,
          );
        },
      ),
      debugShowCheckedModeBanner: false,
      theme: AkylTheme.light(),
      darkTheme: AkylTheme.dark(),
      // Тёмная тема по умолчанию: ассистентом пользуются на ходу и часто
      // в темноте, а заставка Android тоже тёмная — светлая вспышка между
      // ними выглядела бы сбоем.
      themeMode: ThemeMode.system,
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
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onResume: () => widget.controller.setForeground(true),
    onHide: () => widget.controller.setForeground(false),
  );

  @override
  void initState() {
    super.initState();
    _lifecycle;
    widget.controller.addListener(_onChanged);
    widget.controller.init();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    widget.controller.removeListener(_onChanged);
    widget.controller.dispose();
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
      layoutBuilder: (current, previous) =>
          Stack(fit: StackFit.expand, children: [...previous, ?current]),
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
