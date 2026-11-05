import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mahjong_score_engine/mahjong_score_engine.dart';

import '../../core/l10n.dart';

/// 本物の牌に近い見た目で牌を描く（画像を使わず、図形と文字で描く）。
///
/// - 牌の厚み: 白い面の下に、背の色の層を少し見せる
/// - 筒子: 決まった並びの丸（二重の輪）。一筒は大きな飾りの丸
/// - 索子: 節のある竹。一索は鳥
/// - 萬子: 漢数字と赤い「萬」
/// - 字牌: 東南西北は黒、發は緑、中は赤、白は青い枠
/// - 赤ドラ: 赤い5
class TilePainter extends CustomPainter {
  final Tile tile;
  final bool selected;

  /// 文字のフォント（アプリの文字と同じものを使う）
  final TextStyle textStyle;

  TilePainter(this.tile, {this.selected = false, this.textStyle = const TextStyle()});

  // 牌の色（本物の牌の色に近い、落ち着いた色）
  static const ink = Color(0xFF1C1F33);
  static const red = Color(0xFFC8102E);
  static const green = Color(0xFF16794A);
  static const blue = Color(0xFF1C4FA0);
  static const face = Color(0xFFFFFCF2);
  static const faceShade = Color(0xFFEDE6D3);
  static const back = Color(0xFF1E7A57);

  static const _manNums = ['一', '二', '三', '四', '伍', '六', '七', '八', '九'];
  static const _honors = ['東', '南', '西', '北', '白', '發', '中'];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final radius = Radius.circular(w * 0.14);
    final thick = h * 0.07;

