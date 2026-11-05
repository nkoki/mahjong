import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_app/features/practice/practice_generator.dart';
import 'package:mahjong_app/features/practice/practice_screen.dart';
import 'package:mahjong_app/features/session/data/session_repository.dart';
import 'package:mahjong_app/features/session/session_providers.dart';
import 'package:mahjong_score_engine/mahjong_score_engine.dart';

/// 点数計算の練習
void main() {
  test('作った問題は、どれも正しいあがり形で、答えが選択肢に1つだけある', () {
    final rng = Random(1);
    for (var i = 0; i < 300; i++) {
      final q = PracticeGenerator.generate(rng);
      final input = q.input;
      expect(input.handTiles.length, 13 - 3 * input.melds.length);
      // すべての牌は4枚まで
      final all = [...input.handTiles, input.winningTile, for (final m in input.melds) ...m.tiles, ...input.doraTiles, ...input.uraDoraTiles];
      for (final t in all.toSet()) {
        expect(all.where((x) => x == t).length, lessThanOrEqualTo(4), reason: t);
      }
      final r = ScoreCalculator.calculate(input);
      expect(r.isValid, isTrue);
      expect(r.isYakuman, isFalse);
      expect(q.choices.length, 4);
      expect(q.choices.toSet().length, 4);
      expect(q.choices.where((c) => c == q.answer).length, 1);
      if (input.isTsumo) {
        expect(q.answer, ScoreCalculator.formatScore(r, isDealer: input.isDealer, isTsumo: true));
      } else {
        expect(q.answer, '${r.totalScore}点');
      }
      expect(input.uraDoraTiles.isEmpty || input.isRiichi, isTrue);
    }
  });

  test('同じ乱数なら同じ問題', () {
    final a = PracticeGenerator.generate(Random(7));
    final b = PracticeGenerator.generate(Random(7));
    expect(a.answer, b.answer);
    expect(a.input.handTiles, b.input.handTiles);
  });

  testWidgets('選ぶと正解・不正解と内訳を表示し、次の問題へ進める', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    await tester.pumpWidget(ProviderScope(
      overrides: [sessionRepositoryProvider.overrideWithValue(InMemorySessionRepository([]))],
      child: MaterialApp(home: PracticeScreen(random: Random(3))),
    ));
    final q = PracticeGenerator.generate(Random(3));
    expect(find.text('正解 0 / 0問'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('choice-${q.answer}')));
    await tester.pump();
    expect(find.text('正解！'), findsOneWidget);
    expect(find.text('正解 1 / 1問'), findsOneWidget);
    expect(find.textContaining('役: '), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('practice-next')));
    await tester.pump();
    expect(find.text('正解！'), findsNothing);
    // 2問目はわざと間違える
    final wrong = tester
        .widgetList<OutlinedButton>(find.byType(OutlinedButton))
        .map((b) => ((b.child as Text).data)!)
        .firstWhere((c) => find.textContaining('不正解').evaluate().isEmpty && c != '');
    await tester.tap(find.byKey(ValueKey('choice-$wrong')));
    await tester.pump();
    expect(find.textContaining('正解 ').evaluate().isNotEmpty, isTrue);
    expect(find.textContaining('/ 2問'), findsOneWidget);
  });
}
