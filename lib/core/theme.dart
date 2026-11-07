import 'package:flutter/material.dart';

import 'l10n.dart';

/// アプリの見た目（色・形・文字）。
///
/// 自動で作る色の組み合わせ（ColorScheme.fromSeed）は使わず、雀卓と牌から取った色を手で決めている:
/// 卓の緑・牌の象牙色の紙・墨色の文字・中の朱色。角は小さく丸め、影の代わりに細い線で区切る。
class AppTheme {
  AppTheme._();

  /// 卓の布の緑
  static const tableGreen = Color(0xFF1F4A3A);

  /// 中の朱色（強調に使う）
  static const vermilion = Color(0xFFB0352B);

  /// 牌の象牙色（明るい表示の背景）
  static const paper = Color(0xFFF3EEE3);

  /// 墨色（文字）
  static const ink = Color(0xFF26231F);

  /// 暗い表示で使う朱色（白い文字が読める濃さ）
  static const vermilionDark = Color(0xFFB8473C);

  /// 強調の朱色（明るい表示・暗い表示）
  static Color accent(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? vermilionDark : vermilion;

  static const _radius = 6.0;

  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: tableGreen,
      onPrimary: Color(0xFFF7F3EA),
      primaryContainer: Color(0xFFD7E3D9),
      onPrimaryContainer: Color(0xFF0F2A20),
      secondary: Color(0xFF6E5A3C),
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFE9DFCB),
      onSecondaryContainer: Color(0xFF2E2414),
      tertiary: vermilion,
      onTertiary: Colors.white,
      tertiaryContainer: Color(0xFFF2DCD5),
      onTertiaryContainer: Color(0xFF4A120D),
      error: Color(0xFFA2271F),
      onError: Colors.white,
      errorContainer: Color(0xFFF6D9D4),
      onErrorContainer: Color(0xFF410E0A),
      surface: Color(0xFFFBF8F1),
      onSurface: ink,
      onSurfaceVariant: Color(0xFF5C564C),
      surfaceContainerLowest: Color(0xFFFFFDF8),
      surfaceContainerLow: Color(0xFFFDFBF6),
      surfaceContainer: Color(0xFFF3EEE3),
      surfaceContainerHigh: Color(0xFFEDE7DA),
      surfaceContainerHighest: Color(0xFFE6DFD0),
      outline: Color(0xFF8C8577),
      outlineVariant: Color(0xFFD8D0BF),
      inverseSurface: Color(0xFF34302A),
      onInverseSurface: Color(0xFFF3EEE3),
      inversePrimary: Color(0xFF9CC8B2),
      shadow: Color(0x55000000),
      scrim: Colors.black,
      surfaceTint: Colors.transparent,
    );
    return _build(scheme, background: paper);
  }

  static ThemeData dark() {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFF8FC4AA),
      onPrimary: Color(0xFF0D2A1F),
      primaryContainer: Color(0xFF244A3B),
      onPrimaryContainer: Color(0xFFD3E8DC),
      secondary: Color(0xFFD5C2A0),
      onSecondary: Color(0xFF2E2414),
      secondaryContainer: Color(0xFF453826),
      onSecondaryContainer: Color(0xFFEFE3CC),
      tertiary: Color(0xFFE8968B),
      onTertiary: Color(0xFF4A120D),
      tertiaryContainer: Color(0xFF5E241D),
      onTertiaryContainer: Color(0xFFF6D9D4),
      error: Color(0xFFF0A49A),
      onError: Color(0xFF410E0A),
      errorContainer: Color(0xFF6B1D16),
      onErrorContainer: Color(0xFFF6D9D4),
      surface: Color(0xFF1A201D),
      onSurface: Color(0xFFE8E2D6),
      onSurfaceVariant: Color(0xFFB9B2A5),
      surfaceContainerLowest: Color(0xFF111614),
      surfaceContainerLow: Color(0xFF171D1A),
      surfaceContainer: Color(0xFF1C2320),
      surfaceContainerHigh: Color(0xFF232B27),
      surfaceContainerHighest: Color(0xFF2B3430),
      outline: Color(0xFF8A847A),
      outlineVariant: Color(0xFF3A433F),
      inverseSurface: Color(0xFFE8E2D6),
      onInverseSurface: Color(0xFF26231F),
      inversePrimary: tableGreen,
      shadow: Colors.black,
      scrim: Colors.black,
      surfaceTint: Colors.transparent,
    );
    return _build(scheme, background: const Color(0xFF131815));
  }

  /// 数字を等幅にする（点数の桁が縦にそろう）
  static TextTheme _tabular(TextTheme t) {
    TextStyle? f(TextStyle? s) => s?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    return t.copyWith(
      displayLarge: f(t.displayLarge),
      displayMedium: f(t.displayMedium),
      displaySmall: f(t.displaySmall),
      headlineLarge: f(t.headlineLarge),
      headlineMedium: f(t.headlineMedium),
      headlineSmall: f(t.headlineSmall),
      titleLarge: f(t.titleLarge),
      titleMedium: f(t.titleMedium),
      titleSmall: f(t.titleSmall),
      bodyLarge: f(t.bodyLarge),
      bodyMedium: f(t.bodyMedium),
      bodySmall: f(t.bodySmall),
      labelLarge: f(t.labelLarge),
      labelMedium: f(t.labelMedium),
      labelSmall: f(t.labelSmall),
    );
  }

  static ThemeData _build(ColorScheme scheme, {required Color background}) {
    final dark = scheme.brightness == Brightness.dark;
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius));
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    // 点数が縦にそろうように、数字は等幅にする
    final text = base.textTheme.apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface).copyWith(
          titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.2),
          titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          titleSmall: base.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        );
    return base.copyWith(
      scaffoldBackgroundColor: background,
      textTheme: _tabular(text),
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? const Color(0xFF17201C) : tableGreen,
        foregroundColor: dark ? scheme.onSurface : scheme.onPrimary,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: dark ? scheme.onSurface : scheme.onPrimary,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          shape: shape,
          // 暗い表示では、淡い色ではなく深い卓の緑にする
          backgroundColor: dark ? const Color(0xFF2C6B52) : null,
          foregroundColor: dark ? const Color(0xFFF1EEE6) : null,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.5),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: shape,
          side: BorderSide(color: scheme.outline),
          foregroundColor: scheme.onSurface,
        ),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(shape: shape)),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          shape: shape,
          selectedBackgroundColor: dark ? scheme.primaryContainer : tableGreen,
          selectedForegroundColor: dark ? scheme.onPrimaryContainer : scheme.onPrimary,
          side: BorderSide(color: scheme.outline),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: BorderSide(color: scheme.outlineVariant),
        backgroundColor: scheme.surface,
        selectedColor: dark ? scheme.primaryContainer : const Color(0xFFDCE7DF),
        showCheckmark: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(_radius)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(10))),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
      listTileTheme: ListTileThemeData(shape: shape),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: shape,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? scheme.onPrimary : null),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? (dark ? scheme.primary : tableGreen) : null),
      ),
    );
  }
}

