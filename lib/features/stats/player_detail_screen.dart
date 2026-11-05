import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../session/session_providers.dart';
import 'player_detail.dart';

/// プレイヤーの詳しい成績（合計ポイントの推移・対戦相手との成績・役の出現回数）
class PlayerDetailScreen extends ConsumerWidget {
  final String name;
  final int playerCount;
  final DateTime? since;

  /// 期間の表示（例: すべて、直近30日）。null なら「すべて」
  final String? periodLabel;

  const PlayerDetailScreen({
    super.key,
    required this.name,
    required this.playerCount,
    this.since,
    this.periodLabel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final d = PlayerDetail.compute(ref.watch(sessionsProvider), name, playerCount: playerCount, since: since);
    final small = theme.textTheme.bodySmall;
    final period = periodLabel ?? tr('すべて', 'All');

    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text(
              tr('${playerCount == 3 ? "3人打ち" : "4人打ち"}・$period（終局した${d.games.length}対局）',
                  '${playerCount == 3 ? "3-player" : "4-player"} · $period (${d.games.length} finished games)'),
              style: small),
          const SizedBox(height: 12),
          Text(tr('合計ポイントの推移', 'Point trend'), style: theme.textTheme.titleMedium),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 12, 8),
              child: d.games.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16), child: Text(tr('終局した対局がありません', 'No finished games')))
                  : Semantics(
                      label: tr('合計ポイントの推移のグラフ。${d.games.length}対局で ${formatPoint(d.games.last.cumulative)}',
                          'Point trend chart. ${formatPoint(d.games.last.cumulative)} over ${d.games.length} games'),
                      child: SizedBox(
                        height: 200,
                        width: double.infinity,
                        child: CustomPaint(
                          painter: _CumulativePainter(
                            games: d.games,
                            lineColor: theme.colorScheme.primary,
                            axisColor: theme.colorScheme.outline,
                            textStyle: theme.textTheme.labelSmall!.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
          if (d.games.isNotEmpty)
            Text(tr('点は1対局ごとの合計。横軸は対局の日付です。', 'Each dot is the running total after a game. The horizontal axis shows game dates.'),
                style: small),
          const SizedBox(height: 16),
          Text(tr('対戦相手との成績', 'Results against opponents'), style: theme.textTheme.titleMedium),
          Text(
              tr('同じ卓で終局まで打った相手ごとに、自分が上の順位だった回数・下だった回数と、平均順位を比べます。',
                  'For each opponent you finished a game with: how often you placed above / below them, and average places compared.'),
              style: small),
          const SizedBox(height: 4),
          if (d.opponents.isEmpty)
            Padding(padding: const EdgeInsets.all(16), child: Text(tr('まだありません', 'None yet')))
          else
            Card(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  key: const ValueKey('opponents'),
                  columnSpacing: 16,
                  columns: [
                    DataColumn(label: Text(tr('相手', 'Opponent'))),
                    DataColumn(label: Text(tr('同卓', 'Games')), numeric: true),
                    DataColumn(label: Text(tr('上-下', 'Above-below')), numeric: true),
                    DataColumn(label: Text(tr('平均順位\n自分/相手', 'Avg. place\nyou/them')), numeric: true),
                    DataColumn(label: Text(tr('ポイント\n自分/相手', 'Points\nyou/them')), numeric: true),
                  ],
                  rows: [
                    for (final o in d.opponents)
                      DataRow(cells: [
                        DataCell(Text(o.name)),
                        DataCell(Text('${o.games}')),
                        DataCell(Text('${o.above}-${o.below}',
                            style: TextStyle(color: deltaColor(context, (o.above - o.below).toDouble())))),
                        DataCell(Text('${o.myAverageRank.toStringAsFixed(2)} / ${o.theirAverageRank.toStringAsFixed(2)}')),
                        DataCell(Text('${formatPoint(o.myPoints)} / ${formatPoint(o.theirPoints)}')),
                      ]),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text(tr('役の出現回数', 'Yaku counts'), style: theme.textTheme.titleMedium),
          Text(
            tr(
                '手牌で入力した和了（${d.yakuWins}回）の役を数えます（ドラは除く）。'
                    '${d.unknownYakuWins > 0 ? '翻・符で入力した和了・以前の版で記録した和了など${d.unknownYakuWins}回は、役が分からないので含みません。' : ''}',
                'Counts yaku in wins entered with tiles (${d.yakuWins} wins), excluding dora.'
                    '${d.unknownYakuWins > 0 ? ' ${d.unknownYakuWins} wins entered as han/fu or recorded with an older version are not included, as their yaku are unknown.' : ''}'),
            style: small,
          ),
          const SizedBox(height: 4),
          if (d.yaku.isEmpty)
            Padding(padding: const EdgeInsets.all(16), child: Text(tr('まだありません', 'None yet')))
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    for (final (y, n) in d.yaku)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            SizedBox(width: 120, child: Text(yakuName(y), overflow: TextOverflow.ellipsis)),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: n / d.yakuWins,
                                  minHeight: 10,
                                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 100,
                              child: Text(
                                  tr('$n回（${(n * 100 / d.yakuWins).round()}%）',
                                      '${n}x (${(n * 100 / d.yakuWins).round()}%)'),
                                  textAlign: TextAlign.end, style: small),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CumulativePainter extends CustomPainter {
  final List<PlayerGame> games;
  final Color lineColor, axisColor;
  final TextStyle textStyle;

  _CumulativePainter({required this.games, required this.lineColor, required this.axisColor, required this.textStyle});

  @override
  void paint(Canvas canvas, Size size) {
    const left = 44.0, right = 8.0, top = 8.0, bottom = 20.0;
    final w = size.width - left - right, h = size.height - top - bottom;
    // 0 を含み、切りのよい範囲（10ポイント単位など）にする
    final values = [0.0, for (final g in games) g.cumulative];
    final lo0 = values.reduce(math.min), hi0 = values.reduce(math.max);
    final span = math.max(hi0 - lo0, 10);
    final unit = span <= 50 ? 10.0 : span <= 200 ? 50.0 : span <= 500 ? 100.0 : 500.0;
    final lo = (lo0 / unit).floor() * unit;
    var hi = (hi0 / unit).ceil() * unit;
    if (hi == lo) hi = lo + unit;
    final n = values.length;
    double x(int i) => left + (n == 1 ? w / 2 : w * i / (n - 1));
    double y(double v) => top + h * (1 - (v - lo) / (hi - lo));

    final grid = Paint()
      ..color = axisColor.withAlpha(77)
      ..strokeWidth = 1;
    for (var v = lo; v <= hi + 1e-9; v += unit) {
      canvas.drawLine(Offset(left, y(v)), Offset(left + w, y(v)), v == 0 ? (Paint()..color = axisColor) : grid);
      _text(canvas, v == 0 ? '0' : formatPoint(v).replaceAll('.0', ''), Offset(left - 6, y(v)), alignRight: true);
    }
    // 横軸: 対局の日付（多すぎるときは間引く）。[0] は開始
    final step = math.max(1, (games.length / 5).ceil());
    for (var i = 0; i < games.length; i += step) {
      final at = games[i].at;
      _text(canvas, '${at.month}/${at.day}', Offset(x(i + 1), top + h + 4), center: true);
    }
    final path = Path()..moveTo(x(0), y(0));
    for (var i = 0; i < games.length; i++) {
      path.lineTo(x(i + 1), y(games[i].cumulative));
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = lineColor
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke);
    final dot = Paint()..color = lineColor;
    for (var i = 0; i < games.length; i++) {
      canvas.drawCircle(Offset(x(i + 1), y(games[i].cumulative)), games.length > 40 ? 1.5 : 3, dot);
    }
  }

  void _text(Canvas canvas, String s, Offset at, {bool alignRight = false, bool center = false}) {
    final tp = TextPainter(text: TextSpan(text: s, style: textStyle), textDirection: TextDirection.ltr)..layout();
    var dx = at.dx;
    if (alignRight) dx -= tp.width;
    if (center) dx -= tp.width / 2;
    tp.paint(canvas, Offset(dx, alignRight ? at.dy - tp.height / 2 : at.dy));
  }

  @override
  bool shouldRepaint(_CumulativePainter old) => old.games != games || old.lineColor != lineColor;
}
