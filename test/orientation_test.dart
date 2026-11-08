import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_app/main.dart';

/// 画面の向き（縦向きで使う）
void main() {
  test('アプリ版は縦向きに固定している（Android・iOS・Web のマニフェスト）', () {
    expect(File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
        contains('android:screenOrientation="portrait"'));
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    final iphone = RegExp(r'<key>UISupportedInterfaceOrientations</key>\s*<array>(.*?)</array>', dotAll: true)
        .firstMatch(plist)!
        .group(1)!;
    expect(iphone, contains('UIInterfaceOrientationPortrait'));
    expect(iphone, isNot(contains('Landscape')));
    final ipad = RegExp(r'<key>UISupportedInterfaceOrientations~ipad</key>\s*<array>(.*?)</array>', dotAll: true)
        .firstMatch(plist)!
        .group(1)!;
    expect(ipad, isNot(contains('Landscape')));
    expect(plist, contains('<key>UIRequiresFullScreen</key>'));
    expect(File('lib/main.dart').readAsStringSync(), contains('DeviceOrientation.portraitUp'));
    expect(File('web/manifest.json').readAsStringSync(), contains('"orientation": "portrait-primary"'));
  });

  test('お知らせを出すのはスマホを横向きにしたときだけ', () {
    expect(PortraitOnly.isPhoneLandscape(const Size(844, 390)), isTrue);
    expect(PortraitOnly.isPhoneLandscape(const Size(390, 844)), isFalse);
    expect(PortraitOnly.isPhoneLandscape(const Size(1280, 800)), isFalse, reason: 'パソコンのブラウザ・タブレット');
  });

  testWidgets('横向きにするとお知らせを重ね、縦に戻すと入力中の内容が残っている', (tester) async {
    final controller = TextEditingController();
    Widget app() => MaterialApp(
          builder: (context, child) => PortraitOnly(enabled: true, child: child!),
          home: Scaffold(body: TextField(key: const ValueKey('field'), controller: controller)),
        );
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpWidget(app());
    await tester.enterText(find.byKey(const ValueKey('field')), '入力中');
    expect(find.byKey(const ValueKey('portrait-only')), findsNothing);

    tester.view.physicalSize = const Size(844, 390);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('portrait-only')), findsOneWidget);

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('portrait-only')), findsNothing);
    expect(find.text('入力中'), findsOneWidget, reason: '画面は作り直されていない');
    final field = tester.state<EditableTextState>(find.byType(EditableText));
    expect(field.textEditingValue.text, '入力中');
  });
}
