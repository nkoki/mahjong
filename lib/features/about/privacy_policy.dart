import 'package:flutter/material.dart';

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
          '残すことがあります。その扱いは GitHub のプライバシーステートメントのとおりです。',
    ),
    (
      '5. バックアップと CSV',
      '書き出したバックアップや CSV のファイル、コピーしたテキストには、プレイヤーの名前と対局の記録が入ります。'
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
}

/// プライバシーポリシーの画面
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('プライバシーポリシー')),
      body: SelectionArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(PrivacyPolicy.intro, style: theme.textTheme.bodyMedium),
            for (final (heading, body) in PrivacyPolicy.sections) ...[
              const SizedBox(height: 16),
              Text(heading, style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(body, style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: 16),
            Text('GitHub のプライバシーステートメント: ${PrivacyPolicy.githubPrivacyUrl}', style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Text('制定日: ${PrivacyPolicy.enactedOn}', style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
