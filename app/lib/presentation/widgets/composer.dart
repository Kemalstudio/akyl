import 'package:flutter/material.dart';

import '../theme/akyl_theme.dart';

/// Поле ввода с кнопкой записи.
///
/// На этапе 1 фраза набирается с клавиатуры — распознавание подключается на
/// этапе 2 (ТЗ, раздел 4). Кнопка уже стоит на своём месте и в своём размере,
/// чтобы при замене ManualTextStt на T-one интерфейс не пришлось переделывать.
class Composer extends StatefulWidget {
  const Composer({
    super.key,
    required this.controller,
    required this.onSubmit,
    required this.busy,
    required this.listening,
    this.onCancel,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSubmit;
  final bool busy;

  /// Ассистент ждёт ответа — кнопка подсвечена акцентом.
  final bool listening;

  /// Показывается вместо подсказки, когда есть что отменять (ТЗ, FR-9).
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
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.fromLTRB(18, 4, 4, 4),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(AkylShape.composer),
            border: Border.all(
              color: focused ? c.borderStrong : c.border,
              width: 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focus,
                  enabled: !widget.busy,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _submit(),
                  cursorColor: c.textPrimary,
                  cursorWidth: 1.6,
                  cursorRadius: const Radius.circular(2),
                  style: Theme.of(context).textTheme.bodyLarge,
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    hintText: widget.listening
                        ? 'Ответьте: да или отмена'
                        : 'Позвони маме',
                    hintStyle: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(color: c.textMuted),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _ActionButton(
                busy: widget.busy,
                // Есть текст — отправляем его; нет — это кнопка записи.
                sending: _hasText,
                listening: widget.listening,
                onPressed: _submit,
              ),
            ],
          ),
        ),
        SizedBox(height: widget.onCancel != null ? 10 : 0),
        if (widget.onCancel != null)
          Align(
            child: TextButton(
              onPressed: widget.onCancel,
              style: TextButton.styleFrom(
                foregroundColor: c.textSecondary,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Отмена'),
            ),
          ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.busy,
    required this.sending,
    required this.listening,
    required this.onPressed,
  });

  final bool busy;
  final bool sending;
  final bool listening;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    final enabled = !busy && sending;

    final background = switch ((busy, sending, listening)) {
      (true, _, _) => c.surfaceRaised,
      (_, true, _) => c.action,
      (_, _, true) => c.accentMuted,
      _ => c.surfaceRaised,
    };
    final foreground = switch ((busy, sending, listening)) {
      (_, true, _) => c.onAction,
      (_, _, true) => c.accent,
      _ => c.textSecondary,
    };

    return Semantics(
      button: true,
      label: sending ? 'Отправить команду' : 'Слушать',
      child: GestureDetector(
        onTap: enabled ? onPressed : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: background, shape: BoxShape.circle),
          child: Center(
            child: busy
                ? SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(c.textSecondary),
                    ),
                  )
                : Icon(
                    sending ? Icons.arrow_upward_rounded : Icons.mic_none_rounded,
                    size: 21,
                    color: foreground,
                  ),
          ),
        ),
      ),
    );
  }
}
