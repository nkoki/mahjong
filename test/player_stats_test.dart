import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_app/features/session/data/session_repository.dart';
import 'package:mahjong_app/features/session/domain/models.dart';
import 'package:mahjong_app/features/session/domain/session_logic.dart';
import 'package:mahjong_app/features/session/session_providers.dart';
import 'package:mahjong_app/features/stats/player_stats.dart';
import 'package:mahjong_app/features/stats/stats_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

GameSession start(String id, List<String> names, {DateTime? at}) => GameSession.start(
      id: id,
      playerNames: names,
      settings: GameSettings(playerCount: names.length, uma: names.length == 3 ? const [15, 0, -15] : const [20, 10, -10, -20]),
      now: at ?? DateTime(2026, 6, 1),
    );

/// 翻・符で入力した和了を適用する
GameSession win(GameSession s, int winner, {int? loser, int han = 3, int fu = 40}) {
  final wins = SessionLogic.scoreWins(
      s,
      [
        WinEntry.hanFu(
            session: s, winner: winner, isTsumo: loser == null, hanFu: HanFuEntry(han: han, fu: fu))
      ],
      loser: loser);
  return SessionLogic.applyWins(s, wins: wins, loser: loser, description: 'test');
}

/// 「立直 → 和了 → 立直・流局 → 終局」した対局
/// A（親）: 立直してロン和了（B から 7700点）、C: 立直して流局（テンパイ）
GameSession playedGame(String id, List<String> names, {DateTime? at}) {
  var s = start(id, names, at: at);
  s = SessionLogic.toggleRiichi(s, 0);
  s = win(s, 0, loser: 1);
  s = SessionLogic.toggleRiichi(s, 2);
  s = SessionLogic.applyDraw(s,
      type: DrawType.exhaustive, tenpai: [for (var i = 0; i < s.playerCount; i++) i == 2]);
  return SessionLogic.finishManually(s);
}

