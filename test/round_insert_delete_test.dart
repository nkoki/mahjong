import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_app/features/history/history_detail_screen.dart';
import 'package:mahjong_app/features/session/data/session_repository.dart';
import 'package:mahjong_app/features/session/domain/models.dart';
import 'package:mahjong_app/features/session/domain/session_logic.dart';
import 'package:mahjong_app/features/session/screen_awake.dart';
import 'package:mahjong_app/features/session/screens/dashboard_screen.dart';
import 'package:mahjong_app/features/session/session_providers.dart';
import 'package:mahjong_app/features/stats/player_stats.dart';

import 'player_stats_test.dart' show start, win;
import 'table_view_test.dart' show FakeScreenAwake;

int total(GameSession s) =>
    s.scores.fold<int>(0, (a, v) => a + v) + (s.finished ? 0 : s.riichiSticks * 1000);

GameSession riichiDraw(GameSession s, int riichi) {
  s = SessionLogic.toggleRiichi(s, riichi);
  return SessionLogic.applyDraw(s,
      type: DrawType.exhaustive, tenpai: [for (var i = 0; i < s.playerCount; i++) i == riichi]);
}

void main() {
  group('局の削除', () {
    test('二重に入れた局を消すと、点数がその前に戻り、局の進行は変わらない', () {
      final once = win(start('x', ['A', 'B', 'C', 'D']), 1, loser: 2);
      final twice = win(once, 1, loser: 2);
      final e = SessionLogic.deleteRound(twice, 1);
      expect(e.records.length, 1);
      expect(e.scores, once.scores);
      expect(e.roundStartScores, once.scores);
      expect(e.roundLabel, twice.roundLabel, reason: '局・本場はそのまま');
      expect(SessionLogic.undo(e).records.length, 2);
    });

    test('前の局を消すと後の局の点数もずれる', () {
      var s = win(start('x', ['A', 'B', 'C', 'D']), 1, loser: 2);
      s = win(s, 3, loser: 0);
      final e = SessionLogic.deleteRound(s, 0);
      expect(e.records.single.deltas, s.records[1].deltas);
      expect(e.records.single.scoresAfter, [for (var i = 0; i < 4; i++) 25000 + s.records[1].deltas[i]]);
      expect(e.scores, e.records.single.scoresAfter);
    });

    test('その局で出した立直棒は持ち主に戻る', () {
      final s = riichiDraw(start('x', ['A', 'B', 'C', 'D']), 0);
      expect(s.riichiSticks, 1);
      final e = SessionLogic.deleteRound(s, 0);
      expect(e.riichiSticks, 0);
      expect(e.scores, [25000, 25000, 25000, 25000]);
    });

    test('立直棒を後の局で受け取っていたら消せない。受け取った局を消すと供託が場に戻る', () {
      var s = riichiDraw(start('x', ['A', 'B', 'C', 'D']), 0);
      s = win(s, 1, loser: 2); // B が供託1本を受け取る
      expect(s.riichiSticks, 0);
      expect(SessionLogic.validateDeleteRound(s, 0), contains('削除できません'));
      final e = SessionLogic.deleteRound(s, 1);
      expect(e.riichiSticks, 1);
      expect(total(e), 100000);
    });

    test('終局した対局: トップに渡した供託を付け替える', () {
      final s = SessionLogic.finishManually(riichiDraw(start('x', ['A', 'B', 'C', 'D']), 0));
      expect(s.settledSticks, 1);
      final e = SessionLogic.deleteRound(s, 0);
      expect(e.settledSticks, 0);
      expect(e.scores, [25000, 25000, 25000, 25000]);
    });
  });

  group('局の追加', () {
    test('前に差し込むと、後の局と今の点数がずれる', () {
      final s = win(start('x', ['A', 'B', 'C', 'D']), 1, loser: 2);
      final e = SessionLogic.insertRound(s, 0, roundLabel: '東1局 0本場', deltas: [3000, -1000, -1000, -1000]);
      expect(e.records.length, 2);
      expect(e.records[0].kind, 'draw');
      expect(e.records[0].scoresAfter, [28000, 24000, 24000, 24000]);
      expect(e.records[0].edited, isTrue);
      expect(e.records[1].scoresAfter, [for (var i = 0; i < 4; i++) s.records[0].scoresAfter[i] + [3000, -1000, -1000, -1000][i]]);
      expect(e.scores, e.records[1].scoresAfter);
      expect(e.roundLabel, s.roundLabel);
      expect(total(e), 100000);
    });

    test('和了の局は個人成績の和了・放銃に数える（和了点は分からない）', () {
      final s = SessionLogic.finishManually(start('x', ['A', 'B', 'C', 'D']));
      final e = SessionLogic.insertRound(s, 0,
          roundLabel: '東1局', deltas: [0, 8000, -8000, 0], winners: [1], loser: 2);
      final st = {for (final p in PlayerStatsCalculator.compute([e], playerCount: 4).players) p.name: p};
      expect(st['B']!.wins, 1);
      expect(st['C']!.dealIns, 1);
      expect(st['B']!.averageWinPoints, isNull);
      expect(e.finalResults.first.player, 1);
    });

    test('合計が0でない・増減なし・和了者なしは追加できない', () {
      final s = start('x', ['A', 'B', 'C', 'D']);
      expect(SessionLogic.validateInsertRound(s, 0, [1000, 0, 0, 0]), contains('合計を0'));
      expect(SessionLogic.validateInsertRound(s, 0, [0, 0, 0, 0]), isNotNull);
      expect(SessionLogic.validateInsertRound(s, 0, [1000, -1000, 0, 0], winners: []), isNotNull);
      expect(SessionLogic.validateInsertRound(s, 1, [1000, -1000, 0, 0]), isNotNull, reason: '場所');
      expect(SessionLogic.validateInsertRound(s, 0, [1050, -1050, 0, 0]), contains('100点'));
    });
  });

  group('局・本場・供託の修正', () {
    test('点数は変えずに直し、元に戻せる', () {
      final s = start('x', ['A', 'B', 'C', 'D']);
      final e = SessionLogic.adjustProgress(s, roundIndex: 5, honba: 2, riichiSticks: 1);
      expect(e.roundLabel, '南2局 2本場');
      expect(e.dealer, 1);
      expect(e.riichiSticks, 1);
      expect(e.scores, s.scores);
      expect(SessionLogic.undo(e).roundLabel, '東1局 0本場');
    });

    test('選べる局の範囲（西入ありなら延長の4局目まで）。終局後は直せない', () {
      const g = GameSettings();
      expect(SessionLogic.maxRoundIndex(g), 7);
      expect(SessionLogic.maxRoundIndex(g.copyWith(westRound: true)), 11);
      expect(SessionLogic.maxRoundIndex(const GameSettings.sanma(tonpuu: true)), 2);
      final s = start('x', ['A', 'B', 'C', 'D']);
      expect(() => SessionLogic.adjustProgress(s, roundIndex: 8, honba: 0, riichiSticks: 0), throwsArgumentError);
      expect(() => SessionLogic.adjustProgress(SessionLogic.finishManually(s), roundIndex: 0, honba: 0, riichiSticks: 0),
          throwsArgumentError);
    });
  });

  group('画面', () {
    Future<ProviderContainer> pump(WidgetTester tester, GameSession s, Widget home) async {
      await tester.binding.setSurfaceSize(const Size(420, 2400));
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sessionRepositoryProvider.overrideWithValue(InMemorySessionRepository([s])),
          screenAwakeProvider.overrideWithValue(FakeScreenAwake()),
        ],
        child: MaterialApp(home: home),
      ));
      return ProviderScope.containerOf(tester.element(find.byWidget(home)));
    }

    testWidgets('戦績詳細から局を削除し、元に戻せる', (tester) async {
      final s = win(win(start('x', ['A', 'B', 'C', 'D']), 1, loser: 2), 1, loser: 2);
      final c = await pump(tester, s, const HistoryDetailScreen(sessionId: 'x'));
      await tester.tap(find.byTooltip('この局を修正').first); // 新しい順なので最後の局
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('delete-round')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('delete-round')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '削除'));
      await tester.pumpAndSettle();
      expect(c.read(sessionProvider('x'))!.records.length, 1);
      expect(find.text('局を削除しました'), findsOneWidget);
      await tester.tap(find.text('元に戻す'));
      await tester.pumpAndSettle();
      expect(c.read(sessionProvider('x'))!.records.length, 2);
    });

    testWidgets('戦績詳細から入れ忘れた局を追加できる', (tester) async {
      final s = win(start('x', ['A', 'B', 'C', 'D']), 1, loser: 2);
      final c = await pump(tester, s, const HistoryDetailScreen(sessionId: 'x'));
      await tester.tap(find.byKey(const ValueKey('insert-round')));
      await tester.pumpAndSettle();
      final add = find.widgetWithText(FilledButton, '局を追加');
      expect(tester.widget<FilledButton>(add).onPressed, isNull);
      await tester.tap(find.byKey(const ValueKey('insert-winner-3')));
      await tester.tap(find.byKey(const ValueKey('insert-loser-0')));
      await tester.enterText(find.byKey(const ValueKey('insert-delta-3')), '2000');
      await tester.enterText(find.byKey(const ValueKey('insert-delta-0')), '-2000');
      await tester.pump();
      await tester.tap(add);
      await tester.pumpAndSettle();
      final e = c.read(sessionProvider('x'))!;
      expect(e.records.length, 2);
      expect(e.records.last.winners, [3]);
      expect(e.records.last.loser, 0);
      expect(e.scores[3], s.scores[3] + 2000);
      expect(find.text('局を追加しました'), findsOneWidget);
    });

    testWidgets('対局画面のメニューから局・本場・供託を直せる', (tester) async {
      final c = await pump(tester, start('x', ['A', 'B', 'C', 'D']), const DashboardScreen(sessionId: 'x'));
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('局・本場・供託を直す'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('progress-round')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('東2局（親: B）').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('progress-honba-plus')));
      await tester.pump();
      await tester.tap(find.text('直す'));
      await tester.pumpAndSettle();
      expect(c.read(sessionProvider('x'))!.roundLabel, '東2局 1本場');
    });

    testWidgets('3人打ちのウマを戦績詳細で変えられる', (tester) async {
      final s = SessionLogic.finishManually(start('x', ['A', 'B', 'C']));
      await pump(tester, s, const HistoryDetailScreen(sessionId: 'x'));
      await tester.tap(find.widgetWithText(OutlinedButton, '変更'));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '変更する')).onPressed, isNotNull);
    });
  });
}
