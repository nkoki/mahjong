import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_app/features/backup/backup_file_service.dart';
import 'package:mahjong_app/features/backup/backup_screen.dart';
import 'package:mahjong_app/features/backup/csv_export.dart';
import 'package:mahjong_app/features/session/data/session_repository.dart';
import 'package:mahjong_app/features/session/session_providers.dart';

import 'backup_test.dart' show FakeFileService;
import 'player_stats_test.dart' show playedGame, start;

/// 戦績の CSV 書き出し
void main() {
  List<String> lines(String csv) {
    expect(csv.startsWith(CsvExport.bom), isTrue, reason: 'Excel で文字化けしないように BOM を付ける');
    return csv.substring(1).split('\r\n')..removeLast();
  }

  test('値の囲み方（カンマ・ダブルクォート・改行）', () {
    expect(CsvExport.escape('A'), 'A');
    expect(CsvExport.escape('A,B'), '"A,B"');
    expect(CsvExport.escape('A"B'), '"A""B"');
    expect(CsvExport.escape('A\nB'), '"A\nB"');
  });

  test('対局一覧: 1行に1対局（古い順）。3人打ちは4人目を空にする', () {
    final g4 = playedGame('1', ['佐藤', '鈴,木', 'C', 'D'], at: DateTime(2026, 1, 2, 9, 5));
    final g3 = playedGame('2', ['A', 'B', 'C'], at: DateTime(2026, 3, 1));
    final ongoing = start('3', ['A', 'B', 'C', 'D'], at: DateTime(2026, 4, 1));
    final l = lines(CsvExport.games([ongoing, g3, g4]));
    expect(l, hasLength(4));
    expect(l[0].split(',').take(9), ['日時', '人数', '種類', '状態', 'お気に入り', '持ち点', '返し', 'ウマ', '局数']);
    expect(l[0].split(","), hasLength(9 + 16 + 4));
    expect(l[1], startsWith('2026/01/02 09:05,4人,半荘戦,終局,,25000,30000,'));
    expect(l[1], contains(',佐藤,'));
    expect(l[1], contains('"鈴,木"'));
    // 3人打ち: 最後の4列（4人目）が空
    expect(l[2], endsWith(',,,,'));
    // 対局中はポイントが空
    expect(l[3], contains(',対局中,'));
  });

  test('局ごとの記録: 1行に1局', () {
    final g = playedGame('1', ['A', 'B', 'C', 'D'], at: DateTime(2026, 1, 2));
    final l = lines(CsvExport.rounds([g]));
    expect(l, hasLength(1 + g.records.length));
    expect(l[1], startsWith('2026/01/02 00:00,4人,東1局 0本場,和了,test,,A,'));
    expect(l[2], contains(',流局,'));
    final cells = l[1].split(',');
    // 名前・増減・局のあとの点数が局の記録と同じ
    expect(cells.sublist(6), ['A', '${g.records[0].deltas[0]}', '${g.records[0].scoresAfter[0]}',
      'B', '${g.records[0].deltas[1]}', '${g.records[0].scoresAfter[1]}',
      'C', '${g.records[0].deltas[2]}', '${g.records[0].scoresAfter[2]}',
      'D', '${g.records[0].deltas[3]}', '${g.records[0].scoresAfter[3]}']);
  });

  test('ファイル名', () {
    expect(CsvExport.fileName('games', DateTime(2026, 11, 4, 9, 5)), 'mahjong_games_20261104_0905.csv');
  });

  testWidgets('バックアップ画面から CSV を保存できる', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 2000));
    final files = FakeFileService();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sessionRepositoryProvider.overrideWithValue(InMemorySessionRepository([playedGame('1', ['A', 'B', 'C', 'D'])])),
        backupFileServiceProvider.overrideWithValue(files),
      ],
      child: const MaterialApp(home: BackupScreen()),
    ));
    await tester.ensureVisible(find.text('対局一覧'));
    await tester.tap(find.text('対局一覧'));
    await tester.pumpAndSettle();
    expect(files.savedName, startsWith('mahjong_games_'));
    expect(files.saved, startsWith('${CsvExport.bom}日時,'));
    expect(find.textContaining('CSV に書き出しました'), findsOneWidget);

    await tester.tap(find.text('局ごとの記録'));
    await tester.pumpAndSettle();
    expect(files.savedName, startsWith('mahjong_rounds_'));
  });
}
