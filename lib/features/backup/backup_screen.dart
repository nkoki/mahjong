import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../session/domain/session_logic.dart';
import '../session/session_providers.dart';
import 'backup_codec.dart';
import 'backup_file_service.dart';

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
      _snack('${sessions.length}件の対局をバックアップしました');
    } catch (e) {
      _snack('ファイルに保存できませんでした: $e');
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
    _snack('${sessions.length}件の対局のバックアップをコピーしました。'
        'メモアプリなどに貼り付けて保存してください');
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
      _snack('ファイルを読み込めませんでした: $e');
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
            title: const Text('読み込めませんでした'),
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
      _snack('バックアップに対局がありませんでした');
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
          title: const Text('今のデータを置き換えます'),
          content: Text('今ある対局 ${current.length}件はすべて削除され、'
              'バックアップの ${data.sessions.length}件に置き換わります。削除した対局は元に戻せません。'
              '${choice.applySettings && data.hasSettings ? '\nルール設定もバックアップの内容に置き換わります。' : ''}'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('置き換える'),
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
    _snack('${mode == 'replace' ? 'バックアップの内容に置き換えました' : '$added件の対局を追加しました'}'
        '${settingsApplied ? '。ルール設定も読み込みました' : ''}'
        '（保存中: $total件）'
        '${over ? '。${SessionLogic.maxSavedSessions}件を超えているので、次に新しい対局を始めるときに、'
            'お気に入りでない古い対局から削除されます' : ''}');
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
      appBar: AppBar(title: const Text('バックアップ')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              '対局データはこの端末の中だけに保存されています。'
              '機種変更・アプリの削除・ブラウザのデータ削除で消えないように、'
              'ときどきバックアップを書き出して、別の場所に保存しておいてください。',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Card(
              color: recommend ? theme.colorScheme.errorContainer : null,
              child: ListTile(
                leading: Icon(recommend ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                    color: recommend ? theme.colorScheme.onErrorContainer : theme.colorScheme.primary),
                title: Text(last == null ? 'まだバックアップしていません' : '最後のバックアップ: ${formatDateTime(last)}'),
                subtitle: Text('保存中の対局: ${sessions.length}件'),
              ),
            ),
            if (_busy) const LinearProgressIndicator(),
            section('バックアップを書き出す'),
            FilledButton.icon(
              icon: const Icon(Icons.save_alt),
              label: const Text('ファイルに保存'),
              onPressed: sessions.isEmpty ? null : _exportFile,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
              icon: const Icon(Icons.copy),
              label: const Text('テキストをコピー'),
              onPressed: sessions.isEmpty ? null : _exportText,
            ),
            const SizedBox(height: 6),
            Text(
              '・ファイルに保存: スマホでは保存先（「ファイル」アプリ、Google ドライブなど）を選べます。'
              'Web 版ではダウンロードされます。\n'
              '・テキストをコピー: ファイルを扱いにくいときに。メモアプリや自分宛てのメッセージに貼り付けて保存します。\n'
              '・すべての対局（お気に入り、ルール、局の記録、「元に戻す」の履歴10回分）と、ルール設定画面の内容が入ります。'
              'プレイヤーの名前も入るので、他の人に渡すときは注意してください。',
              style: theme.textTheme.bodySmall,
            ),
            section('バックアップから読み込む'),
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('ファイルから読み込む'),
              onPressed: _importFile,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
              icon: const Icon(Icons.content_paste),
              label: const Text('テキストを貼り付けて読み込む'),
              onPressed: _importPasted,
            ),
            const SizedBox(height: 6),
            Text(
              '読み込むときに「今のデータに追加」か「すべて置き換え」を選べます。'
              '追加の場合、すでにある対局は今のデータのまま残ります。',
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
      title: const Text('バックアップを読み込む'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('バックアップの対局: ${data.sessions.length}件'
                '${data.exportedAt != null ? '（${formatDateTime(data.exportedAt!)} に作成）' : ''}'),
            Text('今の対局: $currentCount件'),
            if (data.skipped > 0)
              Text('壊れていて読み込めない対局が${data.skipped}件ありました（読み込みません）。',
                  style: small?.copyWith(color: theme.colorScheme.error)),
            const SizedBox(height: 12),
            Text('今のデータに追加', style: theme.textTheme.titleSmall),
            Text('新しく ${plan.added.length}件を追加します。'
                '${plan.duplicates > 0 ? 'すでにある ${plan.duplicates}件は、今のデータのまま残します。' : ''}',
                style: small),
            const SizedBox(height: 8),
            Text('すべて置き換え', style: theme.textTheme.titleSmall),
            Text('今の対局をすべて削除して、バックアップの内容だけにします。', style: small),
            if (hasSettings) ...[
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('ルール設定も読み込む'),
                subtitle: Text(
                    'この端末のルール設定を、バックアップの内容'
                    '（${[if (data.defaultSettings != null) '4人打ち', if (data.defaultSanmaSettings != null) '3人打ち'].join('・')}）に置き換えます',
                    style: small),
                value: _applySettings,
                onChanged: (v) => setState(() => _applySettings = v ?? false),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('このバックアップにはルール設定が入っていないので、今のルール設定のまま読み込みます。',
                    style: small),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
          onPressed: () => Navigator.pop(context, _ImportChoice('replace', applySettings)),
          child: const Text('すべて置き換え'),
        ),
        FilledButton(
          // 追加する対局がなくても、ルール設定だけ読み込むことはできる
          onPressed: plan.added.isEmpty && !applySettings
              ? null
              : () => Navigator.pop(context, _ImportChoice('merge', applySettings)),
          child: const Text('追加'),
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
      title: const Text('テキストを貼り付けて読み込む'),
      content: TextField(
        controller: _controller,
        maxLines: 6,
        decoration: const InputDecoration(
          hintText: '「テキストをコピー」で書き出した内容を貼り付けてください',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
        FilledButton(
            onPressed: () => Navigator.pop(context, _controller.text),
            child: const Text('読み込む')),
      ],
    );
  }
}
