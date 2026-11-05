import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
        title: const Text('麻雀点数計算'),
        actions: [
          IconButton(
            tooltip: 'ルール設定',
            icon: const Icon(Icons.tune),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const RuleSettingsScreen())),
          ),
          IconButton(
            tooltip: '表示の設定（明るさ・文字の大きさ）',
            icon: const Icon(Icons.brightness_6_outlined),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const DisplaySettingsScreen())),
          ),
          IconButton(
            tooltip: 'データの保存について',
            icon: const Icon(Icons.info_outline),
            onPressed: openInfo,
          ),
          IconButton(
            tooltip: 'ライセンス・データの出典',
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
          Text('4人打ち 点数計算・対局管理',
              textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
          const SizedBox(height: 32),
          FilledButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: const Text('新規対局'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NewSessionScreen()),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
            icon: const Icon(Icons.history),
            label: const Text('戦績'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HistoryListScreen()),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
            icon: const Icon(Icons.leaderboard_outlined),
            label: const Text('個人成績'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const StatsScreen()),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
            icon: const Icon(Icons.table_chart_outlined),
            label: const Text('点数早見表'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ScoreTableScreen()),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
            icon: const Icon(Icons.school_outlined),
            label: const Text('点数計算の練習'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PracticeScreen()),
            ),
          ),
          if (ongoing.isNotEmpty) ...[
            const SizedBox(height: 32),
            Text('対局中（続きから）', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final s in ongoing)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.casino_outlined),
                  title: Text(s.playerNames.join(' / ')),
                  subtitle: Text(
                      '${s.roundLabel}  供託${s.riichiSticks}本\n'
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
                          child: Text('データの保存について', style: theme.textTheme.titleSmall),
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '対局データはこの端末に自動で保存されます。'
                      'アプリを削除したり、ブラウザのデータを消したりすると消えてしまいます。',
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
                tooltip: '閉じる',
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
                ? 'まだバックアップしていません'
                : '最後のバックアップ: ${formatDateTime(last)}'
                    '${recommend ? '（30日以上前）' : ''}',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: recommend ? theme.colorScheme.error : null),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const BackupScreen())),
          child: const Text('バックアップ'),
        ),
      ],
    );
  }
}
