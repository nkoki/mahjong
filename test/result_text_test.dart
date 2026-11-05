import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_app/features/history/history_detail_screen.dart';
import 'package:mahjong_app/features/history/result_text.dart';
import 'package:mahjong_app/features/session/data/session_repository.dart';
import 'package:mahjong_app/features/session/session_providers.dart';

import 'player_stats_test.dart' show playedGame, start, win;

/// 結果の共有（テキストのコピー）
void main() {
  test('終局した対局: 順位・点数・ポイント', () {
    final s = playedGame('x', ['A', 'B', 'C', 'D']);
    final t = ResultText.build(s);
    final lines = t.split('\n');
    expect(lines[0], '【麻雀 対局結果】');
    expect(lines[1], '2026/6/1  半荘戦');
    final r = s.finalResults.first;
    expect(lines[2], startsWith('1位 ${s.playerNames[r.player]}  '));
    expect(lines[2], endsWith(r.point > 0 ? '+${r.point.toStringAsFixed(1)}' : r.point.toStringAsFixed(1)));
    expect(lines.length, 2 + 4 + 1);
    expect(lines.last, 'ウマ 10-20・返し 30,000点・2局');
  });

  test('対局中はポイントを出さない。祝儀・焼き鳥も添える', () {
    var s = start('x', ['A', 'B', 'C']);
    s = win(s, 1, loser: 2);
    final t = ResultText.build(s);
    expect(t, startsWith('【麻雀 対局中（東2局 0本場）の順位】'));
    expect(t, contains('1位 B  '));
    expect(t, contains('3人打ち 半荘戦'));
    expect(t, isNot(contains('+')));

    final f = s.copyWith(
        finished: true, settings: s.settings.copyWith(chips: true, yakitori: 10));
    final ft = ResultText.build(f);
    expect(ft, contains('祝儀 0枚'));
    expect(ft, contains('焼き鳥・トビ賞 -10.0'));
  });

  testWidgets('戦績詳細からコピーできる', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    final s = playedGame('x', ['A', 'B', 'C', 'D']);
    await tester.pumpWidget(ProviderScope(
      overrides: [sessionRepositoryProvider.overrideWithValue(InMemorySessionRepository([s]))],
      child: const MaterialApp(home: HistoryDetailScreen(sessionId: 'x')),
    ));
    await tester.tap(find.byTooltip('結果をコピー（LINE などに貼り付け）'));
    await tester.pumpAndSettle();
    expect(copied, ResultText.build(s));
    expect(find.textContaining('結果をコピーしました'), findsOneWidget);
  });
}
