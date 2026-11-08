import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_app/core/theme.dart';
import 'package:mahjong_app/features/history/history_detail_screen.dart';
import 'package:mahjong_app/features/session/data/session_repository.dart';
import 'package:mahjong_app/features/session/domain/models.dart';
import 'package:mahjong_app/features/session/domain/session_logic.dart';
import 'package:mahjong_app/features/session/screen_awake.dart';
import 'package:mahjong_app/features/session/screens/dashboard_screen.dart';
import 'package:mahjong_app/features/session/screens/home_screen.dart';
import 'package:mahjong_app/features/session/screens/table_view_screen.dart';
import 'package:mahjong_app/features/session/session_providers.dart';
import 'package:mahjong_app/features/stats/stats_screen.dart';
import 'package:mahjong_app/features/win/win_input_screen.dart';
import 'package:mahjong_app/features/win/win_result_screen.dart';

import '../double_ron_test.dart' show pinfuRon;
import '../table_view_test.dart' show FakeScreenAwake;

/// 主な画面の見た目（画像）が変わっていないかを確かめる（ゴールデンテスト）。
///
/// 画面を変えたときは `flutter test --update-goldens test/golden` で画像を作り直し、
/// 作り直した画像（test/golden/goldens/）を目で確かめてからコミットする。
/// テストでは文字が四角で描かれる（テスト用のフォント）。
void main() {
  final at = DateTime(2026, 6, 1, 20, 0);

  WinEntry quick(GameSession s, int winner, {bool tsumo = false, int han = 3, int fu = 40}) =>
      WinEntry.hanFu(session: s, winner: winner, isTsumo: tsumo, hanFu: HanFuEntry(han: han, fu: fu));

  GameSession apply(GameSession s, WinEntry e, {int? loser}) => SessionLogic.applyWins(s,
      wins: SessionLogic.scoreWins(s, [e], loser: loser), loser: loser, description: '和了');

  /// 何局か進めた対局中の対局
  GameSession ongoing({String id = 'x'}) {
    var s = GameSession.start(id: id, playerNames: ['佐藤', '鈴木', '高橋', '田中'], settings: const GameSettings(), now: at);
    s = apply(s, quick(s, 2), loser: 1);
    s = SessionLogic.toggleRiichi(s, 3);
    s = SessionLogic.applyDraw(s, type: DrawType.exhaustive, tenpai: [false, false, true, true]);
    s = apply(s, quick(s, 0, tsumo: true, han: 2, fu: 30));
    return SessionLogic.toggleRiichi(s, 1);
  }

  GameSession finished() => SessionLogic.finishManually(ongoing(id: 'done'));

  Future<void> shot(WidgetTester tester, String name, Widget home,
      {ThemeMode mode = ThemeMode.light, Map<String, String> preferences = const {}}) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    final repo = InMemorySessionRepository([ongoing(), finished()]);
    for (final e in preferences.entries) {
      await repo.savePreference(e.key, e.value);
    }
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sessionRepositoryProvider.overrideWithValue(repo),
        screenAwakeProvider.overrideWithValue(FakeScreenAwake()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: mode,
        home: home,
      ),
    ));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
  }

  testWidgets('ホーム', (t) => shot(t, 'home', const HomeScreen()));
  testWidgets('対局画面', (t) => shot(t, 'dashboard', const DashboardScreen(sessionId: 'x')));
  testWidgets('対局画面（暗い表示）', (t) => shot(t, 'dashboard_dark', const DashboardScreen(sessionId: 'x'), mode: ThemeMode.dark));
  testWidgets('対局画面（卓ビュー）', (t) => shot(t, 'dashboard_table', const DashboardScreen(sessionId: 'x'),
      preferences: {PreferenceKeys.dashboardLayout: 'table'}));
  testWidgets('和了入力', (t) => shot(t, 'win_input', const WinInputScreen(sessionId: 'x')));
  testWidgets('計算結果', (t) {
    final s = ongoing();
    return shot(t, 'win_result',
        WinResultScreen(sessionId: 'x', entries: [WinEntry(winner: 1, input: pinfuRon(s, 1))], loser: 2));
  });
  testWidgets('戦績詳細', (t) => shot(t, 'history_detail', const HistoryDetailScreen(sessionId: 'done')));
  testWidgets('個人成績', (t) => shot(t, 'stats', StatsScreen(now: at)));
  testWidgets('卓に置く表示', (t) => shot(t, 'table_view', const TableViewScreen(sessionId: 'x')));
}
