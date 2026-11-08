import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_app/core/l10n.dart';
import 'package:mahjong_app/features/session/data/session_repository.dart';
import 'package:mahjong_app/features/session/domain/models.dart';
import 'package:mahjong_app/features/session/screen_awake.dart';
import 'package:mahjong_app/features/session/screens/dashboard_screen.dart';
import 'package:mahjong_app/features/session/screens/table_layout.dart';
import 'package:mahjong_app/features/session/session_providers.dart';
import 'package:mahjong_app/features/settings/display_settings.dart';

import 'player_stats_test.dart' show start, win;
import 'table_view_test.dart' show FakeScreenAwake;

/// 対局画面の卓ビュー（グラフィカルなレイアウト）
void main() {
  Future<(ProviderContainer, InMemorySessionRepository)> pump(WidgetTester tester, GameSession s,
      {bool table = true, Size size = const Size(400, 860)}) async {
    await tester.binding.setSurfaceSize(size);
    final repo = InMemorySessionRepository([s]);
    if (table) await repo.savePreference(PreferenceKeys.dashboardLayout, 'table');
    await tester.pumpWidget(ProviderScope(
      overrides: [sessionRepositoryProvider.overrideWithValue(repo), screenAwakeProvider.overrideWithValue(FakeScreenAwake())],
      child: const MaterialApp(home: DashboardScreen(sessionId: 'x')),
    ));
    await tester.pumpAndSettle();
    return (ProviderScope.containerOf(tester.element(find.byType(DashboardScreen))), repo);
  }

  testWidgets('起家を下にして、打つ順番に右・上・左へ並べる。真ん中に局・本場・供託', (tester) async {
    await pump(tester, win(start('x', ['A', 'B', 'C', 'D']), 1, loser: 2));
    expect(find.byType(MahjongTableView), findsOneWidget);
    Offset at(int p) => tester.getCenter(find.byKey(ValueKey('seat-$p')));
    final table = tester.getCenter(find.byType(MahjongTableView));
    expect(at(0).dy, greaterThan(table.dy), reason: '起家は下');
    expect(at(1).dx, greaterThan(table.dx), reason: '下家は右');
    expect(at(2).dy, lessThan(table.dy), reason: '対面は上');
    expect(at(3).dx, lessThan(table.dx), reason: '上家は左');
    expect(find.text('東2局'), findsOneWidget);
    expect(find.text('0本場'), findsOneWidget);
    expect(find.text('30,200'), findsOneWidget);
  });

  testWidgets('席を押すと立直し、もう一度押すと取り消す（千点棒を置く）', (tester) async {
    final (c, _) = await pump(tester, start('x', ['A', 'B', 'C', 'D']));
    expect(find.byType(PointStick), findsOneWidget, reason: '供託なしの薄い点棒だけ');
    await tester.tap(find.byKey(const ValueKey('seat-2')));
    await tester.pumpAndSettle();
    var s = c.read(sessionProvider('x'))!;
    expect(s.riichi[2], isTrue);
    expect(s.riichiSticks, 1);
    expect(find.text('立直中（取消）'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('seat-2')));
    await tester.pumpAndSettle();
    s = c.read(sessionProvider('x'))!;
    expect(s.riichi[2], isFalse);
  });

  testWidgets('3人打ちは北家の席（左）を空ける', (tester) async {
    await pump(tester, start('x', ['A', 'B', 'C']));
    final table = tester.getCenter(find.byType(MahjongTableView));
    expect(find.byKey(const ValueKey('seat-3')), findsNothing);
    expect(tester.getCenter(find.byKey(const ValueKey('seat-2'))).dy, lessThan(table.dy));
    expect(tester.getCenter(find.byKey(const ValueKey('seat-1'))).dx, greaterThan(table.dx));
  });

  testWidgets('幅の狭い画面・長い名前でもはみ出さない', (tester) async {
    await pump(tester, start('x', ['とても長い名前のプレイヤー', 'B', 'C', 'D']), size: const Size(320, 560));
    expect(tester.takeException(), isNull);
  });

  testWidgets('対局画面のメニューから切り替えられ、設定に保存される', (tester) async {
    final (c, repo) = await pump(tester, start('x', ['A', 'B', 'C', 'D']), table: false);
    expect(find.byType(MahjongTableView), findsNothing);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('卓の形で表示'));
    await tester.pumpAndSettle();
    expect(find.byType(MahjongTableView), findsOneWidget);
    expect(repo.preferences[PreferenceKeys.dashboardLayout], 'table');
    expect(c.read(tableLayoutProvider), isTrue);
  });

  testWidgets('表示の設定で選べる', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    final repo = InMemorySessionRepository([]);
    await tester.pumpWidget(ProviderScope(
      overrides: [sessionRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: DisplaySettingsScreen()),
    ));
    await tester.tap(find.text('卓（グラフィカル）'));
    await tester.pumpAndSettle();
    expect(repo.preferences[PreferenceKeys.dashboardLayout], 'table');
    await tester.tap(find.text('シンプル'));
    await tester.pumpAndSettle();
    expect(repo.preferences[PreferenceKeys.dashboardLayout], 'simple');
  });

  testWidgets('英語表示では日本語が残らない', (tester) async {
    L10n.isEnglish = true;
    addTearDown(() => L10n.isEnglish = false);
    await pump(tester, win(start('x', ['Ann', 'Bob', 'Cat', 'Dan']), 1, loser: 2));
    final jp = RegExp(r'[\u3040-\u30ff\u4e00-\u9fff]');
    final left = [
      for (final t in tester.widgetList<Text>(find.byType(Text)))
        if (jp.hasMatch(t.data ?? t.textSpan?.toPlainText() ?? '')) t.data ?? t.textSpan!.toPlainText(),
    ];
    expect(left, isEmpty);
    expect(find.text('East 2'), findsOneWidget);
  });
}
