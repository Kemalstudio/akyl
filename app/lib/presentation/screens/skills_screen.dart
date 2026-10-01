import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/akyl_motion.dart';
import '../theme/akyl_theme.dart';
import '../widgets/cosmic.dart';
import '../widgets/glass_background.dart';

/// Всё, что умеет помощник, по разделам. Нажатие на пример — сразу
/// выполнить: так проще всего узнать возможности, не читая инструкций.
class SkillsScreen extends StatelessWidget {
  const SkillsScreen({super.key, required this.onPick});

  final ValueChanged<String> onPick;

  static const _groups = [
    (
      LucideIcons.phone,
      'Звонки и сообщения',
      [
        'Позвони маме по громкой связи',
        'Напиши Мерет, что я опаздываю',
        'Кто звонил?',
        'Когда я последний раз звонил папе?',
        'Прочитай последнее сообщение',
      ],
    ),
    (
      LucideIcons.bellRing,
      'Напоминания и лекарства',
      [
        'Напоминай каждый день в 9 утра выпить таблетку',
        'Напомни через 10 минут позвонить маме',
        'Какие у меня напоминания?',
      ],
    ),
    (
      LucideIcons.brain,
      'Память',
      [
        'Запомни: ключи от гаража у Ахмеда',
        'Где ключи от гаража?',
        'Что ты помнишь?',
      ],
    ),
    (
      LucideIcons.smartphone,
      'Телефон',
      [
        'Поставь будильник на 7:30',
        'Поставь таймер на 5 минут',
        'Включи фонарик',
        'Сделай громче',
        'Открой ватсап',
        'Сколько заряда?',
      ],
    ),
    (
      LucideIcons.music2,
      'Музыка',
      ['Поставь на паузу', 'Следующий трек', 'Включи музыку'],
    ),
    (
      LucideIcons.calculator,
      'Посчитать',
      ['Сколько будет 25 умножить на 4', '15 процентов от 200'],
    ),
    (LucideIcons.siren, 'Помощь', ['Помогите', 'Мне плохо']),
    (
      LucideIcons.languages,
      'По-туркменски',
      ['Ejeme jaň et', 'Sagat näçe?', 'Salam, nähili?'],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    final text = Theme.of(context).textTheme;
    var order = 0;
    Widget enter(Widget child) => FadeSlideIn(
      delay: AkylMotion.stagger * 1.2 * order++,
      duration: AkylMotion.slow,
      offset: 18,
      child: child,
    );

    return GlassBackground(
      intensity: 0.7,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  Row(
                    children: [
                      GlassCircleButton(
                        icon: LucideIcons.arrowLeft,
                        tooltip: 'Назад',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  enter(
                    Wrap(
                      children: [
                        Text(
                          'Что я ',
                          style: text.displaySmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        GradientText(
                          'умею',
                          shimmer: true,
                          style: text.displaySmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  enter(
                    Text(
                      'Нажмите на пример — и я сразу выполню. Или скажите это '
                      'голосом, начиная с «Макс».',
                      style: text.bodyMedium?.copyWith(color: c.textSecondary),
                    ),
                  ),
                  const SizedBox(height: 22),
                  for (final (icon, title, examples) in _groups) ...[
                    enter(
                      GlassPanel(
                        radius: 24,
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: AkylGradients.button,
                                  ),
                                  child: Icon(
                                    icon,
                                    size: 17,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  title,
                                  style: text.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            for (final example in examples)
                              InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () {
                                  Navigator.of(context).pop();
                                  onPick(example);
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                    horizontal: 4,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        LucideIcons.cornerDownRight,
                                        size: 15,
                                        color: c.accent,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          '«$example»',
                                          style: text.bodyMedium?.copyWith(
                                            color: c.textPrimary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
