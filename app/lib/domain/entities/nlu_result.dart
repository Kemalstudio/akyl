import 'intent.dart';

/// Результат разбора фразы: намерение + слоты + уверенность (ТЗ, раздел 5).
class NluResult {
  const NluResult({
    required this.intent,
    this.slots = const {},
    required this.confidence,
  });

  final Intent intent;
  final Map<Slot, String> slots;

  /// 0.0..1.0. Порог автоматического действия — 0.85 (ТЗ, FR-6).
  final double confidence;

  static const NluResult unknown =
      NluResult(intent: Intent.unknown, confidence: 0.0);

  String? slot(Slot s) => slots[s];

  /// Порог, при котором звонок выполняется без уточнения (ТЗ, FR-6).
  static const double autoExecuteThreshold = 0.85;

  bool get isConfident => confidence >= autoExecuteThreshold;

  NluResult copyWith({
    Intent? intent,
    Map<Slot, String>? slots,
    double? confidence,
  }) =>
      NluResult(
        intent: intent ?? this.intent,
        slots: slots ?? this.slots,
        confidence: confidence ?? this.confidence,
      );

  @override
  String toString() =>
      'NluResult($intent, slots: $slots, conf: ${confidence.toStringAsFixed(2)})';
}
