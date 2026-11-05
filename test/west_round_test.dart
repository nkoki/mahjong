import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_app/features/session/data/session_repository.dart';
import 'package:mahjong_app/features/session/domain/models.dart';
import 'package:mahjong_app/features/session/domain/session_logic.dart';
import 'package:mahjong_app/features/session/screens/dashboard_screen.dart';
import 'package:mahjong_app/features/session/session_providers.dart';
import 'package:mahjong_score_engine/mahjong_score_engine.dart';

/// 半荘戦の指定の局（7=南4局, 8=西1局, 11=西4局）から始まる対局
GameSession at(int roundIndex, List<int> scores, {bool westRound = true, bool tonpuu = false}) =>
    GameSession.start(
      id: 'x',
      playerNames: ['A', 'B', 'C', 'D'],
      settings: GameSettings(westRound: westRound, tonpuu: tonpuu),
    ).copyWith(roundIndex: roundIndex, scores: scores, roundStartScores: scores);

GameSession draw(GameSession s, List<bool> tenpai) =>
    SessionLogic.applyDraw(s, type: DrawType.exhaustive, tenpai: tenpai);

const noTen = [false, false, false, false];

void main() {
  group('西入するかどうか', () {
    test('西入なしなら南4局で終わる', () {
      final s = draw(at(7, [26000, 25000, 25000, 24000], westRound: false), noTen);
      expect(s.finished, isTrue);
    });

    test('誰も返し点（30,000点）に届いていなければ西1局に入る', () {
      final s = draw(at(7, [29000, 25000, 25000, 21000]), noTen);
      expect(s.finished, isFalse);
      expect(s.roundIndex, 8);
      expect(s.roundName, '西1局');
      expect(s.isExtraRound, isTrue);
      expect(s.roundWindTile, '3z'); // 場風は西
    });

    test('返し点に届いた人がいれば南4局で終わる', () {
      final s = draw(at(7, [30000, 25000, 25000, 20000]), noTen);
      expect(s.finished, isTrue);
    });

    test('東風戦は南入', () {
      final s = draw(at(3, [29000, 25000, 25000, 21000], tonpuu: true), noTen);
      expect(s.finished, isFalse);
      expect(s.roundName, '南1局');
      expect(s.settings.extensionName, '南入');
    });
  });

  group('延長戦の終わり方', () {
    test('誰かが返し点に届いた局で終わる（サドンデス）', () {
      final s = draw(at(8, [28000, 24000, 24000, 24000]), [true, false, false, false]);
      expect(s.scores.first, 31000);
      expect(s.finished, isTrue);
    });

    test('届かなければ続く', () {
      // 西1局の親は A。B だけテンパイなので親が流れる
      final s = draw(at(8, [26000, 24000, 25000, 25000]), [false, true, false, false]);
      expect(s.scores[1], 27000);
      expect(s.finished, isFalse);
      expect(s.roundName, '西2局');
    });

    test('西4局が終わったら、届かなくても終わる', () {
      final s = draw(at(11, [29000, 25000, 25000, 21000]), noTen);
      expect(s.finished, isTrue);
    });

    test('西4局で親が連荘して、まだ誰も届いていなければ続く', () {
      // 西4局の親は D（player 3）
      final s = draw(at(11, [26000, 25000, 25000, 24000]), [false, false, false, true]);
      expect(s.scores[3], 27000);
      expect(s.finished, isFalse);
      expect(s.roundLabel, '西4局 1本場');
    });

    test('延長中もトビで終わる', () {
      final s = draw(at(8, [29000, 29000, 41000, 1000]), [true, true, true, false]);
      expect(s.finished, isTrue);
    });
  });

  group('和了止め（西入ありのとき）', () {
    WinInput pinfuRon(GameSession s, int winner) => WinInput(
          handTiles: const ['2m', '3m', '4m', '5m', '6m', '7p', '8p', '9p', '2s', '3s', '4s', '5s', '5s'],
          winningTile: '1m',
          melds: const [],
          winType: 'ron',
          isRiichi: false,
          isIppatsu: false,
          isDoubleRiichi: false,
          doraTiles: const [],
          uraDoraTiles: const [],
          roundWind: s.roundWindTile,
          playerWind: s.seatWindTileOf(winner),
        );

    GameSession dealerWins(List<int> scores) {
      final s = at(7, scores); // 南4局 親は D
      final wins = SessionLogic.scoreWins(s, [WinEntry(winner: 3, input: pinfuRon(s, 3))], loser: 0);
      return SessionLogic.applyWins(s, wins: wins, loser: 0, description: '');
    }

    test('親がトップでも返し点に届いていなければ続く', () {
      final s = dealerWins([24000, 24000, 24000, 28000]); // 親 +1500 → 29500
      expect(s.finished, isFalse);
      expect(s.roundLabel, '南4局 1本場');
    });

    test('親が返し点に届いていれば終わる', () {
      final s = dealerWins([22000, 24000, 24000, 30000]);
      expect(s.finished, isTrue);
    });
  });

  test('保存して読み込んでも西入の設定が残る。以前のデータは西入なし', () {
    const g = GameSettings(westRound: true);
    expect(GameSettings.fromJson(jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>).westRound,
        isTrue);
    final old = const GameSettings().toJson();
    (old['rules'] as Map).remove('westRound');
    expect(GameSettings.fromJson(old).westRound, isFalse);
    expect(const GameSettings(westRound: true).ruleSummary, contains('西入あり'));
  });

  testWidgets('延長戦中は対局画面に終わる条件が表示される', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    final s = at(8, [29000, 25000, 25000, 21000]);
    await tester.pumpWidget(ProviderScope(
      overrides: [sessionRepositoryProvider.overrideWithValue(InMemorySessionRepository([s]))],
      child: const MaterialApp(home: DashboardScreen(sessionId: 'x')),
    ));
    expect(find.text('西1局 0本場'), findsOneWidget);
    expect(find.textContaining('西入（延長戦）中: 返し点 30,000点に届いた人が出た局で終了します（最長 西4局 まで）'),
        findsOneWidget);
  });
}
