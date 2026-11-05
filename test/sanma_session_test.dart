import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_app/features/backup/backup_codec.dart';
import 'package:mahjong_app/features/session/data/session_repository.dart';
import 'package:mahjong_app/features/session/domain/models.dart';
import 'package:mahjong_app/features/session/domain/session_logic.dart';
import 'package:mahjong_app/features/session/screens/new_session_screen.dart';
import 'package:mahjong_app/features/session/session_providers.dart';
import 'package:mahjong_app/features/settings/rule_settings_screen.dart';
import 'package:mahjong_app/features/win/win_input_screen.dart';
import 'package:mahjong_score_engine/mahjong_score_engine.dart';

GameSession sanma({GameSettings settings = const GameSettings.sanma()}) =>
    GameSession.start(id: 'x', playerNames: ['A', 'B', 'C'], settings: settings);

/// 筒子・索子の平和の手（23p の両面待ち）
const pinfu = ['2p', '3p', '4p', '5p', '6p', '7s', '8s', '9s', '2s', '3s', '4s', '5s', '5s'];

WinInput pinfuInput(GameSession s, int winner, {required bool tsumo, List<String> dora = const []}) =>
    WinInput(
      handTiles: pinfu,
      winningTile: '1p',
      melds: const [],
      winType: tsumo ? 'tsumo' : 'ron',
      isRiichi: true,
      isIppatsu: false,
      isDoubleRiichi: false,
      doraTiles: dora,
      uraDoraTiles: const [],
      roundWind: s.roundWindTile,
      playerWind: s.seatWindTileOf(winner),
    );

GameSession noTenDraw(GameSession s) =>
    SessionLogic.applyDraw(s, type: DrawType.exhaustive, tenpai: [false, false, false]);

