import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
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
