import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/akyl_motion.dart';
import '../theme/akyl_theme.dart';
import 'cosmic.dart';
import 'settings_kit.dart';

/// Одна остановка ступенчатого ползунка.
class SliderStop<T> {
  const SliderStop(this.value, this.label, {this.semantic});

  final T value;

  /// Подпись под дорожкой: «10 с», «Средняя».
  final String label;

  /// Что прочитает TalkBack: «10 секунд».
  final String? semantic;
}

/// Ступенчатый ползунок: дорожка с метками, бегунок переезжает на пружине,
/// каждая ступень — лёгкий щелчок вибрацией. Касание по любой метке или
/// перетаскивание; цель касания — вся высота 56 dp, а не тонкая линия.
class SegmentedSlider<T> extends StatefulWidget {
  const SegmentedSlider({
    super.key,
    required this.stops,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
  });

  final List<SliderStop<T>> stops;
  final T value;
  final ValueChanged<T>? onChanged;
  final String? semanticLabel;

  @override
  State<SegmentedSlider<T>> createState() => _SegmentedSliderState<T>();
}

class _SegmentedSliderState<T> extends State<SegmentedSlider<T>>
    with SingleTickerProviderStateMixin {
  late final AnimationController _thumb = AnimationController.unbounded(
    vsync: this,
    value: _index.toDouble(),
  );
  bool _dragging = false;

  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 420,
    damping: 30,
  );

  int get _index {
    final i = widget.stops.indexWhere((s) => s.value == widget.value);
    return i < 0 ? 0 : i;
  }

  @override
  void didUpdateWidget(SegmentedSlider<T> old) {
    super.didUpdateWidget(old);
    if (!_dragging) _springTo(_index);
  }

  @override
  void dispose() {
    _thumb.dispose();
    super.dispose();
  }

  void _springTo(int index) {
    if (!ambientMotion(context)) {
      _thumb.value = index.toDouble();
      return;
    }
    _thumb.animateWith(
      SpringSimulation(_spring, _thumb.value, index.toDouble(), 0),
    );
  }

  void _select(int index) {
    final value = widget.stops[index].value;
    if (value != widget.value) {
      HapticFeedback.selectionClick();
      widget.onChanged?.call(value);
    }
    _springTo(index);
  }

  int _indexAt(double dx, double width) {
    final n = widget.stops.length;
    if (n <= 1) return 0;
    final step = width / (n - 1);
    return (dx / step).round().clamp(0, n - 1);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    final enabled = widget.onChanged != null;
    final text = Theme.of(context).textTheme;
    final stops = widget.stops;
    final current = stops[_index];

    return Semantics(
      slider: true,
      enabled: enabled,
      label: widget.semanticLabel,
      value: current.semantic ?? current.label,
      increasedValue: _index + 1 < stops.length
          ? stops[_index + 1].semantic ?? stops[_index + 1].label
          : null,
      decreasedValue: _index > 0
          ? stops[_index - 1].semantic ?? stops[_index - 1].label
          : null,
      onIncrease: enabled && _index + 1 < stops.length
          ? () => _select(_index + 1)
          : null,
      onDecrease: enabled && _index > 0 ? () => _select(_index - 1) : null,
      child: ExcludeSemantics(
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: LayoutBuilder(
            builder: (context, box) {
              const thumb = 28.0;
              final track = box.maxWidth - thumb;
              double xOf(double i) =>
                  stops.length <= 1 ? 0 : track * i / (stops.length - 1);

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: enabled
                    ? (d) => _select(
                        _indexAt(d.localPosition.dx - thumb / 2, track),
                      )
                    : null,
                onHorizontalDragStart: enabled
                    ? (_) => setState(() => _dragging = true)
                    : null,
                onHorizontalDragUpdate: enabled
                    ? (d) {
                        final pos = ((d.localPosition.dx - thumb / 2) / track)
                            .clamp(0.0, 1.0);
                        _thumb.value = pos * (stops.length - 1);
                        final i = _thumb.value.round();
                        if (stops[i].value != widget.value) {
                          HapticFeedback.selectionClick();
                          widget.onChanged?.call(stops[i].value);
                        }
                      }
                    : null,
                onHorizontalDragEnd: enabled
                    ? (_) {
                        setState(() => _dragging = false);
                        _springTo(_thumb.value.round());
                      }
                    : null,
                child: SizedBox(
                  height: 64,
                  child: AnimatedBuilder(
                    animation: _thumb,
                    builder: (context, _) {
                      final pos = _thumb.value.clamp(0.0, stops.length - 1.0);
                      final x = xOf(pos);
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // Дорожка.
                          Positioned(
                            left: thumb / 2,
                            right: thumb / 2,
                            top: 12,
                            child: Container(
                              height: 4,
                              decoration: BoxDecoration(
                                color: c.border.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          // Пройденная часть.
                          Positioned(
                            left: thumb / 2,
                            top: 12,
                            child: Container(
                              width: x,
                              height: 4,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF7C3AED),
                                    Color(0xFFA78BFA),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          // Метки ступеней и подписи.
                          for (var i = 0; i < stops.length; i++)
                            Positioned(
                              left: xOf(i.toDouble()) + thumb / 2 - 40,
                              width: 80,
                              top: 0,
                              child: Column(
                                children: [
                                  const SizedBox(height: 10),
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: i <= pos
                                          ? const Color(0xFFA78BFA)
                                          : c.borderStrong,
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  AnimatedDefaultTextStyle(
                                    duration: AkylMotion.quick,
                                    style:
                                        (text.labelMedium ?? const TextStyle())
                                            .copyWith(
                                              color: i == _index
                                                  ? c.textPrimary
                                                  : c.textMuted,
                                              fontWeight: i == _index
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                            ),
                                    child: Text(
                                      stops[i].label,
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          // Бегунок.
                          Positioned(
                            left: x,
                            top: 0,
                            child: AnimatedScale(
                              scale: _dragging ? 1.12 : 1,
                              duration: AkylMotion.instant,
                              child: Container(
                                width: thumb,
                                height: thumb,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white,
                                  border: Border.all(
                                    color: const Color(0xFFA78BFA),
                                    width: 3,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(
                                        0xFF7C3AED,
                                      ).withValues(alpha: 0.45),
                                      blurRadius: _dragging ? 16 : 10,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Вариант в листе выбора: значок, название, описание, состояние.
class OptionItem<T> {
  const OptionItem({
    required this.value,
    required this.title,
    required this.description,
    required this.icon,
    this.badge,
    this.available = true,
  });

  final T value;
  final String title;
  final String description;
  final IconData icon;

  /// Короткая пометка справа: «на телефоне», «быстро», «недоступно».
  final String? badge;
  final bool available;
}

/// Нижний лист выбора варианта — вместо выпадающего списка. Карточки с
/// описанием, выбранная подсвечена, недоступные честно помечены.
Future<T?> showOptionSheet<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<OptionItem<T>> items,
  required T selected,
}) {
  HapticFeedback.lightImpact();
  return showModalBottomSheet<T>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    builder: (context) => _OptionSheet<T>(
      title: title,
      subtitle: subtitle,
      items: items,
      selected: selected,
    ),
  );
}

class _OptionSheet<T> extends StatelessWidget {
  const _OptionSheet({
    required this.title,
    required this.subtitle,
    required this.items,
    required this.selected,
  });

  final String title;
  final String? subtitle;
  final List<OptionItem<T>> items;
  final T selected;

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    final text = Theme.of(context).textTheme;
    return GlassSheet(
      child: Flexible(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            Text(
              title,
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                style: text.bodyMedium?.copyWith(color: c.textSecondary),
              ),
            ],
            const SizedBox(height: 20),
            for (var i = 0; i < items.length; i++)
              FadeSlideIn(
                delay: AkylMotion.stagger * i,
                offset: 10,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _OptionCard<T>(
                    item: items[i],
                    selected: items[i].value == selected,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _OptionCard<T> extends StatefulWidget {
  const _OptionCard({required this.item, required this.selected});

  final OptionItem<T> item;
  final bool selected;

  @override
  State<_OptionCard<T>> createState() => _OptionCardState<T>();
}

class _OptionCardState<T> extends State<_OptionCard<T>> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    final text = Theme.of(context).textTheme;
    final item = widget.item;
    final selected = widget.selected;
    final enabled = item.available;

    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: '${item.title}. ${item.description}',
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: enabled
            ? () {
                HapticFeedback.selectionClick();
                Navigator.of(context).pop(item.value);
              }
            : null,
        child: AnimatedScale(
          scale: _down ? 0.98 : 1,
          duration: AkylMotion.instant,
          child: AnimatedContainer(
            duration: AkylMotion.quick,
            curve: AkylMotion.move,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: selected
                  ? c.accent.withValues(alpha: 0.14)
                  : c.surface.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected
                    ? c.accent.withValues(alpha: 0.7)
                    : c.border.withValues(alpha: 0.6),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Opacity(
              opacity: enabled ? 1 : 0.5,
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: selected
                          ? const LinearGradient(
                              colors: [Color(0xFF7C3AED), Color(0xFFA78BFA)],
                            )
                          : null,
                      color: selected ? null : c.accent.withValues(alpha: 0.12),
                    ),
                    child: Icon(
                      item.icon,
                      size: 20,
                      color: selected ? Colors.white : c.accent,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                item.title,
                                style: text.labelLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (item.badge != null) ...[
                              const SizedBox(width: 8),
                              _Tag(item.badge!, muted: !enabled),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.description,
                          style: text.labelMedium?.copyWith(
                            color: c.textMuted,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  AnimatedSwitcher(
                    duration: AkylMotion.quick,
                    child: selected
                        ? Icon(
                            LucideIcons.circleCheck,
                            key: const ValueKey('on'),
                            color: c.accent,
                            size: 22,
                          )
                        : Icon(
                            LucideIcons.circle,
                            key: const ValueKey('off'),
                            color: c.borderStrong,
                            size: 22,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.muted = false});
  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (muted ? c.textMuted : c.accent).withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: muted ? c.textMuted : c.accent,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
