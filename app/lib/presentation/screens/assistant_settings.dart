import 'dart:async';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
import '../../data/contacts/family_names.dart';
import '../../domain/entities/contact.dart';
import '../assistant_controller.dart';
import '../theme/akyl_motion.dart';
import '../theme/akyl_theme.dart';
import '../widgets/akyl_switch.dart';
import '../widgets/glass_background.dart';
import '../widgets/settings_kit.dart';
import 'voice_settings_screen.dart';

class AssistantSettings extends StatefulWidget {
  const AssistantSettings({super.key, required this.controller});
  final AssistantController controller;
  @override
  State<AssistantSettings> createState() => _AssistantSettingsState();
}

class _AssistantSettingsState extends State<AssistantSettings> {
  bool _working = false;
  String? _error;
  String? _note;
  AssistantController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(_refresh);
    controller.refreshContacts();
    controller.refreshCare();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = 'Не удалось сохранить настройку. Проверьте разрешения.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  /// Сначала выбрать, кто это (брат, бабушка…), потом — какой контакт.
  Future<void> _addRelative() async {
    final free = FamilyNames.groups.keys
        .where((r) => !_shownRoles.contains(r))
        .toList();
    final role = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (_) => _RolePicker(roles: free),
    );
    if (role != null && mounted) await _choose(role);
  }

  /// Мама и папа видны всегда, остальные — когда им назначен контакт.
  List<String> get _shownRoles => [
    for (final role in FamilyNames.groups.keys)
      if (role == 'мама' ||
          role == 'папа' ||
          controller.relationships.containsKey(role))
        role,
  ];

  Future<void> _choose(String role) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (_) => _ContactPicker(role: role, contacts: controller.contacts),
    );
    if (choice != null && mounted) {
      await _run(
        () => controller.rememberRelationship(
          role,
          choice.isEmpty ? null : choice,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    final text = Theme.of(context).textTheme;
    final error = _error;
    final voice = controller.voice;

    // Разделы проявляются по очереди, снизу вверх.
    var order = 0;
    Widget enter(Widget child) => FadeSlideIn(
      delay: AkylMotion.stagger * 1.4 * order++,
      duration: AkylMotion.slow,
      offset: 18,
      child: child,
    );

    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: c.background.withValues(alpha: 0.35),
          flexibleSpace: const Glass(radius: 0, child: SizedBox.expand()),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                enter(Text('Настройки', style: text.displaySmall)),
                const SizedBox(height: 6),
                enter(
                  Text(
                    'Как помощник слушает, отвечает и кого называет близкими.',
                    style: text.bodyMedium,
                  ),
                ),
                const SizedBox(height: 22),

                enter(const SettingsSection('Голос')),
                enter(
                  SettingsCard(
                    children: [
                      SettingsRow(
                        icon: LucideIcons.audioLines,
                        title: 'Голос и обращение',
                        subtitle: voice.notificationText,
                        live: voice.micOpen,
                        onTap: () => Navigator.of(context).push(
                          SoftPageRoute<void>(
                            builder: (_) => VoiceSettingsScreen(voice: voice),
                          ),
                        ),
                        trailing: Icon(
                          LucideIcons.chevronRight,
                          size: 16,
                          color: c.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 26),

                enter(const SettingsSection('Близкие')),
                enter(
                  SettingsCard(
                    children: [
                      for (final role in _shownRoles)
                        SettingsRow(
                          icon: LucideIcons.userRound,
                          title: FamilyNames.titles[role] ?? role,
                          subtitle: _relationshipName(role),
                          onTap: _working ? null : () => _choose(role),
                          trailing: Icon(
                            LucideIcons.chevronRight,
                            size: 16,
                            color: c.textMuted,
                          ),
                        ),
                      if (_shownRoles.length < FamilyNames.groups.length)
                        SettingsRow(
                          icon: LucideIcons.plus,
                          title: 'Добавить близкого',
                          subtitle: 'Брат, сестра, бабушка, жена…',
                          onTap: _working ? null : _addRelative,
                          trailing: Icon(
                            LucideIcons.chevronRight,
                            size: 16,
                            color: c.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                enter(
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      'Помощник запомнит их, даже если в контактах записано '
                      'другое имя.',
                      style: text.labelMedium?.copyWith(color: c.textMuted),
                    ),
                  ),
                ),
                const SizedBox(height: 26),

                enter(const SettingsSection('Забота')),
                enter(
                  SettingsCard(
                    children: [
                      SettingsRow(
                        icon: LucideIcons.siren,
                        title: 'SOS по слову «помогите»',
                        subtitle: controller.relatives.isEmpty
                            ? 'Назначьте близких выше — им я позвоню'
                            : 'Позвоню: ${controller.relatives.first.displayName}, '
                                  'SMS с местом: ${controller.relatives.map((c) => c.displayName).join(', ')}',
                        onTap: _working
                            ? null
                            : () => _run(() async {
                                final granted = await controller
                                    .requestLocation();
                                if (mounted && granted) {
                                  setState(
                                    () => _note =
                                        'Место для SOS доступно — в SMS будет ссылка на карту',
                                  );
                                }
                              }),
                        trailing: Icon(
                          LucideIcons.mapPin,
                          size: 18,
                          color: c.textMuted,
                        ),
                      ),
                      SettingsRow(
                        icon: LucideIcons.batteryWarning,
                        title: 'Присмотр за зарядом',
                        subtitle: controller.batteryWatch
                            ? 'Заряд ниже 15% — близким уйдёт SMS'
                            : 'Выключено',
                        onTap: _working || controller.relatives.isEmpty
                            ? null
                            : () => _run(
                                () => controller.setBatteryWatch(
                                  !controller.batteryWatch,
                                ),
                              ),
                        trailing: AkylSwitch(
                          semanticLabel: 'Присмотр за зарядом',
                          value: controller.batteryWatch,
                          onChanged: _working || controller.relatives.isEmpty
                              ? null
                              : (value) => _run(
                                  () => controller.setBatteryWatch(value),
                                ),
                        ),
                      ),
                      SettingsRow(
                        icon: LucideIcons.pill,
                        title: 'Напоминания и лекарства',
                        subtitle:
                            '«Напоминай каждый день в 9 утра выпить таблетку»',
                        trailing: Icon(
                          LucideIcons.mic,
                          size: 16,
                          color: c.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedSize(
                  duration: AkylMotion.base,
                  curve: AkylMotion.move,
                  child: _note == null
                      ? const SizedBox(width: double.infinity)
                      : Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: FadeSlideIn(
                            child: SettingsNotice(
                              icon: LucideIcons.circleCheck,
                              text: _note!,
                              color: c.accent,
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 26),

                enter(const SettingsSection('Вид')),
                enter(
                  SettingsCard(
                    children: [
                      SettingsRow(
                        icon: LucideIcons.accessibility,
                        title: 'Простой режим',
                        subtitle: controller.simpleMode
                            ? 'Крупный текст и большие кнопки звонка'
                            : 'Для родителей: крупнее и проще',
                        onTap: () =>
                            controller.setSimpleMode(!controller.simpleMode),
                        trailing: AkylSwitch(
                          semanticLabel: 'Простой режим',
                          value: controller.simpleMode,
                          onChanged: controller.setSimpleMode,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 26),

                // Ошибка раздвигает место плавно, а не выскакивает.
                AnimatedSize(
                  duration: AkylMotion.base,
                  curve: AkylMotion.move,
                  child: error == null
                      ? const SizedBox(width: double.infinity)
                      : Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: FadeSlideIn(
                            child: SettingsNotice(
                              icon: LucideIcons.triangleAlert,
                              text: error,
                              color: c.danger,
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

  String _relationshipName(String role) {
    final id = controller.relationships[role];
    if (id == null) return 'Выбрать контакт';
    return controller.contacts
            .where((c) => c.id == id)
            .firstOrNull
            ?.displayName ??
        'Контакт удалён — выберите заново';
  }
}

class _ContactPicker extends StatefulWidget {
  const _ContactPicker({required this.role, required this.contacts});
  final String role;
  final List<Contact> contacts;
  @override
  State<_ContactPicker> createState() => _ContactPickerState();
}

class _ContactPickerState extends State<_ContactPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    final text = Theme.of(context).textTheme;
    final contacts = widget.contacts
        .where(
          (c) =>
              c.displayName.toLowerCase().contains(_query) &&
              c.phones.isNotEmpty,
        )
        .toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: GlassSheet(
        height: MediaQuery.sizeOf(context).height * .72,
        child: Column(
          children: [
            Text(
              FamilyNames.titles[widget.role] ?? widget.role,
              style: text.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Кому звонить, когда вы скажете «${widget.role}»',
              style: text.labelMedium?.copyWith(color: c.textMuted),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                decoration: InputDecoration(
                  prefixIcon: Icon(
                    LucideIcons.search,
                    size: 17,
                    color: c.textMuted,
                  ),
                  hintText: 'Найти по имени',
                  filled: true,
                  fillColor: c.surface.withValues(alpha: 0.6),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: c.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: c.border.withValues(alpha: 0.6),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: c.accent),
                  ),
                ),
                onChanged: (value) =>
                    setState(() => _query = value.toLowerCase().trim()),
              ),
            ),
            Expanded(
              child: SoftSwitcher(
                child: contacts.isEmpty
                    ? Center(
                        key: const ValueKey('empty'),
                        child: Text(
                          'Нет подходящих контактов',
                          style: text.bodyMedium?.copyWith(color: c.textMuted),
                        ),
                      )
                    : ListView.builder(
                        key: const ValueKey('list'),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        itemCount: contacts.length,
                        itemBuilder: (_, i) {
                          final tile = _ContactTile(
                            contact: contacts[i],
                            onTap: () => Navigator.pop(context, contacts[i].id),
                          );
                          // Первые строки проявляются по очереди, дальше —
                          // сразу: при прокрутке ждать анимацию незачем.
                          return i < 10
                              ? FadeSlideIn(
                                  delay: AkylMotion.stagger * i,
                                  offset: 10,
                                  child: tile,
                                )
                              : tile;
                        },
                      ),
              ),
            ),
            TextButton.icon(
              onPressed: () => Navigator.pop(context, ''),
              icon: Icon(LucideIcons.circleX, size: 16, color: c.textMuted),
              label: Text(
                'Сбросить назначение',
                style: text.labelMedium?.copyWith(color: c.textMuted),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({required this.contact, required this.onTap});
  final Contact contact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    final text = Theme.of(context).textTheme;
    final name = contact.displayName.trim();
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    c.accent.withValues(alpha: 0.35),
                    const Color(0xFF5B4BE6).withValues(alpha: 0.25),
                  ],
                ),
              ),
              child: Text(
                initial,
                style: text.labelLarge?.copyWith(color: c.textPrimary),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: text.labelLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    contact.primaryPhone!.number,
                    style: text.labelMedium?.copyWith(
                      color: c.textMuted,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Выбор, кого ещё добавить в близкие.
class _RolePicker extends StatelessWidget {
  const _RolePicker({required this.roles});
  final List<String> roles;

  @override
  Widget build(BuildContext context) {
    final c = context.akyl;
    final text = Theme.of(context).textTheme;
    return GlassSheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Кого добавить?', style: text.titleMedium),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (var i = 0; i < roles.length; i++)
                  FadeSlideIn(
                    delay: AkylMotion.stagger * i,
                    offset: 8,
                    child: ActionChip(
                      onPressed: () => Navigator.pop(context, roles[i]),
                      avatar: Icon(
                        LucideIcons.userRound,
                        size: 15,
                        color: c.accent,
                      ),
                      label: Text(FamilyNames.titles[roles[i]] ?? roles[i]),
                      backgroundColor: c.accent.withValues(alpha: 0.12),
                      side: BorderSide(color: c.accent.withValues(alpha: 0.3)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// Нижняя шторка из матового стекла с «ручкой» сверху.
