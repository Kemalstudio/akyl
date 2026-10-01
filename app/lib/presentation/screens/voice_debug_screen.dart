import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/voice/voice_log.dart';
import '../../domain/ports/voice_platform.dart';
import '../theme/akyl_theme.dart';
import '../voice_manager.dart';
import '../widgets/glass_background.dart';
import '../widgets/settings_kit.dart';

/// Панель отладки голоса: что сейчас делает каждый слой конвейера, сколько
/// заняли последние шаги и что происходило. Журнал — только в памяти.
class VoiceDebugScreen extends StatefulWidget {
  const VoiceDebugScreen({super.key, required this.voice});

  final VoiceManager voice;

  @override
  State<VoiceDebugScreen> createState() => _VoiceDebugScreenState();
}

class _VoiceDebugScreenState extends State<VoiceDebugScreen> {
  PlatformVoiceStatus _status = const PlatformVoiceStatus();
  Timer? _poll;

  VoiceManager get voice => widget.voice;

  @override
  void initState() {
    super.initState();
    voice.addListener(_refresh);
    voice.log.addListener(_refresh);
    _load();
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _load());
  }

  Future<void> _load() async {
    final s = await voice.platformStatus();
    if (mounted) setState(() => _status = s);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _poll?.cancel();
    voice.removeListener(_refresh);
    voice.log.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    final text = Theme.of(context).textTheme;
    final d = voice.diagnostics;
    final s = voice.settings;
    String ms(int? v) => v == null ? '—' : '$v мс';

    final rows = <(String, String, bool?)>[
      ('Состояние', voice.phase.name, null),
      (
        'Обращение',
        s.wakeEnabled
            ? 'включено · ${WakePhrases.title(s.wakePhrase)}'
            : 'выключено',
        s.wakeEnabled,
      ),
      ('Микрофон', voice.micOpen ? 'открыт' : 'закрыт', voice.micOpen),
      (
        'Источник звука',
        _status.audioSource.isEmpty ? '—' : _status.audioSource,
        null,
      ),
      (
        'AEC / NS',
        '${_status.echoCancellerActive ? 'вкл' : 'выкл'} / ${_status.noiseSuppressorActive ? 'вкл' : 'выкл'}'
            '${_status.echoCancellerAvailable ? '' : ' (AEC нет)'}',
        null,
      ),
      (
        'Запись заглушена',
        _status.micSilenced ? 'да — микрофон занят' : 'нет',
        !_status.micSilenced,
      ),
      ('VAD', d.vadSpeech ? 'речь' : 'тишина', null),
      ('Распознавание', d.engine, voice.voiceAvailable),
      (
        'Фоновая служба',
        _status.serviceRunning ? 'работает' : 'остановлена',
        _status.serviceRunning,
      ),
      (
        'Помощник Android',
        _status.assistantSelected ? 'выбран' : 'не выбран',
        _status.assistantSelected,
      ),
      ('Экран', _status.locked ? 'заблокирован' : 'разблокирован', null),
      ('Звонок', _status.callActive ? 'идёт' : 'нет', null),
      (
        'Оптимизация батареи',
        _status.ignoringBatteryOptimizations
            ? 'не ограничивает'
            : 'ограничивает',
        _status.ignoringBatteryOptimizations,
      ),
      (
        'Уведомления',
        _status.notificationsAllowed ? 'разрешены' : 'запрещены',
        _status.notificationsAllowed,
      ),
      ('Сеть', 'не используется', true),
    ];

    final latencies = <(String, String)>[
      (
        'Последнее обращение',
        d.lastWake == null ? '—' : '«${d.lastWake}» · всего ${d.wakeCount}',
      ),
      ('Последняя команда', d.lastCommand == null ? '—' : '«${d.lastCommand}»'),
      ('Обращение от начала речи', ms(d.wakeLatency)),
      ('Конец фразы (тишина)', ms(d.sttEndpoint)),
      ('Расшифровка T-one', ms(d.sttDecode)),
      ('Разбор и действие', ms(d.processing)),
      ('Первый звук ответа', ms(d.ttsFirstAudio)),
      ('Нагрузка T-one (RTF)', d.rtf == null ? '—' : d.rtf!.toStringAsFixed(2)),
      ('VAD на окно 32 мс', d.vadMicros == null ? '—' : '${d.vadMicros} мкс'),
    ];

    final log = voice.log.entries.reversed.take(80).toList();

    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: c.background.withValues(alpha: 0.35),
          flexibleSpace: const Glass(radius: 0, child: SizedBox.expand()),
          title: const Text('Отладка голоса'),
          actions: [
            IconButton(
              tooltip: 'Скопировать журнал',
              icon: const Icon(LucideIcons.copy, size: 20),
              onPressed: () {
                Clipboard.setData(
                  ClipboardData(text: voice.log.entries.join('\n')),
                );
                HapticFeedback.lightImpact();
              },
            ),
            IconButton(
              tooltip: 'Очистить журнал',
              icon: const Icon(LucideIcons.trash2, size: 20),
              onPressed: voice.log.clear,
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            const SettingsSection('Слои'),
            _Table(rows: [for (final r in rows) (r.$1, r.$2, r.$3)]),
            const SizedBox(height: 22),
            const SettingsSection('Задержки'),
            _Table(rows: [for (final r in latencies) (r.$1, r.$2, null)]),
            const SizedBox(height: 22),
            const SettingsSection('Журнал'),
            Glass(
              radius: 18,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: c.surface.withValues(alpha: 0.78),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: c.border.withValues(alpha: 0.6)),
                ),
                child: log.isEmpty
                    ? Text(
                        'Пока пусто',
                        style: text.labelMedium?.copyWith(color: c.textMuted),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final e in log)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text(
                                e.toString(),
                                style: text.labelSmall?.copyWith(
                                  fontFamily: 'monospace',
                                  color:
                                      e.tag == VoiceTag.audio ||
                                          e.tag == VoiceTag.background
                                      ? c.textSecondary
                                      : c.textPrimary,
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
    );
  }
}

class _Table extends StatelessWidget {
  const _Table({required this.rows});

  final List<(String, String, bool?)> rows;

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    final text = Theme.of(context).textTheme;
    return Glass(
      radius: 18,
      child: Container(
        decoration: BoxDecoration(
          color: c.surface.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.border.withValues(alpha: 0.6)),
        ),
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0)
                Divider(height: 1, color: c.border.withValues(alpha: 0.4)),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (rows[i].$3 != null) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: rows[i].$3!
                                ? const Color(0xFF34D399)
                                : c.danger,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      flex: 5,
                      child: Text(
                        rows[i].$1,
                        style: text.labelMedium?.copyWith(color: c.textMuted),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 6,
                      child: Text(
                        rows[i].$2,
                        textAlign: TextAlign.end,
                        style: text.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
