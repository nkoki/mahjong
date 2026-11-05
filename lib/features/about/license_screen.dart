import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import 'data_sources.dart';
import 'privacy_policy.dart';

/// ライセンス・データの出典の画面
class LicenseScreen extends StatelessWidget {
  const LicenseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr('ライセンス・データの出典', 'Licenses & data sources'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: Text(tr('プライバシーポリシー', 'Privacy policy')),
              subtitle: Text(tr('情報は集めません。対局の記録は端末の中だけに保存し、写真も送りません',
                  'No data is collected. Game records stay on your device, and photos are never sent')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen())),
            ),
          ),
          const SizedBox(height: 16),
          Text(tr('カメラ認識（牌の認識モデル）', 'Camera recognition (tile recognition model)'),
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(tr(
              '手牌の写真の読み取りは、アプリに入っている認識モデルで、この端末の中で行います。'
                  '写真はどこにも送らず、料金もかかりません（Android・iOS のアプリ版のみ。Web 版では使えません）。'
                  '認識モデルは、次のデータを使って学習させたものです。',
              'Hand photos are read on this device by the recognition model built into the app. '
                  'Photos are never sent anywhere and it is free (Android and iOS apps only; not available on the web version). '
                  'The model was trained with the following data.')),
          const SizedBox(height: 12),
          Text(tr('学習データ', 'Training data'), style: theme.textTheme.titleSmall),
          for (final s in trainingDataSources) _SourceCard(s),
          const SizedBox(height: 12),
          Text(tr('モデルの作成に使った道具', 'Tools used to build the model'), style: theme.textTheme.titleSmall),
          for (final s in modelToolSources) _SourceCard(s),
          const SizedBox(height: 20),
          Text(tr('アプリで使っているソフトウェア', 'Software used in the app'), style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(tr('Flutter や、アプリに組み込んでいるパッケージ（TensorFlow Lite など）のライセンスです。',
              'Licenses of Flutter and the packages built into the app (such as TensorFlow Lite).')),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.article_outlined),
              label: Text(tr('オープンソースライセンスを見る', 'View open source licenses')),
              onPressed: () => showLicensePage(
                context: context,
                applicationName: tr('麻雀点数計算', 'Mahjong Score'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  final DataSource source;

  const _SourceCard(this.source);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SelectionArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(source.title, style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(tr('作成者: ${source.author}', 'Author: ${source.author}')),
              Text(tr('出典: ${source.url}', 'Source: ${source.url}')),
              Text(tr('ライセンス: ${source.license}', 'License: ${source.license}')),
              Text(source.licenseUrl, style: theme.textTheme.bodySmall),
              if (source.changes != null) ...[
                const SizedBox(height: 4),
                Text(tr('変更: ${source.changes}', 'Changes: ${source.changes}'), style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
