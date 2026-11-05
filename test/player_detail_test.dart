import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_app/features/session/data/session_repository.dart';
import 'package:mahjong_app/features/session/domain/models.dart';
import 'package:mahjong_app/features/session/domain/session_logic.dart';
import 'package:mahjong_app/features/session/session_providers.dart';
import 'package:mahjong_app/features/stats/player_detail.dart';
import 'package:mahjong_app/features/stats/player_detail_screen.dart';
import 'package:mahjong_app/features/stats/stats_screen.dart';

import 'double_ron_test.dart' show pinfuRon;
import 'player_stats_test.dart' show start, win;

/// 手牌で入力した和了（平和）
GameSession handWin(GameSession s, int winner, int loser) {
  final wins = SessionLogic.scoreWins(s, [WinEntry(winner: winner, input: pinfuRon(s, winner))], loser: loser);
  return SessionLogic.applyWins(s, wins: wins, loser: loser, description: 'test');
}

/// 個人成績の詳細（推移・対戦相手・役の出現回数）
void main() {
  // 1局目: A が B から手牌で和了（平和）して A トップ / 2局目: B が A から翻・符で和了して B トップ
  List<GameSession> games() => [
        SessionLogic.finishManually(handWin(start('g1', ['A', 'B', 'C', 'D'], at: DateTime(2026, 6, 1)), 0, 1)),
        SessionLogic.finishManually(
            win(start('g2', ['B', 'A', 'C', 'E'], at: DateTime(2026, 6, 2)), 0, loser: 1, han: 4, fu: 30)),
      ];

  test('合計ポイントは古い順に積み上げる', () {
    final d = PlayerDetail.compute(games(), 'A', playerCount: 4);
    expect(d.games.map((g) => g.sessionId), ['g1', 'g2']);
    expect(d.games.first.rank, 1);
    expect(d.games.last.rank, 4);
    expect(d.games.last.cumulative, closeTo(d.games[0].point + d.games[1].point, 1e-9));
  });

  test('対戦相手ごとに同卓数・上下・平均順位を数える', () {
    final d = PlayerDetail.compute(games(), 'A', playerCount: 4);
    final b = d.opponents.firstWhere((o) => o.name == 'B');
    expect(b.games, 2);
    expect(b.above, 1);
    expect(b.below, 1);
    expect(d.opponents.first.games, 2, reason: '同卓が多い順');
    final e = d.opponents.firstWhere((o) => o.name == 'E');
    expect(e.games, 1);
    expect(e.myAverageRank, 4);
  });

  test('役は手牌で入力した和了だけ数え、ドラは除く', () {
    final s = games().first;
    expect(s.records.single.yaku!.single, contains('平和'));
    expect(s.records.single.yaku!.single.any((y) => y.contains('ドラ')), isFalse);
    final a = PlayerDetail.compute(games(), 'A', playerCount: 4);
    expect(a.yakuWins, 1);
    expect(a.yaku.map((e) => e.$1), contains('平和'));
    final b = PlayerDetail.compute(games(), 'B', playerCount: 4);
    expect(b.yakuWins, 0);
    expect(b.unknownYakuWins, 1, reason: '翻・符で入力した和了');
  });

  test('役を保存・読み込みでき、以前の形式（役なし）も読める', () {
    final s = games().first;
    final back = GameSession.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
    expect(back.records.single.yaku, s.records.single.yaku);
    final old = RoundRecord.fromJson(s.records.single.toJson()..remove('yaku'));
    expect(old.yaku, isNull);
    expect(SharedPrefsSessionRepository.formatVersion, greaterThanOrEqualTo(8));
  });

  test('局の修正で和了者を選び直すと、役も新しい和了者に付け替える', () {
    final s = handWin(start('x', ['A', 'B', 'C', 'D']), 0, 1);
    final e = SessionLogic.editRound(s, 0, deltas: s.records[0].deltas, who: (winners: [2], loser: 1));
    expect(e.records[0].yaku, s.records[0].yaku);
  });

  testWidgets('個人成績のカードから開ける', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 2400));
    await tester.pumpWidget(ProviderScope(
      overrides: [sessionRepositoryProvider.overrideWithValue(InMemorySessionRepository(games()))],
      child: const MaterialApp(home: StatsScreen()),
    ));
    await tester.tap(find.byKey(const ValueKey('player-A')));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerDetailScreen), findsOneWidget);
    expect(find.text('合計ポイントの推移'), findsOneWidget);
    expect(find.byKey(const ValueKey('opponents')), findsOneWidget);
    expect(find.text('平和'), findsOneWidget);
    expect(find.textContaining('4人打ち・すべて（終局した2対局）'), findsOneWidget);
  });
}
