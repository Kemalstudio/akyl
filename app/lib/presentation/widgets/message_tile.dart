import 'package:flutter/material.dart';

import '../../domain/entities/skill_result.dart';
import '../assistant_controller.dart';
import '../theme/akyl_motion.dart';
import '../theme/akyl_theme.dart';
import 'akyl_mark.dart';

/// Реплика в истории (ТЗ, FR-10).
///
/// Сказанное пользователем — плашка справа, ответ ассистента — обычный текст
/// слева со знаком на поле. Ответ не берётся в рамку намеренно: он читается
/// как речь, а не как сообщение в мессенджере.
class MessageTile extends StatelessWidget {
  const MessageTile({super.key, required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: FadeSlideIn(
        // Ключ по времени реплики: список перестраивается на каждый кадр
        // набора, и без него анимация проигрывалась бы заново.
        key: ValueKey(message.at),
        duration: AkylMotion.quick,
        offset: 10,
        child: message.fromUser ? _UserLine(message) : _AssistantLine(message),
      ),
    );
  }
}

class _UserLine extends StatelessWidget {
  const _UserLine(this.message);

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: c.surfaceRaised,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(AkylShape.card),
              topRight: Radius.circular(AkylShape.card),
              bottomLeft: Radius.circular(AkylShape.card),
              bottomRight: Radius.circular(6),
            ),
          ),
          child: Text(
            message.text,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      ),
    );
  }
}

class _AssistantLine extends StatelessWidget {
  const _AssistantLine(this.message);

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    final theme = Theme.of(context);

    // Отказ и вопрос отличаются от обычного ответа только цветом строки-пометки:
    // сам текст остаётся одинаково спокойным.
    final (label, labelColor) = switch (message.status) {
      SkillStatus.needsConfirmation => ('Нужно подтверждение', c.accent),
      SkillStatus.needsChoice => ('Уточните', c.accent),
      SkillStatus.failed => ('Не выполнено', c.danger),
      _ => (null, c.textMuted),
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2, right: 12),
          child: AkylMark(size: 18, color: c.textMuted),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (label != null) ...[
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(color: labelColor),
                ),
                const SizedBox(height: 4),
              ],
              Text(message.text, style: theme.textTheme.bodyLarge),
            ],
          ),
        ),
      ],
    );
  }
}
