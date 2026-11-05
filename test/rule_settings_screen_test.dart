import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_app/features/draw/draw_input_screen.dart';
import 'package:mahjong_app/features/session/data/session_repository.dart';
import 'package:mahjong_app/features/session/domain/models.dart';
import 'package:mahjong_app/features/session/domain/session_logic.dart';
import 'package:mahjong_app/features/session/screens/new_session_screen.dart';
import 'package:mahjong_app/features/session/session_providers.dart';
import 'package:mahjong_app/features/settings/rule_settings_screen.dart';
import 'package:mahjong_score_engine/mahjong_score_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

WinInput ron(GameSession s, int winner, List<String> hand, String win, {List<Meld> melds = const []}) =>
    WinInput(
      handTiles: hand,
      winningTile: win,
      melds: melds,
      winType: 'ron',
      isRiichi: false,
      isIppatsu: false,
      isDoubleRiichi: false,
      doraTiles: const [],
      uraDoraTiles: const [],
      roundWind: s.roundWindTile,
      playerWind: s.seatWindTileOf(winner),
    );

const pinfu = ['2m', '3m', '4m', '5m', '6m', '7p', '8p', '9p', '2s', '3s', '4s', '5s', '5s'];

void main() {
  group('ルールの保存', () {
    test('JSON に変換して戻しても同じ。ルールのない古いデータは初期値として読む', () {
      const s = GameSettings(kuitan: false, kiriageMangan: true, renpuuPairFu: 2, doubleRon: false, redDora: false);
      final r = GameSettings.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
      expect(r.kuitan, isFalse);
      expect(r.kiriageMangan, isTrue);
      expect(r.renpuuPairFu, 2);
      expect(r.doubleRon, isFalse);
      expect(r.redDora, isFalse);

      final old = const GameSettings().toJson()..remove('rules');
      final o = GameSettings.fromJson(old);
      expect(o.kuitan, isTrue);
      expect(o.doubleRon, isTrue);
      expect(o.agariYame, isTrue);
    });

    test('ルール設定は端末に保存され、次に起動したときも使われる', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c1 = ProviderContainer(overrides: [
        sessionRepositoryProvider.overrideWithValue(SharedPrefsSessionRepository(prefs)),
      ]);
      await c1.read(defaultSettingsProvider.notifier).save(const GameSettings(kuitan: false, tonpuu: true));
      c1.dispose();
      final c2 = ProviderContainer(overrides: [
        sessionRepositoryProvider.overrideWithValue(SharedPrefsSessionRepository(prefs)),
      ]);
      addTearDown(c2.dispose);
      expect(c2.read(defaultSettingsProvider).kuitan, isFalse);
      expect(c2.read(defaultSettingsProvider).tonpuu, isTrue);
    });
  });

  group('ルールの反映', () {
    test('喰いタンなしの対局では、鳴いた断么九は和了できない', () {
      final s = GameSession.start(
          id: 'x', playerNames: ['A', 'B', 'C', 'D'], settings: const GameSettings(kuitan: false));
      const meld = Meld(type: MeldType.chi, tiles: ['2s', '3s', '4s']);
      final wins = SessionLogic.scoreWins(s, [
        WinEntry(winner: 1, input: ron(s, 1, ['2m', '3m', '4m', '5m', '6m', '7m', '4p', '5p', '6p', '6s'], '6s', melds: [meld])),
      ], loser: 2);
      expect(wins.single.result.isValid, isFalse);
    });

    test('ダブロンなしの対局では2人の和了を受け付けない', () {
      expect(SessionLogic.validateWins([1, 3], loser: 2, doubleRon: false), contains('頭ハネ'));
      expect(SessionLogic.validateWins([1], loser: 2, doubleRon: false), isNull);
    });

    test('和了止めなしなら、オーラスで親がトップでも続く', () {
      GameSession allLast(bool agariYame) => GameSession.start(
              id: 'x',
              playerNames: ['A', 'B', 'C', 'D'],
              settings: GameSettings(tonpuu: true, agariYame: agariYame))
          .copyWith(roundIndex: 3, scores: [25000, 25000, 25000, 35000]); // 東4局 親は D
      for (final yame in [true, false]) {
        final s = allLast(yame);
        final wins = SessionLogic.scoreWins(s, [WinEntry(winner: 3, input: ron(s, 3, pinfu, '1m'))], loser: 0);
        final next = SessionLogic.applyWins(s, wins: wins, loser: 0, description: '');
        expect(next.finished, yame);
        if (!yame) expect(next.honba, 1); // 連荘
      }
    });
  });

  group('画面', () {
    Future<ProviderContainer> pump(WidgetTester tester, Widget home,
        {InMemorySessionRepository? repo}) async {
      await tester.binding.setSurfaceSize(const Size(420, 3000));
      await tester.pumpWidget(ProviderScope(
        overrides: [sessionRepositoryProvider.overrideWithValue(repo ?? InMemorySessionRepository())],
        child: MaterialApp(home: home),
      ));
      return ProviderScope.containerOf(tester.element(find.byType(home.runtimeType)));
    }

    testWidgets('ルール設定で変えて保存すると、新しい対局に使われる', (tester) async {
      // 2つの画面で同じ状態を使うため、状態の入れ物（ProviderContainer）をテスト側で持つ
      final c = ProviderContainer(overrides: [
        sessionRepositoryProvider.overrideWithValue(InMemorySessionRepository()),
      ]);
      addTearDown(c.dispose);
      await tester.binding.setSurfaceSize(const Size(420, 3000));
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: RuleSettingsScreen()),
      ));
      await tester.tap(find.text('喰いタン'));
      await tester.tap(find.text('切り上げ満貫'));
      await tester.tap(find.text('東風戦'));
      await tester.enterText(find.widgetWithText(TextField, '持ち点'), '27000');
      await tester.pump();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      final d = c.read(defaultSettingsProvider);
      expect(d.kuitan, isFalse);
      expect(d.kiriageMangan, isTrue);
      expect(d.tonpuu, isTrue);
      expect(d.startingPoints, 27000);

      // 新規対局の画面に初期値として入り、詳細ルールも引き継がれる
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        // key を変えて、画面遷移の履歴ごと新しく作り直す
        child: const MaterialApp(key: ValueKey('new-session'), home: NewSessionScreen()),
      ));
      await tester.pump();
      expect(find.textContaining('喰いタンなし'), findsOneWidget);
      expect(tester.widget<TextField>(find.widgetWithText(TextField, '持ち点')).controller!.text, '27000');
      await tester.tap(find.text('対局開始'));
      await tester.pumpAndSettle();
      final s = c.read(sessionsProvider).single;
      expect(s.settings.kuitan, isFalse);
      expect(s.settings.kiriageMangan, isTrue);
      expect(s.settings.tonpuu, isTrue);
      expect(s.scores.first, 27000);
    });

    testWidgets('初期値に戻すと、今の動きのルールに戻る', (tester) async {
      final repo = InMemorySessionRepository()..defaultSettings = const GameSettings(kuitan: false, startingPoints: 30000);
      final c = await pump(tester, const RuleSettingsScreen(), repo: repo);
      await tester.tap(find.text('初期値に戻す'));
      await tester.pump();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(c.read(defaultSettingsProvider).kuitan, isTrue);
      expect(c.read(defaultSettingsProvider).startingPoints, 25000);
    });

    testWidgets('流し満貫・途中流局なしの対局では、流局の種類に出ない', (tester) async {
      final s = GameSession.start(
          id: 'x',
          playerNames: ['A', 'B', 'C', 'D'],
          settings: const GameSettings(nagashiMangan: false, abortiveDraws: false));
      await pump(tester, const DrawInputScreen(sessionId: 'x'), repo: InMemorySessionRepository([s]));
      expect(find.text(DrawType.exhaustive.label), findsOneWidget);
      expect(find.text(DrawType.nagashiMangan.label), findsNothing);
      expect(find.text(DrawType.kyuushu.label), findsNothing);
      expect(find.text(DrawType.sanchaho.label), findsNothing);
    });
  });
}
