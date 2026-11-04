import 'package:flutter/material.dart';

/// 雀卓をイメージした緑基調のテーマ
class AppTheme {
  AppTheme._();

  static const tableGreen = Color(0xFF1B5E20);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(seedColor: tableGreen);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        centerTitle: true,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  static ThemeData dark() {
    final scheme =
        ColorScheme.fromSeed(seedColor: tableGreen, brightness: Brightness.dark);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
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
