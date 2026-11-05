import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_app/features/history/history_detail_screen.dart';
import 'package:mahjong_app/features/history/score_chart.dart';
import 'package:mahjong_app/features/session/data/session_repository.dart';
import 'package:mahjong_app/features/session/domain/models.dart';
import 'package:mahjong_app/features/session/session_providers.dart';

import 'player_stats_test.dart' show playedGame, start;

/// 戦績詳細の点数の推移グラフ
void main() {
  test('開始時の点数と、各局のあとの点数', () {
    final s = playedGame('x', ['A', 'B', 'C', 'D']);
    final series = ScoreSeries.of(s);
    expect(series.labels, ['開始', '東1', '東1-1'], reason: '親の和了で連荘');
    expect(series.scores, hasLength(4));
    expect(series.scores[0], [25000, s.records[0].scoresAfter[0], s.records[1].scoresAfter[0]]);
    expect(series.scores.every((p) => p.length == 3), isTrue);
    expect(series.maxScore, greaterThan(25000));
  });

  test('局の名前を短くする', () {
    expect(ScoreSeries.shortRoundLabel('東1局 0本場'), '東1');
    expect(ScoreSeries.shortRoundLabel('南4局 2本場'), '南4-2');
    expect(ScoreSeries.shortRoundLabel('その他'), 'その他');
  });

  testWidgets('戦績詳細に表示し、局が無ければ出さない', (tester) async {
    Future<void> pump(GameSession s) async {
      await tester.binding.setSurfaceSize(const Size(420, 2400));
      await tester.pumpWidget(ProviderScope(
        key: UniqueKey(),
        overrides: [sessionRepositoryProvider.overrideWithValue(InMemorySessionRepository([s]))],
        child: MaterialApp(home: HistoryDetailScreen(sessionId: s.id)),
      ));
    }

    await pump(playedGame('x', ['A', 'B', 'C', 'D']));
    expect(find.text('点数の推移'), findsOneWidget);
    expect(find.byType(ScoreChart), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('点数の推移のグラフ')), findsOneWidget);

    await pump(start('y', ['A', 'B', 'C', 'D']));
    expect(find.text('点数の推移'), findsNothing);
  });
}
