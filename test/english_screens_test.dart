import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_app/core/l10n.dart';
import 'package:mahjong_app/features/backup/backup_screen.dart';
import 'package:mahjong_app/features/draw/draw_input_screen.dart';
import 'package:mahjong_app/features/history/history_detail_screen.dart';
import 'package:mahjong_app/features/history/history_list_screen.dart';
import 'package:mahjong_app/features/practice/practice_screen.dart';
import 'package:mahjong_app/features/score_table/score_table_screen.dart';
import 'package:mahjong_app/features/session/data/session_repository.dart';
import 'package:mahjong_app/features/session/domain/session_logic.dart';
import 'package:mahjong_app/features/session/screen_awake.dart';
import 'package:mahjong_app/features/session/screens/dashboard_screen.dart';
import 'package:mahjong_app/features/session/screens/home_screen.dart';
import 'package:mahjong_app/features/session/screens/new_session_screen.dart';
import 'package:mahjong_app/features/session/session_providers.dart';
import 'package:mahjong_app/features/settings/display_settings.dart';
import 'package:mahjong_app/features/settings/rule_settings_screen.dart';
import 'package:mahjong_app/features/stats/stats_screen.dart';
import 'package:mahjong_app/features/storage/storage_info_screen.dart';
import 'package:mahjong_app/features/win/win_input_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'player_stats_test.dart' show playedGame, start, win;
import 'table_view_test.dart' show FakeScreenAwake;

final _japanese = RegExp(r'[぀-ヿ一-鿿]');

/// 英語表示で、画面に日本語の文字が残っていないか
void main() {
  setUp(() => L10n.isEnglish = true);
  tearDown(() => L10n.isEnglish = false);

  final screens = <String, Widget>{
    'home': const HomeScreen(),
    'new game': const NewSessionScreen(),
    'dashboard': const DashboardScreen(sessionId: 'live'),
    'win input': const WinInputScreen(sessionId: 'live'),
    'draw input': const DrawInputScreen(sessionId: 'live'),
    'history list': const HistoryListScreen(),
    'history detail': const HistoryDetailScreen(sessionId: 'done'),
    'stats': const StatsScreen(),
    'rule settings': const RuleSettingsScreen(),
    'display settings': const DisplaySettingsScreen(),
    'score table': const ScoreTableScreen(),
    'practice': PracticeScreen(random: Random(1)),
    'backup': const BackupScreen(),
    'storage info': const StorageInfoScreen(),
  };

  for (final e in screens.entries) {
    testWidgets('英語: ${e.key}', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(420, 3000));
      // 名前は英語にしておく（入力した名前は日本語でもそのまま出すため）
      var live = win(start('live', ['Ann', 'Bob', 'Cat', 'Dan']), 1, loser: 2);
      live = SessionLogic.toggleRiichi(live, 0);
      final done = playedGame('done', ['Ann', 'Bob', 'Cat', 'Dan']);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sessionRepositoryProvider.overrideWithValue(InMemorySessionRepository([live, done])),
          screenAwakeProvider.overrideWithValue(FakeScreenAwake()),
        ],
        child: MaterialApp(home: e.value),
      ));
      await tester.pumpAndSettle();
      final leftovers = <String>{
        for (final t in tester.widgetList<Text>(find.byType(Text)))
          if ((t.data ?? t.textSpan?.toPlainText() ?? '') case final s when _japanese.hasMatch(s)) s,
        for (final t in tester.widgetList<RichText>(find.byType(RichText)))
          if (t.text.toPlainText() case final s when _japanese.hasMatch(s)) s,
      }
        // 両方の言語で書いた見出しと、局の記録のメモ（保存した文）は除く
        ..removeWhere((s) => s.contains('言語 / Language') || s == 'test' || s.contains('日本語'));
      expect(leftovers, isEmpty, reason: e.key);
    });
  }
}
