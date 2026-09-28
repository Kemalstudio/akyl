import 'package:flutter/material.dart';

import '../theme/akyl_motion.dart';
import '../theme/akyl_theme.dart';
import 'akyl_mark.dart';

/// Первый экран разговора: знак, одна строка и примеры команд.
///
/// Примеры — не украшение: голосовому помощнику нужно с первой секунды
/// показать, что именно он понимает, иначе человек скажет «включи музыку»
/// и решит, что приложение не работает (ТЗ, сценарий С8).
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.onPick});

  final ValueChanged<String> onPick;

  static const List<String> _examples = [
    'Позвони маме',
    'Набери Ахмеда на рабочий',
    'Напиши Мерет что я опаздываю',
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    final theme = Theme.of(context);

    // Содержимое стоит по центру, пока помещается, и начинает прокручиваться,
    // когда экран низкий или шрифт системы увеличен.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: AkylShape.gutter,
          vertical: 32,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight - 64),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Экран собирается сверху вниз: знак, заголовок, примеры.
              // Появление всего разом читалось бы как вспышка.
              FadeSlideIn(child: AkylMark(size: 44, color: c.textPrimary)),
              const SizedBox(height: 22),
              FadeSlideIn(
                delay: AkylMotion.stagger,
                child: Text(
                  'Слушаю команду',
                  style: theme.textTheme.displaySmall,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 10),
              FadeSlideIn(
                delay: AkylMotion.stagger * 2,
                child: Text(
                  'Звонки и сообщения голосом.\nБез интернета, без отправки записи наружу.',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 30),
              for (final (index, example) in _examples.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: FadeSlideIn(
                    delay: AkylMotion.stagger * (3 + index),
                    child: _ExampleCard(
                      text: example,
                      onTap: () => onPick(example),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExampleCard extends StatelessWidget {
  const _ExampleCard({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AkylShape.card),
        child: Ink(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(AkylShape.card),
            border: Border.all(color: c.border),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '«$text»',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
                Icon(Icons.north_east_rounded, size: 16, color: c.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
