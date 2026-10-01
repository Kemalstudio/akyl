import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../domain/entities/conversation.dart';
import '../../domain/entities/skill_result.dart';
import '../theme/akyl_motion.dart';
import '../theme/akyl_theme.dart';
import 'akyl_mark.dart';
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
    this.onConfirm,
    this.onReject,
    this.showActions = true,
  });

  final ChatMessage message;

  /// «Копировать» и «Озвучить» — у последнего ответа, чтобы история не
  /// рябила одинаковыми значками.
  final bool showActions;

  /// «Озвучить ещё раз» под ответом.
  final ValueChanged<String>? onSpeak;

  /// Ответ растёт при печати — список прокручивается за ним.
  final VoidCallback? onTyping;

  /// Ответ на вопрос «отправить?» касанием — только у последней реплики,
  /// пока помощник ждёт ответа.
  final VoidCallback? onConfirm;
  final VoidCallback? onReject;

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
            : _AssistantReply(
                message,
                onSpeak: onSpeak,
                onTyping: onTyping,
                onConfirm: onConfirm,
                onReject: onReject,
                showActions: showActions,
              ),
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
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF7457E8), Color(0xFF6348DA)],
            ),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(22),
              topRight: Radius.circular(22),
              bottomLeft: Radius.circular(22),
              bottomRight: Radius.circular(6),
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: Text(
            _sentence(message.text),
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(height: 1.4, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// Распознаватель пишет речь строчными: «позвони маме». На экране реплика
/// начинается с заглавной, как написал бы человек.
String _sentence(String text) =>
    text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

class _AssistantReply extends StatelessWidget {
  const _AssistantReply(
    this.message, {
    this.onSpeak,
    this.onTyping,
    this.onConfirm,
    this.onReject,
    this.showActions = true,
  });

  final ChatMessage message;
  final ValueChanged<String>? onSpeak;
  final VoidCallback? onTyping;
  final VoidCallback? onConfirm;
  final VoidCallback? onReject;
  final bool showActions;

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
        const Padding(
          padding: EdgeInsets.only(top: 2, right: 12),
          child: AssistantAvatar(size: 28),
        ),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Ответ — просто текст, как речь: без рамки и подложки.
              Padding(
                padding: const EdgeInsets.only(top: 2),
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
              if (onConfirm != null && onReject != null) ...[
                const SizedBox(height: 12),
                _ConfirmButtons(onConfirm: onConfirm!, onReject: onReject!),
              ],
              if (showActions) ...[
                const SizedBox(height: 6),
                _Actions(text: message.text, onSpeak: onSpeak),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// «Отправить» и «Отмена» — ответить на вопрос помощника касанием.
/// Голосом «да» и «отмена» по-прежнему работают.
class _ConfirmButtons extends StatelessWidget {
  const _ConfirmButtons({required this.onConfirm, required this.onReject});

  final VoidCallback onConfirm;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        FilledButton.icon(
          onPressed: () {
            HapticFeedback.mediumImpact();
            onConfirm();
          },
          icon: const Icon(LucideIcons.send, size: 16),
          label: const Text('Отправить'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF6D4AE0),
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 18),
            shape: const StadiumBorder(),
          ),
        ),
        OutlinedButton(
          onPressed: () {
            HapticFeedback.selectionClick();
            onReject();
          },
          style: OutlinedButton.styleFrom(
            foregroundColor: c.textPrimary,
            side: BorderSide(color: c.borderStrong),
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 18),
            shape: const StadiumBorder(),
          ),
          child: const Text('Отмена'),
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
