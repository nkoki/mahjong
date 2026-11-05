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

/// 増えた・減ったの色（暗い表示では明るめの色にして読みやすくする）。0 なら null
Color? deltaColor(BuildContext context, num v) {
  if (v == 0) return null;
  final dark = Theme.of(context).brightness == Brightness.dark;
  if (v > 0) return dark ? Colors.green.shade300 : Colors.green.shade700;
  return dark ? Colors.red.shade300 : Colors.red.shade700;
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
  if (bytes < 1000) return '$bytesバイト';
  if (bytes < 1000 * 1000) return '約${(bytes / 1000).round()}KB';
  return '約${(bytes / 1000 / 1000).toStringAsFixed(1)}MB';
}
