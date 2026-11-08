import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_app/features/session/data/session_repository.dart';
import 'package:mahjong_app/features/session/domain/models.dart';
import 'package:mahjong_app/features/session/domain/session_logic.dart';
import 'package:mahjong_app/features/session/screen_awake.dart';
import 'package:mahjong_app/features/session/screens/dashboard_screen.dart';
import 'package:mahjong_app/features/session/screens/table_view_screen.dart';
import 'package:mahjong_app/features/session/session_providers.dart';

import 'player_stats_test.dart' show start;

class FakeScreenAwake implements ScreenAwake {
  final calls = <bool>[];
  bool get awake => calls.isNotEmpty && calls.last;

  @override
  Future<void> setAwake(bool awake) async => calls.add(awake);
}

/// 卓に置いて使う表示・画面を消さない設定
void main() {
  group('卓の上での位置', () {
    test('4人打ち: 下家は右、対面は向かい、上家は左', () {
      final s = start('x', ['A', 'B', 'C', 'D']);
      expect([for (var p = 0; p < 4; p++) tableSideOf(s, p, 0)],
          [TableSide.bottom, TableSide.right, TableSide.top, TableSide.left]);
      expect([for (var p = 0; p < 4; p++) tableSideOf(s, p, 2)],
          [TableSide.top, TableSide.left, TableSide.bottom, TableSide.right]);
    });

    test('親が変わっても、座っている位置は変わらない', () {
      final s = start('x', ['A', 'B', 'C', 'D']).copyWith(roundIndex: 1); // B が親
      expect(s.dealer, 1);
      expect([for (var p = 0; p < 4; p++) tableSideOf(s, p, 0)],
          [TableSide.bottom, TableSide.right, TableSide.top, TableSide.left]);
    });

    test('3人打ちは北の席が空く', () {
      final s = start('x', ['A', 'B', 'C']);
      expect([for (var p = 0; p < 3; p++) tableSideOf(s, p, 0)],
          [TableSide.bottom, TableSide.right, TableSide.top]);
      expect([for (var p = 0; p < 3; p++) tableSideOf(s, p, 1)],
          [TableSide.left, TableSide.bottom, TableSide.right]);
    });
  });

  group('画面', () {
    Future<(ProviderContainer, FakeScreenAwake, InMemorySessionRepository)> pump(
        WidgetTester tester, Widget home, GameSession s) async {
      await tester.binding.setSurfaceSize(const Size(420, 900));
      final awake = FakeScreenAwake();
      final repo = InMemorySessionRepository([s]);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sessionRepositoryProvider.overrideWithValue(repo),
          screenAwakeProvider.overrideWithValue(awake),
        ],
        child: MaterialApp(home: home),
      ));
      return (ProviderScope.containerOf(tester.element(find.byWidget(home))), awake, repo);
    }

    testWidgets('全員の点数を、それぞれの向きで表示し、回せる', (tester) async {
      var s = start('x', ['A', 'B', 'C', 'D']);
      s = SessionLogic.toggleRiichi(s, 1);
      await pump(tester, const TableViewScreen(sessionId: 'x'), s);
      int turns(int p) => tester.widget<RotatedBox>(find.byKey(ValueKey('table-player-$p'))).quarterTurns;
      expect([for (var p = 0; p < 4; p++) turns(p)], [0, 3, 2, 1]);
      expect(find.text('東 A'), findsOneWidget);
      expect(find.text('立直'), findsOneWidget);
      expect(find.text('東1局'), findsOneWidget);
      expect(find.text('0本場  供託1本'), findsOneWidget);
      expect(find.text('トップ'), findsNWidgets(3), reason: 'A・C・D は 25,000 で同点トップ（B は立直）');

      await tester.tap(find.text('回す'));
      await tester.pump();
      expect(turns(1), 0, reason: 'B が手前になる');
      expect(turns(0), 1);
    });

    testWidgets('対局中は画面を消さず、終局・画面を閉じる・設定をオフにすると元に戻す', (tester) async {
      final (c, awake, repo) = await pump(tester, const DashboardScreen(sessionId: 'x'), start('x', ['A', 'B', 'C', 'D']));
      expect(awake.awake, isTrue);

      // メニューで切り替える（設定は端末に保存する）
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<CheckedPopupMenuItem<String>>(find.ancestor(
                  of: find.text('対局中は画面を消さない'), matching: find.byType(CheckedPopupMenuItem<String>)))
              .checked,
          isTrue);
      await tester.tap(find.text('対局中は画面を消さない'));
      await tester.pumpAndSettle();
      expect(awake.awake, isFalse);
      expect(repo.preferences['keep_screen_on'], '0');
      c.read(preferenceProvider(PreferenceKeys.keepScreenOn).notifier).set('1');
      await tester.pump();
      expect(awake.awake, isTrue);

      // 終局すると元に戻す
      c.read(sessionsProvider.notifier).finish('x');
      await tester.pump();
      expect(awake.awake, isFalse);
    });

    testWidgets('対局画面を閉じると元に戻す', (tester) async {
      final (_, awake, _) = await pump(tester, const DashboardScreen(sessionId: 'x'), start('x', ['A', 'B', 'C', 'D']));
      expect(awake.awake, isTrue);
      await tester.pumpWidget(const SizedBox());
      expect(awake.awake, isFalse);
    });

    testWidgets('メニューから卓に置く表示を開ける', (tester) async {
      await pump(tester, const DashboardScreen(sessionId: 'x'), start('x', ['A', 'B', 'C', 'D']));
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('卓に置いて表示'));
      await tester.pumpAndSettle();
      expect(find.byType(TableViewScreen), findsOneWidget);
      await tester.tap(find.text('閉じる'));
      await tester.pumpAndSettle();
      expect(find.byType(TableViewScreen), findsNothing);
    });
  });
}
