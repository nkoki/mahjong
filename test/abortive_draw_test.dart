import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_app/features/draw/draw_input_screen.dart';
import 'package:mahjong_app/features/session/data/session_repository.dart';
import 'package:mahjong_app/features/session/session_providers.dart';
import 'package:mahjong_app/features/session/domain/models.dart';
import 'package:mahjong_app/features/session/domain/session_logic.dart';

import 'player_stats_test.dart' show start, win;

/// 途中流局（四家立直など）
void main() {
  test('四家立直: 4人の立直棒（供託4本）はすべて場に残り、親はそのままで1本場になる', () {
    var s = start('x', ['A', 'B', 'C', 'D']);
    for (var p = 0; p < 4; p++) {
      s = SessionLogic.toggleRiichi(s, p);
    }
    expect(s.riichiSticks, 4);
    expect(s.scores, [24000, 24000, 24000, 24000]);
    final next = SessionLogic.applyDraw(s, type: DrawType.suucha, tenpai: [false, false, false, false]);
    expect(next.riichiSticks, 4, reason: '供託は次の局に持ち越し');
    expect(next.scores, [24000, 24000, 24000, 24000], reason: 'テンパイ料のやり取りはない');
    expect(next.roundLabel, '東1局 1本場', reason: '親は連荘、本場が1つ増える');
    expect(next.riichi, [false, false, false, false], reason: '次の局は立直なしから');

    // 次の局で和了した人が、供託4本（4,000点）をまとめて受け取る
    final won = win(next, 1, loser: 2);
    expect(won.riichiSticks, 0);
    expect(won.scores[1] - next.scores[1], 5200 + 300 + 4000, reason: '和了点 + 1本場300点 + 供託4,000点');
  });

  test('四家立直: 立直を押していない人からだけ供託を1本ずつ取り、すでに立直している人からは重ねて取らない', () {
    var s = start('x', ['A', 'B', 'C', 'D']);
    s = SessionLogic.toggleRiichi(s, 0);
    s = SessionLogic.toggleRiichi(s, 2); // A と C だけ立直を押した
    expect(s.riichiSticks, 2);
    expect(SessionLogic.suuchaMissingRiichi(s), [1, 3]);
    final next = SessionLogic.applyDraw(s, type: DrawType.suucha, tenpai: [false, false, false, false]);
    expect(next.riichiSticks, 4, reason: '2本 + B・D から1本ずつ');
    expect(next.scores, [24000, 24000, 24000, 24000], reason: '4人とも1,000点ずつ出したことになる');
    expect(next.scores.fold<int>(0, (a, v) => a + v) + next.riichiSticks * 1000, 100000);
    final rec = next.records.single;
    expect(rec.deltas, [-1000, -1000, -1000, -1000]);
    expect(rec.riichi, [0, 1, 2, 3], reason: '4人とも立直した局として記録（個人成績の立直率）');
    expect(rec.description, contains('B・D'));
    // 元に戻すと、供託を取る前（A と C だけ立直）に戻る
    final back = SessionLogic.undo(next);
    expect(back.riichi, [true, false, true, false]);
    expect(back.riichiSticks, 2);
    expect(back.scores, s.scores);
  });

  test('四家立直: 誰も立直を押していなければ4人全員から1本ずつ取る', () {
    final s = start('x', ['A', 'B', 'C', 'D']);
    final next = SessionLogic.applyDraw(s, type: DrawType.suucha, tenpai: [false, false, false, false]);
    expect(next.riichiSticks, 4);
    expect(next.scores, [24000, 24000, 24000, 24000]);
  });

  test('四家立直以外の途中流局（九種九牌など）では、供託を取らない', () {
    final s = SessionLogic.toggleRiichi(start('x', ['A', 'B', 'C', 'D']), 1);
    final next = SessionLogic.applyDraw(s, type: DrawType.kyuushu, tenpai: [false, false, false, false]);
    expect(next.riichiSticks, 1);
    expect(next.scores, [25000, 24000, 25000, 25000]);
  });

  testWidgets('流局の画面で四家立直を選ぶと、誰から供託を取るかと点数の動きを表示する', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    final s = SessionLogic.toggleRiichi(start('x', ['A', 'B', 'C', 'D']), 0);
    await tester.pumpWidget(ProviderScope(
      overrides: [sessionRepositoryProvider.overrideWithValue(InMemorySessionRepository([s]))],
      child: const MaterialApp(home: DrawInputScreen(sessionId: 'x')),
    ));
    final c = ProviderScope.containerOf(tester.element(find.byType(DrawInputScreen)));
    await tester.tap(find.text('四家立直'));
    await tester.pump();
    expect(find.textContaining('立直を押していない B・C・D からも供託を1本'), findsOneWidget);
    expect(find.text('-1,000'), findsNWidgets(3), reason: 'B・C・D（A はすでに立直棒を出している）');
    expect(find.textContaining('供託4本は持ち越し'), findsOneWidget);
    await tester.tap(find.text('確定'));
    await tester.pumpAndSettle();
    final next = c.read(sessionProvider('x'))!;
    expect(next.riichiSticks, 4);
    expect(next.scores, [24000, 24000, 24000, 24000]);
  });
}
