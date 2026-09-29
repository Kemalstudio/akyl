import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/akyl_motion.dart';
import '../theme/akyl_theme.dart';
import 'cosmic.dart';
import 'typewriter_text.dart';

/// Поле ввода в духе ChatGPT: сверху текст, снизу строка кнопок.
///
/// Одна и та же кнопка справа меняет роль: пустое поле — микрофон,
/// есть текст — «отправить», идёт запись — «стоп». В пустом поле
/// подсказки печатаются по буквам, показывая, что умеет помощник.
class Composer extends StatefulWidget {
  const Composer({
    super.key,
    required this.controller,
    required this.onSubmit,
    required this.onListen,
    required this.onStopListening,
    required this.busy,
    required this.listening,
    required this.awaiting,
    required this.voiceAvailable,
    this.wakeListening = false,
    this.level,
    this.partialText = '',
    this.onCancel,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSubmit;

  /// Нажата кнопка записи.
  final VoidCallback onListen;

  /// Нажата кнопка «стоп» во время записи.
  final VoidCallback onStopListening;

  final bool busy;

  /// Микрофон открыт прямо сейчас.
  final bool listening;

  /// Ассистент ждёт ответа на свой вопрос.
  final bool awaiting;

  /// Распознавание доступно: иначе кнопки микрофона нет.
  final bool voiceAvailable;

  /// Микрофон ждёт обращения «Макс».
  final bool wakeListening;

  /// Громкость голоса 0..1 во время записи.
  final ValueListenable<double>? level;

  /// Текст, распознанный к этой секунде.
  final String partialText;

  /// Показывается, когда есть что отменять (ТЗ, FR-9).
  final VoidCallback? onCancel;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final _focus = FocusNode();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    _focus.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    // Слушатель снимается до dispose узла: при освобождении фокуса узел
    // оповещает подписчиков, и setState попал бы на снятый виджет.
    _focus.removeListener(_onFocusChanged);
    _focus.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  void _onTextChanged() {
    if (!mounted) return;
    final has = widget.controller.text.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
  }

  void _submit() {
    final text = widget.controller.text;
    if (text.trim().isEmpty) return;
    widget.controller.clear();
    widget.onSubmit(text);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    final focused = _focus.hasFocus;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Стекло с бегущим бликом по кромке; в фокусе и во время записи
        // кромка и свечение ярче.
        GlassPanel(
          radius: 28,
          runningLight: true,
          glow: true,
          highlighted: focused || widget.listening,
          padding: const EdgeInsets.fromLTRB(18, 6, 8, 8),
          child: Stack(
            children: [
              Positioned(
                top: 6,
                right: 6,
                child: Icon(
                  LucideIcons.sparkle,
                  size: 13,
                  color: c.accent.withValues(alpha: 0.8),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SoftSwitcher(
                    alignment: Alignment.centerLeft,
                    child: widget.listening
                        ? _LiveTranscript(
                            key: const ValueKey('transcript'),
                            text: widget.partialText,
                            level: widget.level,
                          )
                        : _Field(
                            key: const ValueKey('field'),
                            controller: widget.controller,
                            focus: _focus,
                            enabled: !widget.busy,
                            awaiting: widget.awaiting,
                            onSubmitted: _submit,
                          ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: SoftSwitcher(
                            alignment: Alignment.centerLeft,
                            child: widget.wakeListening && !widget.listening
                                ? const _WakeChip(key: ValueKey('wake'))
                                : const SizedBox(
                                    key: ValueKey('none'),
                                    height: 36,
                                  ),
                          ),
                        ),
                      ),
                      if (widget.voiceAvailable &&
                          _hasText &&
                          !widget.listening)
                        _IconButton(
                          icon: LucideIcons.mic,
                          tooltip: 'Сказать голосом',
                          onPressed: widget.busy ? null : widget.onListen,
                        ),
                      const SizedBox(width: 6),
                      _MainButton(
                        busy: widget.busy,
                        listening: widget.listening,
                        sending: _hasText && !widget.listening,
                        voiceAvailable: widget.voiceAvailable,
                        level: widget.level,
                        onPressed: switch ((widget.listening, _hasText)) {
                          (true, _) => widget.onStopListening,
                          (_, true) => _submit,
                          _ => widget.onListen,
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        // Кнопка отмены не возникает рывком: полоса раздвигается плавно.
        AnimatedSize(
          duration: AkylMotion.quick,
          curve: AkylMotion.move,
          alignment: Alignment.topCenter,
          child: widget.onCancel == null
              ? const SizedBox(width: double.infinity, height: 0)
              : Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Align(
                    child: FadeSlideIn(
                      duration: AkylMotion.quick,
                      offset: 6,
                      child: TextButton.icon(
                        onPressed: widget.onCancel,
                        icon: const Icon(LucideIcons.x, size: 15),
                        label: const Text('Отмена'),
                        style: TextButton.styleFrom(
                          foregroundColor: c.textSecondary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

/// Текстовое поле. Пока оно пустое, подсказка печатается по буквам и
/// стирается — одна за другой, как в ChatGPT.
class _Field extends StatefulWidget {
  const _Field({
    super.key,
    required this.controller,
    required this.focus,
    required this.enabled,
    required this.awaiting,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final bool enabled;
  final bool awaiting;
  final VoidCallback onSubmitted;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  static const _hints = [
    'Позвони маме',
    'Напиши Мерет, что я опаздываю',
    'Поставь будильник на 7:30',
    'Включи фонарик',
    'Кто мне звонил?',
    'Какое сегодня число?',
  ];

  Timer? _timer;
  int _hint = 0;
  int _shown = 0;
  bool _erasing = false;
  int _hold = 0;

  @override
  void initState() {
    super.initState();
    if (TypewriterText.enabled) {
      _timer = Timer.periodic(const Duration(milliseconds: 55), _tick);
    } else {
      _shown = _hints.first.length;
    }
  }

  void _tick(Timer _) {
    if (!mounted) return;
    // Печатаем, только пока поле пустое.
    if (widget.controller.text.isNotEmpty || widget.awaiting) return;
    final text = _hints[_hint];
    setState(() {
      if (_hold > 0) {
        _hold--;
      } else if (!_erasing) {
        _shown++;
        if (_shown >= text.length) {
          _shown = text.length;
          _erasing = true;
          _hold = 36; // около двух секунд полной подсказки
        }
      } else {
        _shown -= 2;
        if (_shown <= 0) {
          _shown = 0;
          _erasing = false;
          _hint = (_hint + 1) % _hints.length;
          _hold = 6;
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    final style = Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.4);
    final hint = widget.awaiting
        ? 'Ответьте: да или отмена'
        : '${_hints[_hint].substring(0, math.max(0, _shown))}…';

    return TextField(
      controller: widget.controller,
      focusNode: widget.focus,
      enabled: widget.enabled,
      minLines: 1,
      maxLines: 6,
      textInputAction: TextInputAction.send,
      onSubmitted: (_) => widget.onSubmitted(),
      cursorColor: c.accent,
      cursorWidth: 2,
      cursorRadius: const Radius.circular(2),
      style: style,
      decoration: InputDecoration(
        isDense: true,
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        hintText: hint,
        hintStyle: style?.copyWith(color: c.textMuted),
      ),
    );
  }
}

/// Во время записи: полоски, пляшущие в такт голосу, и текст по мере речи.
class _LiveTranscript extends StatelessWidget {
  const _LiveTranscript({super.key, required this.text, this.level});

  final String text;
  final ValueListenable<double>? level;

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    final style = Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.4);
    final empty = text.trim().isEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          _VoiceBars(level: level),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              empty ? 'Говорите…' : text,
              style: empty ? style?.copyWith(color: c.textMuted) : style,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Пять полосок-эквалайзер: высота следует за громкостью, у каждой свой
/// сдвиг по фазе, чтобы движение было живым, а не синхронным.
class _VoiceBars extends StatefulWidget {
  const _VoiceBars({this.level});
  final ValueListenable<double>? level;

  @override
  State<_VoiceBars> createState() => _VoiceBarsState();
}

class _VoiceBarsState extends State<_VoiceBars>
    with SingleTickerProviderStateMixin {
  late final _wave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (TypewriterText.enabled) _wave.repeat();
  }

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    return SizedBox(
      width: 30,
      height: 22,
      child: AnimatedBuilder(
        animation: Listenable.merge([_wave, widget.level]),
        builder: (context, _) {
          final voice = widget.level?.value ?? 0;
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < 5; i++)
                Container(
                  width: 3.2,
                  height:
                      4 +
                      18 *
                          (0.25 + 0.75 * voice) *
                          (0.5 +
                              0.5 *
                                  math
                                      .sin(_wave.value * 2 * math.pi + i * 1.3)
                                      .abs()),
                  decoration: BoxDecoration(
                    color: c.accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Пилюля «Скажите «Макс» ›» слева под полем, как в макете.
class _WakeChip extends StatelessWidget {
  const _WakeChip({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    return Container(
      height: 34,
      padding: const EdgeInsets.fromLTRB(4, 0, 10, 0),
      decoration: BoxDecoration(
        color: c.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: c.accent.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.accent.withValues(alpha: 0.18),
            ),
            child: Icon(LucideIcons.ear, size: 14, color: c.accent),
          ),
          const SizedBox(width: 8),
          Text(
            'Скажите «Макс»',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: c.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          Icon(LucideIcons.chevronRight, size: 14, color: c.accent),
        ],
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 20, color: c.textSecondary),
      style: IconButton.styleFrom(
        minimumSize: const Size(38, 38),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

/// Главная круглая кнопка справа. Отправка — светлый круг со стрелкой,
/// как у ChatGPT; запись — стоп с кольцом, дышащим в такт голосу.
class _MainButton extends StatelessWidget {
  const _MainButton({
    required this.busy,
    required this.listening,
    required this.sending,
    required this.voiceAvailable,
    required this.onPressed,
    this.level,
  });

  final bool busy;
  final bool listening;
  final bool sending;
  final bool voiceAvailable;
  final VoidCallback onPressed;
  final ValueListenable<double>? level;

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    final enabled = !busy && (sending || listening || voiceAvailable);
    final filled = sending || listening;

    final (icon, label) = switch ((listening, sending)) {
      (true, _) => (LucideIcons.square, 'Остановить запись'),
      (_, true) => (LucideIcons.arrowUp, 'Отправить'),
      _ => (LucideIcons.audioLines, 'Сказать голосом'),
    };

    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: enabled ? onPressed : null,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (listening)
                AnimatedBuilder(
                  animation: level ?? const AlwaysStoppedAnimation(0.0),
                  builder: (context, _) {
                    final voice = level?.value ?? 0;
                    return Container(
                      width: 38 + 12 * voice,
                      height: 38 + 12 * voice,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: c.accent.withValues(alpha: 0.18 + 0.2 * voice),
                      ),
                    );
                  },
                ),
              AnimatedSwitcher(
                duration: AkylMotion.quick,
                switchInCurve: AkylMotion.enter,
                transitionBuilder: (child, animation) =>
                    ScaleTransition(scale: animation, child: child),
                child: !enabled || busy
                    ? Container(
                        key: const ValueKey('idle'),
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: c.surfaceRaised,
                        ),
                        child: Center(
                          child: busy
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation(
                                      c.textSecondary,
                                    ),
                                  ),
                                )
                              : Icon(icon, size: 19, color: c.textMuted),
                        ),
                      )
                    : GlowCircle(
                        key: ValueKey(icon),
                        size: 42,
                        glow: listening ? 1 : (filled ? 0.7 : 0.45),
                        child: Icon(
                          icon,
                          size: listening ? 15 : 20,
                          color: Colors.white,
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
