import 'dart:math' as math;
import 'dart:typed_data';

/// Отпечаток одного слова: кадры MFCC (по 10 мс, 12 коэффициентов).
typedef VoicePrint = List<Float32List>;

/// MFCC — «слуховой» спектр речи, как его чаще всего видят системы
/// распознавания: 25-мс окна через 10 мс, 26 мел-фильтров, 12 кепстральных
/// коэффициентов, вычитание среднего (убирает окраску микрофона).
///
/// Своя реализация на чистом Dart: работает в изоляте конвейера, без
/// нативных библиотек, и считает одно слово (≤1.5 с) за доли миллисекунды.
class MfccExtractor {
  MfccExtractor() {
    for (var i = 0; i < _frame; i++) {
      _window[i] = 0.54 - 0.46 * math.cos(2 * math.pi * i / (_frame - 1));
    }
    _buildFilters();
    for (var k = 0; k < _ceps; k++) {
      for (var m = 0; m < _mels; m++) {
        _dct[k * _mels + m] = math.cos(math.pi * (k + 1) * (m + 0.5) / _mels);
      }
    }
  }

  static const _rate = 16000;
  static const _frame = 400; // 25 мс
  static const _hop = 160; // 10 мс
  static const _fft = 512;
  static const _bins = _fft ~/ 2 + 1;
  static const _mels = 26;
  static const _ceps = 12; // c1..c12, без c0 — громкость не важна

  final _window = Float64List(_frame);
  final _filters = <(int, Float64List)>[]; // начало и веса каждого фильтра
  final _dct = Float64List(_ceps * _mels);

  final _re = Float64List(_fft);
  final _im = Float64List(_fft);

  static double _hzToMel(double hz) =>
      2595 * math.log(1 + hz / 700) / math.ln10;
  static double _melToHz(double mel) => 700 * (math.pow(10, mel / 2595) - 1);

  void _buildFilters() {
    final low = _hzToMel(20), high = _hzToMel(7600);
    final points = [
      for (var i = 0; i < _mels + 2; i++)
        (_melToHz(low + (high - low) * i / (_mels + 1)) * _fft / _rate)
            .floor()
            .clamp(0, _bins - 1),
    ];
    for (var m = 1; m <= _mels; m++) {
      final a = points[m - 1], b = points[m], c = points[m + 1];
      final weights = Float64List(c - a + 1);
      for (var k = a; k <= c; k++) {
        weights[k - a] = k <= b
            ? (b == a ? 1 : (k - a) / (b - a))
            : (c == b ? 1 : (c - k) / (c - b));
      }
      _filters.add((a, weights));
    }
  }

  /// Отпечаток слова: речь выделяется по энергии, тишина по краям отрезается.
  VoicePrint extract(Float32List samples) {
    if (samples.length < _frame) return const [];
    final count = 1 + (samples.length - _frame) ~/ _hop;
    final frames = <Float32List>[];
    final energies = Float64List(count);
    final power = Float64List(_bins);
    final mel = Float64List(_mels);

    for (var f = 0; f < count; f++) {
      final start = f * _hop;
      var energy = 0.0;
      var previous = start > 0 ? samples[start - 1] : 0.0;
      for (var i = 0; i < _fft; i++) {
        if (i < _frame) {
          final s = samples[start + i];
          final emphasized = s - 0.97 * previous; // предыскажение
          previous = s;
          _re[i] = emphasized * _window[i];
          energy += s * s;
        } else {
          _re[i] = 0;
        }
        _im[i] = 0;
      }
      energies[f] = energy;
      _transform();
      for (var k = 0; k < _bins; k++) {
        power[k] = _re[k] * _re[k] + _im[k] * _im[k];
      }
      var loudest = 0.0;
      for (var m = 0; m < _mels; m++) {
        final (a, w) = _filters[m];
        var sum = 0.0;
        for (var k = 0; k < w.length; k++) {
          sum += w[k] * power[a + k];
        }
        mel[m] = sum;
        loudest = math.max(loudest, sum);
      }
      // Динамический диапазон 40 дБ: почти пустые полосы (тишина, чистый
      // тон) иначе дают огромные логарифмы и решают исход сравнения.
      final floor = loudest * 1e-4 + 1e-10;
      for (var m = 0; m < _mels; m++) {
        mel[m] = math.log(math.max(mel[m], floor));
      }
      final ceps = Float32List(_ceps);
      for (var k = 0; k < _ceps; k++) {
        var sum = 0.0;
        for (var m = 0; m < _mels; m++) {
          sum += _dct[k * _mels + m] * mel[m];
        }
        ceps[k] = sum;
      }
      frames.add(ceps);
    }

    // Речь — кадры громче 1/30 самого громкого (≈ −15 дБ).
    var peak = 0.0;
    for (final e in energies) {
      peak = math.max(peak, e);
    }
    if (peak <= 1e-8) return const [];
    var first = 0, last = count - 1;
    while (first < count && energies[first] < peak / 30) {
      first++;
    }
    while (last > first && energies[last] < peak / 30) {
      last--;
    }
    final speech = frames.sublist(first, last + 1);
    if (speech.length < 8) return const []; // короче 80 мс — не слово

    // Вычитание среднего по слову: микрофон и комната окрашивают спектр.
    final mean = Float64List(_ceps);
    for (final c in speech) {
      for (var k = 0; k < _ceps; k++) {
        mean[k] += c[k];
      }
    }
    for (var k = 0; k < _ceps; k++) {
      mean[k] /= speech.length;
    }
    for (final c in speech) {
      for (var k = 0; k < _ceps; k++) {
        c[k] -= mean[k];
      }
    }
    return speech;
  }

