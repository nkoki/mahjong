import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_app/main.dart';
import 'package:mahjong_app/shared/widgets/app_mark.dart';
import 'package:mahjong_app/shared/widgets/tile_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// アプリの印（アイコンと同じ、上から見た卓）
void main() {
  testWidgets('ホーム画面の見出しにアプリの印を出し、牌の絵は使わない', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ProviderScope(child: MahjongApp()));
    await tester.pumpAndSettle();
    expect(find.byType(AppMark), findsOneWidget);
    expect(find.byType(TileView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('どの大きさでも描ける', (tester) async {
    for (final size in [16.0, 48.0, 120.0]) {
      await tester.pumpWidget(Center(child: AppMark(size: size)));
      expect(tester.getSize(find.byType(AppMark)), Size.square(size));
    }
  });

  test('アイコンを作る道具は、アプリの印と同じデザイン（牌を使わない卓の絵）', () {
    final src = File('tools/app_icon/make_icons.py').readAsStringSync();
    expect(src, contains('def table_layer'));
    expect(src, isNot(contains('tile_layer')));
  });
}