    // 影
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.02, h * 0.04, w * 0.98, h * 0.96), radius),
      Paint()
        ..color = const Color(0x40000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
    );
    // 背の層（厚み）
    final body = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w * 0.98, h * 0.98), radius);
    canvas.drawRRect(body, Paint()..color = back);
    // 白い面（上から下へ少し陰る）
    final faceRect = Rect.fromLTWH(0, 0, w * 0.98, h * 0.98 - thick);
    final faceR = RRect.fromRectAndRadius(faceRect, radius);
    canvas.drawRRect(
      faceR,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [face, face, faceShade],
          stops: [0, 0.7, 1],
        ).createShader(faceRect),
    );
    // 面と背の境目の白い線（牌の側面の照り返し）
    canvas.drawRRect(
      faceR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.6, w * 0.02)
        ..color = const Color(0x55000000),
    );

    // 絵柄を描く範囲
    final pad = w * 0.12;
    final area = Rect.fromLTRB(pad, pad * 0.9, faceRect.width - pad, faceRect.height - pad * 0.9);
    canvas.save();
    canvas.clipRRect(faceR);
    _drawFace(canvas, area);
    canvas.restore();

    if (selected) {
      canvas.drawRRect(
        body.deflate(1),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2, w * 0.08)
          ..color = Colors.orange,
      );
    }
  }

  void _drawFace(Canvas canvas, Rect a) {
    final suit = tileSuit(tile);
    final n = tileNumber(tile);
    final aka = isRedDora(tile);
    switch (suit) {
      case 'p':
        _pin(canvas, a, n, aka);
      case 's':
        _sou(canvas, a, n, aka);
      case 'm':
        _man(canvas, a, n, aka);
      default:
        _honor(canvas, a, n);
    }
  }

  // ---- 筒子 ----

  /// 筒子の並び（x, y は描く範囲の中の割合）と色
  static const _pinLayouts = <int, List<(double, double, Color)>>{
    2: [(0.5, 0.25, blue), (0.5, 0.75, green)],
    3: [(0.2, 0.16, blue), (0.5, 0.5, red), (0.8, 0.84, green)],
    4: [(0.27, 0.25, blue), (0.73, 0.25, green), (0.27, 0.75, green), (0.73, 0.75, blue)],
    5: [(0.24, 0.18, blue), (0.76, 0.18, green), (0.5, 0.5, red), (0.24, 0.82, green), (0.76, 0.82, blue)],
    6: [(0.27, 0.15, green), (0.73, 0.15, green), (0.27, 0.53, red), (0.73, 0.53, red), (0.27, 0.86, red), (0.73, 0.86, red)],
    7: [
      (0.18, 0.1, green), (0.5, 0.21, green), (0.82, 0.32, green),
      (0.27, 0.6, red), (0.73, 0.6, red), (0.27, 0.88, red), (0.73, 0.88, red),
    ],
    8: [
      (0.27, 0.11, blue), (0.73, 0.11, blue), (0.27, 0.37, blue), (0.73, 0.37, blue),
      (0.27, 0.63, blue), (0.73, 0.63, blue), (0.27, 0.89, blue), (0.73, 0.89, blue),
    ],
    9: [
      (0.17, 0.15, blue), (0.5, 0.15, blue), (0.83, 0.15, blue),
      (0.17, 0.5, red), (0.5, 0.5, red), (0.83, 0.5, red),
      (0.17, 0.85, green), (0.5, 0.85, green), (0.83, 0.85, green),
    ],
  };

  static const _pinRadius = {2: 0.26, 3: 0.21, 4: 0.23, 5: 0.2, 6: 0.19, 7: 0.17, 8: 0.15, 9: 0.16};

  void _pin(Canvas canvas, Rect a, int n, bool aka) {
    if (n == 1) {
      final c = a.center;
      final r = math.min(a.width, a.height) * 0.5;
      _ring(canvas, c, r, aka ? red : blue);
      _ring(canvas, c, r * 0.68, aka ? red : green);
      canvas.drawCircle(c, r * 0.36, Paint()..color = red);
      canvas.drawCircle(c, r * 0.14, Paint()..color = face);
      // 飾りの点
      final dot = Paint()..color = aka ? red : green;
      for (var i = 0; i < 8; i++) {
        final t = i * math.pi / 4;
        canvas.drawCircle(c + Offset(math.cos(t), math.sin(t)) * r * 0.84, r * 0.06, dot);
      }
      return;
    }
    final r = a.width * _pinRadius[n]!;
    for (final (x, y, color) in _pinLayouts[n]!) {
      final c = Offset(a.left + a.width * x, a.top + a.height * y);
      final col = aka ? red : color;
      canvas.drawCircle(c, r, Paint()..color = col);
      canvas.drawCircle(c, r * 0.72, Paint()..color = face);
      canvas.drawCircle(c, r * 0.5, Paint()..color = col);
      canvas.drawCircle(c, r * 0.17, Paint()..color = face);
    }
  }

  void _ring(Canvas canvas, Offset c, double r, Color color) {
    canvas.drawCircle(c, r, Paint()..color = color);
    canvas.drawCircle(c, r * 0.86, Paint()..color = face);
  }

  // ---- 索子 ----

  /// 竹の並び（中心 x, y、傾き（度）、色）。高さは [_souHeight]
  static const _souLayouts = <int, List<(double, double, double, Color)>>{
    2: [(0.5, 0.25, 0, green), (0.5, 0.75, 0, green)],
    3: [(0.5, 0.25, 0, green), (0.27, 0.75, 0, green), (0.73, 0.75, 0, green)],
    4: [(0.27, 0.25, 0, green), (0.73, 0.25, 0, green), (0.27, 0.75, 0, green), (0.73, 0.75, 0, green)],
    5: [(0.2, 0.25, 0, green), (0.8, 0.25, 0, green), (0.5, 0.5, 0, red), (0.2, 0.75, 0, green), (0.8, 0.75, 0, green)],
    6: [
      (0.18, 0.25, 0, green), (0.5, 0.25, 0, green), (0.82, 0.25, 0, green),
      (0.18, 0.75, 0, green), (0.5, 0.75, 0, green), (0.82, 0.75, 0, green),
    ],
    7: [
      (0.5, 0.15, 0, red),
      (0.18, 0.5, 0, green), (0.5, 0.5, 0, green), (0.82, 0.5, 0, green),
      (0.18, 0.84, 0, green), (0.5, 0.84, 0, green), (0.82, 0.84, 0, green),
    ],
    8: [
      (0.12, 0.25, 0, green), (0.37, 0.25, 22, green), (0.63, 0.25, -22, green), (0.88, 0.25, 0, green),
      (0.12, 0.75, 0, green), (0.37, 0.75, -22, green), (0.63, 0.75, 22, green), (0.88, 0.75, 0, green),
    ],
    9: [
      (0.18, 0.16, 0, green), (0.5, 0.16, 0, red), (0.82, 0.16, 0, green),
      (0.18, 0.5, 0, green), (0.5, 0.5, 0, red), (0.82, 0.5, 0, green),
      (0.18, 0.84, 0, green), (0.5, 0.84, 0, red), (0.82, 0.84, 0, green),
    ],
  };

  static double _souHeight(int n) => switch (n) { 2 => 0.42, 3 || 4 || 5 || 6 || 8 => 0.42, _ => 0.29 };

  void _sou(Canvas canvas, Rect a, int n, bool aka) {
    if (n == 1) {
      _bird(canvas, a, aka);
      return;
    }
    final sh = a.height * _souHeight(n);
    final sw = a.width * (n >= 6 ? 0.13 : 0.15);
    for (final (x, y, deg, color) in _souLayouts[n]!) {
      final c = Offset(a.left + a.width * x, a.top + a.height * y);
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(deg * math.pi / 180);
      _stick(canvas, sw, sh, aka ? red : color);
      canvas.restore();
    }
  }

  /// 節のある竹1本（原点が中心）
  void _stick(Canvas canvas, double w, double h, Color color) {
    final dark = Color.lerp(color, Colors.black, 0.3)!;
    final light = Color.lerp(color, Colors.white, 0.45)!;
    final rect = Rect.fromCenter(center: Offset.zero, width: w, height: h);
    // 竹の丸みが出るように、左右で濃さを変える
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(w * 0.5)),
      Paint()
        ..shader = LinearGradient(colors: [dark, color, light, color, dark], stops: const [0, 0.25, 0.45, 0.7, 1])
            .createShader(rect),
    );
    // 節（上・真ん中・下）: 少しふくらんだ明るい帯
    final node = Paint()
      ..color = face.withAlpha(210)
      ..strokeWidth = math.max(0.6, h * 0.035)
      ..strokeCap = StrokeCap.round;
    final bulge = Paint()..color = dark;
    for (final t in [-0.5, 0.0, 0.5]) {
      final y = h * t * 0.86;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(0, y), width: w * 1.22, height: h * 0.09),
            Radius.circular(h * 0.05)),
        bulge,
      );
      canvas.drawLine(Offset(-w * 0.42, y), Offset(w * 0.42, y), node);
    }
  }

  /// 一索の鳥（尾羽・体・頭）
  void _bird(Canvas canvas, Rect a, bool aka) {
    final body = aka ? red : green;
    final u = a.width, v = a.height;
    Offset p(double x, double y) => Offset(a.left + u * x, a.top + v * y);
    // 尾羽（扇のように広げる）
    final tail = Paint()..color = aka ? red : blue;
    for (var i = 0; i < 3; i++) {
      canvas.save();
      final base = p(0.42, 0.62);
      canvas.translate(base.dx, base.dy);
      canvas.rotate((-35 - i * 25) * math.pi / 180);
      canvas.drawOval(Rect.fromLTWH(0, -u * 0.08, u * 0.5, u * 0.16), i == 1 ? (Paint()..color = body) : tail);
      canvas.drawCircle(Offset(u * 0.42, 0), u * 0.045, Paint()..color = red);
      canvas.restore();
    }
    // 体
    canvas.drawOval(Rect.fromCenter(center: p(0.55, 0.62), width: u * 0.55, height: v * 0.34), Paint()..color = body);
    // 羽
    canvas.drawOval(
      Rect.fromCenter(center: p(0.5, 0.62), width: u * 0.32, height: v * 0.16),
      Paint()..color = Color.lerp(body, Colors.black, 0.3)!,
    );
    // 首と頭
    canvas.drawLine(
      p(0.68, 0.52),
      p(0.74, 0.3),
      Paint()
        ..color = body
        ..strokeWidth = u * 0.13
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(p(0.75, 0.25), u * 0.11, Paint()..color = red);
    canvas.drawCircle(p(0.78, 0.23), u * 0.03, Paint()..color = face);
    // くちばし
    final beak = Path()
      ..moveTo(p(0.84, 0.23).dx, p(0.84, 0.23).dy)
      ..lineTo(p(0.98, 0.28).dx, p(0.98, 0.28).dy)
      ..lineTo(p(0.84, 0.3).dx, p(0.84, 0.3).dy)
      ..close();
    canvas.drawPath(beak, Paint()..color = const Color(0xFFE0A000));
    // 足
    final leg = Paint()
      ..color = red
      ..strokeWidth = math.max(0.8, u * 0.04);
    canvas.drawLine(p(0.5, 0.78), p(0.45, 0.95), leg);
    canvas.drawLine(p(0.62, 0.78), p(0.66, 0.95), leg);
  }

  // ---- 萬子・字牌 ----

  void _man(Canvas canvas, Rect a, int n, bool aka) {
    _text(canvas, _manNums[n - 1], Rect.fromLTRB(a.left, a.top, a.right, a.top + a.height * 0.5), aka ? red : ink);
    _text(canvas, '萬', Rect.fromLTRB(a.left, a.top + a.height * 0.47, a.right, a.bottom), red);
  }

  void _honor(Canvas canvas, Rect a, int n) {
    if (n == 5) {
      // 白: 青い枠
      final frame = a.deflate(a.width * 0.06);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, a.width * 0.07)
        ..color = blue.withAlpha(190);
      canvas.drawRRect(RRect.fromRectAndRadius(frame, Radius.circular(a.width * 0.08)), paint);
      canvas.drawRRect(
        RRect.fromRectAndRadius(frame.deflate(a.width * 0.14), Radius.circular(a.width * 0.04)),
        paint..strokeWidth = math.max(0.6, a.width * 0.03),
      );
      return;
    }
    final color = switch (n) { 6 => green, 7 => red, _ => ink };
    _text(canvas, _honors[n - 1], a, color);
  }

  /// [box] に収まる大きさで文字を描く
  void _text(Canvas canvas, String s, Rect box, Color color) {
    TextPainter layout(double size) => TextPainter(
          text: TextSpan(
            text: s,
            style: textStyle.copyWith(
              color: color,
              fontSize: size,
              fontWeight: FontWeight.w900,
              height: 1.0,
              letterSpacing: 0,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
    var tp = layout(box.height);
    final scale = math.min(box.width / tp.width, box.height / tp.height);
    if (scale < 1) tp = layout(box.height * scale);
    tp.paint(canvas, box.center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(TilePainter old) => old.tile != tile || old.selected != selected || old.textStyle != textStyle;
}

/// 牌の読み上げ用の名前（例: 5萬、赤5筒、東）
String tileSpokenName(Tile tile) {
  final suit = tileSuit(tile);
  final n = tileNumber(tile);
  if (L10n.isEnglish) {
    final redEn = isRedDora(tile) ? 'Red ' : '';
    return switch (suit) {
      'm' => '$redEn$n Man',
      'p' => '$redEn$n Pin',
      's' => '$redEn$n Sou',
      _ => const ['East', 'South', 'West', 'North', 'White', 'Green', 'Red'][n - 1],
    };
  }
  final red = isRedDora(tile) ? '赤' : '';
  return switch (suit) {
    'm' => '$red$n萬',
    'p' => '$red$n筒',
    's' => '$red$n索',
    _ => const ['東', '南', '西', '北', '白', '發', '中'][n - 1],
  };
}
