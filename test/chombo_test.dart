import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_app/features/backup/csv_export.dart';
import 'package:mahjong_app/features/session/data/session_repository.dart';
import 'package:mahjong_app/features/session/domain/models.dart';
import 'package:mahjong_app/features/session/domain/session_logic.dart';
import 'package:mahjong_app/features/session/screen_awake.dart';
import 'package:mahjong_app/features/session/screens/dashboard_screen.dart';
import 'package:mahjong_app/features/session/session_providers.dart';
import 'package:mahjong_app/features/stats/player_stats.dart';

import 'player_stats_test.dart' show start, win;
import 'table_view_test.dart' show FakeScreenAwake;

/// チョンボ（錯和）
void main() {
  group('罰符（満貫払い）', () {
    test('子は親に4000点・子に2000点ずつ、親は全員に4000点ずつ', () {
      final s = start('x', ['A', 'B', 'C', 'D']);
      expect(SessionLogic.chomboDeltas(s, 1), [4000, -8000, 2000, 2000]);
      expect(SessionLogic.chomboDeltas(s, 0), [-12000, 4000, 4000, 4000]);
    });

    test('3人打ちも同じ額ずつ払う', () {
      final s = start('x', ['A', 'B', 'C']);
      expect(SessionLogic.chomboDeltas(s, 2), [4000, 2000, -6000]);
      expect(SessionLogic.chomboDeltas(s, 0), [-8000, 4000, 4000]);
    });
  });

  group('局の進み方', () {
    test('同じ局・同じ本場でやり直し、この局の立直棒は本人に戻す（持ち越しの供託はそのまま）', () {
      var s = start('x', ['A', 'B', 'C', 'D']);
      s = SessionLogic.toggleRiichi(s, 3);
      s = SessionLogic.applyDraw(s, type: DrawType.exhaustive, tenpai: [true, false, false, true]);
      // 親テンパイで連荘: 東1局 1本場、供託1本（D の立直棒）を持ち越し
      expect(s.roundLabel, '東1局 1本場');
      expect(s.riichiSticks, 1);
      s = SessionLogic.toggleRiichi(s, 2); // C が立直（供託2本）
      final before = s.scores;
      final next = SessionLogic.applyChombo(s, 1); // B がチョンボ
      expect(next.roundLabel, '東1局 1本場');
      expect(next.riichiSticks, 1, reason: 'C の立直棒は戻り、D の分は残る');
      expect(next.riichi, [false, false, false, false]);
      expect(next.scores, [before[0] + 4000, before[1] - 8000, before[2] + 2000 + 1000, before[3] + 2000]);
      final rec = next.records.last;
      expect(rec.kind, 'chombo');
      expect(rec.loser, 1);
      expect(rec.description, contains('チョンボ B'));
      // 点数の合計は変わらない（供託の1本分を除いて）
      expect(next.scores.fold<int>(0, (a, v) => a + v) + next.riichiSticks * 1000, 100000);
    });

    test('元に戻すと、チョンボの前（立直したまま）に戻る', () {
      var s = start('x', ['A', 'B', 'C', 'D']);
      s = SessionLogic.toggleRiichi(s, 2);
      final next = SessionLogic.applyChombo(s, 1);
      expect(next.previous!.riichi[2], isTrue);
      expect(next.previous!.scores, s.scores);
      expect(next.previous!.riichiSticks, 1);
    });

    test('オーラスで親がチョンボしても和了止めにはならない', () {
      final s = start('x', ['A', 'B', 'C', 'D']).copyWith(roundIndex: 7, scores: [40000, 20000, 20000, 20000]);
      final next = SessionLogic.applyChombo(s, s.dealer);
      expect(next.finished, isFalse);
      expect(next.roundIndex, 7);
    });
  });

  test('個人成績ではチョンボの回数を数え、和了率などの局数には含めない。CSV にも出る', () {
    var s = start('x', ['A', 'B', 'C', 'D']);
    s = win(s, 1, loser: 2);
    s = SessionLogic.applyChombo(s, 3);
    s = SessionLogic.finishManually(s);
    final players = {for (final p in PlayerStatsCalculator.compute([s], playerCount: 4).players) p.name: p};
    expect(players['D']!.chombo, 1);
    expect(players['A']!.chombo, 0);
    expect(players['B']!.rounds, 1, reason: 'チョンボの局は数えない');
    expect(CsvExport.rounds([s]), contains(',チョンボ,'));
  });

  testWidgets('対局画面のメニューから入力できる', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sessionRepositoryProvider.overrideWithValue(InMemorySessionRepository([start('x', ['A', 'B', 'C', 'D'])])),
        screenAwakeProvider.overrideWithValue(FakeScreenAwake()),
      ],
      child: const MaterialApp(home: DashboardScreen(sessionId: 'x')),
    ));
    final c = ProviderScope.containerOf(tester.element(find.byType(DashboardScreen)));
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('チョンボ（錯和）を入力'));
    await tester.pumpAndSettle();
    final ok = find.text('罰符を払って局をやり直す');
    expect(tester.widget<FilledButton>(find.ancestor(of: ok, matching: find.byType(FilledButton))).onPressed, isNull,
        reason: '人を選ぶまで押せない');
    expect(find.text('8,000点を払う'), findsNWidgets(3));
    expect(find.text('12,000点を払う'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chombo-2')));
    await tester.pump();
    await tester.tap(ok);
    await tester.pumpAndSettle();
    final s = c.read(sessionProvider('x'))!;
    expect(s.scores, [29000, 27000, 17000, 27000]);
    expect(s.roundLabel, '東1局 0本場');
  });
}
