import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../shared/widgets/rule_inputs.dart';
import '../session/domain/models.dart';
import '../session/session_providers.dart';

/// 戦績詳細（順位・ポイント・局ごとの記録）
class HistoryDetailScreen extends ConsumerWidget {
  final String sessionId;
  const HistoryDetailScreen({super.key, required this.sessionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider(sessionId));
    if (s == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('対局が見つかりません')));
    }
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('戦績詳細'),
        actions: [
          IconButton(
            tooltip: s.favorite ? 'お気に入りを解除' : 'お気に入りにする（自動で削除されなくなります）',
            icon: Icon(s.favorite ? Icons.star : Icons.star_border),
            onPressed: () {
              ref.read(sessionsProvider.notifier).toggleFavorite(sessionId);
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(
                  content: Text(s.favorite
                      ? 'お気に入りを解除しました'
                      : 'お気に入りにしました。保存件数が上限を超えても自動で削除されません'),
                ));
            },
          ),
          IconButton(
            tooltip: '削除',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('対局を削除'),
                  content: const Text('この対局の記録を削除しますか？\n削除すると元に戻せません。'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('キャンセル')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('削除')),
                  ],
                ),
              );
              if (ok == true && context.mounted) {
                Navigator.of(context).popUntil((r) => r.isFirst);
                ref.read(sessionsProvider.notifier).delete(sessionId);
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text(s.finished ? '最終結果' : '現在の順位（${s.roundLabel}）',
              style: theme.textTheme.titleMedium),
          Card(
            child: Column(
              children: [
                for (final r in s.finalResults)
                  ListTile(
                    leading: CircleAvatar(child: Text('${r.rank}')),
                    title: Text(s.playerNames[r.player]),
                    subtitle: Text('${formatPoints(r.score)}点'),
                    trailing: s.finished
                        ? Text(formatPoint(r.point), style: theme.textTheme.titleMedium)
                        : null,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text('ルール', style: theme.textTheme.titleMedium),
          Card(
            child: Column(
              children: [
                ListTile(
                  dense: true,
                  title: Text('${s.settings.tonpuu ? "東風戦" : "半荘戦"}  '
                      '持ち点 ${formatPoints(s.settings.startingPoints)} / '
                      '返し ${formatPoints(s.settings.returnPoints)}'),
                  subtitle: Text('オカ ${formatPoint(s.settings.oka)}（トップが受け取る）'),
                ),
                ListTile(
                  title: Text('ウマ: ${s.settings.umaLabel}'),
                  subtitle: Text(s.settings.uma
                      .asMap()
                      .entries
                      .map((e) => '${e.key + 1}位 ${e.value > 0 ? "+" : ""}${e.value}')
                      .join('  ')),
                  trailing: OutlinedButton(
                    onPressed: () => _editUma(context, ref, sessionId, s.settings.uma),
                    child: const Text('変更'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text('局の記録（${s.records.length}局）', style: theme.textTheme.titleMedium),
          if (s.records.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('まだ記録がありません'),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 16,
              columns: [
                const DataColumn(label: Text('局')),
                for (final n in s.playerNames)
                  DataColumn(label: Text(n, overflow: TextOverflow.ellipsis), numeric: true),
              ],
              rows: [
                for (final r in s.records)
                  DataRow(cells: [
                    DataCell(Text(r.roundLabel)),
                    for (final d in r.deltas)
                      DataCell(Text(formatDelta(d),
                          style: TextStyle(
                              color: d > 0
                                  ? Colors.green.shade700
                                  : d < 0
                                      ? Colors.red.shade700
                                      : null))),
                  ]),
                DataRow(cells: [
                  const DataCell(Text('合計', style: TextStyle(fontWeight: FontWeight.bold))),
                  for (final v in s.scores)
                    DataCell(Text(formatPoints(v),
                        style: const TextStyle(fontWeight: FontWeight.bold))),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 12),
          for (final r in s.records.reversed)
            Card(
              child: ListTile(
                dense: true,
                leading: Icon(r.kind == 'win' ? Icons.emoji_events : Icons.water_drop_outlined),
                title: Text(r.roundLabel),
                subtitle: Text(r.description),
              ),
            ),
        ],
      ),
    );
  }
}

/// ウマを変更するダイアログ。変更すると最終ポイントが計算し直される
Future<void> _editUma(
    BuildContext context, WidgetRef ref, String sessionId, List<int> current) async {
  final result = await showDialog<List<int>>(
    context: context,
    builder: (_) => _UmaDialog(initial: current),
  );
  if (result == null) return;
  ref.read(sessionsProvider.notifier).updateUma(sessionId, result);
  if (context.mounted) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text('ウマを ${formatUma(result)} に変更し、ポイントを計算し直しました')));
  }
}

class _UmaDialog extends StatefulWidget {
  final List<int> initial;
  const _UmaDialog({required this.initial});

  @override
  State<_UmaDialog> createState() => _UmaDialogState();
}

class _UmaDialogState extends State<_UmaDialog> {
  late List<int?> _uma = widget.initial;

  @override
  Widget build(BuildContext context) {
    final error = validateUma(_uma);
    return AlertDialog(
      title: const Text('ウマを変更'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('変更できるのはウマだけです。最終ポイント（ウマ・オカ込み）がすぐに計算し直されます。',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              UmaInput(
                initialValue: widget.initial,
                errorText: error,
                onChanged: (v) => setState(() => _uma = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
        FilledButton(
          onPressed: error == null
              ? () => Navigator.pop(context, [for (final v in _uma) v!])
              : null,
          child: const Text('変更する'),
        ),
      ],
    );
  }
}
