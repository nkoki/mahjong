import 'package:flutter/material.dart';

import 'data_sources.dart';

/// ライセンス・データの出典の画面
class LicenseScreen extends StatelessWidget {
  const LicenseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('ライセンス・データの出典')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('カメラ認識（牌の認識モデル）', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          const Text('手牌の写真の読み取りは、アプリに入っている認識モデルで、この端末の中で行います。'
              '写真はどこにも送らず、料金もかかりません（Android・iOS のアプリ版のみ。Web 版では使えません）。'
              '認識モデルは、次のデータを使って学習させたものです。'),
          const SizedBox(height: 12),
          Text('学習データ', style: theme.textTheme.titleSmall),
          for (final s in trainingDataSources) _SourceCard(s),
          const SizedBox(height: 12),
          Text('モデルの作成に使った道具', style: theme.textTheme.titleSmall),
          for (final s in modelToolSources) _SourceCard(s),
          const SizedBox(height: 20),
          Text('アプリで使っているソフトウェア', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          const Text('Flutter や、アプリに組み込んでいるパッケージ（TensorFlow Lite など）のライセンスです。'),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.article_outlined),
              label: const Text('オープンソースライセンスを見る'),
              onPressed: () => showLicensePage(
                context: context,
                applicationName: '麻雀点数計算',
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
              Text('作成者: ${source.author}'),
              Text('出典: ${source.url}'),
              Text('ライセンス: ${source.license}'),
              Text(source.licenseUrl, style: theme.textTheme.bodySmall),
              if (source.changes != null) ...[
                const SizedBox(height: 4),
                Text('変更: ${source.changes}', style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
