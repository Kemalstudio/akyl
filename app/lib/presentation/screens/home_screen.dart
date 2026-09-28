import 'package:flutter/material.dart';

import '../assistant_controller.dart';
import '../theme/akyl_theme.dart';
import '../widgets/akyl_mark.dart';
import '../widgets/composer.dart';
import '../widgets/empty_state.dart';
import '../widgets/message_tile.dart';
import '../widgets/status_strip.dart';

/// Главный экран: история команд (ТЗ, FR-10) и строка ввода.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});

  final AssistantController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _send(String text) async => widget.controller.submit(text);

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    final controller = widget.controller;
    final history = controller.history;
    final awaiting = controller.state.isAwaiting;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: AkylShape.gutter,
        title: const AkylWordmark(),
        actions: [
          IconButton(
            tooltip: controller.ttsEnabled ? 'Выключить голос' : 'Включить голос',
            icon: Icon(
              controller.ttsEnabled
                  ? Icons.volume_up_outlined
                  : Icons.volume_off_outlined,
              color: controller.ttsEnabled ? c.textSecondary : c.textMuted,
            ),
            onPressed: () => controller.setTtsEnabled(!controller.ttsEnabled),
          ),
          if (history.isNotEmpty)
            IconButton(
              tooltip: 'Очистить историю',
              icon: const Icon(Icons.history_toggle_off_rounded),
              onPressed: controller.clearHistory,
            ),
          const SizedBox(width: 6),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: c.border),
        ),
      ),
      body: Column(
        children: [
          if (controller.warning != null)
            _WarningBar(
              text: controller.warning!,
              onDismiss: controller.dismissWarning,
            ),
          Expanded(
            child: history.isEmpty
                ? EmptyState(onPick: _send)
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(
                      AkylShape.gutter,
                      18,
                      AkylShape.gutter,
                      8,
                    ),
                    itemCount: history.length,
                    itemBuilder: (_, i) => MessageTile(message: history[i]),
                  ),
          ),
          StatusStrip(state: controller.state, busy: controller.busy),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AkylShape.gutter,
                0,
                AkylShape.gutter,
                12,
              ),
              child: Composer(
                controller: _input,
                onSubmit: _send,
                onListen: controller.listen,
                onStopListening: controller.stopListening,
                busy: controller.busy,
                listening: controller.listening,
                awaiting: awaiting,
                voiceAvailable: controller.voiceAvailable,
                partialText: controller.partialText,
                onCancel: awaiting ? controller.cancel : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Контакты недоступны — ассистент запустится, но найти никого не сможет.
class _WarningBar extends StatelessWidget {
  const _WarningBar({required this.text, required this.onDismiss});

  final String text;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    return Container(
      width: double.infinity,
      color: c.surface,
      padding: const EdgeInsets.symmetric(
        horizontal: AkylShape.gutter,
        vertical: 12,
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 17, color: c.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: c.textSecondary),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onDismiss,
            child: Icon(Icons.close_rounded, size: 16, color: c.textMuted),
          ),
        ],
      ),
    );
  }
}
