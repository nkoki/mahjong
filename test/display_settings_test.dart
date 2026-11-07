import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_app/core/theme.dart';
import 'package:mahjong_app/features/session/data/session_repository.dart';
import 'package:mahjong_app/features/session/session_providers.dart';
import 'package:mahjong_app/features/settings/display_settings.dart';
import 'package:mahjong_app/features/history/history_detail_screen.dart';
import 'package:mahjong_app/features/session/domain/models.dart';
import 'package:mahjong_app/features/session/screens/dashboard_screen.dart';
import 'package:mahjong_app/features/session/screens/home_screen.dart';
import 'package:mahjong_app/features/session/screens/new_session_screen.dart';
import 'package:mahjong_app/features/stats/stats_screen.dart';
import 'package:mahjong_app/features/win/win_input_screen.dart';
import 'package:mahjong_app/main.dart';

import 'player_stats_test.dart' show playedGame;

/// 表示の設定（明るさ・文字の大きさ）
void main() {
  test('保存した値の読み方（変な値は初期値）', () {
    expect(themeModeOf(null), ThemeMode.system);
    expect(themeModeOf('dark'), ThemeMode.dark);
    expect(themeModeOf('light'), ThemeMode.light);
    expect(themeModeOf('xxx'), ThemeMode.system);
    expect(textScaleOf(null), 1.0);
    expect(textScaleOf('1.3'), 1.3);
    expect(textScaleOf('9'), 1.0);
  });

  Future<InMemorySessionRepository> pumpApp(WidgetTester tester, {Map<String, String> prefs = const {}}) async {
    await tester.binding.setSurfaceSize(const Size(420, 1200));
    final repo = InMemorySessionRepository()..preferences.addAll(prefs);
    await tester.pumpWidget(ProviderScope(
      overrides: [sessionRepositoryProvider.overrideWithValue(repo)],
      child: const MahjongApp(),
    ));
    return repo;
  }

  double scaleOf(WidgetTester tester, Finder f) => MediaQuery.of(tester.element(f)).textScaler.scale(10) / 10;

  testWidgets('保存した設定で起動する', (tester) async {
    await pumpApp(tester, prefs: {'theme_mode': 'dark', 'text_scale': '1.3'});
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode, ThemeMode.dark);
    expect(Theme.of(tester.element(find.text('新規対局'))).brightness, Brightness.dark);
    expect(scaleOf(tester, find.text('新規対局')), closeTo(1.3, 1e-9));
  });

  testWidgets('ホーム画面から表示の設定を開いて変えると、すぐに反映され保存される', (tester) async {
    final repo = await pumpApp(tester);
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode, ThemeMode.system);
    // 設定はホームのメニューの「設定」のまとまりにある
    await tester.scrollUntilVisible(find.text('表示の設定（明るさ・文字の大きさ）'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('表示の設定（明るさ・文字の大きさ）'));
    await tester.pumpAndSettle();
    expect(find.byType(DisplaySettingsScreen), findsOneWidget);

    await tester.tap(find.text('暗い'));
    await tester.pumpAndSettle();
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode, ThemeMode.dark);
    expect(repo.preferences[PreferenceKeys.themeMode], 'dark');

    await tester.tap(find.text('大'));
    await tester.pumpAndSettle();
    expect(scaleOf(tester, find.text('見本')), closeTo(1.15, 1e-9));
    expect(repo.preferences[PreferenceKeys.textScale], '1.15');
  });

  testWidgets('増減の色は暗い表示では明るめ', (tester) async {
    late Color? lightUp, darkUp;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Builder(builder: (c) {
        lightUp = deltaColor(c, 100);
        expect(deltaColor(c, 0), isNull);
        return const SizedBox();
      }),
    ));
    await tester.pumpWidget(MaterialApp(
      key: UniqueKey(), // 前の画面を使い回すと、テーマが切り替わる途中の色になる
      theme: AppTheme.dark(),
      home: Builder(builder: (c) {
        darkUp = deltaColor(c, 100);
        return const SizedBox();
      }),
    ));
    expect(lightUp, const Color(0xFF1F6B4A));
    expect(darkUp, const Color(0xFF8FC4AA));
    expect(darkUp!.computeLuminance(), greaterThan(lightUp!.computeLuminance()), reason: '暗い表示では明るめ');
  });

  group('文字を特大にして、暗い表示・幅の狭い画面でもはみ出さない', () {
    final finished = playedGame('done', ['佐藤', '鈴木', '高橋', '田中']);
    final ongoing = GameSession.start(
        id: 'x', playerNames: ['佐藤', '鈴木', '高橋', '田中'], settings: const GameSettings(), now: DateTime(2026, 6, 1));
    final screens = <String, Widget>{
      'ホーム': const HomeScreen(),
      '新規対局': const NewSessionScreen(),
      '対局画面': const DashboardScreen(sessionId: 'x'),
      '和了入力': const WinInputScreen(sessionId: 'x'),
      '戦績詳細': const HistoryDetailScreen(sessionId: 'done'),
      '個人成績': const StatsScreen(),
      '表示の設定': const DisplaySettingsScreen(),
    };
    for (final e in screens.entries) {
      testWidgets(e.key, (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 3000));
        await tester.pumpWidget(ProviderScope(
          overrides: [sessionRepositoryProvider.overrideWithValue(InMemorySessionRepository([ongoing, finished]))],
          child: MaterialApp(
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: ThemeMode.dark,
            builder: (c, child) => applyTextScale(c, child, 1.3),
            home: e.value,
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
