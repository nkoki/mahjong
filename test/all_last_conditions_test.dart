import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_app/features/session/data/session_repository.dart';
import 'package:mahjong_app/features/session/domain/all_last_conditions.dart';
import 'package:mahjong_app/features/session/domain/models.dart';
import 'package:mahjong_app/features/session/screen_awake.dart';
import 'package:mahjong_app/features/session/screens/dashboard_screen.dart';
import 'package:mahjong_app/features/session/session_providers.dart';

import 'player_stats_test.dart' show start;
import 'table_view_test.dart' show FakeScreenAwake;

/// オーラスの条件（トップになるのに必要な和了）
void main() {
  // 南4局（親は D）、A がトップ
  GameSession allLast({List<int> scores = const [30000, 25000, 25000, 20000], int honba = 0, int sticks = 0}) =>
      start('x', ['A', 'B', 'C', 'D']).copyWith(roundIndex: 7, scores: scores, honba: honba, riichiSticks: sticks);

  test('オーラス・延長戦だけで表示し、それ以外の局や終局後は表示しない', () {
    expect(AllLastConditions.applies(allLast()), isTrue);
    expect(AllLastConditions.applies(start('x', ['A', 'B', 'C', 'D'])), isFalse);
    expect(AllLastConditions.applies(allLast().copyWith(roundIndex: 8)), isTrue, reason: '西入');
    expect(AllLastConditions.applies(allLast().copyWith(finished: true)), isFalse);
    expect(AllLastConditions.applies(start('x', ['A', 'B', 'C']).copyWith(roundIndex: 5)), isTrue, reason: '3人打ちの南3局');
  });

  test('子: 同点では上家（起家に近い人）が上なので、差より多く取る必要がある', () {
    final c = AllLastConditions.compute(allLast());
    expect(c.map((e) => e.player), [1, 2, 3], reason: 'トップ以外を順位順に');
    final b = c.first;
    // 5000点差: ロンは 5200（5000 では同点で A が上）
    expect(b.ron!.handLabel, '3翻40符', reason: '2翻80符 より 符の少ない 3翻40符');
    expect(b.ron!.score, '5200');
    expect(b.ron!.highFu, isNull);
    // 直撃は差が倍で縮まるので 2600
    expect(b.direct!.handLabel, '2翻40符');
    expect(b.direct!.score, '2600');
    // ツモ: 1000-2000 は A が 29000 で同点。40符までの手では 1300-2600、符が高ければ 1200-2300
    expect(b.tsumo!.score, '1300-2600');
    expect(b.tsumo!.highFu!.handLabel, '2翻70符');
    expect(b.tsumo!.highFu!.score, '1200-2300');
  });

  test('親（10000点差）', () {
    final d = AllLastConditions.compute(allLast()).last;
    expect(d.player, 3);
    expect(d.ron!.handLabel, '4翻30符');
    expect(d.ron!.score, '11600');
    expect(d.ron!.highFu!.handLabel, '2翻110符');
    expect(d.direct!.score, '5800');
    expect(d.tsumo!.score, '2600オール');
  });

  test('本場と供託を含めて計算する（表示する点数には含めない）', () {
    final b = AllLastConditions.compute(allLast(honba: 2, sticks: 2)).first;
    // 供託 2000点と本場 600点が付くので、2600 のロンで 30200 になる
    expect(b.ron!.score, '2600');
    expect(b.direct!.score, '1000');
    expect(b.tsumo!.score, '500-1000');
  });

  test('役満でも届かなければ null。満貫以上は名前で示す', () {
    final c = AllLastConditions.compute(allLast(scores: const [60000, 20000, 15000, 5000]));
    expect(c.first.ron, isNull);
    expect(c.first.tsumo, isNull);
    expect(c.first.direct!.handLabel, '三倍満');
    expect(c.last.tsumo!.handLabel, '役満');
    expect(c.last.tsumo!.score, '16000オール');
  });

  testWidgets('対局画面の帯から条件を開ける', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sessionRepositoryProvider.overrideWithValue(InMemorySessionRepository([allLast()])),
        screenAwakeProvider.overrideWithValue(FakeScreenAwake()),
      ],
      child: const MaterialApp(home: DashboardScreen(sessionId: 'x')),
    ));
    await tester.tap(find.byKey(const ValueKey('all-last-conditions')));
    await tester.pumpAndSettle();
    expect(find.text('トップになるのに必要な和了'), findsOneWidget);
    expect(find.text('3翻40符（5200）'), findsNWidgets(2), reason: 'B と C');
    expect(find.textContaining('符が高ければ 2翻70符（1200-2300）'), findsNWidgets(2));
  });

  testWidgets('オーラスでなければ帯を出さない', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sessionRepositoryProvider.overrideWithValue(InMemorySessionRepository([start('x', ['A', 'B', 'C', 'D'])])),
        screenAwakeProvider.overrideWithValue(FakeScreenAwake()),
      ],
      child: const MaterialApp(home: DashboardScreen(sessionId: 'x')),
    ));
    expect(find.byKey(const ValueKey('all-last-conditions')), findsNothing);
  });
}
