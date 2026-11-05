import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_app/features/backup/csv_export.dart';
import 'package:mahjong_app/features/session/data/session_repository.dart';
import 'package:mahjong_app/features/session/domain/models.dart';
import 'package:mahjong_app/features/session/domain/session_logic.dart';
import 'package:mahjong_app/features/session/session_providers.dart';
import 'package:mahjong_app/features/settings/rule_settings_screen.dart';
import 'package:mahjong_app/features/stats/player_stats.dart';
import 'package:mahjong_app/features/win/win_result_screen.dart';
import 'package:mahjong_score_engine/mahjong_score_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

GameSession chipsGame({bool chips = true}) => GameSession.start(
    id: 'x', playerNames: ['A', 'B', 'C', 'D'], settings: GameSettings(chips: chips), now: DateTime(2026, 6, 1));

/// 立直・一発・裏ドラ1・赤5（5p 赤）のロン（B が和了）
WinInput akaUraRon(GameSession s, int winner) => WinInput(
      handTiles: const ['2m', '3m', '4m', '5m', '6m', '7m', '7p', '8p', '9p', '3s', '4s', '5pr', '5p'],
      winningTile: '2s',
      melds: const [],
      winType: 'ron',
      isRiichi: true,
      isIppatsu: true,
      isDoubleRiichi: false,
      doraTiles: const [],
      uraDoraTiles: const ['1m'], // 裏ドラは 2m
      roundWind: s.roundWindTile,
      playerWind: s.seatWindTileOf(winner),
    );

