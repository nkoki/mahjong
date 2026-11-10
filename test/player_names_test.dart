import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_app/features/session/data/session_repository.dart';
import 'package:mahjong_app/features/session/domain/models.dart';
import 'package:mahjong_app/features/session/domain/session_logic.dart';
import 'package:mahjong_app/features/session/screens/new_session_screen.dart';
import 'package:mahjong_app/features/session/session_providers.dart';
import 'package:mahjong_app/shared/widgets/player_name_field.dart';

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

  group('名前の部分一致', () {
    const names = ['伊藤', '佐藤', 'たなか', 'Tanaka', '田中', 'タナカ太郎'];
    test('含む名前を選び、前方一致を先に並べる', () {
      expect(matchPlayerNames(names, '藤'), ['伊藤', '佐藤']);
      expect(matchPlayerNames(names, ''), names);
      expect(matchPlayerNames(names, 'nak'), ['Tanaka']);
    });
    test('大文字・小文字、ひらがな・カタカナの違いは無視する', () {
      expect(matchPlayerNames(names, 'TAN'), ['Tanaka']);
      expect(matchPlayerNames(names, 'たなか'), ['タナカ太郎'], reason: '入力と同じ名前（たなか）は出さない');
      expect(matchPlayerNames(names, 'タナ'), ['たなか', 'タナカ太郎']);
      expect(matchPlayerNames(names, '太郎'), ['タナカ太郎']);
    });
    test('ほかの欄に入っている名前は出さない', () {
      expect(matchPlayerNames(names, '藤', exclude: {'佐藤'}), ['伊藤']);
    });
    test('過去の名前はすべて候補にする（上限なし）', () {
      final many = [for (var i = 0; i < 30; i++) game('m$i', ['P$i', 'Q$i', 'R$i', 'S$i'], DateTime(2026, 1, 1 + i))];
      expect(SessionLogic.recentPlayerNames(many, limit: null), hasLength(120));
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

    testWidgets('過去のプレイヤーは画面に並べず、名前の欄を押したときだけ一覧で出る', (tester) async {
      await pump(tester, [old, mid]);
      expect(nameOf(tester, 0), '', reason: '入力欄は空（ヒントで「プレイヤー1」）');
      expect(find.text('鈴木'), findsNothing, reason: '欄を押すまでは出さない');
      expect(find.byType(ActionChip), findsNothing);
      await tester.tap(find.byKey(const ValueKey('player-name-0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('player-name-options')), findsOneWidget);
      expect(find.text('過去のプレイヤー（6人）。文字を入れると絞り込めます'), findsOneWidget);
      // 新しく使った順（一覧は下へ動かして続きを見る）
      final scroll = find.descendant(
          of: find.byKey(const ValueKey('player-name-options')), matching: find.byType(Scrollable));
      for (final n in ['伊藤', '佐藤', '山本', '鈴木', '高橋', '田中']) {
        await tester.scrollUntilVisible(find.widgetWithText(ListTile, n), 40, scrollable: scroll);
        expect(find.widgetWithText(ListTile, n), findsOneWidget);
      }
      await tester.scrollUntilVisible(find.widgetWithText(ListTile, '鈴木'), -40, scrollable: scroll);
      await tester.tap(find.widgetWithText(ListTile, '鈴木'));
      await tester.pumpAndSettle();
      expect(nameOf(tester, 0), '鈴木');
      expect(find.byKey(const ValueKey('player-name-options')), findsNothing, reason: '選んだら一覧を閉じる');
    });

    testWidgets('文字を入れると部分一致で絞り込み、ほかの欄に入っている名前は出さない', (tester) async {
      await pump(tester, [old, mid, game('d', ['たなか', 'Tanaka', 'X', 'Y'], DateTime(2026, 4, 1))]);
      await tester.enterText(find.byKey(const ValueKey('player-name-0')), '藤');
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, '伊藤'), findsOneWidget);
      expect(find.widgetWithText(ListTile, '佐藤'), findsOneWidget);
      expect(find.widgetWithText(ListTile, '鈴木'), findsNothing);
      await tester.tap(find.widgetWithText(ListTile, '佐藤'));
      await tester.pumpAndSettle();
      expect(nameOf(tester, 0), '佐藤');

      // 2つ目の欄では、1つ目に入れた佐藤は出ない
      await tester.tap(find.byKey(const ValueKey('player-name-1')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, '佐藤'), findsNothing);
      expect(find.widgetWithText(ListTile, '伊藤'), findsOneWidget);
      // ▼ を押すと一覧を閉じる
      await tester.tap(find.byTooltip('過去のプレイヤーから選ぶ').at(1));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('player-name-options')), findsNothing);
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
