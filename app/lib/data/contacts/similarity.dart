/// Нечёткое сравнение имён (ТЗ, FR-5).
/// Jaro-Winkler выбран потому, что даёт бонус за совпадающее начало слова:
/// STT чаще ошибается в конце имени, чем в первых буквах.
class Similarity {
  const Similarity();

  static const double _winklerPrefixWeight = 0.1;
  static const int _maxPrefix = 4;

  /// 0.0..1.0
  static double jaroWinkler(String a, String b) {
    final j = jaro(a, b);
    if (j < 0.7) return j; // стандартный порог: бонус только близким строкам

    var prefix = 0;
    final limit = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < limit && i < _maxPrefix; i++) {
      if (a[i] != b[i]) break;
      prefix++;
    }
    return j + prefix * _winklerPrefixWeight * (1 - j);
  }

  static double jaro(String a, String b) {
    if (a == b) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;

    final window = (a.length > b.length ? a.length : b.length) ~/ 2 - 1;
    final aMatched = List<bool>.filled(a.length, false);
    final bMatched = List<bool>.filled(b.length, false);

    var matches = 0;
    for (var i = 0; i < a.length; i++) {
      final lo = (i - window) < 0 ? 0 : i - window;
      final hi = (i + window + 1) > b.length ? b.length : i + window + 1;
      for (var k = lo; k < hi; k++) {
        if (bMatched[k] || a[i] != b[k]) continue;
        aMatched[i] = true;
        bMatched[k] = true;
        matches++;
        break;
      }
    }
    if (matches == 0) return 0.0;

    var transpositions = 0;
    var k = 0;
    for (var i = 0; i < a.length; i++) {
      if (!aMatched[i]) continue;
      while (!bMatched[k]) {
        k++;
      }
      if (a[i] != b[k]) transpositions++;
      k++;
    }

    final m = matches.toDouble();
    return (m / a.length + m / b.length + (m - transpositions / 2) / m) / 3;
  }
}