/// 祝儀（チップ）
void main() {
  group('枚数の動き', () {
    test('ロンは放銃者が、ツモはほかの全員が払う', () {
      final s = chipsGame();
      expect(SessionLogic.chipDeltas(s, {1: 3}, loser: 2), [0, 3, -3, 0]);
      expect(SessionLogic.chipDeltas(s, {1: 2}), [-2, 6, -2, -2]);
      expect(SessionLogic.chipDeltas(s, {1: 1, 3: 2}, loser: 2), [0, 1, -3, 2], reason: 'ダブロン');
      expect(SessionLogic.chipDeltas(s, {1: 0}), [0, 0, 0, 0]);
    });

    test('目安は赤ドラ・裏ドラ・一発の数。翻・符で入力したときは 0', () {
      final s = chipsGame();
      final hand = SessionLogic.scoreWins(s, [WinEntry(winner: 1, input: akaUraRon(s, 1))], loser: 2).single;
      expect(hand.result.isValid, isTrue);
      expect(SessionLogic.suggestedChips(s, hand), 3);
      final quick = SessionLogic.scoreWins(s, [
        WinEntry.hanFu(session: s, winner: 1, isTsumo: false, hanFu: const HanFuEntry(han: 3, fu: 40))
      ], loser: 2).single;
      expect(SessionLogic.suggestedChips(s, quick), 0);
    });

    test('局の記録に残り、対局ごとの合計が出る。祝儀なしのルールでは記録しない', () {
      var s = chipsGame();
      var wins = SessionLogic.scoreWins(s, [WinEntry(winner: 1, input: akaUraRon(s, 1))], loser: 2);
      s = SessionLogic.applyWins(s, wins: wins, loser: 2, description: '', chips: {1: 3});
      expect(s.records.last.chips, [0, 3, -3, 0]);
      wins = SessionLogic.scoreWins(
          s, [WinEntry.hanFu(session: s, winner: 0, isTsumo: true, hanFu: const HanFuEntry(han: 3, fu: 40))]);
      s = SessionLogic.applyWins(s, wins: wins, description: '', chips: {0: 0});
      expect(s.records.last.chips, isNull, reason: '祝儀の動きが無い局は記録しない');
      expect(s.chipTotals, [0, 3, -3, 0]);

      final off = chipsGame(chips: false);
      final w = SessionLogic.scoreWins(off, [WinEntry(winner: 1, input: akaUraRon(off, 1))], loser: 2);
      expect(SessionLogic.applyWins(off, wins: w, loser: 2, description: '', chips: {1: 3}).records.last.chips,
          isNull);
    });
  });

  test('保存して戻しても同じ。version 4 以前のデータは祝儀なし', () async {
    var s = chipsGame();
    final wins = SessionLogic.scoreWins(s, [WinEntry(winner: 1, input: akaUraRon(s, 1))], loser: 2);
    s = SessionLogic.applyWins(s, wins: wins, loser: 2, description: '', chips: {1: 3});
    final back = GameSession.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
    expect(back.settings.chips, isTrue);
    expect(back.chipTotals, [0, 3, -3, 0]);
    expect(back.settings.ruleSummary, contains('祝儀あり'));

    // version 4 のデータ（祝儀の項目が無い）
    final old = chipsGame(chips: false);
    expect(old.settings.toJson()['rules'], isNot(contains('chips')));
    SharedPreferences.setMockInitialValues({
      SharedPrefsSessionRepository.indexKey: jsonEncode({'version': 4, 'ids': ['x']}),
      SharedPrefsSessionRepository.sessionKey('x'): jsonEncode({'version': 4, 'session': old.toJson()}),
    });
    final loaded = SharedPrefsSessionRepository(await SharedPreferences.getInstance()).loadAll().single;
    expect(loaded.settings.chips, isFalse);
    expect(loaded.chipTotals, [0, 0, 0, 0]);
    expect(loaded.settings.ruleSummary, isNot(contains('祝儀あり')));
    expect(SharedPrefsSessionRepository.formatVersion, 5);
  });

  test('個人成績と CSV に祝儀の合計が出る', () {
    var s = chipsGame();
    final wins = SessionLogic.scoreWins(s, [WinEntry(winner: 1, input: akaUraRon(s, 1))], loser: 2);
    s = SessionLogic.finishManually(SessionLogic.applyWins(s, wins: wins, loser: 2, description: '', chips: {1: 3}));
    final summary = PlayerStatsCalculator.compute([s], playerCount: 4);
    expect(summary.hasChips, isTrue);
    expect({for (final p in summary.players) p.name: p.chips}, {'A': 0, 'B': 3, 'C': -3, 'D': 0});
    final row = CsvExport.games([s]).split('\r\n')[1].split(',');
    expect(row.sublist(row.length - 4), ['0', '3', '-3', '0']);
    expect(PlayerStatsCalculator.compute([chipsGame(chips: false)], playerCount: 4).hasChips, isFalse);
  });

  group('画面', () {
    testWidgets('計算結果で祝儀の枚数を変えて確定すると、記録に残る', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 2600));
      final s = chipsGame();
      await tester.pumpWidget(ProviderScope(
        overrides: [sessionRepositoryProvider.overrideWithValue(InMemorySessionRepository([s]))],
        child: MaterialApp(
          home: WinResultScreen(
              sessionId: 'x', entries: [WinEntry(winner: 1, input: akaUraRon(s, 1))], loser: 2),
        ),
      ));
      final c = ProviderScope.containerOf(tester.element(find.byType(WinResultScreen)));
      expect(find.text('祝儀（B）'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('chips-1'))).data, '3枚', reason: '目安の枚数');
      await tester.tap(find.byTooltip('祝儀を増やす'));
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(const ValueKey('chips-1'))).data, '4枚');
      await tester.ensureVisible(find.text('この結果で確定'));
      await tester.tap(find.text('この結果で確定'));
      await tester.pumpAndSettle();
      final after = c.read(sessionProvider('x'))!;
      expect(after.records.single.chips, [0, 4, -4, 0]);
      expect(after.records.single.description, contains('祝儀4枚'));
    });

    testWidgets('祝儀なしのルールでは欄を出さない', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 2600));
      final s = chipsGame(chips: false);
      await tester.pumpWidget(ProviderScope(
        overrides: [sessionRepositoryProvider.overrideWithValue(InMemorySessionRepository([s]))],
        child: MaterialApp(
          home: WinResultScreen(
              sessionId: 'x', entries: [WinEntry(winner: 1, input: akaUraRon(s, 1))], loser: 2),
        ),
      ));
      expect(find.textContaining('祝儀'), findsNothing);
    });

    testWidgets('ルール設定で祝儀を記録するように変えられる', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 4000));
      await tester.pumpWidget(ProviderScope(
        overrides: [sessionRepositoryProvider.overrideWithValue(InMemorySessionRepository())],
        child: const MaterialApp(home: RuleSettingsScreen()),
      ));
      final c = ProviderScope.containerOf(tester.element(find.byType(RuleSettingsScreen)));
      await tester.ensureVisible(find.text('祝儀（チップ）を記録する'));
      await tester.tap(find.text('祝儀（チップ）を記録する'));
      await tester.pump();
      await tester.ensureVisible(find.text('保存'));
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(c.read(defaultSettingsProvider).chips, isTrue);
    });
  });
}