void main() {
  group('3人打ちの進行', () {
    test('35,000点持ちで3人。親は 東1→東2→東3→南1 と回る', () {
      var s = sanma();
      expect(s.scores, [35000, 35000, 35000]);
      expect(s.riichi, [false, false, false]);
      expect([for (var p = 0; p < 3; p++) s.seatWindTileOf(p)], ['1z', '2z', '3z']);
      final names = <String>[];
      for (var i = 0; i < 4; i++) {
        names.add(s.roundName);
        s = noTenDraw(s);
      }
      expect(names, ['東1局', '東2局', '東3局', '南1局']);
      expect(s.dealer, 1);
    });

    test('半荘戦は南3局、東風戦は東3局で終わる', () {
      var s = sanma();
      for (var i = 0; i < 6; i++) {
        expect(s.finished, isFalse);
        s = noTenDraw(s);
      }
      expect(s.finished, isTrue);

      var t = sanma(settings: const GameSettings.sanma(tonpuu: true));
      for (var i = 0; i < 3; i++) {
        t = noTenDraw(t);
      }
      expect(t.finished, isTrue);
    });

    test('ノーテン罰符は場に3,000点', () {
      final one = SessionLogic.drawDeltas(sanma(), type: DrawType.exhaustive, tenpai: [true, false, false]);
      expect(one, [3000, -1500, -1500]);
      final two = SessionLogic.drawDeltas(sanma(), type: DrawType.exhaustive, tenpai: [true, true, false]);
      expect(two, [1500, 1500, -3000]);
    });

    test('子の満貫ツモ: ツモ損は 親4000・子2000、折半は 親5000・子3000', () {
      final s = sanma();
      // 立直 ツモ 平和 ドラ2（表示牌 1p→2p、6s→7s） = 5翻 満貫
      final w = SessionLogic.scoreWins(
          s, [WinEntry(winner: 1, input: pinfuInput(s, 1, tsumo: true, dora: ['1p', '6s']))]);
      expect(SessionLogic.winsDeltas(s, w), [-4000, 6000, -2000]);

      final split = sanma(settings: const GameSettings.sanma(sanmaTsumoSplit: true));
      final w2 = SessionLogic.scoreWins(split,
          [WinEntry(winner: 1, input: pinfuInput(split, 1, tsumo: true, dora: ['1p', '6s']))]);
      expect(SessionLogic.winsDeltas(split, w2), [-5000, 8000, -3000]);
    });

    test('流し満貫（子・ツモ損）は 親4000・子2000', () {
      final d = SessionLogic.drawDeltas(sanma(),
          type: DrawType.nagashiMangan, tenpai: [false, false, false], nagashiPlayer: 2);
      expect(d, [-4000, -2000, 6000]);
    });

    test('ダブロンの本場は、放銃者から見て打つ順番が近い方（3人で回る）', () {
      expect(SessionLogic.honbaTaker([0, 1], loser: 2, playerCount: 3), 0); // C の次は A
      expect(SessionLogic.honbaTaker([0, 2], loser: 1, playerCount: 3), 2);
    });

    test('最終結果: オカは (40,000-35,000)×3 = +15、ウマ ±15、合計は0', () {
      final s = SessionLogic.finishManually(sanma().copyWith(scores: [45000, 35000, 25000]));
      final r = s.finalResults;
      expect(r.map((x) => x.player), [0, 1, 2]);
      expect(r[0].point, closeTo(5 + 15 + 15, 0.001));
      expect(r[1].point, closeTo(-5 + 0, 0.001));
      expect(r[2].point, closeTo(-15 - 15, 0.001));
      expect(r.fold<double>(0, (a, x) => a + x.point), closeTo(0, 0.001));
    });

    test('3人打ちの流局の種類は 通常流局・流し満貫・九種九牌・四開槓', () {
      expect(DrawType.availableFor(const GameSettings.sanma()),
          [DrawType.exhaustive, DrawType.nagashiMangan, DrawType.kyuushu, DrawType.suukan]);
      expect(DrawType.availableFor(const GameSettings()), DrawType.values);
    });

    test('局の修正も3人分', () {
      final s = SessionLogic.applyDraw(sanma(), type: DrawType.exhaustive, tenpai: [true, false, false]);
      expect(SessionLogic.validateRoundEdit(s, 0, [1500, 1500, -3000]), isNull);
      expect(SessionLogic.validateRoundEdit(s, 0, [1500, 1500, -1000]), contains('3人の合計'));
      final e = SessionLogic.editRound(s, 0, deltas: [1500, 1500, -3000]);
      expect(e.scores, [36500, 36500, 32000]);
    });
  });

  group('保存', () {
    test('3人打ちの対局を保存して読み込める。以前のデータは4人打ち', () {
      final s = noTenDraw(sanma());
      final r = GameSession.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
      expect(r.playerCount, 3);
      expect(r.settings.isSanma, isTrue);
      expect(r.settings.nukiDora, isTrue);
      expect(r.roundName, '東2局');
      final old = const GameSettings().toJson()..remove('playerCount');
      expect(GameSettings.fromJson(old).playerCount, 4);
    });

    test('ルール設定は4人打ちと3人打ちで別々に保存され、バックアップにも入る', () async {
      final repo = InMemorySessionRepository();
      final c = ProviderContainer(overrides: [sessionRepositoryProvider.overrideWithValue(repo)]);
      addTearDown(c.dispose);
      expect(c.read(defaultSanmaSettingsProvider).startingPoints, 35000);
      await c.read(defaultSanmaSettingsProvider.notifier)
          .save(const GameSettings.sanma(sanmaTsumoSplit: true));
      expect(repo.defaultSanmaSettings!.sanmaTsumoSplit, isTrue);
      expect(c.read(defaultSettingsProvider).playerCount, 4); // 4人打ちは変わらない

      final data = BackupCodec.decode(BackupCodec.encode([],
          defaultSettings: const GameSettings(), defaultSanmaSettings: c.read(defaultSanmaSettingsProvider)));
      expect(data.defaultSanmaSettings!.sanmaTsumoSplit, isTrue);
      expect(data.defaultSettings!.playerCount, 4);
    });
  });

  group('画面', () {
    testWidgets('新規対局で3人打ちを選ぶと、3人分の入力欄と3人打ちの初期値になる', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 2400));
      await tester.pumpWidget(ProviderScope(
        overrides: [sessionRepositoryProvider.overrideWithValue(InMemorySessionRepository())],
        child: const MaterialApp(home: NewSessionScreen()),
      ));
      final c = ProviderScope.containerOf(tester.element(find.byType(NewSessionScreen)));
      await tester.tap(find.text('3人打ち'));
      await tester.pump();
      expect(find.text('北家'), findsNothing);
      expect(find.widgetWithText(TextField, '西家'), findsOneWidget);
      expect(tester.widget<TextField>(find.widgetWithText(TextField, '持ち点')).controller!.text, '35000');
      expect(find.byKey(const ValueKey('uma-3')), findsNothing); // ウマは3位まで
      expect(find.textContaining('ツモ損'), findsWidgets);

      await tester.ensureVisible(find.text('対局開始'));
      await tester.tap(find.text('対局開始'));
      await tester.pumpAndSettle();
      final s = c.read(sessionsProvider).single;
      expect(s.playerCount, 3);
      expect(s.scores, [35000, 35000, 35000]);
      expect(s.settings.uma, [15, 0, -15]);
      expect(find.text('35,000'), findsNWidgets(3));
    });

    testWidgets('3人打ちの和了入力: 二萬〜八萬は出ず、抜きドラを入力できる', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 2400));
      await tester.pumpWidget(ProviderScope(
        overrides: [sessionRepositoryProvider.overrideWithValue(InMemorySessionRepository([sanma()]))],
        child: const MaterialApp(home: WinInputScreen(sessionId: 'x')),
      ));
      expect(find.byKey(const ValueKey('palette-2m')), findsNothing);
      expect(find.byKey(const ValueKey('palette-5mr')), findsNothing);
      expect(find.byKey(const ValueKey('palette-9m')), findsOneWidget);
      expect(find.text('北 家'), findsNothing);

      await tester.tap(find.text('南 B'));
      await tester.tap(find.text('ツモ'));
      await tester.pump();
      for (final t in pinfu) {
        await tester.tap(find.byKey(ValueKey('palette-$t')));
        await tester.pump();
      }
      await tester.tap(find.byKey(const ValueKey('palette-1p')));
      await tester.pump();
      await tester.tap(find.byTooltip('増やす'));
      await tester.tap(find.byTooltip('増やす'));
      await tester.pump();
      expect(find.text('北 × 2'), findsOneWidget);

      await tester.tap(find.text('計算'));
      await tester.pumpAndSettle();
      expect(find.text('抜きドラ'), findsOneWidget);
      expect(find.text('2翻'), findsWidgets);
    });

    testWidgets('ルール設定で3人打ちのルールを編集・保存できる（4人打ちとは別）', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 3200));
      final repo = InMemorySessionRepository();
      await tester.pumpWidget(ProviderScope(
        overrides: [sessionRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: RuleSettingsScreen()),
      ));
      expect(find.text('北抜き（抜きドラ）'), findsNothing);
      await tester.tap(find.text('3人打ちのルール'));
      await tester.pump();
      expect(find.text('北抜き（抜きドラ）'), findsOneWidget);
      await tester.tap(find.text('折半'));
      await tester.tap(find.text('北抜き（抜きドラ）'));
      await tester.pump();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(repo.defaultSanmaSettings!.sanmaTsumoSplit, isTrue);
      expect(repo.defaultSanmaSettings!.nukiDora, isFalse);
      expect(repo.defaultSettings, isNull); // 4人打ちのルールは触っていない
    });
  });
}
