import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Палитра Akyl.
///
/// Почти монохром: фон, бумага и три уровня текста. Цвет появляется ровно в
/// одном месте — когда ассистент слушает или ждёт ответа. Интерфейс голосового
/// помощника большую часть времени смотрят боковым зрением, и любая лишняя
/// краска в нём начинает спорить с единственным, что важно: состоянием.
@immutable
class AkylColors extends ThemeExtension<AkylColors> {
  const AkylColors({
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.accentMuted,
    required this.danger,
    required this.onAction,
    required this.action,
  });

  /// Фон экрана.
  final Color background;

  /// Поля ввода, карточки подсказок.
  final Color surface;

  /// Реплика пользователя, нажатое состояние.
  final Color surfaceRaised;

  final Color border;
  final Color borderStrong;

  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  /// Единственный цветной акцент: слушаю / жду ответа.
  final Color accent;
  final Color accentMuted;

  final Color danger;

  /// Главная кнопка: заливка [action], значок [onAction].
  final Color action;
  final Color onAction;

  // Нейтральная палитра, как у ChatGPT и Claude: графит вместо цвета,
  // фиолетовый — только акцент. Спокойный фон не спорит с текстом.
  static const AkylColors dark = AkylColors(
    background: Color(0xFF09081A),
    surface: Color(0xFF161431),
    surfaceRaised: Color(0xFF211E42),
    border: Color(0xFF2E2A58),
    borderStrong: Color(0xFF4A4485),
    textPrimary: Color(0xFFF1F0FA),
    textSecondary: Color(0xFFBDB9DC),
    textMuted: Color(0xFF8E89B5),
    accent: Color(0xFFA78BFA),
    accentMuted: Color(0xFF2A2352),
    danger: Color(0xFFF58A9B),
    action: Color(0xFFF1F0FA),
    onAction: Color(0xFF09081A),
  );

  static const AkylColors light = AkylColors(
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFF4F4F5),
    surfaceRaised: Color(0xFFEAEAEC),
    border: Color(0xFFE4E4E7),
    borderStrong: Color(0xFFC9C9CF),
    textPrimary: Color(0xFF0D0D0F),
    textSecondary: Color(0xFF52525B),
    textMuted: Color(0xFF7C7C86),
    accent: Color(0xFF6D4AE0),
    accentMuted: Color(0xFFEFEAFE),
    danger: Color(0xFFC0392B),
    action: Color(0xFF0D0D0F),
    onAction: Color(0xFFFFFFFF),
  );

  @override
  AkylColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceRaised,
    Color? border,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? accent,
    Color? accentMuted,
    Color? danger,
    Color? action,
    Color? onAction,
  }) {
    return AkylColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      accent: accent ?? this.accent,
      accentMuted: accentMuted ?? this.accentMuted,
      danger: danger ?? this.danger,
      action: action ?? this.action,
      onAction: onAction ?? this.onAction,
    );
  }

  @override
  AkylColors lerp(ThemeExtension<AkylColors>? other, double t) {
    if (other is! AkylColors) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AkylColors(
      background: mix(background, other.background),
      surface: mix(surface, other.surface),
      surfaceRaised: mix(surfaceRaised, other.surfaceRaised),
      border: mix(border, other.border),
      borderStrong: mix(borderStrong, other.borderStrong),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      textMuted: mix(textMuted, other.textMuted),
      accent: mix(accent, other.accent),
      accentMuted: mix(accentMuted, other.accentMuted),
      danger: mix(danger, other.danger),
      action: mix(action, other.action),
      onAction: mix(onAction, other.onAction),
    );
  }

  /// Короткий доступ: `context.akyl.textSecondary`.
  static AkylColors of(BuildContext context) =>
      Theme.of(context).extension<AkylColors>() ?? dark;
}

extension AkylColorsContext on BuildContext {
  AkylColors get akyl => AkylColors.of(this);
}

/// Радиусы и отступы — одни на всё приложение.
abstract final class AkylShape {
  /// Поле ввода и главная кнопка.
  static const double composer = 26;

  /// Реплики и карточки.
  static const double card = 18;

  /// Подсказки и мелкие элементы.
  static const double chip = 12;

  static const double gutter = 20;
}

abstract final class AkylTheme {
  static ThemeData dark() => _build(AkylColors.dark, Brightness.dark);

  static ThemeData light() => _build(AkylColors.light, Brightness.light);

  /// Цвета системных панелей под текущую тему: строка состояния прозрачная,
  /// панель навигации сливается с фоном — иначе внизу остаётся чужая полоса.
  static SystemUiOverlayStyle overlayStyle(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: dark
          ? AkylColors.dark.background
          : AkylColors.light.background,
      systemNavigationBarIconBrightness: dark
          ? Brightness.light
          : Brightness.dark,
      systemNavigationBarDividerColor: Colors.transparent,
    );
  }

  /// Nunito: скруглённый гротеск. Системный Roboto звучит по-канцелярски,
  /// а ассистент разговаривает с человеком — шрифт должен быть мягче.
  static const String fontFamily = 'Nunito';

  static ThemeData _build(AkylColors c, Brightness brightness) {
    final base = ThemeData(
      brightness: brightness,
      useMaterial3: true,
      fontFamily: fontFamily,
    );

    // Плотная, слегка сжатая типографика: так экран читается как документ,
    // а не как набор кнопок.
    final text = base.textTheme.copyWith(
      // Nunito шире и круглее Roboto, поэтому трекинг чуть плотнее,
      // а межстрочный интервал чуть больше — иначе строки слипаются.
      displaySmall: TextStyle(
        fontSize: 30,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
        color: c.textPrimary,
      ),
      titleMedium: TextStyle(
        fontSize: 17,
        height: 1.35,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: c.textPrimary,
      ),
      // Трекинг задан явно: иначе ThemeData подмешивает геометрию Material
      // (0.5 у bodyLarge), и широкий Nunito выглядит разреженным.
      bodyLarge: TextStyle(
        fontSize: 15.5,
        height: 1.5,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.1,
        color: c.textPrimary,
      ),
      bodyMedium: TextStyle(
        fontSize: 14.5,
        height: 1.5,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        color: c.textSecondary,
      ),
      labelLarge: TextStyle(
        fontSize: 14,
        height: 1.25,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: c.textPrimary,
      ),
      labelSmall: TextStyle(
        fontSize: 11.5,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: c.textMuted,
      ),
      labelMedium: TextStyle(
        fontSize: 12.5,
        height: 1.25,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: c.textSecondary,
      ),
    );

    return base.copyWith(
      scaffoldBackgroundColor: c.background,
      colorScheme: base.colorScheme.copyWith(
        surface: c.background,
        primary: c.textPrimary,
        secondary: c.accent,
        error: c.danger,
      ),
      // apply, а не просто text: заданные ниже TextStyle создаются с нуля и
      // семейство из ThemeData не наследуют — без этой строки Nunito
      // применялся бы только к стилям, которые мы не переопределили.
      textTheme: text.apply(fontFamily: fontFamily),
      splashFactory: InkSparkle.splashFactory,
      extensions: [c],
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: overlayStyle(brightness),
        iconTheme: IconThemeData(color: c.textSecondary, size: 22),
      ),
      iconTheme: IconThemeData(color: c.textSecondary, size: 22),
      dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.surfaceRaised,
        contentTextStyle: text.bodyLarge,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AkylShape.chip),
        ),
      ),
    );
  }
}
