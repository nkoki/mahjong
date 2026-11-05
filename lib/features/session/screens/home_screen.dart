import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n.dart';
import '../../../core/routes.dart';
import '../../../core/theme.dart';
import '../../about/license_screen.dart';
import '../../history/history_list_screen.dart';
import '../../practice/practice_screen.dart';
import '../../score_table/score_table_screen.dart';
import '../../stats/stats_screen.dart';
import '../../backup/backup_screen.dart';
import '../../settings/display_settings.dart';
import '../../settings/rule_settings_screen.dart';
import '../../storage/storage_info_screen.dart';
import '../session_providers.dart';
import 'new_session_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ongoing =
        ref.watch(sessionsProvider).where((s) => !s.finished).toList();
    final theme = Theme.of(context);
    final saveError = ref.watch(saveErrorProvider);
    final warnings = ref.watch(loadWarningsProvider);
    void openInfo() => Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const StorageInfoScreen()));

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('麻雀点数計算', 'Mahjong Scorer')),
        actions: [
          IconButton(
            tooltip: tr('ルール設定', 'Rules'),
            icon: const Icon(Icons.tune),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const RuleSettingsScreen())),
          ),
          IconButton(
            tooltip: tr('表示の設定（明るさ・文字の大きさ）', 'Display (theme, text size, language)'),
            icon: const Icon(Icons.brightness_6_outlined),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const DisplaySettingsScreen())),
          ),
          IconButton(
            tooltip: tr('データの保存について', 'About data storage'),
            icon: const Icon(Icons.info_outline),
            onPressed: openInfo,
          ),
          IconButton(
            tooltip: tr('ライセンス・データの出典', 'Licenses & data sources'),
            icon: const Icon(Icons.description_outlined),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const LicenseScreen())),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (saveError != null)
            _NoticeCard(
              icon: Icons.error_outline,
              message: saveError,
              error: true,
              onTap: openInfo,
            ),
          for (var i = 0; i < warnings.length; i++)
            _NoticeCard(
              icon: Icons.warning_amber_rounded,
              message: warnings[i],
              onClose: () => ref.read(loadWarningsProvider.notifier).state = [
                for (var j = 0; j < warnings.length; j++)
                  if (j != i) warnings[j]
              ],
            ),
          const SizedBox(height: 16),
          Icon(Icons.grid_view_rounded, size: 72, color: theme.colorScheme.primary),
          const SizedBox(height: 8),
          Text(tr('4人打ち 点数計算・対局管理', '4-player scoring & game manager'),
              textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
          const SizedBox(height: 32),
          FilledButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: Text(tr('新規対局', 'New game')),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NewSessionScreen()),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
            icon: const Icon(Icons.history),
            label: Text(tr('戦績', 'Records')),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HistoryListScreen()),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
            icon: const Icon(Icons.leaderboard_outlined),
            label: Text(tr('個人成績', 'Player stats')),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const StatsScreen()),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
            icon: const Icon(Icons.table_chart_outlined),
            label: Text(tr('点数早見表', 'Score table')),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ScoreTableScreen()),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
            icon: const Icon(Icons.school_outlined),
            label: Text(tr('点数計算の練習', 'Scoring practice')),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PracticeScreen()),
            ),
          ),
          if (ongoing.isNotEmpty) ...[
            const SizedBox(height: 32),
            Text(tr('対局中（続きから）', 'In progress (continue)'), style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final s in ongoing)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.casino_outlined),
                  title: Text(s.playerNames.join(' / ')),
                  subtitle: Text(
                      '${displayRoundLabel(s.roundLabel)}  ${tr('供託${s.riichiSticks}本', 'Riichi sticks: ${s.riichiSticks}')}\n'
                      '${[for (final v in s.scores) formatPoints(v)].join(' / ')}'),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(dashboardRoute(s.id)),
                ),
              ),
          ],
          const SizedBox(height: 32),
          Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: openInfo,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.save_outlined, size: 20, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(tr('データの保存について', 'About data storage'), style: theme.textTheme.titleSmall),
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tr(
                          '対局データはこの端末に自動で保存されます。'
                              'アプリを削除したり、ブラウザのデータを消したりすると消えてしまいます。',
                          'Game data is saved automatically on this device. '
                              'It will be lost if you uninstall the app or clear browser data.'),
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    const StorageUsageView(),
                    const Divider(height: 20),
                    _BackupRow(sessionCount: ref.watch(sessionsProvider).length),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// お知らせ（保存の失敗・読み込みの問題など）
class _NoticeCard extends StatelessWidget {
  final IconData icon;
  final String message;
  final bool error;
  final VoidCallback? onTap;
  final VoidCallback? onClose;

  const _NoticeCard({
    required this.icon,
    required this.message,
    this.error = false,
    this.onTap,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = error ? scheme.errorContainer : scheme.tertiaryContainer;
    final fg = error ? scheme.onErrorContainer : scheme.onTertiaryContainer;
    return Card(
      color: bg,
      child: ListTile(
        leading: Icon(icon, color: fg),
        title: Text(message, style: TextStyle(color: fg, fontSize: 14)),
        onTap: onTap,
        trailing: onClose == null
            ? null
            : IconButton(
                tooltip: tr('閉じる', 'Close'),
                icon: Icon(Icons.close, color: fg),
                onPressed: onClose,
              ),
      ),
    );
  }
}

/// バックアップの状況とボタン
class _BackupRow extends ConsumerWidget {
  final int sessionCount;
  const _BackupRow({required this.sessionCount});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final last = ref.watch(lastBackupProvider);
    final recommend = shouldRecommendBackup(sessionCount, last);
    return Row(
      children: [
        Icon(recommend ? Icons.warning_amber_rounded : Icons.backup_outlined,
            size: 20, color: recommend ? theme.colorScheme.error : theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            last == null
                ? tr('まだバックアップしていません', 'No backup yet')
                : tr('最後のバックアップ: ${formatDateTime(last)}', 'Last backup: ${formatDateTime(last)}') +
                    (recommend ? tr('（30日以上前）', ' (over 30 days ago)') : ''),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: recommend ? theme.colorScheme.error : null),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const BackupScreen())),
          child: Text(tr('バックアップ', 'Backup')),
        ),
      ],
    );
  }
}
