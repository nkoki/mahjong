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
import '../../../shared/widgets/app_mark.dart';
import '../domain/models.dart';
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

    void push(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          const _Header(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                if (ongoing.isNotEmpty) ...[
                  _SectionLabel(tr('対局中（続きから）', 'In progress (continue)')),
                  for (final s in ongoing) _OngoingSlip(session: s),
                  const SizedBox(height: 12),
                ],
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.accent(context),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 56),
                  ),
                  onPressed: () => push(const NewSessionScreen()),
                  child: Text(tr('新規対局', 'New game')),
                ),
                _SectionLabel(tr('記録', 'Records')),
                _MenuGroup(children: [
                  _MenuRow(icon: Icons.format_list_numbered, title: tr('戦績', 'Records'), onTap: () => push(const HistoryListScreen())),
                  _MenuRow(icon: Icons.person_outline, title: tr('個人成績', 'Player stats'), onTap: () => push(const StatsScreen())),
                ]),
                _SectionLabel(tr('道具', 'Tools')),
                _MenuGroup(children: [
                  _MenuRow(icon: Icons.grid_on, title: tr('点数早見表', 'Score table'), onTap: () => push(const ScoreTableScreen())),
                  _MenuRow(icon: Icons.edit_note, title: tr('点数計算の練習', 'Scoring practice'), onTap: () => push(const PracticeScreen())),
                ]),
                _SectionLabel(tr('設定', 'Settings')),
                _MenuGroup(children: [
                  _MenuRow(icon: Icons.rule, title: tr('ルール設定', 'Rules'), onTap: () => push(const RuleSettingsScreen())),
                  _MenuRow(
                      icon: Icons.contrast,
                      title: tr('表示の設定（明るさ・文字の大きさ）', 'Display (theme, text size, language)'),
                      onTap: () => push(const DisplaySettingsScreen())),
                  _MenuRow(
                      icon: Icons.article_outlined,
                      title: tr('ライセンス・データの出典', 'Licenses & data sources'),
                      onTap: () => push(const LicenseScreen())),
                ]),
                _SectionLabel(tr('データ', 'Data')),
                _MenuGroup(children: [
                  InkWell(
                    onTap: openInfo,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(tr('データの保存について', 'About data storage'), style: theme.textTheme.titleSmall),
                              ),
                              Icon(Icons.chevron_right, color: theme.colorScheme.outline),
                            ],
                          ),
                          const SizedBox(height: 4),
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
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                    child: _BackupRow(sessionCount: ref.watch(sessionsProvider).length),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ホームのいちばん上の看板（卓の緑に、東南西北の牌とアプリの名前）
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: dark ? const Color(0xFF17201C) : AppTheme.tableGreen,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('麻雀点数計算', 'Mahjong Scorer'),
                      style: const TextStyle(
                        color: Color(0xFFF7F3EA),
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      tr('点数計算と対局の記録', 'Scoring and game records'),
                      style: const TextStyle(color: Color(0xCCF7F3EA), fontSize: 13, letterSpacing: 1),
                    ),
                  ],
                ),
              ),
              // アプリの印（アイコンと同じ、上から見た卓。飾りなので読み上げでは読まない）
              const AppMark(size: 56),
            ],
          ),
        ),
      ),
    );
  }
}

/// まとまりの見出し
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 6),
      child: Text(text,
          style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
    );
  }
}

/// 線で囲んだメニューのまとまり（行の間に区切り線）
class _MenuGroup extends StatelessWidget {
  final List<Widget> children;
  const _MenuGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 16, color: scheme.outlineVariant),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  const _MenuRow({required this.icon, required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: scheme.onSurfaceVariant),
            const SizedBox(width: 14),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 16))),
            Icon(Icons.chevron_right, color: scheme.outline),
          ],
        ),
      ),
    );
  }
}

/// 対局中の対局（点数表の紙のように、名前と点数を並べる）
class _OngoingSlip extends StatelessWidget {
  final GameSession session;
  const _OngoingSlip({required this.session});

  @override
  Widget build(BuildContext context) {
    final s = session;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(dashboardRoute(s.id)),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 4, color: AppTheme.accent(context)),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${displayRoundLabel(s.roundLabel)}  ${tr('供託${s.riichiSticks}本', 'Riichi sticks: ${s.riichiSticks}')}',
                          style: theme.textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 14,
                          runSpacing: 4,
                          children: [
                            for (var p = 0; p < s.playerCount; p++)
                              Text.rich(TextSpan(children: [
                                TextSpan(text: '${s.playerNames[p]} ', style: theme.textTheme.bodySmall),
                                TextSpan(
                                    text: formatPoints(s.scores[p]),
                                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                              ])),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, color: scheme.outline),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
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
