/// Системные вызовы Android: звонок, SMS, чтение контактов.
/// Единственное место, где Dart говорит с Kotlin (ТЗ, раздел 5).
abstract class Phone {
  /// Все нужные разрешения выданы.
  Future<bool> hasPermissions();

  Future<bool> requestPermissions();

  /// Немедленный звонок — ACTION_CALL, без экрана набора (ТЗ, FR-6).
  ///
  /// [speaker] — включить громкую связь, когда звонок соединится: «позвони
  /// маме по громкой связи». Включается после соединения, а не сразу:
  /// до этого аудиотракт ещё не в режиме разговора.
  Future<void> call(String number, {bool speaker = false});

  /// Отправить SMS. Вызывается только после подтверждения (ТЗ, FR-7).
  Future<void> sendSms({required String number, required String text});
}
