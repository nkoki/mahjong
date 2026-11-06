import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_app/features/score_table/score_table_screen.dart';
import 'package:mahjong_score_engine/mahjong_score_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 点数早見表
void main() {
  const rules = ScoreRules();

  group('マスの点数', () {
    test('子の 30符・40符', () {
      final c = ScoreTable.cell(han: 2, fu: 30, isDealer: false, rules: rules);
      expect(c.ron, '2000');
      expect(c.tsumo, '500-1000');
      expect(c.limitName, isNull);
      expect(ScoreTable.cell(han: 3, fu: 40, isDealer: false, rules: rules).ron, '5200');
    });

    test('親', () {
      final c = ScoreTable.cell(han: 3, fu: 30, isDealer: true, rules: rules);
      expect(c.ron, '5800');
      expect(c.tsumo, '2000オール');
    });

    test('20符はツモだけ、25符・20符は1翻では無い', () {
      final pinfu = ScoreTable.cell(han: 2, fu: 20, isDealer: false, rules: rules);
      expect(pinfu.ron, isNull);
      expect(pinfu.tsumo, '400-700');
      final one = ScoreTable.cell(han: 1, fu: 25, isDealer: false, rules: rules);
      expect(one.ron, isNull);
      expect(one.tsumo, isNull);
    });

    test('満貫になるマスは名前が付く。切り上げ満貫の設定に従う', () {
      expect(ScoreTable.cell(han: 3, fu: 70, isDealer: false, rules: rules).limitName, '満貫');
      final c = ScoreTable.cell(han: 4, fu: 30, isDealer: false, rules: rules);
      expect(c.ron, '7700');
      expect(c.limitName, isNull);
      final kiriage = ScoreTable.cell(han: 4, fu: 30, isDealer: false, rules: const ScoreRules(kiriageMangan: true));
      expect(kiriage.ron, '8000');
      expect(kiriage.limitName, '満貫');
    });

    test('満貫以上の行', () {
      final rows = {
        for (final (name, _, h) in ScoreTable.limits)
          name: ScoreTable.cell(han: h.han, fu: 30, yakuman: h.yakuman, isDealer: false, rules: rules)
      };
      expect(rows['満貫']!.ron, '8000');
      expect(rows['跳満']!.tsumo, '3000-6000');
      expect(rows['倍満']!.ron, '16000');
      expect(rows['三倍満']!.ron, '24000');
      expect(rows['役満']!.tsumo, '8000-16000');
    });

    test('ツモで受け取る合計: 3人打ちのツモ損は北家の分だけ少なく、折半は4人打ちと同じ', () {
      int? total(ScoreRules r, {bool dealer = false}) =>
          ScoreTable.cell(han: 5, fu: 30, isDealer: dealer, rules: r).tsumoTotal;
      expect(total(rules), 8000);
      expect(total(const ScoreRules(playerCount: 3)), 6000);
      expect(total(const ScoreRules(playerCount: 3, sanmaTsumoSplit: true)), 8000);
      expect(total(rules, dealer: true), 12000);
      expect(total(const ScoreRules(playerCount: 3), dealer: true), 8000);
      // 1人が払う額: ツモ損は4人打ちと同じ、折半は増える
      expect(ScoreTable.cell(han: 5, fu: 30, isDealer: false, rules: const ScoreRules(playerCount: 3)).tsumo, '2000-4000');
      expect(ScoreTable.cell(han: 5, fu: 30, isDealer: false, rules: const ScoreRules(playerCount: 3, sanmaTsumoSplit: true)).tsumo,
          '3000-5000');
      // ロンは同じ
      expect(ScoreTable.cell(han: 3, fu: 30, isDealer: false, rules: const ScoreRules(playerCount: 3)).ron, '3900');
    });

    test('3人打ち（ツモ損）は子・親の2人が払う', () {
      final c = ScoreTable.cell(han: 1, fu: 30, isDealer: true, rules: const ScoreRules(playerCount: 3));
      expect(c.tsumo, '500オール');
    });
  });

  testWidgets('3人打ちはツモの合計とツモ損・折半の説明を出し、その場で切り替えて比べられる', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(420, 3000));
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: ScoreTableScreen())));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tsumo-split')), findsNothing);
    expect(find.textContaining('計8,000'), findsNothing, reason: '4人打ちでは合計を出さない');
    await tester.tap(find.text('3人打ち'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ツモ損: 1人が払う額は4人打ちと同じ'), findsOneWidget);
    expect(find.text('2000-4000\n計6,000'), findsOneWidget, reason: '満貫の行');
    await tester.tap(find.text('折半'));
    await tester.pumpAndSettle();
    expect(find.text('3000-5000\n計8,000'), findsOneWidget);
    expect(find.textContaining('折半: いない北家の分'), findsOneWidget);
  });

  testWidgets('子・親を切り替えられる', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(420, 2400));
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: ScoreTableScreen())));
    await tester.pumpAndSettle();
    expect(find.text('1000-2000'), findsWidgets, reason: '子の 3翻30符・2翻60符など');
    expect(find.text('3000-6000'), findsOneWidget);
    await tester.tap(find.text('親'));
    await tester.pumpAndSettle();
    expect(find.text('2000オール'), findsWidgets);
    expect(find.text('6000オール'), findsOneWidget);
    expect(find.text('1000-2000'), findsNothing);
  });
}
