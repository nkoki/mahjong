import 'dart:convert';

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

/// 対局の途中のプレイヤーの交代
void main() {
  // 東1局: B が C からロン → C を E に交代 → 東2局: E が A からロン → 終局
  GameSession played() {
    var s = win(start('x', ['A', 'B', 'C', 'D']), 1, loser: 2);
    s = SessionLogic.substitute(s, 2, ' E ');
    s = win(s, 2, loser: 0);
    return SessionLogic.finishManually(s);
  }

  Map<String, PlayerStats> stats(List<GameSession> s) =>
      {for (final p in PlayerStatsCalculator.compute(s, playerCount: 4).players) p.name: p};

  test('点数と席を引き継ぎ、それぞれの局を打っていた人の名前が分かる', () {
    final s = played();
    expect(s.playerNames, ['A', 'B', 'E', 'D']);
    expect(s.substitutions.single.fromRecord, 1);
    expect(s.nameAt(0, 2), 'C');
    expect(s.nameAt(1, 2), 'E');
    expect(s.nameAt(0, 0), 'A');
    expect(s.allNames, containsAll(['C', 'E']));
  });

  test('個人成績: 交代前の局は抜けた人、後の局と最終結果は入った人', () {
    final st = stats([played()]);
    expect(st['C']!.dealIns, 1);
    expect(st['C']!.rounds, 1);
    expect(st['C']!.games, 0, reason: '最終結果は終局したときに打っていた人');
    expect(st['E']!.wins, 1);
    expect(st['E']!.rounds, 1);
    expect(st['E']!.games, 1);
  });

  test('今打っている人の名前にはできない。1局も打たずにもう一度交代したら1回にまとめる', () {
    final s = start('x', ['A', 'B', 'C', 'D']);
    expect(SessionLogic.validateSubstitute(s, 0, 'B'), isNotNull);
    expect(SessionLogic.validateSubstitute(s, 0, ' '), isNotNull);
    expect(SessionLogic.validateSubstitute(SessionLogic.finishManually(s), 0, 'E'), isNotNull);
    var t = SessionLogic.substitute(s, 0, 'E');
    t = SessionLogic.substitute(t, 0, 'F');
    expect(t.substitutions.single.from, 'A');
    expect(t.substitutions.single.to, 'F');
    // 元の人に戻したら交代なし
    expect(SessionLogic.substitute(t, 0, 'A').substitutions, isEmpty);
  });

  test('元に戻すと交代する前に戻る（保存して読み込んでも）', () {
    var s = win(start('x', ['A', 'B', 'C', 'D']), 1, loser: 2);
    s = SessionLogic.substitute(s, 2, 'E');
    s = win(s, 2, loser: 0);
    final loaded = GameSession.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
    expect(loaded.substitutions.single.to, 'E');
    expect(loaded.playerNames[2], 'E');
    final back1 = SessionLogic.undo(loaded);
    expect(back1.playerNames[2], 'E');
    final back2 = SessionLogic.undo(back1);
    expect(back2.playerNames[2], 'C');
    expect(back2.substitutions, isEmpty);
  });

  test('名前を変えると交代の記録と元に戻す用の前の状態も変わる', () {
    final s = played();
    final r = SessionLogic.renamePlayer([s], 'C', 'しー');
    expect(r.renamed, 1);
    final t = r.sessions.single;
    expect(t.nameAt(0, 2), 'しー');
    expect(SessionLogic.renamePlayer([s], 'E', 'A').skipped, 1, reason: 'A も同じ対局にいる');
  });

  test('前に局を追加・削除すると、交代の局の番号もずれる', () {
    final s = played();
    final ins = SessionLogic.insertRound(s, 0, roundLabel: 'x', deltas: [1000, -1000, 0, 0]);
    expect(ins.substitutions.single.fromRecord, 2);
    expect(ins.nameAt(1, 2), 'C');
    final del = SessionLogic.deleteRound(s, 0);
    expect(del.substitutions.single.fromRecord, 0);
    expect(del.nameAt(0, 2), 'E');
  });

  test('以前の形式（交代なし）も読める', () {
    final s = win(start('x', ['A', 'B', 'C', 'D']), 1, loser: 2);
    final j = s.toJson();
    expect(j.containsKey('substitutions'), isFalse);
    expect(GameSession.fromJson(jsonDecode(jsonEncode(j)) as Map<String, dynamic>).substitutions, isEmpty);
    expect(SharedPrefsSessionRepository.formatVersion, greaterThanOrEqualTo(7));
  });

  testWidgets('対局画面のメニューから交代し、戦績詳細に表示される', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    final repo = InMemorySessionRepository([win(start('x', ['A', 'B', 'C', 'D']), 1, loser: 2)]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sessionRepositoryProvider.overrideWithValue(repo),
        screenAwakeProvider.overrideWithValue(FakeScreenAwake()),
      ],
      child: const MaterialApp(home: DashboardScreen(sessionId: 'x')),
    ));
    final c = ProviderScope.containerOf(tester.element(find.byType(DashboardScreen)));
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('プレイヤーを交代'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sub-seat-3')));
    await tester.enterText(find.byKey(const ValueKey('sub-name')), 'B');
    await tester.pump();
    expect(find.textContaining('今この対局で打っています'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('sub-name')), 'F');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '交代'));
    await tester.pumpAndSettle();
    expect(c.read(sessionProvider('x'))!.playerNames, ['A', 'B', 'C', 'F']);
    expect(find.text('F'), findsWidgets);

    await tester.binding.setSurfaceSize(const Size(420, 4000));
    await tester.pumpWidget(ProviderScope(
      key: UniqueKey(),
      overrides: [sessionRepositoryProvider.overrideWithValue(InMemorySessionRepository([c.read(sessionProvider('x'))!]))],
      child: const MaterialApp(home: HistoryDetailScreen(sessionId: 'x')),
    ));
    expect(find.text('D → F'), findsOneWidget);
    expect(find.text('これからの局から'), findsOneWidget);
  });
}
