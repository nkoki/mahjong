import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_app/features/history/history_list_screen.dart';
import 'package:mahjong_app/features/session/domain/models.dart';
import 'package:mahjong_app/features/session/session_providers.dart';

import 'game_limit_test.dart' show finishedGames, containerWith;

/// 戦績の選択削除・お気に入り以外の全件削除
void main() {
  test('deleteMany: 指定した対局だけを削除する（お気に入りも削除できる）', () {
    final c = containerWith(finishedGames(4, favorites: {1}));
    final n = c.read(sessionsProvider.notifier).deleteMany({'g0', 'g1'});
    expect(n, 2);
    expect(c.read(sessionsProvider).map((s) => s.id), ['g3', 'g2']);
  });

  test('deleteAllExceptFavorites: お気に入り以外を削除し、対局中の対局も削除する', () {
    final games = finishedGames(4, favorites: {0, 2});
    games[0] = games[0].copyWith(finished: false); // g3 は対局中
    final c = containerWith(games);
    final n = c.read(sessionsProvider.notifier).deleteAllExceptFavorites();
    expect(n, 2);
    expect(c.read(sessionsProvider).map((s) => s.id), ['g2', 'g0']);
    expect(c.read(sessionsProvider).every((s) => s.favorite), isTrue);
  });

  group('画面', () {
    Future<ProviderContainer> pump(WidgetTester tester, List<GameSession> sessions) async {
      await tester.binding.setSurfaceSize(const Size(400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final c = containerWith(sessions);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: HistoryListScreen()),
      ));
      return c;
    }

    Future<void> openMenu(WidgetTester tester, String item) async {
      await tester.tap(find.byKey(const ValueKey('history-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item));
      await tester.pumpAndSettle();
    }

    testWidgets('チェックボックスは選択モードにしたときだけ出る', (tester) async {
      await pump(tester, finishedGames(3));
      expect(find.byType(Checkbox), findsNothing);
      await openMenu(tester, '選択して削除');
      expect(find.byType(Checkbox), findsNWidgets(3));
      expect(find.text('0件を選択'), findsOneWidget);
      // 選択をやめると消える
      await tester.tap(find.byKey(const ValueKey('selection-close')));
      await tester.pump();
      expect(find.byType(Checkbox), findsNothing);
      expect(find.text('戦績'), findsOneWidget);
    });

    testWidgets('お気に入りを含まない選択削除は、確認して削除する', (tester) async {
      final c = await pump(tester, finishedGames(3, favorites: {2}));
      await openMenu(tester, '選択して削除');
      await tester.tap(find.byKey(const ValueKey('session-g0')));
      await tester.tap(find.byKey(const ValueKey('select-g1')));
      await tester.pump();
      expect(find.text('2件を選択'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('delete-selected')));
      await tester.pumpAndSettle();
      expect(find.text('お気に入りが含まれています'), findsNothing);
      expect(find.textContaining('選択した2件の対局を削除しますか？'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('confirm-delete-selected')));
      await tester.pumpAndSettle();
      expect(c.read(sessionsProvider).map((s) => s.id), ['g2']);
      expect(find.byType(Checkbox), findsNothing, reason: '削除したら選択モードを終える');
      expect(find.text('2件の対局を削除しました'), findsOneWidget);
    });

    testWidgets('お気に入りを含む選択削除は警告し、キャンセルすれば削除しない・OKなら削除する', (tester) async {
      final c = await pump(tester, finishedGames(3, favorites: {1}));
      await openMenu(tester, '選択して削除');
      await tester.tap(find.byKey(const ValueKey('session-g0')));
      await tester.tap(find.byKey(const ValueKey('session-g1')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('delete-selected')));
      await tester.pumpAndSettle();
      expect(find.text('お気に入りが含まれています'), findsOneWidget);
      expect(find.textContaining('お気に入り（★）の対局が1件含まれています'), findsOneWidget);
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();
      expect(c.read(sessionsProvider), hasLength(3));
      expect(find.text('2件を選択'), findsOneWidget, reason: 'キャンセルしたら選択はそのまま');

      await tester.tap(find.byKey(const ValueKey('delete-selected')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('お気に入りも含めて削除'));
      await tester.pumpAndSettle();
      expect(c.read(sessionsProvider).map((s) => s.id), ['g2']);
    });

    testWidgets('表示中をすべて選択できる。長押しでも選択モードになる', (tester) async {
      await pump(tester, finishedGames(3));
      await tester.longPress(find.byKey(const ValueKey('session-g1')));
      await tester.pump();
      expect(find.text('1件を選択'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('select-all')));
      await tester.pump();
      expect(find.text('3件を選択'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('select-all')));
      await tester.pump();
      expect(find.text('0件を選択'), findsOneWidget);
    });

    testWidgets('お気に入り以外をすべて削除: お気に入りは残る', (tester) async {
      final c = await pump(tester, finishedGames(4, favorites: {0, 3}));
      await openMenu(tester, 'お気に入り以外をすべて削除');
      expect(find.textContaining('お気に入り（★）以外の2件の対局をすべて削除しますか？'), findsOneWidget);
      expect(find.textContaining('お気に入りの2件は残ります'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('confirm-delete-all')));
      await tester.pumpAndSettle();
      expect(c.read(sessionsProvider).map((s) => s.id), ['g3', 'g0']);
    });

    testWidgets('お気に入りしかないときは、何も削除せずに知らせる', (tester) async {
      final c = await pump(tester, finishedGames(2, favorites: {0, 1}));
      await openMenu(tester, 'お気に入り以外をすべて削除');
      expect(find.byKey(const ValueKey('confirm-delete-all')), findsNothing);
      expect(find.text('お気に入り以外の対局はありません'), findsOneWidget);
      expect(c.read(sessionsProvider), hasLength(2));
    });
  });
}
