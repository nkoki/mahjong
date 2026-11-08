import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// アプリの印（アプリのアイコンと同じデザイン）。
/// 上から見た卓: 木の枠・緑の卓・中央の盤（親の印の金色の点）・4人の前の立直棒。
/// アイコンの画像は tools/app_icon/make_icons.py で作る。デザインを変えるときは両方を合わせる
class AppMark extends StatelessWidget {
  final double size;
  const AppMark({super.key, this.size = 48});

  @override
  Widget build(BuildContext context) =>
      ExcludeSemantics(child: CustomPaint(size: Size.square(size), painter: const _AppMarkPainter()));
}

class _AppMarkPainter extends CustomPainter {
  const _AppMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width;
    final c = Offset(u / 2, u / 2);
    final outer = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(u * 0.09));
    canvas.drawRRect(outer.shift(Offset(0, u * 0.02)), Paint()..color = const Color(0x40000000));
    canvas.drawRRect(
      outer,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF6E4B2A), Color(0xFF4A3019)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCircle(center: c, radius: u * 0.44), Radius.circular(u * 0.05)),
        Paint()..color = AppTheme.tableGreen);

    final shadow = Paint()
      ..color = const Color(0x55000000)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, u * 0.012);
    final shadowOffset = Offset(0, u * 0.012);

    // 中央の盤と親の印
    final panel = RRect.fromRectAndRadius(Rect.fromCircle(center: c, radius: u * 0.17), Radius.circular(u * 0.04));
    canvas.drawRRect(panel.shift(shadowOffset), shadow);
    canvas.drawRRect(panel, Paint()..color = const Color(0xFF0F1F19));
    canvas.drawRRect(
        panel,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = u * 0.016
          ..color = const Color(0xFF2F5545));
    canvas.drawCircle(c, u * 0.045, Paint()..color = const Color(0xFFFFD27A));

    // 4人の前の立直棒（千点棒）
    final gap = u * 0.29, length = u * 0.36, thick = u * 0.062;
    for (final (d, vertical) in [
      (Offset(0, gap), false),
      (Offset(0, -gap), false),
      (Offset(gap, 0), true),
      (Offset(-gap, 0), true),
    ]) {
      final center = c + d;
      final rect = Rect.fromCenter(
          center: center, width: vertical ? thick : length, height: vertical ? length : thick);
      final stick = RRect.fromRectAndRadius(rect, Radius.circular(thick / 2));
      canvas.drawRRect(stick.shift(shadowOffset), shadow);
      canvas.drawRRect(stick, Paint()..color = const Color(0xFFFFFCF4));
      canvas.drawCircle(center, thick * 0.3, Paint()..color = AppTheme.vermilion);
    }
  }

  @override
  bool shouldRepaint(_AppMarkPainter oldDelegate) => false;
}
