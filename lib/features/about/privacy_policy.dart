import 'package:flutter/material.dart';

import '../../core/l10n.dart';

/// プライバシーポリシー。
///
/// 同じ内容を web/privacy.html にも書いている（GitHub Pages で公開し、ストアに登録する URL にする）。
/// 変えるときは両方を直す（test/privacy_policy_test.dart で、見出しと問い合わせ先がそろっているかを確かめている）。
class PrivacyPolicy {
  PrivacyPolicy._();

  static const appName = '麻雀点数計算';
  static const enactedOn = '2026年11月5日';
  static const contactUrl = 'https://github.com/nkoki/mahjong/issues';
  static const githubPrivacyUrl =
      'https://docs.github.com/ja/site-policy/privacy-policies/github-general-privacy-statement';
  static const googlePrivacyUrl = 'https://policies.google.com/privacy?hl=ja';

  static const intro = '「$appName」（以下「このアプリ」）は、利用者の個人情報やプライバシーに関わる情報を、'
      '開発者が集めることはありません。このアプリでの情報の扱いは次のとおりです。';

  /// （見出し, 本文）
  static const sections = [
    (
      '1. 集める情報',
      '開発者は、利用者の情報を集めません。アカウントの登録もありません。',
    ),
    (
      '2. 端末に保存する情報',
      '対局の記録（プレイヤーの名前・点数・局の記録）、ルール設定、表示の設定は、利用者の端末の中'
          '（Web 版ではブラウザの中）だけに保存し、開発者を含む外部には送りません。'
          'アプリを削除する（Web 版ではブラウザのサイトデータを消す）と、これらのデータは消えます。',
    ),
    (
      '3. カメラと写真',
      'カメラ認識で撮影した写真や選んだ写真は、端末の中にある認識モデルで牌を読み取るためだけに使い、'
          '保存も送信もしません。カメラや写真は、利用者がカメラ認識のボタンを押したときだけ使います。',
    ),
    (
      '4. 通信',
      'スマホのアプリ版には、インターネットで通信する機能はありません（Android 版はインターネットの権限を持っていません）。'
          'Web 版は GitHub Pages から配信していて、ページを開くときに GitHub がアクセスの記録（IP アドレスなど）を'
          '残すことがあります。その扱いは GitHub のプライバシーステートメントのとおりです。'
          'また Web 版は、日本語などの文字を表示するためのフォントを Google Fonts から読み込むので、'
          'Google にもアクセスの記録が残ることがあります。その扱いは Google のプライバシーポリシーのとおりです。',
    ),
    (
      '5. バックアップと CSV',
      '書き出したバックアップや CSV のファイル、コピーしたテキスト、共有した結果の画像には、プレイヤーの名前と対局の記録が入ります。'
          '保存先や送り先は利用者が選び、このアプリが自動で送ることはありません。',
    ),
    (
      '6. 広告と利用状況の解析',
      '広告や、利用状況を解析するツール（アクセス解析など）は使っていません。',
    ),
    (
      '7. 第三者への提供',
      '情報を集めないため、第三者に提供することもありません。',
    ),
    (
      '8. お子さまの情報',
      '年齢に関係なく、利用者の情報を集めません。',
    ),
    (
      '9. このポリシーの変更',
      'このポリシーを変えるときは、アプリ内のこの画面と、Web 版のプライバシーポリシーのページでお知らせします。',
    ),
    (
      '10. お問い合わせ',
      'このアプリやこのポリシーについてのお問い合わせは、次のページ（GitHub の Issues）で受け付けています。\n$contactUrl',
    ),
  ];

  /// 英語の制定日
  static const enactedOnEn = 'November 5, 2026';

  /// [intro] の英語版（正式なものは日本語版）
  static const introEn = '"Mahjong Score" (hereinafter "this app") does not have its developer collect any personal '
      'information or privacy-related information about its users. This app handles information as follows.';

  /// [sections] の英語版（正式なものは日本語版）
  static const sectionsEn = [
    (
      '1. Information collected',
      'The developer does not collect any user information. There is no account registration.',
    ),
    (
      '2. Information stored on the device',
      'Game records (player names, points and hand records), rule settings and display settings are stored only on '
          'your device (in the browser for the web version) and are never sent outside, including to the developer. '
          'Deleting the app (clearing the browser site data for the web version) deletes this data.',
    ),
    (
      '3. Camera and photos',
      'Photos taken or selected for camera recognition are used only to read tiles with the recognition model on '
          'the device, and are neither saved nor sent. The camera and photos are used only when you press the camera '
          'recognition button.',
    ),
    (
      '4. Network communication',
      'The smartphone app has no feature that communicates over the internet (the Android version does not have '
          'the internet permission). The web version is served from GitHub Pages, and GitHub may keep access logs '
          '(such as IP addresses) when the page is opened. These are handled according to the GitHub Privacy Statement. '
          'The web version also loads fonts from Google Fonts to display Japanese and other characters, so Google may '
          'also keep access logs. These are handled according to the Google Privacy Policy.',
    ),
    (
      '5. Backups and CSV',
      'Exported backup and CSV files, copied text and shared result images contain player names and game records. '
          'You choose where they are saved or sent; this app never sends them automatically.',
    ),
    (
      '6. Advertising and usage analytics',
      'This app uses no advertising and no tools that analyze usage (such as access analytics).',
    ),
    (
      '7. Disclosure to third parties',
      'Since no information is collected, none is provided to third parties.',
    ),
    (
      "8. Children's information",
      'Regardless of age, no user information is collected.',
    ),
    (
      '9. Changes to this policy',
      'When this policy changes, it will be announced on this screen in the app and on the privacy policy page of '
          'the web version.',
    ),
    (
      '10. Contact',
      'Questions about this app or this policy are accepted on the following page (GitHub Issues).\n$contactUrl',
    ),
  ];
}

/// プライバシーポリシーの画面
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr('プライバシーポリシー', 'Privacy policy'))),
      body: SelectionArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (L10n.isEnglish) ...[
              Text('This is a translation for reference. The Japanese version is the official privacy policy.',
                  style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
              const SizedBox(height: 12),
            ],
            Text(tr(PrivacyPolicy.intro, PrivacyPolicy.introEn), style: theme.textTheme.bodyMedium),
            for (final (heading, body) in L10n.isEnglish ? PrivacyPolicy.sectionsEn : PrivacyPolicy.sections) ...[
              const SizedBox(height: 16),
              Text(heading, style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(body, style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: 16),
            Text(
                tr('GitHub のプライバシーステートメント: ${PrivacyPolicy.githubPrivacyUrl}',
                    'GitHub Privacy Statement: ${PrivacyPolicy.githubPrivacyUrl}'),
                style: theme.textTheme.bodySmall),
            Text(
                tr('Google のプライバシーポリシー: ${PrivacyPolicy.googlePrivacyUrl}',
                    'Google Privacy Policy: ${PrivacyPolicy.googlePrivacyUrl}'),
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Text(tr('制定日: ${PrivacyPolicy.enactedOn}', 'Effective: ${PrivacyPolicy.enactedOnEn}'),
                style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
