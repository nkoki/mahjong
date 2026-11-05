import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_app/shared/widgets/tile_painter.dart';
import 'package:mahjong_app/shared/widgets/tile_view.dart';

/// 牌の表示
void main() {
  final all = [
    for (final s in ['m', 'p', 's']) ...[for (var i = 1; i <= 9; i++) '$i$s', '5${s}r'],
    for (var i = 1; i <= 7; i++) '${i}z',
  ];

  test('読み上げ用の名前', () {
    expect(tileSpokenName('5m'), '5萬');
    expect(tileSpokenName('5pr'), '赤5筒');
    expect(tileSpokenName('1s'), '1索');
    expect(tileSpokenName('6z'), '發');
  });

  testWidgets('すべての牌を、大きさ・向きを変えても描ける。読み上げの名前が付く', (tester) async {
    for (final width in [20.0, 32.0, 64.0]) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Wrap(children: [
            for (final t in all) TileView(t, width: width, selected: t == '1z', sideways: t == '2z', dimmed: t == '3z'),
          ]),
        ),
      ));
      expect(tester.takeException(), isNull);
    }
    expect(find.bySemanticsLabel('赤5萬'), findsOneWidget);
    expect(find.bySemanticsLabel('中'), findsOneWidget);
  });

  testWidgets('押せる牌は押すと知らせ、薄い表示（残りなし）の牌は押せない', (tester) async {
    var tapped = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Row(children: [
        TileView('1m', onTap: () => tapped.add('1m')),
        TileView('2m', dimmed: true, onTap: () => tapped.add('2m')),
      ]),
    ));
    await tester.tap(find.bySemanticsLabel('1萬'));
    await tester.tap(find.bySemanticsLabel('2萬'), warnIfMissed: false);
    expect(tapped, ['1m']);
    final size = tester.getSize(find.bySemanticsLabel('1萬'));
    expect(size.height / size.width, closeTo(1.35, 0.01));
  });
}
