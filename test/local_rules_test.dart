import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_app/features/session/domain/models.dart';
import 'package:mahjong_app/features/session/domain/session_logic.dart';
import 'package:mahjong_app/features/session/session_providers.dart';
import 'package:mahjong_app/features/settings/rule_settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'player_stats_test.dart' show start, win;

/// ローカルルール（焼き鳥・トビ賞）
void main() {
  GameSession withRules(GameSession s, {int yakitori = 0, int tobiBonus = 0}) =>
      s.copyWith(settings: s.settings.copyWith(yakitori: yakitori, tobiBonus: tobiBonus));

  Map<int, FinalResult> results(GameSession s) => {for (final r in s.finalResults) r.player: r};

  group('焼き鳥', () {
    test('和了しなかった人が払い、和了した人で等分する', () {
      var s = withRules(start('x', ['A', 'B', 'C', 'D']), yakitori: 10);
      s = win(s, 1, loser: 2);
      s = win(s, 0); // A のツモ
      final before = withRules(s, yakitori: 0);
      s = SessionLogic.finishManually(s);
      final plain = results(SessionLogic.finishManually(before));
      expect(s.yakitoriPlayers, [2, 3]);
      final r = results(s);
      expect(r[2]!.adjustment, -10);
      expect(r[3]!.adjustment, -10);
      expect(r[0]!.adjustment, 10);
      expect(r[1]!.adjustment, 10);
      for (var p = 0; p < 4; p++) {
        expect(r[p]!.point, closeTo(plain[p]!.point + r[p]!.adjustment, 1e-9));
      }
      expect(s.finalResults.fold<double>(0, (a, e) => a + e.point), closeTo(0, 1e-9));
    });

    test('1人だけ和了なら3人分をもらう。誰も和了していなければ動かない', () {
      var s = withRules(start('x', ['A', 'B', 'C', 'D']), yakitori: 5);
      final none = SessionLogic.finishManually(s);
      expect(none.localRuleAdjustments, [0, 0, 0, 0]);
      s = SessionLogic.finishManually(win(s, 2, loser: 0));
      expect(s.localRuleAdjustments, [-5, -5, 15, -5]);
    });

    test('終局するまでは足さない', () {
      final s = win(withRules(start('x', ['A', 'B', 'C', 'D']), yakitori: 10), 1, loser: 2);
      expect(s.localRuleAdjustments, [0, 0, 0, 0]);
    });

    test('和了者の記録が無い古い局があれば数えない', () {
      var s = withRules(start('x', ['A', 'B', 'C', 'D']), yakitori: 10);
      s = win(s, 1, loser: 2);
      final old = RoundRecord.fromJson({...s.records.first.toJson()}..remove('winners'));
      s = SessionLogic.finishManually(s.copyWith(records: [old]));
      expect(s.yakitoriPlayers, isEmpty);
      expect(s.localRuleAdjustments, [0, 0, 0, 0]);
    });

    test('3人打ち', () {
      var s = withRules(start('x', ['A', 'B', 'C']), yakitori: 10);
      s = SessionLogic.finishManually(win(s, 0, loser: 1));
      expect(s.localRuleAdjustments, [20, -10, -10]);
    });
  });

  group('トビ賞', () {
    test('和了で飛ばした人がもらう', () {
      var s = withRules(start('x', ['A', 'B', 'C', 'D']), tobiBonus: 10)
          .copyWith(scores: [30000, 5000, 30000, 35000]);
      s = win(s, 0, loser: 1); // 親の 7700 で B が飛ぶ
      expect(s.finished, isTrue);
      expect(s.scores[1], lessThan(0));
      expect(s.localRuleAdjustments, [10, -10, 0, 0]);
      expect(results(s)[1]!.adjustment, -10);
    });

    test('ツモで2人飛んだら両方から', () {
      var s = withRules(start('x', ['A', 'B', 'C', 'D']), tobiBonus: 5)
          .copyWith(scores: [30000, 1000, 1000, 68000]);
      s = win(s, 3, han: 3, fu: 40); // D のツモ
      expect(s.finished, isTrue);
      expect(s.localRuleAdjustments, [0, -5, -5, 10]);
    });

    test('トビなしのルール・流局で飛んだときは動かない', () {
      var s = withRules(start('x', ['A', 'B', 'C', 'D']), tobiBonus: 10)
          .copyWith(scores: [30000, 500, 34500, 35000]);
      final drawn = SessionLogic.applyDraw(s, type: DrawType.exhaustive, tenpai: [true, false, true, true]);
      expect(drawn.finished, isTrue);
      expect(drawn.localRuleAdjustments, [0, 0, 0, 0]);
      final noTobi = s.copyWith(settings: s.settings.copyWith(tobi: false));
      final w = SessionLogic.finishManually(win(noTobi, 0, loser: 1));
      expect(w.localRuleAdjustments, [0, 0, 0, 0]);
    });
  });

  group('保存', () {
    test('設定を保存・読み込みでき、以前の形式（項目なし）はなしとして読む', () {
      const g = GameSettings(yakitori: 10, tobiBonus: 5);
      final back = GameSettings.fromJson(g.toJson());
      expect(back.yakitori, 10);
      expect(back.tobiBonus, 5);
      final old = GameSettings.fromJson(const GameSettings().toJson());
      expect(old.yakitori, 0);
      expect(old.tobiBonus, 0);
      expect(const GameSettings().toJson()['rules'], isNot(contains('yakitori')));
      expect(g.ruleSummary, containsAll(['焼き鳥 10P', 'トビ賞 5P']));
    });
  });

  testWidgets('ルール設定で選べる', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(420, 4000));
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: RuleSettingsScreen())));
    await tester.pumpAndSettle();
    final c = ProviderScope.containerOf(tester.element(find.byType(RuleSettingsScreen)));
    await tester.tap(find.byKey(const ValueKey('yakitori-10')));
    await tester.tap(find.byKey(const ValueKey('tobiBonus-20')));
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    final saved = c.read(defaultSettingsProvider);
    expect(saved.yakitori, 10);
    expect(saved.tobiBonus, 20);
  });
}
