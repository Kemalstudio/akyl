import 'contact.dart';
import 'intent.dart';
import 'nlu_result.dart';

/// Контекст диалога живёт 60 секунд (ТЗ, FR-8): «ему», «ей», «ещё раз», «первому».
class DialogContext {
  DialogContext({this.ttl = const Duration(seconds: 60), DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final Duration ttl;
  final DateTime Function() _clock;

  Contact? _lastContact;
  PhoneType? _lastPhoneType;
  NluResult? _pendingAction;
  List<ContactMatch> _choices = const [];
  DateTime? _touchedAt;

  /// Последний собеседник — для «позвони ему ещё раз» (сценарий С7).
  Contact? get lastContact => _alive ? _lastContact : null;

  PhoneType? get lastPhoneType => _alive ? _lastPhoneType : null;

  /// Действие, ожидающее подтверждения (SMS, ТЗ FR-7).
  NluResult? get pendingAction => _alive ? _pendingAction : null;

  /// Варианты, из которых пользователь выбирает (сценарий С5).
  List<ContactMatch> get choices => _alive ? _choices : const [];

  bool get _alive {
    final t = _touchedAt;
    if (t == null) return false;
    return _clock().difference(t) <= ttl;
  }

  /// Контекст ещё не истёк и в нём что-то есть.
  bool get isAlive => _alive;

  void rememberContact(Contact contact, {PhoneType? phoneType}) {
    _lastContact = contact;
    _lastPhoneType = phoneType;
    _touch();
  }

  void awaitConfirmation(NluResult action) {
    _pendingAction = action;
    _touch();
  }

  void offerChoices(List<ContactMatch> matches) {
    _choices = List.unmodifiable(matches);
    _touch();
  }

  void clearPending() {
    _pendingAction = null;
    _choices = const [];
  }

  /// Полный сброс — после «отмена» или выполнения команды.
  void reset() {
    _lastContact = null;
    _lastPhoneType = null;
    _pendingAction = null;
    _choices = const [];
    _touchedAt = null;
  }

  void _touch() => _touchedAt = _clock();
}
