import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../session/domain/session_logic.dart';
import '../session/session_providers.dart';
import 'backup_codec.dart';
import 'backup_file_service.dart';
import 'csv_export.dart';

String formatDateTime(DateTime d) =>
    '${d.year}/${d.month}/${d.day} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';

/// バックアップを勧めるべきか（対局があるのに、一度もしていない・30日以上していない）
bool shouldRecommendBackup(int sessionCount, DateTime? lastBackupAt, {DateTime? now}) {
  if (sessionCount == 0) return false;
  if (lastBackupAt == null) return true;
  return (now ?? DateTime.now()).difference(lastBackupAt).inDays >= 30;
}

/// バックアップ・復元の画面
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 6)));
  }

  Future<void> _recordBackup() async {
    final now = DateTime.now();
    ref.read(lastBackupProvider.notifier).state = now;
    await ref.read(sessionRepositoryProvider).setLastBackupAt(now);
  }

  // ---------------------------------------------------------------------
  // 書き出し
  // ---------------------------------------------------------------------
  Future<void> _exportFile() async {
    final sessions = ref.read(sessionsProvider);
    final now = DateTime.now();
    setState(() => _busy = true);
    try {
      final ok = await ref
          .read(backupFileServiceProvider)
          .save(
              BackupCodec.fileName(now),
              BackupCodec.encode(sessions,
                  defaultSettings: ref.read(defaultSettingsProvider),
                  defaultSanmaSettings: ref.read(defaultSanmaSettingsProvider),
                  now: now));
      if (!ok) return;
      await _recordBackup();
      _snack(tr('${sessions.length}件の対局をバックアップしました', 'Backed up ${sessions.length} games'));
    } catch (e) {
      _snack(tr('ファイルに保存できませんでした: $e', 'Could not save the file: $e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportText() async {
    final sessions = ref.read(sessionsProvider);
    await Clipboard.setData(ClipboardData(
        text: BackupCodec.encode(sessions,
            defaultSettings: ref.read(defaultSettingsProvider),
            defaultSanmaSettings: ref.read(defaultSanmaSettingsProvider))));
    await _recordBackup();
    _snack(tr(
        '${sessions.length}件の対局のバックアップをコピーしました。'
            'メモアプリなどに貼り付けて保存してください',
        'Copied a backup of ${sessions.length} games. '
            'Paste it into a notes app or similar to keep it'));
  }

  /// 戦績を CSV（表計算ソフト用）に書き出す。[kind] は 'games'（対局一覧）か 'rounds'（局ごとの記録）
  Future<void> _exportCsv(String kind) async {
    final sessions = ref.read(sessionsProvider);
    final content = kind == 'games' ? CsvExport.games(sessions) : CsvExport.rounds(sessions);
    setState(() => _busy = true);
    try {
      final ok = await ref.read(backupFileServiceProvider).save(
          CsvExport.fileName(kind, DateTime.now()), content,
          dialogTitle: tr('CSV の保存先', 'Save CSV to'));
      if (ok) {
        _snack(kind == 'games'
            ? tr('${sessions.length}件の対局を CSV に書き出しました', 'Exported ${sessions.length} games to CSV')
            : tr('局ごとの記録を CSV に書き出しました', 'Exported round records to CSV'));
      }
    } catch (e) {
      _snack(tr('ファイルに保存できませんでした: $e', 'Could not save the file: $e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------------
  // 読み込み
  // ---------------------------------------------------------------------
  Future<void> _importFile() async {
    setState(() => _busy = true);
    String? text;
    try {
      text = await ref.read(backupFileServiceProvider).pick();
    } catch (e) {
      _snack(tr('ファイルを読み込めませんでした: $e', 'Could not read the file: $e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (text != null) await _importText(text);
  }

  Future<void> _importPasted() async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => const _PasteDialog(),
    );
    if (text != null && text.trim().isNotEmpty) await _importText(text);
  }

  Future<void> _importText(String text) async {
    final BackupData data;
    try {
      data = BackupCodec.decode(text);
    } on BackupFormatException catch (e) {
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(tr('読み込めませんでした', 'Could not import')),
            content: Text(e.message),
            actions: [
              FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            ],
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    if (data.sessions.isEmpty && !data.hasSettings) {
      _snack(tr('バックアップに対局がありませんでした', 'The backup contained no games'));
      return;
    }

    final current = ref.read(sessionsProvider);
    final plan = BackupCodec.planMerge(current, data.sessions);
    final choice = await showDialog<_ImportChoice>(
      context: context,
      builder: (ctx) => _ImportDialog(
        data: data,
        currentCount: current.length,
        plan: plan,
      ),
    );
    if (choice == null || !mounted) return;
    final mode = choice.mode;

    if (mode == 'replace') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('今のデータを置き換えます', 'Replace current data')),
          content: Text(tr(
              '今ある対局 ${current.length}件はすべて削除され、'
                  'バックアップの ${data.sessions.length}件に置き換わります。削除した対局は元に戻せません。'
                  '${choice.applySettings && data.hasSettings ? '\nルール設定もバックアップの内容に置き換わります。' : ''}',
              'All ${current.length} current games will be deleted and '
                  'replaced with the ${data.sessions.length} games in the backup. Deleted games cannot be restored.'
                  '${choice.applySettings && data.hasSettings ? '\nRule settings will also be replaced with those in the backup.' : ''}')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('キャンセル', 'Cancel'))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('置き換える', 'Replace')),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }

    final added = ref
        .read(sessionsProvider.notifier)
        .importSessions(data.sessions, replace: mode == 'replace');
    final settingsApplied = choice.applySettings && data.hasSettings;
    if (settingsApplied) {
      if (data.defaultSettings != null) {
        await ref.read(defaultSettingsProvider.notifier).save(data.defaultSettings!);
      }
      if (data.defaultSanmaSettings != null) {
        await ref.read(defaultSanmaSettingsProvider.notifier).save(data.defaultSanmaSettings!);
      }
    }
    final total = ref.read(sessionsProvider).length;
    final over = total > SessionLogic.maxSavedSessions;
    _snack(tr(
        '${mode == 'replace' ? 'バックアップの内容に置き換えました' : '$added件の対局を追加しました'}'
            '${settingsApplied ? '。ルール設定も読み込みました' : ''}'
            '（保存中: $total件）'
            '${over ? '。${SessionLogic.maxSavedSessions}件を超えているので、次に新しい対局を始めるときに、'
                'お気に入りでない古い対局から削除されます' : ''}',
        '${mode == 'replace' ? 'Replaced with the backup' : 'Added $added games'}'
            '${settingsApplied ? '. Rule settings were also imported' : ''}'
            ' (saved: $total)'
            '${over ? '. Since there are more than ${SessionLogic.maxSavedSessions}, the oldest non-favorite games '
                'will be deleted when you start a new game' : ''}'));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sessions = ref.watch(sessionsProvider);
    final last = ref.watch(lastBackupProvider);
    final recommend = shouldRecommendBackup(sessions.length, last);

    Widget section(String title) => Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          child: Text(title, style: theme.textTheme.titleMedium),
        );

    return Scaffold(
      appBar: AppBar(title: Text(tr('バックアップ', 'Backup'))),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              tr(
                  '対局データはこの端末の中だけに保存されています。'
                      '機種変更・アプリの削除・ブラウザのデータ削除で消えないように、'
                      'ときどきバックアップを書き出して、別の場所に保存しておいてください。',
                  'Game data is stored only on this device. '
                      'To avoid losing it when you change devices, uninstall the app, or clear browser data, '
                      'export a backup from time to time and keep it somewhere else.'),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Card(
              color: recommend ? theme.colorScheme.errorContainer : null,
              child: ListTile(
                leading: Icon(recommend ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                    color: recommend ? theme.colorScheme.onErrorContainer : theme.colorScheme.primary),
                title: Text(last == null
                    ? tr('まだバックアップしていません', 'No backup yet')
                    : tr('最後のバックアップ: ${formatDateTime(last)}', 'Last backup: ${formatDateTime(last)}')),
                subtitle: Text(tr('保存中の対局: ${sessions.length}件', 'Saved games: ${sessions.length}')),
              ),
            ),
            if (_busy) const LinearProgressIndicator(),
            section(tr('バックアップを書き出す', 'Export backup')),
            FilledButton.icon(
              icon: const Icon(Icons.save_alt),
              label: Text(tr('ファイルに保存', 'Save to file')),
              onPressed: sessions.isEmpty ? null : _exportFile,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
              icon: const Icon(Icons.copy),
              label: Text(tr('テキストをコピー', 'Copy as text')),
              onPressed: sessions.isEmpty ? null : _exportText,
            ),
            const SizedBox(height: 6),
            Text(
              tr(
                  '・ファイルに保存: スマホでは保存先（「ファイル」アプリ、Google ドライブなど）を選べます。'
                      'Web 版ではダウンロードされます。\n'
                      '・テキストをコピー: ファイルを扱いにくいときに。メモアプリや自分宛てのメッセージに貼り付けて保存します。\n'
                      '・すべての対局（お気に入り、ルール、局の記録、「元に戻す」の履歴10回分）と、ルール設定画面の内容が入ります。'
                      'プレイヤーの名前も入るので、他の人に渡すときは注意してください。',
                  '- Save to file: on phones you can choose where to save (Files app, Google Drive, etc.). '
                      'On the web version it is downloaded.\n'
                      '- Copy as text: for when files are inconvenient. Paste it into a notes app or a message to yourself.\n'
                      '- Includes all games (favorites, rules, round records, the last 10 undo steps) and the rule settings. '
                      'Player names are included too, so be careful when giving it to others.'),
              style: theme.textTheme.bodySmall,
            ),
            section(tr('表計算ソフト用に書き出す（CSV）', 'Export for spreadsheets (CSV)')),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.table_chart_outlined),
                  label: Text(tr('対局一覧', 'Game list')),
                  onPressed: sessions.isEmpty ? null : () => _exportCsv('games'),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.table_rows_outlined),
                  label: Text(tr('局ごとの記録', 'Round records')),
                  onPressed: sessions.isEmpty ? null : () => _exportCsv('rounds'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              tr(
                  'Excel や Google スプレッドシートで開ける形式です。対局一覧は1行に1対局（名前・点数・順位・ポイント）、'
                      '局ごとの記録は1行に1局（内容・点数の増減）です。'
                      'CSV はバックアップの代わりにはなりません（このアプリに読み込むことはできません）。',
                  'A format you can open in Excel or Google Sheets. The game list has one game per row (names, points, ranks, scores); '
                      'round records have one round per row (details, point changes). '
                      'CSV is not a substitute for a backup (it cannot be imported into this app).'),
              style: theme.textTheme.bodySmall,
            ),
            section(tr('バックアップから読み込む', 'Import from backup')),
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
              icon: const Icon(Icons.file_open_outlined),
              label: Text(tr('ファイルから読み込む', 'Import from file')),
              onPressed: _importFile,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
              icon: const Icon(Icons.content_paste),
              label: Text(tr('テキストを貼り付けて読み込む', 'Paste text to import')),
              onPressed: _importPasted,
            ),
            const SizedBox(height: 6),
            Text(
              tr(
                  '読み込むときに「今のデータに追加」か「すべて置き換え」を選べます。'
                      '追加の場合、すでにある対局は今のデータのまま残ります。',
                  'When importing, you can choose "Add to current data" or "Replace all". '
                      'When adding, games that already exist are kept as they are.'),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// 読み込み方法の選択結果
class _ImportChoice {
  /// 'merge'（今のデータに追加） | 'replace'（すべて置き換え）
  final String mode;

  /// ルール設定も読み込むか
  final bool applySettings;

  const _ImportChoice(this.mode, this.applySettings);
}

/// 読み込み方法の選択
class _ImportDialog extends StatefulWidget {
  final BackupData data;
  final int currentCount;
  final MergePlan plan;

  const _ImportDialog({required this.data, required this.currentCount, required this.plan});

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  bool _applySettings = true;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final plan = widget.plan;
    final currentCount = widget.currentCount;
    final hasSettings = data.hasSettings;
    final applySettings = hasSettings && _applySettings;
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    return AlertDialog(
      title: Text(tr('バックアップを読み込む', 'Import backup')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr(
                'バックアップの対局: ${data.sessions.length}件'
                    '${data.exportedAt != null ? '（${formatDateTime(data.exportedAt!)} に作成）' : ''}',
                'Games in backup: ${data.sessions.length}'
                    '${data.exportedAt != null ? ' (created ${formatDateTime(data.exportedAt!)})' : ''}')),
            Text(tr('今の対局: $currentCount件', 'Current games: $currentCount')),
            if (data.skipped > 0)
              Text(
                  tr('壊れていて読み込めない対局が${data.skipped}件ありました（読み込みません）。',
                      '${data.skipped} games are corrupted and cannot be imported (they will be skipped).'),
                  style: small?.copyWith(color: theme.colorScheme.error)),
            const SizedBox(height: 12),
            Text(tr('今のデータに追加', 'Add to current data'), style: theme.textTheme.titleSmall),
            Text(
                tr(
                    '新しく ${plan.added.length}件を追加します。'
                        '${plan.duplicates > 0 ? 'すでにある ${plan.duplicates}件は、今のデータのまま残します。' : ''}',
                    'Adds ${plan.added.length} new games.'
                        '${plan.duplicates > 0 ? ' ${plan.duplicates} games that already exist are kept as they are.' : ''}'),
                style: small),
            const SizedBox(height: 8),
            Text(tr('すべて置き換え', 'Replace all'), style: theme.textTheme.titleSmall),
            Text(tr('今の対局をすべて削除して、バックアップの内容だけにします。', 'Deletes all current games and keeps only the backup.'),
                style: small),
            if (hasSettings) ...[
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(tr('ルール設定も読み込む', 'Also import rule settings')),
                subtitle: Text(
                    tr(
                        'この端末のルール設定を、バックアップの内容'
                            '（${[if (data.defaultSettings != null) '4人打ち', if (data.defaultSanmaSettings != null) '3人打ち'].join('・')}）に置き換えます',
                        'Replaces the rule settings on this device with those in the backup '
                            '(${[if (data.defaultSettings != null) '4-player', if (data.defaultSanmaSettings != null) '3-player'].join(', ')})'),
                    style: small),
                value: _applySettings,
                onChanged: (v) => setState(() => _applySettings = v ?? false),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                    tr('このバックアップにはルール設定が入っていないので、今のルール設定のまま読み込みます。',
                        'This backup has no rule settings, so the current rule settings are kept.'),
                    style: small),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('キャンセル', 'Cancel'))),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
          onPressed: () => Navigator.pop(context, _ImportChoice('replace', applySettings)),
          child: Text(tr('すべて置き換え', 'Replace all')),
        ),
        FilledButton(
          // 追加する対局がなくても、ルール設定だけ読み込むことはできる
          onPressed: plan.added.isEmpty && !applySettings
              ? null
              : () => Navigator.pop(context, _ImportChoice('merge', applySettings)),
          child: Text(tr('追加', 'Add')),
        ),
      ],
    );
  }
}

/// テキストを貼り付けるダイアログ（入力欄の controller はダイアログと一緒に破棄する）
class _PasteDialog extends StatefulWidget {
  const _PasteDialog();

  @override
  State<_PasteDialog> createState() => _PasteDialogState();
}

class _PasteDialogState extends State<_PasteDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('テキストを貼り付けて読み込む', 'Paste text to import')),
      content: TextField(
        controller: _controller,
        maxLines: 6,
        decoration: InputDecoration(
          hintText: tr('「テキストをコピー」で書き出した内容を貼り付けてください', 'Paste the text exported with "Copy as text"'),
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('キャンセル', 'Cancel'))),
        FilledButton(
            onPressed: () => Navigator.pop(context, _controller.text),
            child: Text(tr('読み込む', 'Import'))),
      ],
    );
  }
}
