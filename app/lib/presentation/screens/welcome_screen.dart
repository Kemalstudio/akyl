import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';

import '../assistant_controller.dart';
import '../theme/akyl_motion.dart';
import '../theme/akyl_theme.dart';
import '../widgets/akyl_mark.dart';
import '../widgets/alym_logo.dart';
import '../widgets/glass_background.dart';

/// Экран входа: знак, обещание и запрос разрешений.
///
/// Показывается один раз — если разрешения уже выданы, [AssistantController]
/// пропускает его при запуске. Три строки внизу — не маркетинг: звонок и SMS
/// голосом требуют доступа, который пользователь имеет право не дать, и он
/// должен заранее понимать, зачем.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({
    super.key,
    required this.controller,
    required this.onReady,
  });

  final AssistantController controller;
  final VoidCallback onReady;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _requesting = false;
  bool _denied = false;

  Future<void> _request() async {
    setState(() {
      _requesting = true;
      _denied = false;
    });

    final granted = await widget.controller.requestPermissions();
    if (!mounted) return;

    setState(() {
      _requesting = false;
      _denied = !granted;
    });
    if (granted) widget.onReady();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    final theme = Theme.of(context);

    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Spacer(flex: 3),
                const FadeSlideIn(
                  child: AlymLogo(phase: VoicePhase.disabled, size: 64),
                ),
                const SizedBox(height: 28),
                FadeSlideIn(
                  delay: AkylMotion.stagger,
                  child: Text(
                    AkylWordmark.appName,
                    style: theme.textTheme.displaySmall?.copyWith(fontSize: 38),
                  ),
                ),
                const SizedBox(height: 12),
                FadeSlideIn(
                  delay: AkylMotion.stagger * 2,
                  child: Text(
                    'Звонки и сообщения голосом.\nВсё считается на телефоне.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: c.textSecondary,
                      fontSize: 16.5,
                    ),
                  ),
                ),
                const Spacer(flex: 2),
                FadeSlideIn(
                  delay: AkylMotion.stagger * 3,
                  child: Glass(
                    radius: 24,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                      decoration: BoxDecoration(
                        color: c.surface.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: c.border.withValues(alpha: 0.6),
                        ),
                      ),
                      child: const Column(
                        children: [
                          _Point(
                            icon: LucideIcons.cloudOff,
                            title: 'Работает без интернета',
                            subtitle: 'Распознавание речи идёт на устройстве',
                          ),
                          _Point(
                            icon: LucideIcons.lock,
                            title: 'Голос никуда не уходит',
                            subtitle: 'Записи и контакты не покидают телефон',
                          ),
                          _Point(
                            icon: LucideIcons.heart,
                            title: 'Ближе к вашим близким',
                            subtitle:
                                'Запоминает, кому звонить по слову «мама»',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const Spacer(flex: 2),
                // Отказ появляется мягко: экран не должен дёргаться в ответ
                // на действие, которое человек уже воспринял как неудачу.
                AnimatedSize(
                  duration: AkylMotion.base,
                  curve: AkylMotion.move,
                  alignment: Alignment.topCenter,
                  child: !_denied
                      ? const SizedBox(width: double.infinity)
                      : Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Text(
                            'Без доступа к звонкам, SMS и контактам ассистент '
                            'не сможет выполнить ни одну команду. Разрешения '
                            'можно выдать в настройках приложения.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: c.danger,
                            ),
                          ),
                        ),
                ),
                FadeSlideIn(
                  delay: AkylMotion.stagger * 6,
                  child: _PrimaryButton(
                    label: _denied
                        ? 'Попробовать ещё раз'
                        : 'Разрешить и начать',
                    busy: _requesting,
                    onPressed: _request,
                  ),
                ),
                const SizedBox(height: 14),
                FadeSlideIn(
                  delay: AkylMotion.stagger * 7,
                  child: Center(
                    child: TextButton(
                      onPressed: _requesting ? null : widget.onReady,
                      style: TextButton.styleFrom(foregroundColor: c.textMuted),
                      child: const Text('Посмотреть без разрешений'),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: c.accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 17, color: c.accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.labelLarge),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: c.textMuted,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: AkylMotion.quick,
      opacity: busy ? 0.7 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AkylShape.composer),
          gradient: const LinearGradient(
            colors: [Color(0xFF8B5CF6), Color(0xFF5B4BE6)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6D4AE0).withValues(alpha: 0.25),
              blurRadius: 20,
              spreadRadius: -10,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton(
            onPressed: busy ? null : onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.transparent,
              disabledBackgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AkylShape.composer),
              ),
              textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontSize: 16,
                letterSpacing: -0.2,
              ),
            ),
            child: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : Text(label),
          ),
        ),
      ),
    );
  }
}
