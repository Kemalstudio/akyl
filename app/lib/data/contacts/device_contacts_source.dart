import 'package:flutter/services.dart';

import '../../domain/entities/contact.dart';
import '../../domain/entities/intent.dart';
import '../../domain/ports/contacts_source.dart';

/// Адресная книга устройства через ContactsContract (Kotlin).
///
/// Контакты не покидают телефон и никуда не кэшируются на диск (ТЗ, раздел 3:
/// приватность) — индекс живёт только в памяти процесса.
class DeviceContactsSource implements ContactsSource {
  const DeviceContactsSource();

  static const MethodChannel _channel = MethodChannel('dev.akyl/contacts');

  @override
  Future<List<Contact>> loadAll() async {
    final raw = await _channel.invokeListMethod<Map<Object?, Object?>>('loadAll');
    if (raw == null) return const [];
    return raw.map(_toContact).toList();
  }

  static Contact _toContact(Map<Object?, Object?> m) {
    final phones = (m['phones'] as List<Object?>? ?? const [])
        .cast<Map<Object?, Object?>>()
        .map(_toPhone)
        .toList();
    return Contact(
      id: m['id'] as String? ?? '',
      displayName: m['displayName'] as String? ?? '',
      phones: phones,
    );
  }

  static PhoneNumber _toPhone(Map<Object?, Object?> m) => PhoneNumber(
        number: m['number'] as String? ?? '',
        type: _phoneType(m['type'] as String?),
        label: m['label'] as String?,
      );

  /// Строки приходят из Kotlin, где ContactsContract.TYPE_* уже приведён
  /// к именам PhoneType — одно место сопоставления вместо магических чисел.
  static PhoneType _phoneType(String? name) {
    for (final t in PhoneType.values) {
      if (t.name == name) return t;
    }
    return PhoneType.other;
  }
}
