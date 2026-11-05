import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_app/features/session/data/session_repository.dart';
import 'package:mahjong_app/features/session/domain/session_logic.dart';
import 'package:mahjong_app/features/session/session_providers.dart';
import 'package:mahjong_app/features/stats/player_stats.dart';
import 'package:mahjong_app/features/stats/stats_screen.dart';

import 'player_stats_test.dart' show playedGame, start;

/// プレイヤー名の変更・まとめ
void main() {
  test('すべての対局で名前を変え、変えない対局は同じオブジェクトのまま', () {
    final a = playedGame('a', ['たろう', 'B', 'C', 'D']);
    final b = playedGame('b', ['B', 'C', 'D', 'たろう']);
    final c = playedGame('c', ['E', 'F', 'G', 'H']);
    final r = SessionLogic.renamePlayer([a, b, c], 'たろう', ' 太郎 ');
    expect(r.renamed, 2);
    expect(r.skipped, 0);
    expect(r.sessions[0].playerNames, ['太郎', 'B', 'C', 'D']);
    expect(r.sessions[1].playerNames.last, '太郎');
    expect(identical(r.sessions[2], c), isTrue);
    // 点数や局の記録はそのまま
    expect(r.sessions[0].scores, a.scores);
    expect(r.sessions[0].records, a.records);
  });

  test('表記ゆれをまとめると、個人成績で同じ人として集計する。両方がいる対局は変えない', () {
    final a = playedGame('a', ['たろう', 'B', 'C', 'D']);
    final b = playedGame('b', ['太郎', 'B', 'C', 'D']);
    final both = playedGame('c', ['たろう', '太郎', 'C', 'D']);
    final r = SessionLogic.renamePlayer([a, b, both], 'たろう', '太郎');
    expect(r.renamed, 1);
    expect(r.skipped, 1);
    expect(identical(r.sessions[2], both), isTrue);
    final names = {for (final p in PlayerStatsCalculator.compute(r.sessions, playerCount: 4).players) p.name: p};
    expect(names['太郎']!.games, 3);
    expect(names['たろう']!.games, 1);
  });

  test('空の名前・同じ名前にはできない', () {
    expect(SessionLogic.validateRename('A', ' '), isNotNull);
    expect(SessionLogic.validateRename('A', 'A'), isNotNull);
    expect(() => SessionLogic.renamePlayer([], 'A', ''), throwsArgumentError);
  });

  test('名前を変えたあとに元に戻しても、名前は戻らない', () {
    var s = start('x', ['A', 'B', 'C', 'D']);
    s = SessionLogic.toggleRiichi(s, 0);
    s = SessionLogic.renamePlayer([s], 'A', 'あ').sessions.single;
    expect(SessionLogic.undo(s).playerNames.first, 'あ');
  });

  testWidgets('個人成績の画面から名前をまとめられる', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 2400));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sessionRepositoryProvider.overrideWithValue(InMemorySessionRepository([
          playedGame('a', ['たろう', 'B', 'C', 'D']),
          playedGame('b', ['太郎', 'B', 'C', 'D']),
        ])),
      ],
      child: const MaterialApp(home: StatsScreen()),
    ));
    final c = ProviderScope.containerOf(tester.element(find.byType(StatsScreen)));
    await tester.tap(find.byKey(const ValueKey('rename-たろう')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ActionChip, '太郎'));
    await tester.pump();
    expect(find.textContaining('同じ人としてまとめます'), findsOneWidget);
    await tester.tap(find.text('まとめる'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1対局で「たろう」を「太郎」にまとめました'), findsOneWidget);
    expect(c.read(sessionsProvider).every((s) => s.playerNames.contains('太郎')), isTrue);
    expect(find.byKey(const ValueKey('rename-たろう')), findsNothing);
  });
}
