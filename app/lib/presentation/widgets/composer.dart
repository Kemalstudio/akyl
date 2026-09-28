import 'package:flutter/material.dart';

import '../theme/akyl_motion.dart';
import '../theme/akyl_theme.dart';

/// Строка ввода: голос и клавиатура на равных.
///
/// Пока идёт запись, поле заменяется распознанным текстом — он появляется
/// по мере речи (ТЗ, FR-2), а не после её конца: так видно, что ассистент
/// слышит, ещё до того как он что-то сделает.
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

  /// Ассистент ждёт ответа на свой вопрос — кнопка подсвечена акцентом.
  final bool awaiting;

  /// Распознавание доступно: иначе кнопка записи не показывается.
  final bool voiceAvailable;

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
    // оповещает подписчиков, и setState попал бы уже на снятый со сцены виджет.
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
        AnimatedContainer(
          duration: AkylMotion.quick,
          curve: AkylMotion.move,
          padding: const EdgeInsets.fromLTRB(18, 4, 4, 4),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(AkylShape.composer),
            border: Border.all(
              color: widget.listening
                  ? c.accent
                  : (focused ? c.borderStrong : c.border),
              width: 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: SoftSwitcher(
                  alignment: Alignment.centerLeft,
                  child: widget.listening
                      ? _LiveTranscript(
                          key: const ValueKey('transcript'),
                          text: widget.partialText,
                        )
                      : _Field(
                          key: const ValueKey('field'),
                          controller: widget.controller,
                          focus: _focus,
                          enabled: !widget.busy,
                          hint: widget.awaiting
                              ? 'Ответьте: да или отмена'
                              : 'Позвони маме',
                          onSubmitted: _submit,
                        ),
                ),
              ),
              const SizedBox(width: 8),
              _ActionButton(
                busy: widget.busy,
                listening: widget.listening,
                // Есть текст — кнопка отправляет его; нет — включает микрофон.
                sending: _hasText && !widget.listening,
                awaiting: widget.awaiting,
                voiceAvailable: widget.voiceAvailable,
                onPressed: switch ((widget.listening, _hasText)) {
                  (true, _) => widget.onStopListening,
                  (_, true) => _submit,
                  _ => widget.onListen,
                },
              ),
            ],
          ),
        ),
        // Кнопка отмены не возникает рывком: полоса раздвигается, и текст
        // проявляется уже в готовом месте.
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
                      child: TextButton(
                        onPressed: widget.onCancel,
                        style: TextButton.styleFrom(
                          foregroundColor: c.textSecondary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Отмена'),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    super.key,
    required this.controller,
    required this.focus,
    required this.enabled,
    required this.hint,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final bool enabled;
  final String hint;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    final style = Theme.of(context).textTheme.bodyLarge;

    return TextField(
      controller: controller,
      focusNode: focus,
      enabled: enabled,
      minLines: 1,
      maxLines: 5,
      textInputAction: TextInputAction.send,
      onSubmitted: (_) => onSubmitted(),
      cursorColor: c.textPrimary,
      cursorWidth: 1.6,
      cursorRadius: const Radius.circular(2),
      style: style,
      decoration: InputDecoration(
        isDense: true,
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        hintText: hint,
        hintStyle: style?.copyWith(color: c.textMuted),
      ),
    );
  }
}

/// Распознанный текст во время речи. Пока слов нет — подсказка «Говорите».
class _LiveTranscript extends StatelessWidget {
  const _LiveTranscript({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    final style = Theme.of(context).textTheme.bodyLarge;
    final empty = text.trim().isEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Text(
        empty ? 'Говорите…' : text,
        style: empty ? style?.copyWith(color: c.accent) : style,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  const _ActionButton({
    required this.busy,
    required this.listening,
    required this.sending,
    required this.awaiting,
    required this.voiceAvailable,
    required this.onPressed,
  });

  final bool busy;
  final bool listening;
  final bool sending;
  final bool awaiting;
  final bool voiceAvailable;
  final VoidCallback onPressed;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (widget.listening) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_ActionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.listening == oldWidget.listening) return;
    if (widget.listening) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;

    final enabled = !widget.busy &&
        (widget.sending || widget.listening || widget.voiceAvailable);

    final background = switch ((widget.busy, widget.sending, widget.listening)) {
      (true, _, _) => c.surfaceRaised,
      (_, true, _) => c.action,
      (_, _, true) => c.accent,
      _ => widget.awaiting ? c.accentMuted : c.surfaceRaised,
    };
    final foreground = switch ((widget.busy, widget.sending, widget.listening)) {
      (_, true, _) => c.onAction,
      (_, _, true) => c.background,
      _ => widget.awaiting ? c.accent : c.textSecondary,
    };

    final icon = switch ((widget.busy, widget.sending, widget.listening)) {
      (_, true, _) => Icons.arrow_upward_rounded,
      (_, _, true) => Icons.stop_rounded,
      _ => Icons.mic_none_rounded,
    };

    return Semantics(
      button: true,
      label: switch ((widget.sending, widget.listening)) {
        (true, _) => 'Отправить команду',
        (_, true) => 'Остановить запись',
        _ => 'Сказать команду',
      },
      child: GestureDetector(
        onTap: enabled ? widget.onPressed : null,
        child: SizedBox(
          width: 52,
          height: 52,
          child: Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Кольцо, расходящееся от кнопки, пока идёт запись.
                if (widget.listening)
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, _) => Container(
                      width: 44 + 8 * _pulse.value,
                      height: 44 + 8 * _pulse.value,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: c.accent.withValues(
                          alpha: 0.28 * (1 - _pulse.value),
                        ),
                      ),
                    ),
                  ),
                AnimatedContainer(
                  duration: AkylMotion.quick,
                  curve: AkylMotion.move,
                  width: 44,
                  height: 44,
                  decoration:
                      BoxDecoration(color: background, shape: BoxShape.circle),
                  child: Center(
                    // Микрофон, стрелка и стоп — одна кнопка: значок меняется
                    // перетеканием, а не подменой кадра.
                    child: SoftSwitcher(
                      duration: AkylMotion.instant,
                      child: widget.busy
                          ? SizedBox(
                              key: const ValueKey('busy'),
                              width: 17,
                              height: 17,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation(c.textSecondary),
                              ),
                            )
                          : Icon(
                              icon,
                              key: ValueKey(icon),
                              size: 21,
                              color: foreground,
                            ),
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
