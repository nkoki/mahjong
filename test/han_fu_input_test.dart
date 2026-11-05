import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_app/features/session/data/session_repository.dart';
import 'package:mahjong_app/features/session/domain/models.dart';
import 'package:mahjong_app/features/session/domain/session_logic.dart';
import 'package:mahjong_app/features/session/session_providers.dart';
import 'package:mahjong_app/features/win/win_input_screen.dart';
import 'package:mahjong_app/features/win/win_result_screen.dart';

import 'double_ron_test.dart' show pinfuRon;

GameSession newGame({GameSettings settings = const GameSettings()}) => GameSession.start(
    id: 'x', playerNames: settings.isSanma ? ['A', 'B', 'C'] : ['A', 'B', 'C', 'D'], settings: settings);

WinEntry quick(GameSession s, int winner, {required bool tsumo, int han = 0, int fu = 0, int yakuman = 0}) =>
    WinEntry.hanFu(
      session: s,
      winner: winner,
      isTsumo: tsumo,
      hanFu: HanFuEntry(han: han, fu: fu, yakuman: yakuman),
    );

/// 翻・符で入力する簡易入力
void main() {
  group('点数移動', () {
    test('子のロン（本場・供託も受け取る）', () {
      var s = newGame().copyWith(honba: 1);
      s = SessionLogic.toggleRiichi(s, 0); // A が立直（供託1本）
      final wins = SessionLogic.scoreWins(s, [quick(s, 1, tsumo: false, han: 3, fu: 40)], loser: 2);
      expect(wins.single.hanFu, isNotNull);
      expect(wins.single.result.totalScore, 5200);
      final d = SessionLogic.winsDeltas(s, wins, loser: 2);
      expect(d, [0, 5200 + 300 + 1000, -(5200 + 300), 0]);
      final next = SessionLogic.applyWins(s, wins: wins, loser: 2, description: 'test');
      expect(next.roundIndex, 1, reason: '子の和了なので親流れ');
      expect(next.honba, 0);
      expect(next.scores.fold<int>(0, (a, v) => a + v), 100000);
    });

    test('親のツモは連荘', () {
      final s = newGame();
      final wins = SessionLogic.scoreWins(s, [quick(s, 0, tsumo: true, han: 3, fu: 40)]);
      expect(SessionLogic.winsDeltas(s, wins), [7800, -2600, -2600, -2600]);
      final next = SessionLogic.applyWins(s, wins: wins, description: '');
      expect(next.roundIndex, 0);
      expect(next.honba, 1);
    });

    test('役満・満貫以上', () {
      final s = newGame();
      expect(SessionLogic.scoreWins(s, [quick(s, 1, tsumo: false, yakuman: 1)], loser: 0).single.result.totalScore,
          32000);
      expect(SessionLogic.scoreWins(s, [quick(s, 1, tsumo: false, han: 6)], loser: 0).single.result.totalScore,
          12000);
    });

    test('ダブロンで、1人は翻・符、もう1人は手牌で入力', () {
      final s = newGame().copyWith(honba: 1);
      final wins = SessionLogic.scoreWins(
          s, [quick(s, 1, tsumo: false, han: 2, fu: 30), WinEntry(winner: 3, input: pinfuRon(s, 3))],
          loser: 2);
      // C(2) の次は D(3) → D が本場を受け取る
      expect(wins[0].result.paymentDetails.winnerGain, 2000);
      expect(wins[1].result.paymentDetails.winnerGain, 1000 + 300);
      expect(SessionLogic.winsDeltas(s, wins, loser: 2), [0, 2000, -3300, 1300]);
    });

    test('3人打ちのツモ損', () {
      final s = newGame(settings: const GameSettings(playerCount: 3));
      final wins = SessionLogic.scoreWins(s, [quick(s, 1, tsumo: true, han: 5)]);
      expect(SessionLogic.winsDeltas(s, wins), [-4000, 6000, -2000]);
    });

    test('翻・符で入力した役満は包を選べない（どの役満か分からないため）', () {
      final s = newGame(settings: const GameSettings(pao: true));
      final w = SessionLogic.scoreWins(s, [quick(s, 1, tsumo: true, yakuman: 1)]).single;
      expect(SessionLogic.canChoosePao(s, w), isFalse);
    });
  });

  group('画面', () {
    Future<ProviderContainer> pump(WidgetTester tester, GameSession session) async {
      await tester.binding.setSurfaceSize(const Size(420, 2000));
      await tester.pumpWidget(ProviderScope(
        overrides: [sessionRepositoryProvider.overrideWithValue(InMemorySessionRepository([session]))],
        child: const MaterialApp(home: WinInputScreen(sessionId: 'x')),
      ));
      return ProviderScope.containerOf(tester.element(find.byType(WinInputScreen)));
    }

    Future<void> tap(WidgetTester tester, Finder f) async {
      await tester.tap(f);
      await tester.pump();
    }

    testWidgets('翻・符を選んで計算し、確定できる', (tester) async {
      final c = await pump(tester, newGame().copyWith(honba: 1));
      await tap(tester, find.text('南 B').first);
      await tap(tester, find.widgetWithText(ChoiceChip, '西 C').last);
      await tap(tester, find.text('翻・符で入力'));
      // 手牌の欄と牌パレットは出ない
      expect(find.textContaining('手牌（'), findsNothing);
      expect(find.text('翻数と符を選んでください'), findsOneWidget);
      await tap(tester, find.widgetWithText(ChoiceChip, '3翻'));
      await tap(tester, find.widgetWithText(ChoiceChip, '40符'));
      expect(find.text('子のロン 5200点'), findsOneWidget);

      await tester.tap(find.text('計算'));
      await tester.pumpAndSettle();
      expect(find.byType(WinResultScreen), findsOneWidget);
      expect(find.text('3翻 40符'), findsOneWidget);
      expect(find.text('翻・符で入力（手牌は入力していません）'), findsOneWidget);
      expect(find.text('+5,500'), findsOneWidget, reason: '1本場の300点を含む');

      await tester.tap(find.text('この結果で確定'));
      await tester.pumpAndSettle();
      final s = c.read(sessionProvider('x'))!;
      expect(s.scores, [25000, 30500, 19500, 25000]);
      expect(s.records.single.description, contains('3翻 40符'));
      expect(s.records.single.description, contains('翻・符で入力'));
    });

    testWidgets('選んだ入力方法を覚えていて、次に開いたときも同じになる', (tester) async {
      final repo = InMemorySessionRepository([newGame()]);
      Future<void> open() async {
        await tester.binding.setSurfaceSize(const Size(420, 2000));
        await tester.pumpWidget(ProviderScope(
          key: UniqueKey(),
          overrides: [sessionRepositoryProvider.overrideWithValue(repo)],
          child: const MaterialApp(home: WinInputScreen(sessionId: 'x')),
        ));
      }

      await open();
      expect(find.textContaining('手牌（'), findsOneWidget, reason: '最初は手牌で入力');
      await tap(tester, find.text('翻・符で入力'));
      expect(repo.preferences['win_input_mode'], 'hanfu');
      // アプリを開き直しても翻・符で入力のまま
      await open();
      expect(find.textContaining('手牌（'), findsNothing);
      expect(find.text('翻数と符を選んでください'), findsOneWidget);
    });

    testWidgets('放銃者のボタンにも風が付く', (tester) async {
      await pump(tester, newGame());
      await tap(tester, find.text('南 B').first);
      expect(find.widgetWithText(ChoiceChip, '西 C'), findsNWidgets(2), reason: '和了者と放銃者の両方');
      expect(find.widgetWithText(ChoiceChip, '南 B'), findsOneWidget, reason: '和了者は放銃者に出ない');
    });

    testWidgets('ロンでは20符を選べず、5翻以上は符を選ばない', (tester) async {
      await pump(tester, newGame());
      await tap(tester, find.text('翻・符で入力'));
      await tap(tester, find.widgetWithText(ChoiceChip, '2翻'));
      final chip20 = tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '20符'));
      expect(chip20.onSelected, isNull);
      // ツモにすると選べる
      await tap(tester, find.text('ツモ'));
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '20符')).onSelected, isNotNull);

      await tap(tester, find.widgetWithText(ChoiceChip, '5翻'));
      expect(find.widgetWithText(ChoiceChip, '30符'), findsNothing);
      expect(find.textContaining('満貫'), findsWidgets);
    });

    testWidgets('親のツモは「オール」で見込みを表示し、選び忘れを知らせる', (tester) async {
      await pump(tester, newGame());
      await tap(tester, find.text('東 A').first);
      await tap(tester, find.text('ツモ'));
      await tap(tester, find.text('翻・符で入力'));
      await tap(tester, find.widgetWithText(ChoiceChip, '3翻'));
      await tester.tap(find.text('計算'));
      await tester.pump();
      expect(find.text('符を選んでください'), findsOneWidget);
      await tap(tester, find.widgetWithText(ChoiceChip, '40符'));
      expect(find.text('親のツモ 2600オール'), findsOneWidget);
      await tap(tester, find.widgetWithText(ChoiceChip, '役満'));
      expect(find.text('親のツモ 16000オール（役満）'), findsOneWidget);
    });
  });
}
