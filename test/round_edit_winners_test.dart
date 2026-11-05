import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_app/features/history/round_edit_screen.dart';
import 'package:mahjong_app/features/session/data/session_repository.dart';
import 'package:mahjong_app/features/session/domain/models.dart';
import 'package:mahjong_app/features/session/domain/session_logic.dart';
import 'package:mahjong_app/features/session/session_providers.dart';
import 'package:mahjong_app/features/stats/player_stats.dart';

import 'player_stats_test.dart' show start, win;

/// 局の修正で和了者・放銃者を直し、個人成績に合わせる
void main() {
  // 東1局: B が C からロン（3翻40符 5200）
  GameSession played() => win(start('x', ['A', 'B', 'C', 'D']), 1, loser: 2);

  Map<String, PlayerStats> stats(GameSession s) =>
      {for (final p in PlayerStatsCalculator.compute([SessionLogic.finishManually(s)], playerCount: 4).players) p.name: p};

  test('選び間違いの修正: 和了点は新しい和了者に付け替え、個人成績も変わる', () {
    final s = played();
    // 本当は D が C からロン
    final e = SessionLogic.editRound(s, 0,
        deltas: [0, 0, -5200, 5200], who: (winners: [3], loser: 2));
    final r = e.records[0];
    expect(r.winners, [3]);
    expect(r.loser, 2);
    expect(r.winPoints, [5200]);
    expect(r.edited, isTrue);
    final st = stats(e);
    expect(st['D']!.wins, 1);
    expect(st['D']!.averageWinPoints, 5200);
    expect(st['B']!.wins, 0);
    expect(st['C']!.dealIns, 1);
  });

  test('ロンをツモに直せる', () {
    final e = SessionLogic.editRound(played(), 0,
        deltas: [-1300, 5200, -1300, -2600], who: (winners: [1], loser: null));
    expect(e.records[0].loser, isNull);
    expect(stats(e)['C']!.dealIns, 0);
  });

  test('和了者の人数を変えると和了点は消し、平均打点に含めない', () {
    var s = played();
    s = win(s, 1, loser: 3); // 東2局: B が D からロン
    final e = SessionLogic.editRound(s, 0,
        deltas: [5200, 5200, -10400, 0], who: (winners: [0, 1], loser: 2));
    expect(e.records[0].winPoints, isNull);
    final b = stats(e)['B']!;
    expect(b.wins, 2);
    expect(b.winPointsCount, 1);
    expect(b.averageWinPoints, s.records[1].winPoints!.first.toDouble(), reason: '和了点が分かる1回だけで平均');
  });

  test('正しくない組み合わせは保存できない', () {
    final s = played();
    expect(SessionLogic.validateWinners(s, [], 2), isNotNull);
    expect(SessionLogic.validateWinners(s, [1], 1), isNotNull);
    expect(SessionLogic.validateWinners(s, [0, 1], null), contains('ダブロン'));
    expect(SessionLogic.validateWinners(s, [1], 2), isNull);
    expect(() => SessionLogic.editRound(s, 0, deltas: s.records[0].deltas, who: (winners: [2], loser: 2)),
        throwsArgumentError);
    // 流局の局は直せない
    final d = SessionLogic.applyDraw(s, type: DrawType.exhaustive, tenpai: [true, false, false, false]);
    expect(SessionLogic.canEditWinners(d.records[1]), isFalse);
  });

  testWidgets('修正画面で和了者・放銃者を選び直せる（3人打ちでも）', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    final s = win(start('x', ['A', 'B', 'C']), 1, loser: 2);
    await tester.pumpWidget(ProviderScope(
      overrides: [sessionRepositoryProvider.overrideWithValue(InMemorySessionRepository([s]))],
      child: const MaterialApp(home: RoundEditScreen(sessionId: 'x', index: 0)),
    ));
    final c = ProviderScope.containerOf(tester.element(find.byType(RoundEditScreen)));
    expect(find.text('和了した人'), findsOneWidget);
    // B の和了を外すと、和了者がいないので保存できない
    await tester.tap(find.byKey(const ValueKey('winner-1')));
    await tester.pump();
    expect(find.text('和了した人を選んでください'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('winner-0')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('loser-2')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('delta-0')), '${s.records[0].deltas[1]}');
    await tester.enterText(find.byKey(const ValueKey('delta-1')), '0');
    await tester.pump();
    await tester.tap(find.text('修正を保存'));
    await tester.pumpAndSettle();
    final r = c.read(sessionProvider('x'))!.records[0];
    expect(r.winners, [0]);
    expect(r.loser, 2);
  });
}
