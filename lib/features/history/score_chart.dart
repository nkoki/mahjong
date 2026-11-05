import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../session/domain/models.dart';

/// 点数の推移（グラフに描く値）
class ScoreSeries {
  /// 横軸の目盛りの名前（[0] は「開始」、そのあとは局の名前。例: 東1）
  final List<String> labels;

  /// プレイヤーごとの点数（[labels] と同じ長さ）
  final List<List<int>> scores;

  const ScoreSeries(this.labels, this.scores);

  /// 対局の開始時の点数と、各局が終わったあとの点数
  factory ScoreSeries.of(GameSession s) {
    final labels = ['開始', for (final r in s.records) shortRoundLabel(r.roundLabel)];
    final scores = [
      for (var p = 0; p < s.playerCount; p++)
        [s.settings.startingPoints, for (final r in s.records) r.scoresAfter[p]]
    ];
    return ScoreSeries(labels, scores);
  }

  int get minScore => scores.expand((v) => v).reduce(math.min);
  int get maxScore => scores.expand((v) => v).reduce(math.max);

  /// "東1局 0本場" → "東1"、"東1局 2本場" → "東1-2"
  static String shortRoundLabel(String label) {
    final m = RegExp(r'^(.+?)局\s*(\d+)本場').firstMatch(label);
    if (m == null) return label;
    final honba = int.parse(m.group(2)!);
    return honba == 0 ? m.group(1)! : '${m.group(1)}-$honba';
  }
}

/// プレイヤーごとの線の色（明るい表示・暗い表示のどちらでも見分けやすい色）
const scoreChartColors = [Color(0xFFE53935), Color(0xFF1E88E5), Color(0xFF43A047), Color(0xFFFB8C00)];

/// 点数の推移の折れ線グラフ
class ScoreChart extends StatelessWidget {
  final GameSession session;
  const ScoreChart({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final series = ScoreSeries.of(session);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: '点数の推移のグラフ。'
              '${[for (var p = 0; p < session.playerCount; p++) '${session.playerNames[p]} ${formatPoints(series.scores[p].last)}点'].join('、')}',
          child: SizedBox(
            height: 200,
            width: double.infinity,
            child: CustomPaint(
              painter: _ScoreChartPainter(
                series: series,
                base: session.settings.startingPoints,
                axisColor: theme.colorScheme.outline,
                textStyle: theme.textTheme.labelSmall!.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 12,
          children: [
            for (var p = 0; p < session.playerCount; p++)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 14, height: 4, color: scoreChartColors[p % scoreChartColors.length]),
                  const SizedBox(width: 4),
                  Text(session.playerNames[p], style: theme.textTheme.bodySmall),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _ScoreChartPainter extends CustomPainter {
  final ScoreSeries series;
  final int base;
  final Color axisColor;
  final TextStyle textStyle;

  _ScoreChartPainter({required this.series, required this.base, required this.axisColor, required this.textStyle});

  @override
  void paint(Canvas canvas, Size size) {
    const left = 44.0, right = 8.0, top = 8.0, bottom = 20.0;
    final w = size.width - left - right, h = size.height - top - bottom;
    // 縦軸は1万点単位で切りのよい範囲にする
    final lo = (math.min(series.minScore, base) / 10000).floor() * 10000;
    var hi = (math.max(series.maxScore, base) / 10000).ceil() * 10000;
    if (hi == lo) hi = lo + 10000;
    double x(int i) => left + (series.labels.length == 1 ? w / 2 : w * i / (series.labels.length - 1));
    double y(num v) => top + h * (1 - (v - lo) / (hi - lo));

    final grid = Paint()
      ..color = axisColor.withAlpha(77)
      ..strokeWidth = 1;
    for (var v = lo; v <= hi; v += 10000) {
      canvas.drawLine(Offset(left, y(v)), Offset(left + w, y(v)), grid);
      _text(canvas, '${v ~/ 1000}k', Offset(left - 6, y(v)), alignRight: true);
    }
    // 持ち点の線
    canvas.drawLine(
        Offset(left, y(base)),
        Offset(left + w, y(base)),
        Paint()
          ..color = axisColor
          ..strokeWidth = 1);
    // 横軸の目盛り（多すぎるときは間引く）
    final step = math.max(1, (series.labels.length / 6).ceil());
    for (var i = 0; i < series.labels.length; i += step) {
      _text(canvas, series.labels[i], Offset(x(i), top + h + 4), center: true);
    }

    for (var p = 0; p < series.scores.length; p++) {
      final color = scoreChartColors[p % scoreChartColors.length];
      final line = Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke;
      final path = Path();
      for (var i = 0; i < series.scores[p].length; i++) {
        final o = Offset(x(i), y(series.scores[p][i]));
        if (i == 0) {
          path.moveTo(o.dx, o.dy);
        } else {
          path.lineTo(o.dx, o.dy);
        }
      }
      canvas.drawPath(path, line);
      canvas.drawCircle(Offset(x(series.scores[p].length - 1), y(series.scores[p].last)), 4, Paint()..color = color);
    }
  }

  void _text(Canvas canvas, String s, Offset at, {bool alignRight = false, bool center = false}) {
    final tp = TextPainter(text: TextSpan(text: s, style: textStyle), textDirection: TextDirection.ltr)..layout();
    final dx = alignRight ? at.dx - tp.width : (center ? at.dx - tp.width / 2 : at.dx);
    final dy = center ? at.dy : at.dy - tp.height / 2;
    tp.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(_ScoreChartPainter old) => old.series != series || old.axisColor != axisColor;
}