  /// Быстрое преобразование Фурье по месту, 512 точек.
  void _transform() {
    final n = _fft;
    for (var i = 1, j = 0; i < n; i++) {
      var bit = n >> 1;
      for (; j & bit != 0; bit >>= 1) {
        j ^= bit;
      }
      j ^= bit;
      if (i < j) {
        final tr = _re[i];
        _re[i] = _re[j];
        _re[j] = tr;
        final ti = _im[i];
        _im[i] = _im[j];
        _im[j] = ti;
      }
    }
    for (var len = 2; len <= n; len <<= 1) {
      final angle = -2 * math.pi / len;
      final wr = math.cos(angle), wi = math.sin(angle);
      for (var i = 0; i < n; i += len) {
        var cr = 1.0, ci = 0.0;
        for (var j = 0; j < len ~/ 2; j++) {
          final ar = _re[i + j], ai = _im[i + j];
          final br = _re[i + j + len ~/ 2], bi = _im[i + j + len ~/ 2];
          final tr = br * cr - bi * ci, ti = br * ci + bi * cr;
          _re[i + j] = ar + tr;
          _im[i + j] = ai + ti;
          _re[i + j + len ~/ 2] = ar - tr;
          _im[i + j + len ~/ 2] = ai - ti;
          final next = cr * wr - ci * wi;
          ci = cr * wi + ci * wr;
          cr = next;
        }
      }
    }
  }
}

/// Расстояние между двумя словами: динамическое выравнивание по времени
/// (DTW) — «Макс» можно сказать быстрее или медленнее. Нормировано на
/// длину пути, поэтому короткие и длинные слова сравнимы.
double voicePrintDistance(VoicePrint a, VoicePrint b) {
  final n = a.length, m = b.length;
  if (n == 0 || m == 0) return double.infinity;
  // Слово вдвое длиннее или короче образца — точно другое слово.
  if (n > 2 * m || m > 2 * n) return double.infinity;
  final band = math.max((0.35 * math.max(n, m)).ceil(), (n - m).abs() + 2);
  var previous = Float64List(m + 1)..fillRange(0, m + 1, double.infinity);
  var current = Float64List(m + 1);
  previous[0] = 0;
  for (var i = 1; i <= n; i++) {
    current.fillRange(0, m + 1, double.infinity);
    final center = (i * m / n).round();
    final from = math.max(1, center - band), to = math.min(m, center + band);
    for (var j = from; j <= to; j++) {
      final x = a[i - 1], y = b[j - 1];
      var sum = 0.0;
      for (var k = 0; k < x.length; k++) {
        final d = x[k] - y[k];
        sum += d * d;
      }
      final best = math.min(
        previous[j - 1],
        math.min(previous[j], current[j - 1]),
      );
      current[j] = math.sqrt(sum) + best;
    }
    final swap = previous;
    previous = current;
    current = swap;
  }
  return previous[m] / (n + m);
}

/// Образцы голоса человека для одиночного «Макс» и порог сходства.
class WakeVoice {
  const WakeVoice({required this.prints, required this.threshold});

  final List<VoicePrint> prints;
  final double threshold;

  bool get isEmpty => prints.isEmpty;

  /// Ближайший образец.
  double distance(VoicePrint word) {
    var best = double.infinity;
    for (final p in prints) {
      best = math.min(best, voicePrintDistance(word, p));
    }
    return best;
  }

  bool matches(VoicePrint word) => !isEmpty && distance(word) <= threshold;

  /// Порог по самим образцам: насколько близки друг к другу два самых
  /// похожих «Макс» этого человека.
  ///
  /// Замер на синтезе: одиночное «Макс» с тремя образцами узнаётся в 9–12
  /// случаях из 12 (без них — 5–7), одиночные «да», «так», «нет», «мама»,
  /// «Максим», «алло», «вакс», «нас» будят помощника 0–2 раза из 16. Средняя
  /// из двух меньших взаимных дистанций образцов отделяет их лучше всего;
  /// границы не дают порогу уйти в крайности на неудачных записях.
  factory WakeVoice.enroll(List<VoicePrint> prints) {
    final usable = prints.where((p) => p.isNotEmpty).toList();
    final pairs = <double>[
      for (var i = 0; i < usable.length; i++)
        for (var j = i + 1; j < usable.length; j++)
          voicePrintDistance(usable[i], usable[j]),
    ]..sort();
    final base = pairs.isEmpty
        ? _maxThreshold
        : pairs.length == 1
        ? pairs.first
        : (pairs[0] + pairs[1]) / 2;
    final threshold = (base * 1.05).clamp(_minThreshold, _maxThreshold);
    return WakeVoice(prints: usable, threshold: threshold);
  }

  static const _minThreshold = 3.4;
  static const _maxThreshold = 4.2;

  Map<String, Object> toJson() => {
    'threshold': threshold,
    'prints': [
      for (final p in prints)
        [
          for (final frame in p) [for (final v in frame) v],
        ],
    ],
  };

  static WakeVoice? fromJson(Object? json) {
    if (json is! Map) return null;
    final threshold = json['threshold'];
    final raw = json['prints'];
    if (threshold is! num || raw is! List) return null;
    final prints = <VoicePrint>[
      for (final p in raw.whereType<List<Object?>>())
        [
          for (final frame in p.whereType<List<Object?>>())
            Float32List.fromList([
              for (final v in frame) (v as num?)?.toDouble() ?? 0,
            ]),
        ],
    ];
    if (prints.isEmpty) return null;
    return WakeVoice(prints: prints, threshold: threshold.toDouble());
  }
}
