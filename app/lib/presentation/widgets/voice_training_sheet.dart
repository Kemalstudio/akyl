import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../domain/voice/voice_print.dart';
import '../theme/akyl_motion.dart';
import '../theme/akyl_theme.dart';
import '../voice_manager.dart';
import 'alym_logo.dart';
import 'cosmic.dart';
import 'settings_kit.dart';

/// Обучение «Макс» своему голосу: три коротких записи.
///
/// Нужно для одиночного имени с паузой («Макс» … «какое сегодня число»):
/// распознаватель часто не расшифровывает одно короткое слово, а сравнение
/// по звучанию с тремя образцами узнаёт его. Хранятся отпечатки MFCC,
/// а не запись голоса.
Future<void> showVoiceTraining(BuildContext context, VoiceManager voice) {
  HapticFeedback.lightImpact();
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    isDismissible: false,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (_) => _TrainingSheet(voice: voice),
  );
}

class _TrainingSheet extends StatefulWidget {
  const _TrainingSheet({required this.voice});
  final VoiceManager voice;

  @override
  State<_TrainingSheet> createState() => _TrainingSheetState();
}

class _TrainingSheetState extends State<_TrainingSheet> {
  static const _needed = 3;
  final _prints = <VoicePrint>[];
  bool _recording = false;
  bool _done = false;
  bool _cancelled = false;
  String? _hint;

  VoiceManager get voice => widget.voice;

  @override
  void initState() {
    super.initState();
    voice.addListener(_refresh);
    WidgetsBinding.instance.addPostFrameCallback((_) => _record());
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _cancelled = true;
    voice.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _record() async {
    if (_recording || _done || _cancelled) return;
    setState(() {
      _recording = true;
      _hint = null;
    });
    final word = await voice.captureVoiceSample();
    if (!mounted || _cancelled) return;
    setState(() => _recording = false);
    if (word == null) {
      setState(() => _hint = 'Микрофон недоступен. Проверьте разрешение.');
      return;
    }
    if (word.print.isEmpty) {
      unawaited(HapticFeedback.heavyImpact());
      setState(
        () => _hint = word.durationMs == 0
            ? 'Не расслышал. Скажите «Макс» чуть громче.'
            : 'Слишком длинно — нужно одно слово «Макс».',
      );
      return;
    }
    unawaited(HapticFeedback.selectionClick());
    setState(() => _prints.add(word.print));
    if (_prints.length < _needed) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await _record();
      return;
    }
    await voice.saveVoice(_prints);
    unawaited(HapticFeedback.mediumImpact());
    if (mounted) setState(() => _done = true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    final text = Theme.of(context).textTheme;
    final step = (_prints.length + 1).clamp(1, _needed);

    return GlassSheet(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AlymLogo(
              phase: _done
                  ? VoicePhase.disabled
                  : _recording
                  ? VoicePhase.listeningForCommand
                  : VoicePhase.listeningForWake,
              level: voice.level,
              wakeCount: _prints.length,
              size: 64,
            ),
            const SizedBox(height: 8),
            SoftSwitcher(
              child: Text(
                _done ? 'Готово' : 'Скажите «Макс»',
                key: ValueKey(_done),
                style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 8),
            SoftSwitcher(
              child: Text(
                _done
                    ? 'Теперь одно «Макс» с паузой узнаётся по вашему голосу.'
                    : _hint ??
                          (_recording
                              ? 'Слушаю · запись $step из $_needed'
                              : 'Обычным голосом, как будете звать помощника'),
                key: ValueKey('$_done$_hint$_recording$step'),
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(
                  color: _hint != null ? c.danger : c.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _needed; i++)
                  AnimatedContainer(
                    duration: AkylMotion.quick,
                    curve: AkylMotion.move,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    width: i < _prints.length ? 28 : 10,
                    height: 10,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(5),
                      gradient: i < _prints.length
                          ? AkylGradients.button
                          : null,
                      color: i < _prints.length ? null : c.borderStrong,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(_done ? 'Закрыть' : 'Отмена'),
                  ),
                ),
                if (!_done && !_recording && _hint != null) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _record,
                      icon: const Icon(LucideIcons.mic, size: 18),
                      label: const Text('Ещё раз'),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Хранятся не записи голоса, а их отпечатки — только на телефоне.',
              textAlign: TextAlign.center,
              style: text.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}
