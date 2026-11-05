import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_app/features/session/data/session_repository.dart';
import 'package:mahjong_app/features/session/domain/models.dart';
import 'package:mahjong_app/features/session/domain/session_logic.dart';
import 'package:mahjong_app/features/session/session_providers.dart';
import 'package:mahjong_app/features/win/win_result_screen.dart';
import 'package:mahjong_score_engine/mahjong_score_engine.dart';

const chunPon = Meld(type: MeldType.pon, tiles: ['7z', '7z', '7z']);

GameSession newGame({bool pao = true, int honba = 0}) => GameSession.start(
        id: 'x', playerNames: ['A', 'B', 'C', 'D'], settings: GameSettings(pao: pao))
    .copyWith(honba: honba);

/// 中をポンした大三元（白・發は暗刻）。23m の両面待ちで 1m 和了
WinInput daisangen(GameSession s, int winner, {required bool tsumo}) => WinInput(
      handTiles: const ['5z', '5z', '5z', '6z', '6z', '6z', '2m', '3m', '9p', '9p'],
      winningTile: '1m',
      melds: const [chunPon],
      winType: tsumo ? 'tsumo' : 'ron',
      isRiichi: false,
      isIppatsu: false,
      isDoubleRiichi: false,
      doraTiles: const [],
      uraDoraTiles: const [],
      roundWind: s.roundWindTile,
      playerWind: s.seatWindTileOf(winner),
    );

/// 大三元＋字一色（東の単騎待ち）
WinInput daisangenTsuiso(GameSession s, int winner) => WinInput(
      handTiles: const ['5z', '5z', '5z', '6z', '6z', '6z', '1z', '1z', '1z', '2z'],
      winningTile: '2z',
      melds: const [chunPon],
      winType: 'tsumo',
      isRiichi: false,
      isIppatsu: false,
      isDoubleRiichi: false,
      doraTiles: const [],
      uraDoraTiles: const [],
      roundWind: s.roundWindTile,
      playerWind: s.seatWindTileOf(winner),
    );

ScoredWin scored(GameSession s, WinInput input, int winner, {int? loser, int? pao}) =>
    SessionLogic.scoreWins(s, [WinEntry(winner: winner, input: input)], loser: loser)
        .single
        .withPao(pao);

void main() {
  group('包の点数移動', () {
    test('子のツモ: 包の人が役満 32,000点と本場を全額払う', () {
      final s = newGame(honba: 1);
      final w = scored(s, daisangen(s, 1, tsumo: true), 1, pao: 3);
      expect(w.result.yakuList.map((y) => y.name), contains('大三元'));
      expect(SessionLogic.paoDeltas(s, w), [0, 32300, 0, -32300]);
    });

    test('親のツモ: 包の人が 48,000点を払う', () {
      final s = newGame();
      final w = scored(s, daisangen(s, 0, tsumo: true), 0, pao: 2);
      expect(SessionLogic.paoDeltas(s, w), [48000, 0, -48000, 0]);
    });

    test('ほかの人からのロン: 包の人と放銃者で半分ずつ（本場は放銃者）', () {
      final s = newGame(honba: 2);
      final w = scored(s, daisangen(s, 1, tsumo: false), 1, loser: 2, pao: 3);
      expect(SessionLogic.paoDeltas(s, w, loser: 2), [0, 32600, -16600, -16000]);
    });

    test('包の人からのロン: 普段どおり放銃者が全額', () {
      final s = newGame();
      final w = scored(s, daisangen(s, 1, tsumo: false), 1, loser: 2, pao: 2);
      expect(SessionLogic.paoDeltas(s, w, loser: 2), [0, 32000, -32000, 0]);
    });

    test('ダブル役満（大三元＋字一色）のツモ: 包の人は大三元の分だけ全額、残りは普段どおり', () {
      final s = newGame();
      final w = scored(s, daisangenTsuiso(s, 1), 1, pao: 3);
      expect(w.result.yakumanCount, 2);
      expect(SessionLogic.paoUnits(w.result), 1);
      // 字一色の分（親16,000・子8,000ずつ）は普段どおり、大三元の分 32,000 は D
      expect(SessionLogic.paoDeltas(s, w), [-16000, 64000, -8000, -40000]);
    });

    test('包の人を選ばなければ普段どおり', () {
      final s = newGame();
      final w = scored(s, daisangen(s, 1, tsumo: true), 1);
      expect(SessionLogic.paoDeltas(s, w), [-16000, 32000, -8000, -8000]);
    });
  });

  group('包を選べるか', () {
    test('大三元・大四喜があり、包ありのルールのときだけ', () {
      final s = newGame();
      expect(SessionLogic.canChoosePao(s, scored(s, daisangen(s, 1, tsumo: true), 1)), isTrue);
      final off = newGame(pao: false);
      expect(SessionLogic.canChoosePao(off, scored(off, daisangen(off, 1, tsumo: true), 1)), isFalse);
    });
  });

  group('結果画面', () {
    Future<ProviderContainer> pump(WidgetTester tester, GameSession s, WinInput input, {int? loser}) async {
      await tester.binding.setSurfaceSize(const Size(420, 2400));
      await tester.pumpWidget(ProviderScope(
        overrides: [sessionRepositoryProvider.overrideWithValue(InMemorySessionRepository([s]))],
        child: MaterialApp(
          home: WinResultScreen(
              sessionId: 'x', entries: [WinEntry(winner: 1, input: input)], loser: loser),
        ),
      ));
      return ProviderScope.containerOf(tester.element(find.byType(WinResultScreen)));
    }

    testWidgets('大三元のときは包の人を選べて、点数移動と記録に反映される', (tester) async {
      final s = newGame();
      final c = await pump(tester, s, daisangen(s, 1, tsumo: true));
      expect(find.text('包（責任払い）'), findsOneWidget);
      expect(find.text('-16,000'), findsOneWidget); // 選ぶ前は親が 16,000点

      await tester.tap(find.widgetWithText(ChoiceChip, 'D'));
      await tester.pump();
      expect(find.text('-32,000'), findsOneWidget);
      expect(find.text('-16,000'), findsNothing);

      await tester.tap(find.text('この結果で確定'));
      await tester.pumpAndSettle();
      final after = c.read(sessionProvider('x'))!;
      expect(after.scores, [25000, 57000, 25000, -7000]);
      expect(after.records.single.description, endsWith('（包: D）'));
    });

    testWidgets('包なしのルールでは選ぶ欄が出ない', (tester) async {
      final s = newGame(pao: false);
      await pump(tester, s, daisangen(s, 1, tsumo: true));
      expect(find.text('包（責任払い）'), findsNothing);
    });
  });
}
