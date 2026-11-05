import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_app/features/session/data/session_repository.dart';
import 'package:mahjong_app/features/session/domain/models.dart';
import 'package:mahjong_app/features/session/domain/session_logic.dart';
import 'package:mahjong_app/features/session/screens/new_session_screen.dart';
import 'package:mahjong_app/features/session/session_providers.dart';

GameSession game(String id, List<String> names, DateTime at) => GameSession.start(
      id: id,
      playerNames: names,
      settings: GameSettings(playerCount: names.length),
      now: at,
    );

/// プレイヤー名の候補
void main() {
  final old = game('a', ['佐藤', '鈴木', '高橋', '田中'], DateTime(2026, 1, 1));
  final mid = game('b', ['伊藤', '佐藤', 'プレイヤー3', '山本'], DateTime(2026, 2, 1));
  final sanma = game('c', ['渡辺', '佐藤', '中村'], DateTime(2026, 3, 1));

  group('候補の作り方', () {
    test('最近使った順・重複なし・「プレイヤー1」などは除く', () {
      expect(SessionLogic.recentPlayerNames([old, mid, sanma]),
          ['渡辺', '佐藤', '中村', '伊藤', '山本', '鈴木', '高橋', '田中']);
      expect(SessionLogic.recentPlayerNames([old, mid, sanma], limit: 3), ['渡辺', '佐藤', '中村']);
      expect(SessionLogic.recentPlayerNames([]), isEmpty);
    });

    test('前回のメンバーは同じ人数の一番新しい対局', () {
      expect(SessionLogic.lastMembers([old, mid, sanma], 4), ['伊藤', '佐藤', 'プレイヤー3', '山本']);
      expect(SessionLogic.lastMembers([old, mid, sanma], 3), ['渡辺', '佐藤', '中村']);
      expect(SessionLogic.lastMembers([old], 3), isNull);
    });

    test('同じ名前の人がいたら注意する（空の欄は「プレイヤー1」などとして比べる）', () {
      expect(SessionLogic.validatePlayerNames(['A', 'B', 'C', 'D']), isNull);
      expect(SessionLogic.validatePlayerNames(['A', '', '', '']), isNull);
      expect(SessionLogic.validatePlayerNames(['A', 'B', 'A ', 'D']), contains('同じ名前'));
      expect(SessionLogic.validatePlayerNames(['プレイヤー2', '', 'C', 'D']), contains('同じ名前'));
    });
  });

  group('新規対局の画面', () {
    Future<ProviderContainer> pump(WidgetTester tester, List<GameSession> sessions) async {
      await tester.binding.setSurfaceSize(const Size(420, 2600));
      await tester.pumpWidget(ProviderScope(
        overrides: [sessionRepositoryProvider.overrideWithValue(InMemorySessionRepository(sessions))],
        child: const MaterialApp(home: NewSessionScreen()),
      ));
      return ProviderScope.containerOf(tester.element(find.byType(NewSessionScreen)));
    }

    String nameOf(WidgetTester tester, int i) =>
        tester.widget<TextField>(find.byKey(ValueKey('player-name-$i'))).controller!.text;

    testWidgets('候補をタップすると空いている欄に入り、使った名前は選べなくなる', (tester) async {
      await pump(tester, [old, mid]);
      expect(nameOf(tester, 0), '', reason: '入力欄は空（ヒントで「プレイヤー1」）');
      await tester.tap(find.widgetWithText(ActionChip, '鈴木'));
      await tester.pump();
      await tester.tap(find.widgetWithText(ActionChip, '伊藤'));
      await tester.pump();
      expect([nameOf(tester, 0), nameOf(tester, 1), nameOf(tester, 2)], ['鈴木', '伊藤', '']);
      expect(tester.widget<ActionChip>(find.widgetWithText(ActionChip, '鈴木')).onPressed, isNull);
      expect(tester.widget<ActionChip>(find.widgetWithText(ActionChip, '高橋')).onPressed, isNotNull);
    });

    testWidgets('前回のメンバーを座順のまま入れて開始できる', (tester) async {
      final c = await pump(tester, [old, mid]);
      await tester.tap(find.textContaining('前回のメンバー'));
      await tester.pump();
      expect([for (var i = 0; i < 4; i++) nameOf(tester, i)], ['伊藤', '佐藤', '', '山本']);
      await tester.ensureVisible(find.text('対局開始'));
      await tester.tap(find.text('対局開始'));
      await tester.pumpAndSettle();
      final created = c.read(sessionsProvider).firstWhere((s) => s.id != 'a' && s.id != 'b');
      expect(created.playerNames, ['伊藤', '佐藤', 'プレイヤー3', '山本']);
    });

    testWidgets('同じ名前があると開始できない', (tester) async {
      await pump(tester, const []);
      expect(find.textContaining('前回のメンバー'), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('player-name-0')), 'A');
      await tester.enterText(find.byKey(const ValueKey('player-name-1')), 'A');
      await tester.pump();
      expect(find.textContaining('同じ名前の人がいます'), findsOneWidget);
      await tester.ensureVisible(find.text('対局開始'));
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '対局開始')).onPressed, isNull);
      // 消すボタンで直せる
      await tester.tap(find.byTooltip('名前を消す').at(1));
      await tester.pump();
      expect(find.textContaining('同じ名前の人がいます'), findsNothing);
    });
  });
}
