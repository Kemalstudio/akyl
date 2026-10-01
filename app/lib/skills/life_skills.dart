import '../data/contacts/morphology.dart';
import '../domain/entities/contact.dart';
import '../domain/entities/dialog_context.dart';
import '../domain/entities/intent.dart';
import '../domain/entities/nlu_result.dart';
import '../domain/entities/skill_result.dart';
import '../domain/ports/contact_resolver.dart';
import '../domain/ports/device_control.dart';
import '../domain/ports/life_ports.dart';
import '../domain/ports/phone.dart';
import '../domain/ports/skill.dart';

// --- Память ------------------------------------------------------------------

/// Слова заметки, по которым её потом ищут: основы длиной 4 буквы,
/// чтобы «ключи», «ключей», «ключах» совпадали между собой.
Set<String> _stems(String text) => RussianMorphology.normalize(text)
    .split(' ')
    .where((w) => w.length >= 3 && !_filler.contains(w))
    .map((w) => w.length > 5 ? w.substring(0, 5) : w)
    .toSet();

const _filler = {
  'что',
  'это',
  'мои',
  'мой',
  'моя',
  'мне',
  'про',
  'где',
  'как',
  'все',
  'был',
  'была',
  'было',
  'они',
  'его',
  'она',
  'там',
  'тут',
  'еще',
};

MemoryNote? _bestNote(List<MemoryNote> notes, String query) {
  final wanted = _stems(query);
  MemoryNote? best;
  var bestScore = 0;
  for (final note in notes) {
    final score = _stems(note.text).intersection(wanted).length;
    if (score > bestScore) {
      best = note;
      bestScore = score;
    }
  }
  return best;
}

/// «2 дня назад», «сегодня», «вчера».
String spokenAgo(DateTime at, DateTime now) {
  final day = DateTime(at.year, at.month, at.day);
  final today = DateTime(now.year, now.month, now.day);
  final days = today.difference(day).inDays;
  if (days <= 0) return 'сегодня';
  if (days == 1) return 'вчера';
  if (days < 7) return '$days ${_plural(days, 'день', 'дня', 'дней')} назад';
  final weeks = days ~/ 7;
  if (days < 30) {
    return '$weeks ${_plural(weeks, 'неделю', 'недели', 'недель')} назад';
  }
  final months = days ~/ 30;
  return '$months ${_plural(months, 'месяц', 'месяца', 'месяцев')} назад';
}

String _plural(int n, String one, String few, String many) {
  final mod100 = n % 100;
  final mod10 = n % 10;
  if (mod100 >= 11 && mod100 <= 14) return many;
  if (mod10 == 1) return one;
  if (mod10 >= 2 && mod10 <= 4) return few;
  return many;
}

