import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../backup/backup_screen.dart';
import '../session/domain/session_logic.dart';
import '../session/session_providers.dart';

/// 保存状況の表示（ホーム画面と「データの保存について」画面で使う）
class StorageUsageView extends ConsumerWidget {
  /// 上限の説明文まで表示するか
  final bool detailed;
  const StorageUsageView({super.key, this.detailed = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sessionsProvider);
    final usage = ref.read(sessionRepositoryProvider).usage();
    final theme = Theme.of(context);
    final warnColor = theme.colorScheme.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
            '保存中の対局: ${sessions.length} / ${SessionLogic.maxSavedSessions}件'
            '（${formatBytes(usage.bytes)}）',
            style: theme.textTheme.bodyMedium),
        if (sessions.length >= SessionLogic.maxSavedSessions)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '上限に達しています。新しい対局を始めると、お気に入りにしていない一番古い対局が削除されます。',
              style: theme.textTheme.bodySmall?.copyWith(color: warnColor),
            ),
          ),
        if (usage.ratio != null) ...[
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: usage.ratio,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
            color: usage.isNearLimit ? warnColor : null,
          ),
          const SizedBox(height: 4),
          Text(
            'ブラウザの保存容量の上限（目安 ${formatBytes(usage.limitBytes!)}）の'
            '${(usage.ratio! * 100).toStringAsFixed(usage.ratio! < 0.1 ? 1 : 0)}%を使用中',
            style: theme.textTheme.bodySmall?.copyWith(
                color: usage.isNearLimit ? warnColor : null),
          ),
          if (usage.isNearLimit)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '上限に近づいています。上限を超えると新しい対局を保存できなくなるので、'
                '不要な対局を戦績画面から削除してください。',
                style: theme.textTheme.bodySmall?.copyWith(color: warnColor),
              ),
            ),
        ],
      ],
    );
  }
}

/// 「データの保存について」画面（保存の仕組みと注意点）
class StorageInfoScreen extends ConsumerWidget {
  const StorageInfoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    Widget item(IconData icon, String title, String body, {bool warn = false}) {
      return ListTile(
        leading: Icon(icon, color: warn ? theme.colorScheme.error : theme.colorScheme.primary),
        title: Text(title, style: theme.textTheme.titleSmall),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(body),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('データの保存について')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: StorageUsageView(detailed: true),
              ),
            ),
          ),
          const SizedBox(height: 8),
          item(Icons.save_outlined, '自動で保存されます',
              '立直・和了・流局・元に戻す・削除など、操作のたびに自動で保存されます。'
              '保存ボタンはありません。アプリを閉じても、次に開いたときに「続きから」再開できます。'),
          item(Icons.inventory_2_outlined, '保存されるのは最新100対局まで',
              '対局が100件を超えると、新しい対局を始めたときに、お気に入り（★）にしていない'
              '一番古い対局から自動で削除されます（削除する前に確認が表示されます）。'
              '残したい対局は、戦績画面で ★ を押してお気に入りにしてください。'
              '対局中の対局は削除されません。',
              warn: true),
          item(Icons.phone_android, 'この端末だけに保存されます',
              '保存先はこの端末（Web 版ではこのブラウザ）の中だけです。'
              'インターネット上には保存されないので、他のスマホ・パソコン・ブラウザとは共有されません。'),
          item(
              Icons.warning_amber_rounded,
              '次の場合はデータが消えます',
              kIsWeb
                  ? '・ブラウザの閲覧履歴やサイトデータ（Cookie など）を消したとき\n'
                      '・シークレットモード（プライベートブラウズ）で使い、画面を閉じたとき\n'
                      '・別のブラウザや別の端末で開いたとき（データは見えません）\n'
                      '・iPhone・iPad の Safari で、7日間このページを開かなかったとき'
                      '（Safari の仕組みです。共有ボタンから「ホーム画面に追加」して、'
                      'そのアイコンから使うと対象外になります）'
                  : '・アプリをアンインストールしたとき\n'
                      '・端末の設定からアプリのデータ（ストレージ）を消去したとき\n'
                      '・機種変更したとき（データは引き継がれません）',
              warn: true),
          ListTile(
            leading: Icon(Icons.backup_outlined, color: theme.colorScheme.primary),
            title: Text('バックアップできます', style: theme.textTheme.titleSmall),
            subtitle: const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('データが消えたときに備えて、ときどきバックアップを書き出して別の場所に保存してください。'
                  '機種変更のときも、バックアップを新しい端末で読み込めば引き継げます。'),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const BackupScreen())),
          ),
          if (kIsWeb)
            item(Icons.storage_outlined, '保存容量の上限があります（Web 版）',
                'ブラウザに保存できる量は1サイトあたり約5MBまでです。'
                '1対局（半荘）あたり約5KBなので、100対局でも約0.5MBで収まります。'
                'お気に入りを大量に残した場合などで上限に近づくと、ホーム画面でお知らせします。'),
          item(Icons.undo, '「元に戻す」は、開き直すと直近10回まで',
              'アプリを使っている間は何回でも元に戻せますが、アプリを閉じて開き直したあとに'
              '元に戻せるのは、直近10回分の操作までです。'),
          item(Icons.key_outlined, 'カメラ認識の API キーはバックアップに入りません',
              'カメラ認識の設定（API キー）はこの端末の中にだけ保存され、バックアップには入りません。'
              '機種変更したときは、新しい端末でもう一度入力してください。'),
          item(Icons.delete_outline, '削除した対局は元に戻せません',
              '戦績画面から対局を削除すると、その対局の記録は完全に消えます。', warn: true),
          item(Icons.healing_outlined, 'データが壊れていた場合',
              '保存データの一部が壊れていて読み込めなかった場合は、ホーム画面でお知らせします。'
              '壊れたデータは消さずに端末内に残しています。'),
        ],
      ),
    );
  }
}
