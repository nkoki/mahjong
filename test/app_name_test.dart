import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// アプリ名が各プラットフォームの設定でそろっているか
void main() {
  const name = '麻雀点数計算';

  test('Android', () {
    expect(File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
        contains('android:label="$name"'));
  });

  test('iOS', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(plist, contains('<key>CFBundleDisplayName</key>\n\t<string>$name</string>'));
    expect(plist, contains('<key>CFBundleName</key>\n\t<string>$name</string>'));
  });

  test('Web', () {
    final html = File('web/index.html').readAsStringSync();
    expect(html, contains('<title>$name</title>'));
    expect(html, contains('apple-mobile-web-app-title" content="$name"'));
    final manifest =
        jsonDecode(File('web/manifest.json').readAsStringSync()) as Map<String, dynamic>;
    expect(manifest['name'], name);
    expect(manifest['short_name'], name);
  });

  test('アプリ内のタイトル', () {
    expect(File('lib/main.dart').readAsStringSync(), contains("title: '$name'"));
  });
}
