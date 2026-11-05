import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mahjong_app/features/about/license_screen.dart';
import 'package:mahjong_app/features/about/privacy_policy.dart';

/// ストアに公開するための設定（アプリの ID・権限・署名・アイコン・プライバシーポリシー）
void main() {
  const appId = 'app.naashi.mahjong';

  group('アプリの ID', () {
    test('Android の applicationId と namespace、MainActivity のパッケージ', () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, contains('applicationId = "$appId"'));
      expect(gradle, contains('namespace = "$appId"'));
      expect(File('android/app/src/main/kotlin/app/naashi/mahjong/MainActivity.kt').readAsStringSync(),
          contains('package $appId'));
    });

    test('iOS の Bundle ID', () {
      final ids = RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);')
          .allMatches(File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync())
          .map((m) => m.group(1))
          .toSet();
      expect(ids, {appId, '$appId.RunnerTests'});
    });

    test('Flutter の初期値（com.example）が残っていない', () {
      for (final dir in ['android/app/src', 'ios/Runner', 'ios/Runner.xcodeproj']) {
        for (final f in Directory(dir).listSync(recursive: true).whereType<File>()) {
          if (!RegExp(r'\.(kt|kts|xml|plist|pbxproj|swift)$').hasMatch(f.path)) continue;
          expect(f.readAsStringSync(), isNot(contains('com.example')), reason: f.path);
        }
      }
    });
  });

  test('正式版のアプリはインターネットの権限を持たない（開発用の debug / profile だけ）', () {
    expect(File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
        isNot(contains('<uses-permission android:name="android.permission.INTERNET"/>')));
    expect(File('android/app/src/debug/AndroidManifest.xml').readAsStringSync(),
        contains('android.permission.INTERNET'));
  });

  test('正式版の署名は key.properties から読み、鍵はリポジトリに入れない', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('rootProject.file("key.properties")'));
    expect(gradle, contains('signingConfigs.getByName("release")'));
    final ignore = File('android/.gitignore').readAsLinesSync();
    expect(ignore, containsAll(['key.properties', '**/*.jks', '**/*.keystore']));
  });

  group('アイコン', () {
    img.Image png(String path) => img.decodePng(File(path).readAsBytesSync())!;

    test('iOS: Contents.json のすべての大きさがあり、透明な部分が無い', () {
      const dir = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
      final images = (jsonDecode(File('$dir/Contents.json').readAsStringSync())['images'] as List)
          .cast<Map<String, dynamic>>();
      for (final i in images) {
        final size = double.parse((i['size'] as String).split('x').first);
        final scale = int.parse((i['scale'] as String).replaceAll('x', ''));
        final p = png('$dir/${i['filename']}');
        expect(p.width, (size * scale).round(), reason: i['filename'] as String);
        expect(p.height, p.width);
        expect(p.numChannels, 3, reason: 'App Store は透明な部分のあるアイコンを受け付けない');
      }
    });

    test('Android: 各密度のアイコンとアダプティブアイコン', () {
      const sizes = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192};
      sizes.forEach((d, px) {
        expect(png('android/app/src/main/res/mipmap-$d/ic_launcher.png').width, px, reason: d);
        expect(png('android/app/src/main/res/mipmap-$d/ic_launcher_foreground.png').width, px * 108 ~/ 48, reason: d);
      });
      final adaptive = File('android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml').readAsStringSync();
      expect(adaptive, contains('@color/ic_launcher_background'));
      expect(adaptive, contains('@mipmap/ic_launcher_foreground'));
    });

    test('Web とストア用', () {
      expect(png('web/icons/Icon-512.png').width, 512);
      expect(png('web/icons/Icon-maskable-512.png').width, 512);
      expect(png('store/icon-512.png').width, 512);
      final manifest = jsonDecode(File('web/manifest.json').readAsStringSync()) as Map<String, dynamic>;
      expect(manifest['theme_color'], '#1B5E20');
    });
  });

  group('プライバシーポリシー', () {
    test('Web 版のページ（web/privacy.html）とアプリ内の画面の内容がそろっている', () {
      final html = File('web/privacy.html').readAsStringSync();
      String plain(String s) => s.replaceAll(RegExp(r'<[^>]+>'), '').replaceAll(RegExp(r'\s+'), '');
      final page = plain(html);
      expect(page, contains(plain(PrivacyPolicy.intro)));
      for (final (heading, body) in PrivacyPolicy.sections) {
        expect(html, contains('<h2>$heading</h2>'), reason: heading);
        // 本文（URL の部分は HTML ではリンクになっているので、文の部分で比べる）
        expect(page, contains(plain(body.split('\n').first)), reason: heading);
      }
      expect(html, contains(PrivacyPolicy.contactUrl));
      expect(html, contains(PrivacyPolicy.githubPrivacyUrl));
      expect(html, contains(PrivacyPolicy.googlePrivacyUrl));
      expect(html, contains('制定日: ${PrivacyPolicy.enactedOn}'));
      // GitHub Pages では /<リポジトリ名>/ の下で動くので、/ から始まるパスを使わない
      expect(RegExp(r'''(href|src)="/[^/]''').hasMatch(html), isFalse);
    });

    testWidgets('ライセンス画面から開ける', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 2000));
      await tester.pumpWidget(const MaterialApp(home: LicenseScreen()));
      await tester.tap(find.text('プライバシーポリシー'));
      await tester.pumpAndSettle();
      expect(find.byType(PrivacyPolicyScreen), findsOneWidget);
      expect(find.text('1. 集める情報'), findsOneWidget);
      await tester.scrollUntilVisible(find.textContaining(PrivacyPolicy.contactUrl), 300);
      expect(find.textContaining(PrivacyPolicy.contactUrl), findsOneWidget);
    });
  });
}