/// 個人成績
void main() {
  group('局の記録', () {
    test('和了者・放銃者・立直した人・和了点を記録する', () {
      final s = playedGame('x', ['A', 'B', 'C', 'D']);
      final w = s.records[0];
      expect(w.winners, [0]);
      expect(w.loser, 1);
      expect(w.riichi, [0]);
      expect(w.winPoints, [7700]);
      expect(w.hasPlayDetails, isTrue);
      final d = s.records[1];
      expect(d.winners, isEmpty);
      expect(d.loser, isNull);
      expect(d.riichi, [2]);
    });

    test('ダブロン・ツモも記録する', () {
      var s = start('x', ['A', 'B', 'C', 'D']);
      final wins = SessionLogic.scoreWins(
          s,
          [
            WinEntry.hanFu(session: s, winner: 1, isTsumo: false, hanFu: const HanFuEntry(han: 1, fu: 30)),
            WinEntry.hanFu(session: s, winner: 3, isTsumo: false, hanFu: const HanFuEntry(han: 2, fu: 30)),
          ],
          loser: 2);
      s = SessionLogic.applyWins(s, wins: wins, loser: 2, description: '');
      expect(s.records.last.winners, [1, 3]);
      expect(s.records.last.winPoints, [1000, 2000]);
      s = win(s, 0); // A のツモ
      expect(s.records.last.loser, isNull);
    });

    test('局の内容を修正しても記録は残る', () {
      final s = playedGame('x', ['A', 'B', 'C', 'D']);
      final edited = s.records[0].copyWith(description: '修正', edited: true);
      expect(edited.winners, [0]);
      expect(edited.loser, 1);
      expect(edited.riichi, [0]);
      expect(edited.winPoints, [7700]);
    });

    test('JSON に保存して戻しても同じ。記録の無い以前の局も読める', () {
      final s = playedGame('x', ['A', 'B', 'C', 'D']);
      final back = RoundRecord.fromJson(jsonDecode(jsonEncode(s.records[0].toJson())) as Map<String, dynamic>);
      expect(back.winners, [0]);
      expect(back.loser, 1);
      expect(back.riichi, [0]);
      expect(back.winPoints, [7700]);
      final old = RoundRecord.fromJson(const {
        'roundLabel': '東1局 0本場',
        'kind': 'win',
        'description': 'A ロン',
        'deltas': [1000, -1000, 0, 0],
        'scoresAfter': [26000, 24000, 25000, 25000],
      });
      expect(old.hasPlayDetails, isFalse);
      expect(old.winners, isNull);
    });
  });

  test('保存データの version 3（記録の無い局）を読み込め、version 4 で保存し直す', () async {
    final s = playedGame('old', ['A', 'B', 'C', 'D']);
    final json = s.toJson();
    // version 3 のときの局の記録（和了者などが無い）
    final records = [
      for (final r in s.records)
        Map<String, dynamic>.from(r.toJson())
          ..remove('winners')
          ..remove('loser')
          ..remove('riichi')
          ..remove('winPoints')
    ];
    json['records'] = records;
    json.remove('previous');
    SharedPreferences.setMockInitialValues({
      SharedPrefsSessionRepository.indexKey: jsonEncode({'version': 3, 'ids': ['old']}),
      SharedPrefsSessionRepository.sessionKey('old'): jsonEncode({'version': 3, 'session': json}),
    });
    final prefs = await SharedPreferences.getInstance();
    final repo = SharedPrefsSessionRepository(prefs);
    final loaded = repo.loadAll().single;
    expect(loaded.records, hasLength(2));
    expect(loaded.records.every((r) => !r.hasPlayDetails), isTrue);
    expect(loaded.finalResults.first.player, 0);

    // 集計では順位・ポイントだけに含め、和了率などには含めない
    final summary = PlayerStatsCalculator.compute([loaded], playerCount: 4);
    expect(summary.roundsWithoutDetails, 2);
    final a = summary.players.firstWhere((p) => p.name == 'A');
    expect(a.games, 1);
    expect(a.winRate, isNull);

    // 次に保存するときは version 4
    final next = SessionLogic.toggleFavorite(loaded);
    await repo.saveAll([next]);
    final saved = jsonDecode(prefs.getString(SharedPrefsSessionRepository.sessionKey('old'))!) as Map<String, dynamic>;
    expect(saved['version'], SharedPrefsSessionRepository.formatVersion);
    expect(SharedPrefsSessionRepository.formatVersion, 4);
  });

  group('集計', () {
    final g1 = playedGame('1', ['A', 'B', 'C', 'D'], at: DateTime(2025, 12, 1));
    final g2 = playedGame('2', ['B', 'A', 'E', 'C'], at: DateTime(2026, 6, 1));
    final ongoing = start('3', ['A', 'B', 'C', 'D']);
    final sanma = playedGame('4', ['A', 'B', 'C']);

    test('終局した同じ人数の対局を、名前ごとに集計する', () {
      final summary = PlayerStatsCalculator.compute([g1, g2, ongoing, sanma], playerCount: 4);
      expect(summary.games, 2, reason: '対局中と3人打ちは含めない');
      expect(summary.roundsWithoutDetails, 0);
      final byName = {for (final p in summary.players) p.name: p};
      expect(byName.keys.toSet(), {'A', 'B', 'C', 'D', 'E'});

      // g1 では A（座0）が B から和了、g2 では B（座0）が A から和了
      final a = byName['A']!;
      expect(a.games, 2);
      expect(a.rounds, 4);
      expect(a.wins, 1);
      expect(a.dealIns, 1);
      expect(a.riichi, 1);
      expect(a.winRate, 0.25);
      expect(a.dealInRate, 0.25);
      expect(a.averageWinPoints, 7700);
      expect(a.rankCounts.fold<int>(0, (x, v) => x + v), 2);

      final d = byName['D']!;
      expect(d.games, 1);
      expect(d.wins, 0);
      expect(d.averageWinPoints, isNull);
      expect(d.winRate, 0);

      // 合計ポイントの多い順
      final points = [for (final p in summary.players) p.totalPoints];
      expect(points, [...points]..sort((x, y) => y.compareTo(x)));
      // ポイントは全員の合計が 0
      expect(points.fold<double>(0, (x, v) => x + v), closeTo(0, 1e-9));
    });

    test('期間で絞り込める', () {
      final summary = PlayerStatsCalculator.compute([g1, g2], playerCount: 4, since: DateTime(2026, 1, 1));
      expect(summary.games, 1);
      expect(summary.players.map((p) => p.name).toSet(), {'A', 'B', 'C', 'E'});
    });

    test('3人打ち', () {
      final summary = PlayerStatsCalculator.compute([g1, sanma], playerCount: 3);
      expect(summary.games, 1);
      expect(summary.players.first.rankCounts, hasLength(3));
    });

    test('平均順位・トップ率・ラス率', () {
      const p = PlayerStats(
          name: 'X',
          rankCounts: [2, 1, 0, 1],
          totalPoints: 40,
          rounds: 0,
          wins: 0,
          dealIns: 0,
          riichi: 0,
          winPointsTotal: 0);
      expect(p.games, 4);
      expect(p.averageRank, 2.0);
      expect(p.topRate, 0.5);
      expect(p.lastRate, 0.25);
      expect(p.averagePoints, 10);
      expect(p.winRate, isNull);
    });
  });

  group('画面', () {
    Future<void> pump(WidgetTester tester, List<GameSession> sessions) async {
      await tester.binding.setSurfaceSize(const Size(420, 2400));
      await tester.pumpWidget(ProviderScope(
        overrides: [sessionRepositoryProvider.overrideWithValue(InMemorySessionRepository(sessions))],
        child: MaterialApp(home: StatsScreen(now: DateTime(2026, 6, 10))),
      ));
    }

    testWidgets('プレイヤーごとの成績を表示し、人数・期間で切り替えられる', (tester) async {
      await pump(tester, [
        playedGame('1', ['A', 'B', 'C', 'D'], at: DateTime(2025, 12, 1)),
        playedGame('2', ['B', 'A', 'E', 'C'], at: DateTime(2026, 6, 1)),
        playedGame('4', ['A', 'B', 'C']),
      ]);
      expect(find.textContaining('終局した対局（2対局）'), findsOneWidget);
      expect(find.text('E'), findsOneWidget);
      expect(find.text('和了率'), findsNWidgets(5));
      expect(find.text('25.0%'), findsWidgets);

      await tester.tap(find.text('今年'));
      await tester.pump();
      expect(find.textContaining('終局した対局（1対局）'), findsOneWidget);
      expect(find.text('D'), findsNothing);

      await tester.tap(find.text('3人打ち'));
      await tester.pump();
      expect(find.textContaining('終局した対局（1対局）'), findsOneWidget);
      expect(find.text('E'), findsNothing);
    });

    testWidgets('終局した対局が無いときの表示', (tester) async {
      await pump(tester, [start('3', ['A', 'B', 'C', 'D'])]);
      expect(find.text('この条件で終局した対局はまだありません'), findsOneWidget);
    });

    testWidgets('以前の版で記録した局があると、和了率などに含めないことを表示する', (tester) async {
      final s = playedGame('1', ['A', 'B', 'C', 'D']);
      // 和了者などの記録が無い局（version 3 以前）
      final old = s.copyWith(records: [
        for (final r in s.records)
          RoundRecord(
            roundLabel: r.roundLabel,
            kind: r.kind,
            description: r.description,
            deltas: r.deltas,
            scoresAfter: r.scoresAfter,
          )
      ]);
      await pump(tester, [old]);
      expect(find.textContaining('以前の版で記録した2局'), findsOneWidget);
      expect(find.text('－'), findsWidgets, reason: '和了率などは集計できない');
      expect(find.text('対局数'), findsNWidgets(4));
    });
  });
}
