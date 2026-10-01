import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';

import '../assistant_controller.dart';
import '../theme/akyl_motion.dart';
import '../theme/akyl_theme.dart';
import 'akyl_mark.dart';

/// Боковая панель с историей разговоров.
///
/// Заголовки придумывает сам ассистент по разобранной команде, а не по её
/// тексту: «позвони пожалуйста маме по громкой связи» становится
/// «Звонок: Мама». Список сгруппирован по времени — искать разговор проще
/// по «когда это было», чем по названию.
class HistoryDrawer extends StatelessWidget {
  const HistoryDrawer({super.key, required this.controller});

  final AssistantController controller;

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    final groups = _groupByDate(controller.conversations, DateTime.now());

    const radius = BorderRadius.only(
      topRight: Radius.circular(26),
      bottomRight: Radius.circular(26),
    );
    return Drawer(
      backgroundColor: Colors.transparent,
      elevation: 0,
      width: 300,
      shape: const RoundedRectangleBorder(borderRadius: radius),
      clipBehavior: Clip.antiAlias,
      // Матовое стекло: сквозь панель видно, как плывут пятна фона.
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              c.surface.withValues(alpha: 0.94),
              Color.lerp(
                c.surface,
                const Color(0xFF7C3AED),
                0.18,
              )!.withValues(alpha: 0.94),
            ],
          ),
          border: Border(
            right: BorderSide(color: c.border.withValues(alpha: 0.6)),
          ),
        ),
        child: _content(context, groups),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    List<({String title, List<Conversation> items})> groups,
  ) {
    final c = context.akyl;
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: AkylWordmark(markSize: 20, fontSize: 17),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _NewChatButton(
              onTap: () {
                controller.startNewConversation();
                Navigator.of(context).pop();
              },
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: groups.isEmpty
                ? _EmptyHistory()
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    itemCount: groups.length,
                    itemBuilder: (context, index) {
                      final group = groups[index];
                      return FadeSlideIn(
                        delay: AkylMotion.stagger * index,
                        offset: 8,
                        child: _Group(
                          title: group.title,
                          conversations: group.items,
                          currentId: controller.current.id,
                          onOpen: (id) {
                            controller.openConversation(id);
                            Navigator.of(context).pop();
                          },
                          onDelete: controller.deleteConversation,
                        ),
                      );
                    },
                  ),
          ),
          if (controller.conversations.isNotEmpty) ...[
            Divider(color: c.border, height: 1),
            _ClearAllButton(controller: controller),
          ],
        ],
      ),
    );
  }

  /// «Сегодня», «Вчера», «На этой неделе», «Раньше».
  static List<({String title, List<Conversation> items})> _groupByDate(
    List<Conversation> all,
    DateTime now,
  ) {
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekAgo = today.subtract(const Duration(days: 7));

    final buckets = <String, List<Conversation>>{
      'Сегодня': [],
      'Вчера': [],
      'На этой неделе': [],
      'Раньше': [],
    };

    for (final conversation in all) {
      final at = conversation.updatedAt;
      final day = DateTime(at.year, at.month, at.day);
      final key = switch (day) {
        _ when !day.isBefore(today) => 'Сегодня',
        _ when !day.isBefore(yesterday) => 'Вчера',
        _ when !day.isBefore(weekAgo) => 'На этой неделе',
        _ => 'Раньше',
      };
      buckets[key]!.add(conversation);
    }

    return [
      for (final entry in buckets.entries)
        if (entry.value.isNotEmpty) (title: entry.key, items: entry.value),
    ];
  }
}

class _NewChatButton extends StatelessWidget {
  const _NewChatButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AkylShape.chip),
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF8B5CF6), Color(0xFF5B4BE6)],
            ),
            borderRadius: BorderRadius.circular(AkylShape.chip),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                const Icon(LucideIcons.plus, size: 19, color: Colors.white),
                const SizedBox(width: 10),
                Text(
                  'Новый разговор',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({
    required this.title,
    required this.conversations,
    required this.currentId,
    required this.onOpen,
    required this.onDelete,
  });

  final String title;
  final List<Conversation> conversations;
  final String currentId;
  final ValueChanged<String> onOpen;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: c.textMuted),
          ),
        ),
        for (final conversation in conversations)
          _ConversationTile(
            conversation: conversation,
            selected: conversation.id == currentId,
            onTap: () => onOpen(conversation.id),
            onDelete: () => onDelete(conversation.id),
          ),
      ],
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.selected,
    required this.onTap,
    required this.onDelete,
  });

  final Conversation conversation;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;

    return Dismissible(
      key: ValueKey(conversation.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: c.danger.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(AkylShape.chip),
        ),
        child: Icon(LucideIcons.trash2, size: 19, color: c.danger),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AkylShape.chip),
          child: AnimatedContainer(
            duration: AkylMotion.quick,
            curve: AkylMotion.move,
            decoration: BoxDecoration(
              color: selected
                  ? c.accent.withValues(alpha: 0.16)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AkylShape.chip),
              border: Border.all(
                color: selected
                    ? c.accent.withValues(alpha: 0.3)
                    : Colors.transparent,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: AkylMotion.quick,
                  curve: AkylMotion.move,
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? c.accent : c.border,
                  ),
                ),
                Expanded(
                  child: Text(
                    conversation.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontSize: 14.5,
                      color: selected ? c.textPrimary : c.textSecondary,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: FadeSlideIn(
          duration: AkylMotion.slow,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.accent.withValues(alpha: 0.14),
                  border: Border.all(color: c.accent.withValues(alpha: 0.3)),
                ),
                child: Icon(
                  LucideIcons.messageCircleHeart,
                  size: 26,
                  color: c.accent,
                ),
              ),
              const SizedBox(height: 16),
              Text('Пока пусто', style: text.titleMedium),
              const SizedBox(height: 6),
              Text(
                'Здесь появятся ваши разговоры.\nЗаголовок ассистент придумает сам.',
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(color: c.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClearAllButton extends StatelessWidget {
  const _ClearAllButton({required this.controller});

  final AssistantController controller;

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    return TextButton.icon(
      onPressed: () async {
        final confirmed = await _confirm(context);
        if (confirmed != true) return;
        await controller.clearAllConversations();
      },
      icon: Icon(LucideIcons.trash2, size: 18, color: c.textMuted),
      label: Text(
        'Очистить историю',
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: c.textMuted),
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        alignment: Alignment.center,
      ),
    );
  }

  /// Удаление всей истории необратимо — спрашиваем, как и про SMS.
  Future<bool?> _confirm(BuildContext context) {
    final c = context.akyl;
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AkylShape.card),
        ),
        title: Text(
          'Удалить все разговоры?',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        content: Text(
          'Историю нельзя будет восстановить.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(foregroundColor: c.textSecondary),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: c.danger),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }
}
