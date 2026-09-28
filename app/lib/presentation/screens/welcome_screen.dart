import 'package:flutter/material.dart';

import '../assistant_controller.dart';
import '../theme/akyl_theme.dart';
import '../widgets/akyl_mark.dart';

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

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(flex: 3),
              AkylMark(size: 64, color: c.textPrimary),
              const SizedBox(height: 28),
              Text('akyl',
                  style: theme.textTheme.displaySmall?.copyWith(fontSize: 38)),
              const SizedBox(height: 12),
              Text(
                'Звонки и сообщения голосом.\nВсё считается на телефоне.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: c.textSecondary,
                  fontSize: 16.5,
                ),
              ),
              const Spacer(flex: 2),
              const _Point(
                icon: Icons.cloud_off_rounded,
                title: 'Работает без интернета',
                subtitle: 'Распознавание речи идёт на устройстве',
              ),
              const _Point(
                icon: Icons.lock_outline_rounded,
                title: 'Голос никуда не уходит',
                subtitle: 'Записи и контакты не покидают телефон',
              ),
              const _Point(
                icon: Icons.bolt_outlined,
                title: 'Звонок за секунду',
                subtitle: 'От конца фразы до гудка — меньше секунды',
              ),
              const Spacer(flex: 2),
              if (_denied)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Text(
                    'Без доступа к звонкам, SMS и контактам ассистент '
                    'не сможет выполнить ни одну команду. Разрешения можно '
                    'выдать в настройках приложения.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: c.danger),
                  ),
                ),
              _PrimaryButton(
                label: _denied ? 'Попробовать ещё раз' : 'Разрешить и начать',
                busy: _requesting,
                onPressed: _request,
              ),
              const SizedBox(height: 14),
              Center(
                child: TextButton(
                  onPressed: _requesting ? null : widget.onReady,
                  style: TextButton.styleFrom(foregroundColor: c.textMuted),
                  child: const Text('Посмотреть без разрешений'),
                ),
              ),
              const SizedBox(height: 12),
            ],
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
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 19, color: c.textMuted),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.labelLarge),
                const SizedBox(height: 3),
                Text(subtitle, style: theme.textTheme.bodyMedium),
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
    final c = context.akyl;
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: c.action,
          foregroundColor: c.onAction,
          disabledBackgroundColor: c.surfaceRaised,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AkylShape.composer),
          ),
          textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontSize: 16,
                letterSpacing: -0.2,
              ),
        ),
        child: busy
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(c.textSecondary),
                ),
              )
            : Text(label),
      ),
    );
  }
}
