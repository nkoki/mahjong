import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_app/features/history/history_list_screen.dart';
import 'package:mahjong_app/features/session/data/session_repository.dart';
import 'package:mahjong_app/features/session/domain/models.dart';
import 'package:mahjong_app/features/session/session_providers.dart';
import 'package:mahjong_app/features/stats/stats_screen.dart';

import 'player_stats_test.dart' show playedGame;

/// 戦績の絞り込み
void main() {
  final now = DateTime(2026, 6, 30);
  final sessions = <GameSession>[
    playedGame('a', ['Taro', 'B', 'C', 'D'], at: DateTime(2026, 6, 20)),
    playedGame('b', ['花子', 'B', 'C'], at: DateTime(2026, 3, 1)),
    playedGame('c', ['E', 'F', 'G', 'H'], at: DateTime(2025, 12, 31)).copyWith(favorite: true),
  ];
  List<String> ids(HistoryFilter f) => [for (final s in f.apply(sessions, now)) s.id];

  test('名前（一部・大文字小文字を区別しない）', () {
    expect(ids(const HistoryFilter(name: 'taro')), ['a']);
    expect(ids(const HistoryFilter(name: ' B ')), ['a', 'b']);
    expect(ids(const HistoryFilter(name: 'Z')), isEmpty);
  });

  test('人数・期間・お気に入り、組み合わせ', () {
    expect(ids(const HistoryFilter(playerCount: 3)), ['b']);
    expect(ids(const HistoryFilter(playerCount: 4)), ['a', 'c']);
    expect(ids(const HistoryFilter(period: StatsPeriod.days30)), ['a']);
    expect(ids(const HistoryFilter(period: StatsPeriod.thisYear)), ['a', 'b']);
    expect(ids(const HistoryFilter(favoritesOnly: true)), ['c']);
    expect(ids(const HistoryFilter(name: 'B', playerCount: 4)), ['a']);
    expect(const HistoryFilter().isActive, isFalse);
    expect(const HistoryFilter(name: 'x').isActive, isTrue);
  });

  testWidgets('画面で絞り込み、解除できる', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    await tester.pumpWidget(ProviderScope(
      overrides: [sessionRepositoryProvider.overrideWithValue(InMemorySessionRepository(sessions))],
      child: MaterialApp(home: HistoryListScreen(now: now)),
    ));
    expect(find.textContaining('Taro / B'), findsOneWidget);
    expect(find.textContaining('花子 / B'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('history-name')), '花');
    await tester.pump();
    expect(find.textContaining('Taro / B'), findsNothing);
    expect(find.textContaining('花子 / B'), findsOneWidget);
    expect(find.text('3件中 1件を表示'), findsOneWidget);
    await tester.tap(find.text('4人打ち'));
    await tester.pump();
    expect(find.text('この条件に合う対局はありません'), findsOneWidget);
    await tester.tap(find.text('絞り込みを解除'));
    await tester.pump();
    expect(find.textContaining('Taro / B'), findsOneWidget);
    expect(find.textContaining('E / F'), findsOneWidget);
    await tester.tap(find.text('直近30日'));
    await tester.pump();
    expect(find.textContaining('E / F'), findsNothing);
    expect(find.textContaining('Taro / B'), findsOneWidget);
  });
}