/// 増えた・減ったの色（暗い表示では明るめの色にして読みやすくする）。0 なら null
Color? deltaColor(BuildContext context, num v) {
  if (v == 0) return null;
  final dark = Theme.of(context).brightness == Brightness.dark;
  if (v > 0) return dark ? const Color(0xFF8FC4AA) : const Color(0xFF1F6B4A);
  return dark ? const Color(0xFFE8968B) : AppTheme.vermilion;
}

/// 点数の表示（例: 25000 → "25,000"）
String formatPoints(int v) {
  final neg = v < 0;
  final s = v.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return neg ? '-$buf' : buf.toString();
}

/// 増減の表示（例: +3900 / -1300 / ±0）
String formatDelta(int v) {
  if (v == 0) return '±0';
  return v > 0 ? '+${formatPoints(v)}' : formatPoints(v);
}

/// ポイント表示（例: +45.0 / -12.3）
String formatPoint(double v) {
  final s = v.toStringAsFixed(1);
  return v > 0 ? '+$s' : s;
}

/// データサイズの表示（例: 523 → "523バイト", 51234 → "約51KB", 1234567 → "約1.2MB"）
String formatBytes(int bytes) {
  if (bytes < 1000) return tr('$bytesバイト', '$bytes bytes');
  if (bytes < 1000 * 1000) return tr('約${(bytes / 1000).round()}KB', 'about ${(bytes / 1000).round()} KB');
  return tr('約${(bytes / 1000 / 1000).toStringAsFixed(1)}MB', 'about ${(bytes / 1000 / 1000).toStringAsFixed(1)} MB');
}
