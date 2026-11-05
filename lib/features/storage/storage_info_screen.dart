import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
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
            tr(
                '保存中の対局: ${sessions.length} / ${SessionLogic.maxSavedSessions}件'
                    '（${formatBytes(usage.bytes)}）',
                'Saved games: ${sessions.length} / ${SessionLogic.maxSavedSessions}'
                    ' (${formatBytes(usage.bytes)})'),
            style: theme.textTheme.bodyMedium),
        if (sessions.length >= SessionLogic.maxSavedSessions)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              tr('上限に達しています。新しい対局を始めると、お気に入りにしていない一番古い対局が削除されます。',
                  'The limit has been reached. Starting a new game deletes the oldest non-favorite game.'),
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
            tr(
                'ブラウザの保存容量の上限（目安 ${formatBytes(usage.limitBytes!)}）の'
                    '${(usage.ratio! * 100).toStringAsFixed(usage.ratio! < 0.1 ? 1 : 0)}%を使用中',
                'Using ${(usage.ratio! * 100).toStringAsFixed(usage.ratio! < 0.1 ? 1 : 0)}% of the browser storage limit'
                    ' (approx. ${formatBytes(usage.limitBytes!)})'),
            style: theme.textTheme.bodySmall?.copyWith(
                color: usage.isNearLimit ? warnColor : null),
          ),
          if (usage.isNearLimit)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                tr(
                    '上限に近づいています。上限を超えると新しい対局を保存できなくなるので、'
                        '不要な対局を戦績画面から削除してください。',
                    'Approaching the limit. Beyond it, new games cannot be saved, '
                        'so please delete games you no longer need from the history screen.'),
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
      appBar: AppBar(title: Text(tr('データの保存について', 'About data storage'))),
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
          item(
              Icons.save_outlined,
              tr('自動で保存されます', 'Saved automatically'),
              tr(
                  '立直・和了・流局・元に戻す・削除など、操作のたびに自動で保存されます。'
                      '保存ボタンはありません。アプリを閉じても、次に開いたときに「続きから」再開できます。',
                  'Every action (riichi, win, draw, undo, delete, etc.) is saved automatically. '
                      'There is no save button. Even if you close the app, you can "Continue" next time.')),
          item(
              Icons.inventory_2_outlined,
              tr('保存されるのは最新100対局まで', 'Only the latest 100 games are kept'),
              tr(
                  '対局が100件を超えると、新しい対局を始めたときに、お気に入り（★）にしていない'
                      '一番古い対局から自動で削除されます（削除する前に確認が表示されます）。'
                      '残したい対局は、戦績画面で ★ を押してお気に入りにしてください。'
                      '対局中の対局は削除されません。',
                  'When there are more than 100 games, starting a new game automatically deletes '
                      'the oldest game that is not a favorite (★) (you are asked to confirm first). '
                      'To keep a game, tap ★ on the history screen to make it a favorite. '
                      'Games in progress are not deleted.'),
              warn: true),
          item(
              Icons.phone_android,
              tr('この端末だけに保存されます', 'Stored only on this device'),
              tr(
                  '保存先はこの端末（Web 版ではこのブラウザ）の中だけです。'
                      'インターネット上には保存されないので、他のスマホ・パソコン・ブラウザとは共有されません。',
                  'Data is stored only on this device (on the web version, in this browser). '
                      'It is not stored online, so it is not shared with other phones, computers, or browsers.')),
          item(
              Icons.warning_amber_rounded,
              tr('次の場合はデータが消えます', 'Data is lost when'),
              kIsWeb
                  ? tr(
                      '・ブラウザの閲覧履歴やサイトデータ（Cookie など）を消したとき\n'
                          '・シークレットモード（プライベートブラウズ）で使い、画面を閉じたとき\n'
                          '・別のブラウザや別の端末で開いたとき（データは見えません）\n'
                          '・iPhone・iPad の Safari で、7日間このページを開かなかったとき'
                          '（Safari の仕組みです。共有ボタンから「ホーム画面に追加」して、'
                          'そのアイコンから使うと対象外になります）',
                      '- You clear browsing history or site data (cookies, etc.)\n'
                          '- You use private/incognito mode and close the page\n'
                          '- You open it in another browser or on another device (the data is not visible)\n'
                          '- In Safari on iPhone/iPad, you do not open this page for 7 days '
                          '(a Safari policy; it does not apply if you use "Add to Home Screen" from the share button '
                          'and open the app from that icon)')
                  : tr(
                      '・アプリをアンインストールしたとき\n'
                          '・端末の設定からアプリのデータ（ストレージ）を消去したとき\n'
                          '・機種変更したとき（データは引き継がれません）',
                      '- You uninstall the app\n'
                          '- You clear the app data (storage) in the device settings\n'
                          '- You change devices (data is not transferred)'),
              warn: true),
          ListTile(
            leading: Icon(Icons.backup_outlined, color: theme.colorScheme.primary),
            title: Text(tr('バックアップできます', 'You can make a backup'), style: theme.textTheme.titleSmall),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(tr(
                  'データが消えたときに備えて、ときどきバックアップを書き出して別の場所に保存してください。'
                      '機種変更のときも、バックアップを新しい端末で読み込めば引き継げます。',
                  'In case data is lost, export a backup from time to time and keep it somewhere else. '
                      'When changing devices, import the backup on the new device to transfer your data.')),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const BackupScreen())),
          ),
          if (kIsWeb)
            item(
                Icons.storage_outlined,
                tr('保存容量の上限があります（Web 版）', 'Storage is limited (web version)'),
                tr(
                    'ブラウザに保存できる量は1サイトあたり約5MBまでです。'
                        '1対局（半荘）あたり約5KBなので、100対局でも約0.5MBで収まります。'
                        'お気に入りを大量に残した場合などで上限に近づくと、ホーム画面でお知らせします。',
                    'A browser can store about 5 MB per site. '
                        'One game (hanchan) takes about 5 KB, so even 100 games fit in about 0.5 MB. '
                        'If you approach the limit (e.g. by keeping many favorites), the home screen will tell you.')),
          item(
              Icons.undo,
              tr('「元に戻す」は、開き直すと直近10回まで', 'After reopening, undo goes back only 10 steps'),
              tr(
                  'アプリを使っている間は何回でも元に戻せますが、アプリを閉じて開き直したあとに'
                      '元に戻せるのは、直近10回分の操作までです。',
                  'While using the app you can undo any number of times, but after closing and reopening '
                      'the app you can undo only the last 10 actions.')),
          item(
              Icons.key_outlined,
              tr('カメラ認識の API キーはバックアップに入りません', 'The camera recognition API key is not backed up'),
              tr(
                  'カメラ認識の設定（API キー）はこの端末の中にだけ保存され、バックアップには入りません。'
                      '機種変更したときは、新しい端末でもう一度入力してください。',
                  'The camera recognition setting (API key) is stored only on this device and is not included in backups. '
                      'When you change devices, enter it again on the new device.')),
          item(
              Icons.delete_outline,
              tr('削除した対局は元に戻せません', 'Deleted games cannot be restored'),
              tr('戦績画面から対局を削除すると、その対局の記録は完全に消えます。',
                  'Deleting a game from the history screen permanently erases its records.'),
              warn: true),
          item(
              Icons.healing_outlined,
              tr('データが壊れていた場合', 'If data is corrupted'),
              tr(
                  '保存データの一部が壊れていて読み込めなかった場合は、ホーム画面でお知らせします。'
                      '壊れたデータは消さずに端末内に残しています。',
                  'If part of the saved data is corrupted and cannot be loaded, the home screen will tell you. '
                      'The corrupted data is kept on the device, not deleted.')),
        ],
      ),
    );
  }
}
