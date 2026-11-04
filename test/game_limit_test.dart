import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_app/features/history/history_list_screen.dart';
import 'package:mahjong_app/features/session/data/session_repository.dart';
import 'package:mahjong_app/features/session/domain/models.dart';
import 'package:mahjong_app/features/session/domain/session_logic.dart';
import 'package:mahjong_app/features/session/screens/new_session_screen.dart';
import 'package:mahjong_app/features/session/session_providers.dart';

/// [n] 件の終局済み対局（i が小さいほど古い）。一覧と同じく新しい順に並べる
List<GameSession> finishedGames(int n, {Set<int> favorites = const {}}) => [
      for (var i = n - 1; i >= 0; i--)
        GameSession.start(
          id: 'g$i',
          playerNames: ['A$i', 'B', 'C', 'D'],
          settings: const GameSettings(),
          now: DateTime(2026, 1, 1).add(Duration(hours: i)),
        ).copyWith(finished: true, favorite: favorites.contains(i)),
    ];

ProviderContainer containerWith(List<GameSession> sessions) {
  final c = ProviderContainer(overrides: [
    sessionRepositoryProvider.overrideWithValue(InMemorySessionRepository(sessions)),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('削除する対局の選び方', () {
    test('100件以下なら削除しない', () {
      expect(SessionLogic.sessionsToPrune(finishedGames(100)), isEmpty);
    });

    test('超えた分だけ、一番古い対局から削除する', () {
      final r = SessionLogic.sessionsToPrune(finishedGames(102));
      expect(r.map((s) => s.id), ['g0', 'g1']);
    });

    test('お気に入りは削除せず、その次に古い対局を削除する', () {
      final r = SessionLogic.sessionsToPrune(finishedGames(101, favorites: {0, 1}));
      expect(r.map((s) => s.id), ['g2']);
    });

    test('対局中の対局は削除しない', () {
      final games = finishedGames(101);
      final oldestOngoing = games.last.copyWith(finished: false); // g0 を対局中に
      final r = SessionLogic.sessionsToPrune([...games.take(100), oldestOngoing]);
      expect(r.map((s) => s.id), ['g1']);
    });

    test('全部お気に入りなら削除せず、100件を超えて残す', () {
      final r = SessionLogic.sessionsToPrune(
          finishedGames(101, favorites: {for (var i = 0; i < 101; i++) i}));
      expect(r, isEmpty);
    });
  });

  group('新規対局の作成', () {
    test('100件ある状態で新しく始めると、一番古い対局が削除されて100件になる', () {
      final c = containerWith(finishedGames(100, favorites: {0}));
      final n = c.read(sessionsProvider.notifier);
      expect(n.sessionsRemovedByNextCreate().map((s) => s.id), ['g1']);
      final id = n.create(['新', 'B', 'C', 'D'], const GameSettings());
      final ids = c.read(sessionsProvider).map((s) => s.id).toList();
      expect(ids, hasLength(100));
      expect(ids.first, id);
      expect(ids, contains('g0')); // お気に入りは残る
      expect(ids, isNot(contains('g1')));
    });

    test('99件なら何も削除しない', () {
      final c = containerWith(finishedGames(99));
      final n = c.read(sessionsProvider.notifier);
      expect(n.sessionsRemovedByNextCreate(), isEmpty);
      n.create(['新', 'B', 'C', 'D'], const GameSettings());
      expect(c.read(sessionsProvider), hasLength(100));
    });
  });

  group('お気に入り', () {
    test('保存して読み込んでも残る。以前のデータはお気に入りなしとして読む', () {
      final s = finishedGames(1).single.copyWith(favorite: true);
      final restored = GameSession.fromJson(
          jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
      expect(restored.favorite, isTrue);

      final old = s.toJson()..remove('favorite');
      expect(GameSession.fromJson(old).favorite, isFalse);
    });

    test('元に戻してもお気に入りの設定は変わらない', () {
      final c = containerWith(const []);
      final n = c.read(sessionsProvider.notifier);
      final id = n.create(['A', 'B', 'C', 'D'], const GameSettings());
      n.applyDraw(id, type: DrawType.kyuushu, tenpai: [false, false, false, false]);
      n.toggleFavorite(id);
      n.undo(id);
      final s = c.read(sessionProvider(id))!;
      expect(s.records, isEmpty); // 局は元に戻った
      expect(s.favorite, isTrue); // お気に入りはそのまま
    });
  });

  group('画面', () {
    Future<void> pump(WidgetTester tester, List<GameSession> sessions, Widget home) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sessionRepositoryProvider.overrideWithValue(InMemorySessionRepository(sessions)),
        ],
        child: MaterialApp(home: home),
      ));
    }

    testWidgets('戦績一覧で★を押すとお気に入りになり、絞り込める', (tester) async {
      await pump(tester, finishedGames(3), const HistoryListScreen());
      expect(find.text('保存中: 3 / 100件（★お気に入り 0件）'), findsOneWidget);

      await tester.tap(find.byTooltip('お気に入りにする').first);
      await tester.pump();
      expect(find.text('保存中: 3 / 100件（★お気に入り 1件）'), findsOneWidget);

      await tester.tap(find.text('お気に入り（1）'));
      await tester.pump();
      expect(find.byTooltip('お気に入りを解除'), findsOneWidget);
      expect(find.byTooltip('お気に入りにする'), findsNothing);
    });

    testWidgets('上限のとき、次に削除される対局に印が付く', (tester) async {
      await pump(tester, finishedGames(100, favorites: {0}), const HistoryListScreen());
      await tester.scrollUntilVisible(find.text('次に新しい対局を始めると削除されます'), 500,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('次に新しい対局を始めると削除されます'), findsOneWidget);
    });

    testWidgets('上限のとき、新規対局の開始前に削除の確認が出る', (tester) async {
      await pump(tester, finishedGames(100), const NewSessionScreen());
      await tester.scrollUntilVisible(find.text('対局開始'), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('対局開始'));
      await tester.pumpAndSettle();
      expect(find.text('古い対局が削除されます'), findsOneWidget);
      expect(find.textContaining('A0 / B / C / D'), findsOneWidget);

      // キャンセルすると何も削除されない
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();
      final element = tester.element(find.byType(NewSessionScreen));
      final c = ProviderScope.containerOf(element);
      expect(c.read(sessionsProvider), hasLength(100));
      expect(c.read(sessionProvider('g0')), isNotNull);
    });
  });
}
