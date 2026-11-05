import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mahjong_app/features/history/history_detail_screen.dart';
import 'package:mahjong_app/features/history/result_image.dart';
import 'package:mahjong_app/features/session/data/session_repository.dart';
import 'package:mahjong_app/features/session/session_providers.dart';

import 'player_stats_test.dart' show playedGame;

class FakeSharer implements ImageSharer {
  Uint8List? png;
  String? fileName;

  @override
  Future<void> share(Uint8List png, {required String fileName, required String title}) async {
    this.png = png;
    this.fileName = fileName;
  }
}

/// 結果を画像で共有
void main() {
  test('ファイル名に対局の日時を入れる', () {
    final s = playedGame('x', ['A', 'B', 'C', 'D'], at: DateTime(2026, 6, 1, 9, 5));
    expect(resultImageFileName(s), 'mahjong_20260601_0905.png');
  });

  testWidgets('戦績詳細の共有メニューから、結果の画像を作って共有する', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    final sharer = FakeSharer();
    final s = playedGame('x', ['A', 'B', 'C', 'D']);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sessionRepositoryProvider.overrideWithValue(InMemorySessionRepository([s])),
        imageSharerProvider.overrideWithValue(sharer),
      ],
      child: const MaterialApp(home: HistoryDetailScreen(sessionId: 'x')),
    ));
    await tester.tap(find.byTooltip('結果を共有（画像・テキスト）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('画像で共有'));
    await tester.pumpAndSettle();
    expect(find.byType(ResultCard), findsOneWidget);
    expect(find.descendant(of: find.byType(ResultCard), matching: find.text('対局結果')), findsOneWidget);
    // 画像にするのは実際の描画が要るので、runAsync の中で押す
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('share-image')));
      for (var i = 0; i < 50 && sharer.png == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pumpAndSettle();
    expect(sharer.fileName, 'mahjong_20260601_0000.png');
    final decoded = img.decodePng(sharer.png!)!;
    expect(decoded.width, ResultCard.width * 3, reason: '3倍の解像度');
    expect(find.byType(ResultCard), findsNothing, reason: '共有したら閉じる');
  });
}
