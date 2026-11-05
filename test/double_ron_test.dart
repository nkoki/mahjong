import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_app/features/session/data/session_repository.dart';
import 'package:mahjong_app/features/session/domain/models.dart';
import 'package:mahjong_app/features/session/domain/session_logic.dart';
import 'package:mahjong_app/features/session/session_providers.dart';
import 'package:mahjong_app/features/win/win_input_screen.dart';
import 'package:mahjong_score_engine/mahjong_score_engine.dart';

const pinfuHand = ['2m', '3m', '4m', '5m', '6m', '7p', '8p', '9p', '2s', '3s', '4s', '5s', '5s'];

/// 平和の手（1m でロン）。子なら 1000点、親なら 1500点
WinInput pinfuRon(GameSession s, int winner) => WinInput(
      handTiles: pinfuHand,
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

GameSession newGame() => GameSession.start(
    id: 'x', playerNames: ['A', 'B', 'C', 'D'], settings: const GameSettings());

void main() {
  group('本場・供託を受け取る人（上家取り）', () {
    test('放銃者から見て打つ順番が近い方', () {
      expect(SessionLogic.honbaTaker([1, 3], loser: 2), 3); // C の次は D
      expect(SessionLogic.honbaTaker([1, 3], loser: 0), 1); // A の次は B
      expect(SessionLogic.honbaTaker([0, 2], loser: 3), 0); // D の次は A
      expect(SessionLogic.honbaTaker([2]), 2); // ツモ
    });
  });

  group('ダブロンの点数', () {
    test('本場・供託は近い方だけが受け取り、放銃者は2人分を払う', () {
      var s = newGame().copyWith(honba: 1);
      s = SessionLogic.toggleRiichi(s, 0); // A が立直（供託1本）
      final wins = SessionLogic.scoreWins(
          s, [WinEntry(winner: 1, input: pinfuRon(s, 1)), WinEntry(winner: 3, input: pinfuRon(s, 3))],
          loser: 2);
      // C(2) の次は D(3) → D が本場300点と供託1000点を受け取る
      expect(wins[0].result.paymentDetails.winnerGain, 1000);
      expect(wins[1].result.paymentDetails.winnerGain, 1000 + 300 + 1000);
      final d = SessionLogic.winsDeltas(s, wins, loser: 2);
      expect(d, [0, 1000, -(1000 + 1300), 2300]);
    });

    test('子2人のダブロンは親流れで0本場、供託はなくなる', () {
      var s = newGame().copyWith(honba: 2);
      s = SessionLogic.toggleRiichi(s, 1);
      final wins = SessionLogic.scoreWins(
          s, [WinEntry(winner: 1, input: pinfuRon(s, 1)), WinEntry(winner: 3, input: pinfuRon(s, 3))],
          loser: 2);
      final next = SessionLogic.applyWins(s, wins: wins, loser: 2, description: 'ダブロン');
      expect(next.roundIndex, 1);
      expect(next.honba, 0);
      expect(next.riichiSticks, 0);
      expect(next.scores.fold<int>(0, (a, v) => a + v), 100000);
      expect(next.records.single.description, 'ダブロン');
    });

    test('和了者に親がいれば連荘して本場+1', () {
      final s = newGame();
      final wins = SessionLogic.scoreWins(
          s, [WinEntry(winner: 0, input: pinfuRon(s, 0)), WinEntry(winner: 2, input: pinfuRon(s, 2))],
          loser: 1);
      expect(wins[0].result.totalScore, 1500); // 親の平和ロン
      final next = SessionLogic.applyWins(s, wins: wins, loser: 1, description: '');
      expect(next.roundIndex, 0);
      expect(next.honba, 1);
      expect(next.scores, [26500, 22500, 26000, 25000]);
    });

    test('入力チェック', () {
      expect(SessionLogic.validateWins([1, 3], loser: 2), isNull);
      expect(SessionLogic.validateWins([1, 3]), contains('ツモ'));
      expect(SessionLogic.validateWins([1, 2], loser: 2), contains('放銃者'));
      expect(SessionLogic.validateWins([0, 1, 3], loser: 2), contains('三家和'));
      expect(SessionLogic.validateWins([1, 1], loser: 2), contains('同じ人'));
    });
  });

  testWidgets('画面からダブロンを入力して確定できる', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 2600));
    final session = newGame().copyWith(honba: 1, riichiSticks: 1, scores: [25000, 25000, 25000, 24000]);
    await tester.pumpWidget(ProviderScope(
      overrides: [sessionRepositoryProvider.overrideWithValue(InMemorySessionRepository([session]))],
      child: const MaterialApp(home: WinInputScreen(sessionId: 'x')),
    ));
    final c = ProviderScope.containerOf(tester.element(find.byType(WinInputScreen)));

    Future<void> tapTile(String t) async {
      await tester.tap(find.byKey(ValueKey('palette-$t')).last);
      await tester.pump();
    }

    // 1人目: B（南家）が C からロン
    await tester.tap(find.text('南 B'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ChoiceChip, 'C'));
    await tester.pump();
    for (final t in pinfuHand) {
      await tapTile(t);
    }
    await tapTile('1m');
    await tester.tap(find.text('計算'));
    await tester.pumpAndSettle();
    expect(find.text('計算結果'), findsOneWidget);

    // 2人目を入力
    await tester.tap(find.text('ダブロン：もう1人のロン和了を入力'));
    await tester.pumpAndSettle();
    expect(find.text('2人目の和了入力'), findsOneWidget);
    expect(find.text('南 B'), findsNothing); // 1人目と放銃者は選べない
    expect(find.text('C（1人目と同じ）'), findsOneWidget);
    await tester.tap(find.text('北 D'));
    await tester.pump();
    for (final t in pinfuHand) {
      await tapTile(t);
    }
    // 和了牌（1m）は1人目と同じなので入力済み
    await tester.tap(find.text('計算').last);
    await tester.pumpAndSettle();

    expect(find.text('計算結果（ダブロン）'), findsOneWidget);
    expect(find.textContaining('打つ順番が近い D が受け取ります'), findsOneWidget);
    expect(find.text('ダブロン：もう1人のロン和了を入力'), findsNothing); // 3人目は不可

    await tester.tap(find.text('2人分の結果で確定'));
    await tester.pumpAndSettle();
    final s = c.read(sessionProvider('x'))!;
    // B +1000、D +1000+300+1000、C -2300
    expect(s.scores, [25000, 26000, 22700, 26300]);
    expect(s.records.single.description, startsWith('ダブロン: B ロン ← C'));
    expect(s.roundIndex, 1); // 親流れ
  });
}
