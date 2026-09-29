import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../domain/entities/conversation.dart';
import '../../domain/entities/skill_result.dart';
import '../theme/akyl_motion.dart';
import '../theme/akyl_theme.dart';
import 'akyl_mark.dart';
import 'cosmic.dart';
import 'typewriter_text.dart';

/// Реплика в истории (ТЗ, FR-10), в духе ChatGPT.
///
/// Сказанное человеком — серая плашка справа. Ответ помощника — обычный
/// текст слева с аватаром: он читается как речь, а не как сообщение
/// в мессенджере. Свежий ответ печатается по буквам.
class MessageTile extends StatelessWidget {
  const MessageTile({
    super.key,
    required this.message,
    this.onSpeak,
    this.onTyping,
  });

  final ChatMessage message;

  /// «Озвучить ещё раз» под ответом.
  final ValueChanged<String>? onSpeak;

  /// Ответ растёт при печати — список прокручивается за ним.
  final VoidCallback? onTyping;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: message.fromUser ? 14 : 10,
        bottom: message.fromUser ? 6 : 10,
      ),
      child: _Arrive(
        // Ключ по времени реплики: список перестраивается на каждый кадр
        // набора, и без него анимация проигрывалась бы заново.
        key: ValueKey(message.at),
        fromRight: message.fromUser,
        child: message.fromUser
            ? _UserBubble(message)
            : _AssistantReply(message, onSpeak: onSpeak, onTyping: onTyping),
      ),
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble(this.message);

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        // Своя реплика — светящийся градиентный «пузырь» с острым углом
        // к краю экрана, как у мессенджеров.
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF8B5CF6).withValues(alpha: 0.92),
                const Color(0xFF5B5BF0).withValues(alpha: 0.92),
              ],
            ),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(22),
              topRight: Radius.circular(22),
              bottomLeft: Radius.circular(22),
              bottomRight: Radius.circular(6),
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7C3AED).withValues(alpha: 0.4),
                blurRadius: 18,
                spreadRadius: -4,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Text(
            message.text,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(height: 1.4, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class _AssistantReply extends StatelessWidget {
  const _AssistantReply(this.message, {this.onSpeak, this.onTyping});

  final ChatMessage message;
  final ValueChanged<String>? onSpeak;
  final VoidCallback? onTyping;

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    final theme = Theme.of(context);

    // Вопрос и отказ отличаются только пометкой над текстом: сам ответ
    // остаётся одинаково спокойным.
    final (label, labelColor, labelIcon) = switch (message.status) {
      SkillStatus.needsConfirmation => (
        'Нужно подтверждение',
        c.accent,
        LucideIcons.circleCheck,
      ),
      SkillStatus.needsChoice => (
        'Уточните',
        c.accent,
        LucideIcons.messageCircle,
      ),
      SkillStatus.failed => ('Не выполнено', c.danger, LucideIcons.circleX),
      _ => (null, c.textMuted, null),
    };

    // Печатается только то, что пришло только что; история из памяти
    // показывается сразу.
    final fresh = DateTime.now().difference(message.at).inSeconds < 3;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4, right: 10),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.5),
                  blurRadius: 12,
                ),
              ],
            ),
            child: const AssistantAvatar(size: 30),
          ),
        ),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GlassPanel(
                radius: 20,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (label != null) ...[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(labelIcon, size: 14, color: labelColor),
                          const SizedBox(width: 6),
                          Text(
                            label,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: labelColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                    ],
                    TypewriterText(
                      message.text,
                      animate: fresh,
                      onProgress: onTyping,
                      style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              _Actions(text: message.text, onSpeak: onSpeak),
            ],
          ),
        ),
      ],
    );
  }
}

/// Кнопки под ответом: скопировать и озвучить ещё раз.
class _Actions extends StatefulWidget {
  const _Actions({required this.text, this.onSpeak});

  final String text;
  final ValueChanged<String>? onSpeak;

  @override
  State<_Actions> createState() => _ActionsState();
}

class _ActionsState extends State<_Actions> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _SmallAction(
          icon: _copied ? LucideIcons.check : LucideIcons.copy,
          tooltip: _copied ? 'Скопировано' : 'Копировать',
          onTap: _copy,
        ),
        if (widget.onSpeak != null)
          _SmallAction(
            icon: LucideIcons.volume2,
            tooltip: 'Озвучить',
            onTap: () => widget.onSpeak!(widget.text),
          ),
      ],
    );
  }
}

class _SmallAction extends StatelessWidget {
  const _SmallAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 18,
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: SoftSwitcher(
            duration: AkylMotion.instant,
            child: Icon(
              icon,
              key: ValueKey(icon),
              size: 16,
              color: c.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// Появление реплики: своя влетает справа, ответ — слева, обе чуть
/// подрастают из 94%. Кривая с лёгким «докатом», как в чатах на Dribbble.
class _Arrive extends StatelessWidget {
  const _Arrive({super.key, required this.fromRight, required this.child});

  final bool fromRight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutBack,
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset((fromRight ? 28 : -28) * (1 - t), 10 * (1 - t)),
          child: Transform.scale(
            scale: 0.94 + 0.06 * t,
            alignment: fromRight ? Alignment.centerRight : Alignment.centerLeft,
            child: child,
          ),
        ),
      ),
    );
  }
}