class RememberSkill implements Skill {
  RememberSkill({required this.store, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final MemoryStore store;
  final DateTime Function() _clock;

  @override
  Intent get intent => Intent.remember;

  @override
  Future<SkillResult> execute(NluResult result, DialogContext ctx) async {
    final text = result.slot(Slot.value);
    if (text == null || text.isEmpty) {
      return SkillResult.failed(
        'Что запомнить? Скажите, например: запомни, ключи у Ахмеда',
      );
    }
    final notes = await store.load();
    notes.add(MemoryNote(text: text, at: _clock()));
    await store.save(notes);
    return SkillResult.done('Запомнил: $text');
  }
}

class RecallSkill implements Skill {
  RecallSkill({required this.store, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final MemoryStore store;
  final DateTime Function() _clock;

  @override
  Intent get intent => Intent.recall;

  @override
  Future<SkillResult> execute(NluResult result, DialogContext ctx) async {
    final notes = await store.load();
    if (notes.isEmpty) {
      return SkillResult.done(
        'Я пока ничего не запоминал. Скажите: запомни, и что именно',
      );
    }
    final query = result.slot(Slot.value);
    if (query == null) {
      final recent = notes.reversed.take(3).map((n) => n.text).join('; ');
      return SkillResult.done('Я помню: $recent');
    }
    final note = _bestNote(notes, query);
    if (note == null) {
      return SkillResult.done('Про «$query» вы мне ничего не говорили');
    }
    return SkillResult.done(
      'Вы говорили ${spokenAgo(note.at, _clock())}: ${note.text}',
    );
  }
}

class ForgetSkill implements Skill {
  ForgetSkill({required this.store});

  final MemoryStore store;

  @override
  Intent get intent => Intent.forget;

  @override
  Future<SkillResult> execute(NluResult result, DialogContext ctx) async {
    final notes = await store.load();
    final note = _bestNote(notes, result.slot(Slot.value) ?? '');
    if (note == null) return SkillResult.done('Такой записи нет');
    notes.remove(note);
    await store.save(notes);
    return SkillResult.done('Забыл: ${note.text}');
  }
}

// --- Звонки ------------------------------------------------------------------

/// «Когда я последний раз звонил папе».
class LastCallSkill implements Skill {
  LastCallSkill({
    required this.resolver,
    required this.device,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final ContactResolver resolver;
  final DeviceControl device;
  final DateTime Function() _clock;

  @override
  Intent get intent => Intent.lastCall;

  @override
  Future<SkillResult> execute(NluResult result, DialogContext ctx) async {
    final spoken = result.slot(Slot.contact) ?? '';
    final matches = await resolver.resolve(spoken);
    if (matches.isEmpty) {
      return SkillResult.failed('Не нашёл «$spoken» в контактах');
    }
    final contact = matches.first.contact;
    final numbers = [for (final p in contact.phones) p.number];
    try {
      final call = await device.lastCallWith(numbers);
      final name = contact.displayName;
      if (call == null) {
        return SkillResult.done('С контактом $name звонков не было');
      }
      final ago = spokenAgo(call.at, _clock());
      final hh = call.at.hour.toString().padLeft(2, '0');
      final mm = call.at.minute.toString().padLeft(2, '0');
      final what = switch (call.type) {
        'outgoing' => 'Вы звонили: $name',
        'missed' => 'Пропущенный звонок от: $name',
        _ => '$name звонил(а) вам',
      };
      // Давно не созванивались — мягко подсказываем.
      final nudge = _clock().difference(call.at).inDays >= 3
          ? '. Давно не созванивались — скажите «позвони», и я наберу'
          : '';
      return SkillResult.done('$what $ago в $hh:$mm$nudge', contact: contact);
    } on DeviceControlError catch (e) {
      return SkillResult.failed(e.message);
    }
  }
}

// --- Напоминания -------------------------------------------------------------

class RemindSkill implements Skill {
  RemindSkill({required this.scheduler, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final ReminderScheduler scheduler;
  final DateTime Function() _clock;
  static int _sequence = 0;

  @override
  Intent get intent => Intent.remind;

  @override
  Future<SkillResult> execute(NluResult result, DialogContext ctx) async {
    final when = result.slot(Slot.value);
    final text = result.slot(Slot.message);
    if (text == null || text.isEmpty) {
      return SkillResult.failed(
        'О чём напомнить? Например: напомни в 9 утра выпить таблетку',
      );
    }
    if (when == null) {
      return SkillResult.failed(
        'Когда напомнить? Скажите «в 9 утра», «через 10 минут» или «каждый день в 8»',
      );
    }

    final now = _clock();
    final parts = when.split('|');
    final DateTime at;
    var daily = false;
    switch (parts.first) {
      case 'in':
        at = now.add(Duration(seconds: int.parse(parts[1])));
      case 'once':
        at = DateTime.parse(parts[1]);
      case 'daily':
        daily = true;
        final hm = parts[1].split(':').map(int.parse).toList();
        var next = DateTime(now.year, now.month, now.day, hm[0], hm[1]);
        if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
        at = next;
      default:
        return SkillResult.failed('Не понял, когда напомнить');
    }

    // Секунды плюс счётчик: два напоминания за одну секунду не столкнутся.
    final id = (now.millisecondsSinceEpoch ~/ 1000 + _sequence++) % 1000000000;
    try {
      await scheduler.schedule(
        Reminder(id: id, text: text, at: at, daily: daily),
      );
    } on DeviceControlError catch (e) {
      return SkillResult.failed(e.message);
    }
    return SkillResult.done('Напомню ${_spokenWhen(at, now, daily)}: $text');
  }
}

String _hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String _spokenWhen(DateTime at, DateTime now, bool daily) {
  if (daily) return 'каждый день в ${_hhmm(at)}';
  final minutes = at.difference(now).inMinutes;
  if (minutes < 60) {
    final m = minutes < 1 ? 1 : minutes;
    return 'через $m ${_plural(m, 'минуту', 'минуты', 'минут')}';
  }
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(at.year, at.month, at.day);
  final prefix = day == today
      ? 'сегодня'
      : day.difference(today).inDays == 1
      ? 'завтра'
      : '${at.day}.${at.month.toString().padLeft(2, '0')}';
  return '$prefix в ${_hhmm(at)}';
}

class ListRemindersSkill implements Skill {
  ListRemindersSkill({required this.scheduler, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final ReminderScheduler scheduler;
  final DateTime Function() _clock;

  @override
  Intent get intent => Intent.listReminders;

  @override
  Future<SkillResult> execute(NluResult result, DialogContext ctx) async {
    final list = await scheduler.list();
    if (list.isEmpty) return SkillResult.done('Напоминаний нет');
    final now = _clock();
    final spoken = list
        .map((r) => '${_spokenWhen(r.at, now, r.daily)} — ${r.text}')
        .join('; ');
    return SkillResult.done('Напоминания: $spoken');
  }
}

class CancelReminderSkill implements Skill {
  CancelReminderSkill({required this.scheduler});

  final ReminderScheduler scheduler;

  @override
  Intent get intent => Intent.cancelReminder;

  @override
  Future<SkillResult> execute(NluResult result, DialogContext ctx) async {
    final list = await scheduler.list();
    if (list.isEmpty) return SkillResult.done('Напоминаний нет');
    final query = result.slot(Slot.value) ?? '';
    if (query == '*') {
      for (final r in list) {
        await scheduler.cancel(r.id);
      }
      return SkillResult.done('Удалил все напоминания: ${list.length}');
    }
    // Без уточнения — последнее поставленное.
    Reminder? target = query.isEmpty ? list.last : null;
    if (target == null) {
      final wanted = _stems(query);
      var best = 0;
      for (final r in list) {
        final score = _stems(r.text).intersection(wanted).length;
        if (score > best) {
          best = score;
          target = r;
        }
      }
    }
    if (target == null) return SkillResult.done('Такого напоминания нет');
    await scheduler.cancel(target.id);
    return SkillResult.done('Удалил напоминание: ${target.text}');
  }
}

// --- SOS ---------------------------------------------------------------------

/// «Помогите», «мне плохо»: сразу звонок первому из близких и SMS всем
/// с местом на карте.
///
/// SMS здесь уходит без «да» — исключение из ТЗ (FR-7) ради экстренного
/// случая. Согласие дано заранее: SOS работает, только если человек сам
/// назначил близких в настройках.
class SosSkill implements Skill {
  SosSkill({
    required this.phone,
    required this.device,
    required this.relatives,
  });

  final Phone phone;
  final DeviceControl device;

  /// Назначенные близкие в порядке важности.
  final Future<List<Contact>> Function() relatives;

  @override
  Intent get intent => Intent.sos;

  @override
  Future<SkillResult> execute(NluResult result, DialogContext ctx) async {
    final people = [
      for (final c in await relatives())
        if (c.primaryPhone != null) c,
    ];
    if (people.isEmpty) {
      return SkillResult.failed(
        'Назначьте близких в настройках — тогда по слову «помогите» я сразу '
        'позвоню им и отправлю, где вы. Экстренная служба: 112',
      );
    }

    ({double lat, double lon})? place;
    try {
      place = await device.location().timeout(
        const Duration(seconds: 6),
        onTimeout: () => null,
      );
    } catch (_) {
      place = null;
    }
    final where = place == null
        ? ''
        : ' Я здесь: https://maps.google.com/?q='
              '${place.lat.toStringAsFixed(5)},${place.lon.toStringAsFixed(5)}';
    final text = 'SOS! Мне нужна помощь, позвоните мне.$where (Alym AI)';

    final sent = <String>[];
    for (final person in people) {
      try {
        await phone.sendSms(number: person.primaryPhone!.number, text: text);
        sent.add(person.displayName);
      } catch (_) {
        // Одна ошибка не должна остановить остальные SMS.
      }
    }
    final first = people.first;
    await phone.call(first.primaryPhone!.number, speaker: true);

    return SkillResult.done(
      'Звоню: ${first.displayName}. SMS с просьбой о помощи'
      '${place == null ? '' : ' и местом'} отправлено: ${sent.join(', ')}',
      contact: first,
      alreadySpoken: true,
    );
  }
}
