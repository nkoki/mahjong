import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_app/features/session/data/session_repository.dart';
import 'package:mahjong_app/features/session/domain/models.dart';
import 'package:mahjong_app/features/session/domain/session_logic.dart';
import 'package:mahjong_app/features/session/screens/new_session_screen.dart';
import 'package:mahjong_app/features/session/session_providers.dart';
import 'package:mahjong_app/features/settings/rule_settings_screen.dart';

import 'player_stats_test.dart' show win;

GameSession startWith(GameLength length, {int players = 4, bool westRound = false}) => GameSession.start(
      id: 'x',
      playerNames: ['A', 'B', 'C', 'D'].take(players).toList(),
      settings: players == 3
          ? GameSettings(playerCount: 3, uma: const [15, 0, -15], length: length, westRound: westRound)
          : GameSettings(length: length, westRound: westRound),
      now: DateTime(2026, 6, 1),
    );

GameSession draw(GameSession s, List<bool> tenpai, {DrawType type = DrawType.exhaustive}) =>
    SessionLogic.applyDraw(s, type: type, tenpai: tenpai);

/// 対局の長さ（一局精算・東風戦・半荘戦・一荘戦）
void main() {
  test('局数: 一局精算は1局、東風は人数分、半荘は2周、一荘は4周（東南西北）', () {
    expect(const GameSettings(length: GameLength.single).totalRounds, 1);
    expect(const GameSettings(length: GameLength.tonpuu).totalRounds, 4);
    expect(const GameSettings().totalRounds, 8);
    expect(const GameSettings(length: GameLength.iichan).totalRounds, 16);
    expect(const GameSettings(playerCount: 3, length: GameLength.iichan).totalRounds, 12);
    expect(const GameSettings(playerCount: 3, length: GameLength.single).totalRounds, 1);
    // 東風戦の指定（tonpuu）は今まで通り使える
    expect(const GameSettings(tonpuu: true).length, GameLength.tonpuu);
    expect(const GameSettings(length: GameLength.tonpuu).tonpuu, isTrue);
    expect(const GameSettings(length: GameLength.iichan).tonpuu, isFalse);
  });

  group('一局精算', () {
    test('親が和了しても連荘せずに終局し、順位・ウマで精算する', () {
      final s = win(startWith(GameLength.single), 0, loser: 1, han: 3, fu: 40);
      expect(s.finished, isTrue);
      expect(s.records, hasLength(1));
      expect(s.finalResults.first.player, 0);
      expect(s.finalResults.map((r) => r.point).fold<double>(0, (a, v) => a + v), closeTo(0, 0.01));
    });

    test('子の和了・通常流局（親テンパイでも）で終局する', () {
      expect(win(startWith(GameLength.single), 2).finished, isTrue);
      final d = draw(startWith(GameLength.single), [true, false, false, false]);
      expect(d.finished, isTrue);
      expect(d.records.single.kind, 'draw');
    });

    test('供託は終局時にトップが受け取る', () {
      var s = SessionLogic.toggleRiichi(startWith(GameLength.single), 1);
      s = draw(s, [false, true, false, false]);
      expect(s.finished, isTrue);
      expect(s.riichiSticks, 0);
      expect(s.scores.fold<int>(0, (a, v) => a + v), 100000);
    });

    test('途中流局・チョンボは局のやり直しなので終局しない', () {
      final a = draw(startWith(GameLength.single), [false, false, false, false], type: DrawType.kyuushu);
      expect(a.finished, isFalse);
      expect(a.honba, 1);
      final c = SessionLogic.applyChombo(startWith(GameLength.single), 1);
      expect(c.finished, isFalse);
      // やり直した局を終えると終局
      expect(win(a, 1).finished, isTrue);
    });

    test('3人打ちでも1局で終局する', () {
      expect(win(startWith(GameLength.single, players: 3), 0, loser: 1).finished, isTrue);
    });

    test('西入（延長）の設定があっても使わない', () {
      final s = startWith(GameLength.single, westRound: true);
      expect(s.settings.extensionEnabled, isFalse);
      expect(draw(s, [false, false, false, false]).finished, isTrue);
    });
  });

  group('一荘戦', () {
    test('南4局のあと西1局・北1局へ進み、北4局で終局する', () {
      var s = startWith(GameLength.iichan);
      final names = <String>[];
      while (!s.finished) {
        names.add(s.roundName);
        s = draw(s, [false, false, false, false]);
      }
      expect(names, hasLength(16));
      expect(names[4], '南1局');
      expect(names[8], '西1局');
      expect(names[12], '北1局');
      expect(names.last, '北4局');
    });

    test('3人打ちは12局（北3局まで）', () {
      var s = startWith(GameLength.iichan, players: 3);
      var n = 0;
      String last = '';
      while (!s.finished) {
        last = s.roundName;
        s = draw(s, [false, false, false]);
        n++;
      }
      expect(n, 12);
      expect(last, '北3局');
    });

    test('西入（延長）の設定があっても北4局で終わる', () {
      final s = startWith(GameLength.iichan, westRound: true)
          .copyWith(roundIndex: 15, scores: [26000, 25000, 25000, 24000], roundStartScores: [26000, 25000, 25000, 24000]);
      expect(s.settings.extensionEnabled, isFalse);
      expect(s.isAllLast, isTrue);
      expect(draw(s, [false, false, false, false]).finished, isTrue);
    });
  });

  group('保存', () {
    test('一局精算・一荘戦を保存して読み込める', () {
      for (final l in GameLength.values) {
        final j = GameSettings(length: l).toJson();
        expect(GameSettings.fromJson(j).length, l);
        final sj = GameSettings(playerCount: 3, uma: const [15, 0, -15], length: l).toJson();
        expect(GameSettings.fromJson(sj).length, l);
      }
    });

    test('version 8 以前のデータ（length なし）は東風戦・半荘戦として読める', () {
      final old = const GameSettings().toJson()..remove('length');
      expect(GameSettings.fromJson({...old, 'tonpuu': true}).length, GameLength.tonpuu);
      expect(GameSettings.fromJson({...old, 'tonpuu': false}).length, GameLength.hanchan);
      expect(SharedPrefsSessionRepository.formatVersion, greaterThanOrEqualTo(9));
    });

    test('copyWith の tonpuu 指定でも長さが変わる', () {
      const s = GameSettings(length: GameLength.iichan);
      expect(s.copyWith(tonpuu: true).length, GameLength.tonpuu);
      expect(s.copyWith(kuitan: false).length, GameLength.iichan);
      expect(s.copyWith(length: GameLength.single).length, GameLength.single);
    });
  });

  group('画面', () {
    testWidgets('新規対局の画面で一局精算を選んで始められる', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 3000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final c = ProviderContainer(overrides: [
        sessionRepositoryProvider.overrideWithValue(InMemorySessionRepository()),
      ]);
      addTearDown(c.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: NewSessionScreen()),
      ));
      await tester.pump();
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('game-length')), matching: find.text('一局')));
      await tester.pump();
      expect(find.textContaining('1局で終局'), findsWidgets);
      await tester.tap(find.text('対局開始'));
      await tester.pumpAndSettle();
      expect(c.read(sessionsProvider).single.settings.length, GameLength.single);
    });

    testWidgets('ルール設定で一荘戦を選ぶと、西入の設定は選べなくなる', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 3000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final c = ProviderContainer(overrides: [
        sessionRepositoryProvider.overrideWithValue(InMemorySessionRepository()),
      ]);
      addTearDown(c.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: RuleSettingsScreen()),
      ));
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('game-length')), matching: find.text('一荘')));
      await tester.pump();
      final west = tester.widgetList<SwitchListTile>(find.byType(SwitchListTile))
          .where((w) => (w.title as Text?)?.data?.contains('西入') ?? false);
      expect(west, isNotEmpty);
      expect(west.first.onChanged, isNull);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(c.read(defaultSettingsProvider).length, GameLength.iichan);
    });
  });
}
