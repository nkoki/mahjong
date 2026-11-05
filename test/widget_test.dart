import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_app/main.dart';

void main() {
  testWidgets('新規対局を開始するとダッシュボードが表示される', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 860));
    await tester.pumpWidget(const ProviderScope(child: MahjongApp()));

    expect(find.text('新規対局'), findsOneWidget);
    await tester.tap(find.text('新規対局'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('対局開始'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('対局開始'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('対局開始'));
    await tester.pumpAndSettle();

    expect(find.text('東1局 0本場'), findsOneWidget);
    expect(find.text('25,000'), findsNWidgets(4));

    // 立直すると 24,000 になる
    await tester.tap(find.text('立直').first);
    await tester.pump();
    expect(find.text('24,000'), findsOneWidget);
    expect(find.textContaining('供託 1本'), findsOneWidget);
  });

  testWidgets('和了入力で手牌を入れて計算・確定できる', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    await tester.pumpWidget(const ProviderScope(child: MahjongApp()));
    await tester.tap(find.text('新規対局'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('対局開始'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('対局開始'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('対局開始'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('和了'));
    await tester.pumpAndSettle();

    // 和了者: 東 プレイヤー1（親）・ツモ
    await tester.tap(find.text('東 プレイヤー1').first);
    await tester.tap(find.text('ツモ'));
    await tester.pump();

    // 23m 456m 789p 234s 55s + 1m ツモ（平和・ツモ）
    Future<void> tapTile(String key) async {
      await tester.tap(find.byKey(ValueKey('palette-$key')));
      await tester.pump();
    }

    for (final t in ['2m', '3m', '4m', '5m', '6m', '7p', '8p', '9p', '2s', '3s', '4s', '5s', '5s']) {
      await tapTile(t);
    }
    await tapTile('1m'); // 和了牌
    await tester.tap(find.text('計算'));
    await tester.pumpAndSettle();

    expect(find.text('計算結果'), findsOneWidget);
    expect(find.text('平和'), findsOneWidget);
    expect(find.text('700オール'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('この結果で確定'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('この結果で確定'));
    await tester.pumpAndSettle();

    expect(find.text('東1局 1本場'), findsOneWidget);
    expect(find.text('27,100'), findsOneWidget);
  });
}
