import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../shared/widgets/rule_inputs.dart';
import '../session/domain/models.dart';
import '../session/session_providers.dart';
import 'result_image.dart';
import 'round_edit_screen.dart';
import 'round_insert_screen.dart';
import 'score_chart.dart';

/// 戦績詳細（順位・ポイント・局ごとの記録）
class HistoryDetailScreen extends ConsumerWidget {
  final String sessionId;
  const HistoryDetailScreen({super.key, required this.sessionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider(sessionId));
    if (s == null) {
      return Scaffold(appBar: AppBar(), body: Center(child: Text(tr('対局が見つかりません', 'Game not found'))));
    }
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('戦績詳細', 'Game details')),
        actions: [
          IconButton(
            tooltip: tr('結果を共有（画像・テキスト）', 'Share result (image/text)'),
            icon: const Icon(Icons.share_outlined),
            onPressed: () => showShareMenu(context, s),
          ),
          IconButton(
            tooltip: s.favorite
                ? tr('お気に入りを解除', 'Remove from favorites')
                : tr('お気に入りにする（自動で削除されなくなります）', 'Add to favorites (never auto-deleted)'),
            icon: Icon(s.favorite ? Icons.star : Icons.star_border),
            onPressed: () {
              ref.read(sessionsProvider.notifier).toggleFavorite(sessionId);
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(
                  content: Text(s.favorite
                      ? tr('お気に入りを解除しました', 'Removed from favorites')
                      : tr('お気に入りにしました。保存件数が上限を超えても自動で削除されません',
                          'Added to favorites. It will not be auto-deleted even when the save limit is exceeded')),
                ));
            },
          ),
          IconButton(
            tooltip: tr('削除', 'Delete'),
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(tr('対局を削除', 'Delete game')),
                  content: Text(tr('この対局の記録を削除しますか？\n削除すると元に戻せません。', 'Delete this game record?\nThis cannot be undone.')),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(tr('キャンセル', 'Cancel'))),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(tr('削除', 'Delete'))),
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
          Text(s.finished ? tr('最終結果', 'Final result') : tr('現在の順位（${s.roundLabel}）', 'Current standings (${displayRoundLabel(s.roundLabel)})'),
              style: theme.textTheme.titleMedium),
          Card(
            child: Column(
              children: [
                for (final r in s.finalResults)
                  ListTile(
                    leading: CircleAvatar(child: Text('${r.rank}')),
                    title: Text(s.playerNames[r.player]),
                    subtitle: Text(tr(
                        '${formatPoints(r.score)}点'
                            '${s.settings.chips ? '  祝儀 ${_chipText(s.chipTotals[r.player])}' : ''}'
                            '${r.adjustment != 0 ? '  焼き鳥・トビ賞 ${formatPoint(r.adjustment)}' : ''}',
                        '${formatPoints(r.score)} pts'
                            '${s.settings.chips ? '  Chips ${_chipText(s.chipTotals[r.player])}' : ''}'
                            '${r.adjustment != 0 ? '  Yakitori/bust bonus ${formatPoint(r.adjustment)}' : ''}')),
                    trailing: s.finished
                        ? Text(formatPoint(r.point), style: theme.textTheme.titleMedium)
                        : null,
                  ),
              ],
            ),
          ),
          if (s.records.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(tr('点数の推移', 'Score progression'), style: theme.textTheme.titleMedium),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 12, 8),
                child: ScoreChart(session: s),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(tr('ルール', 'Rules'), style: theme.textTheme.titleMedium),
          Card(
            child: Column(
              children: [
                ListTile(
                  dense: true,
                  title: Text(tr(
                      '${s.settings.isSanma ? "3人打ち " : ""}${s.settings.tonpuu ? "東風戦" : "半荘戦"}  '
                          '持ち点 ${formatPoints(s.settings.startingPoints)} / '
                          '返し ${formatPoints(s.settings.returnPoints)}',
                      '${s.settings.isSanma ? "3-player " : ""}${s.settings.tonpuu ? "East-only" : "Hanchan"}  '
                          'Start ${formatPoints(s.settings.startingPoints)} / '
                          'Return ${formatPoints(s.settings.returnPoints)}')),
                  subtitle: Text(tr(
                      'オカ ${formatPoint(s.settings.oka)}（トップが受け取る）'
                          '${s.settings.tobi ? "・トビあり" : "・トビなし"}\n'
                          '${s.settings.ruleSummary.join("・")}',
                      'Oka ${formatPoint(s.settings.oka)} (to the top player)'
                          '${s.settings.tobi ? " · Bust on" : " · Bust off"}\n'
                          '${s.settings.ruleSummary.join(" · ")}')),
                  isThreeLine: true,
                ),
                ListTile(
                  title: Text(tr('ウマ: ${s.settings.umaLabel}', 'Uma: ${s.settings.umaLabel}')),
                  subtitle: Text(s.settings.uma
                      .asMap()
                      .entries
                      .map((e) => tr('${e.key + 1}位 ${e.value > 0 ? "+" : ""}${e.value}',
                          '#${e.key + 1} ${e.value > 0 ? "+" : ""}${e.value}'))
                      .join('  ')),
                  trailing: OutlinedButton(
                    onPressed: () => _editUma(context, ref, sessionId, s.settings.uma),
                    child: Text(tr('変更', 'Change')),
                  ),
                ),
              ],
            ),
          ),
          if (s.substitutions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(tr('途中の交代', 'Substitutions'), style: theme.textTheme.titleMedium),
            Card(
              child: Column(
                children: [
                  for (final x in s.substitutions)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.swap_horiz),
                      title: Text('${x.from} → ${x.to}'),
                      subtitle: Text(x.fromRecord < s.records.length
                          ? tr('${s.records[x.fromRecord].roundLabel}から',
                              'From ${displayRoundLabel(s.records[x.fromRecord].roundLabel)}')
                          : tr('これからの局から', 'From the next round')),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(tr('局の記録（${s.records.length}局）', 'Rounds (${s.records.length})'), style: theme.textTheme.titleMedium),
          if (s.records.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                tr(
                    '下の一覧の局をタップすると、その局の点数の増減を修正・削除できます'
                        '${s.records.any((r) => r.edited) ? "（* は修正済みの局）" : ""}。',
                    'Tap a round below to edit or delete its score changes'
                        '${s.records.any((r) => r.edited) ? " (* = edited)" : ""}.'),
                style: theme.textTheme.bodySmall,
              ),
            ),
          if (s.records.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(tr('まだ記録がありません', 'No rounds yet')),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('insert-round'),
              icon: const Icon(Icons.playlist_add),
              label: Text(tr('入れ忘れた局を追加', 'Add a missed round')),
              onPressed: () async {
                final r = await Navigator.of(context).push<Object>(
                    MaterialPageRoute(builder: (_) => RoundInsertScreen(sessionId: sessionId)));
                if (context.mounted) _showUndo(context, sessionId, r);
              },
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 16,
              columns: [
                DataColumn(label: Text(tr('局', 'Round'))),
                for (final n in s.playerNames)
                  DataColumn(label: Text(n, overflow: TextOverflow.ellipsis), numeric: true),
              ],
              rows: [
                for (final r in s.records)
                  DataRow(cells: [
                    DataCell(Text('${displayRoundLabel(r.roundLabel)}${r.edited ? " *" : ""}')),
                    for (final d in r.deltas)
                      DataCell(Text(formatDelta(d),
                          style: TextStyle(color: deltaColor(context, d)))),
                  ]),
                DataRow(cells: [
                  DataCell(Text(tr('合計', 'Total'), style: const TextStyle(fontWeight: FontWeight.bold))),
                  for (final v in s.scores)
                    DataCell(Text(formatPoints(v),
                        style: const TextStyle(fontWeight: FontWeight.bold))),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 12),
          for (var i = s.records.length - 1; i >= 0; i--)
            Card(
              child: ListTile(
                dense: true,
                leading: Icon(switch (s.records[i].kind) {
                  'win' => Icons.emoji_events,
                  'chombo' => Icons.block,
                  _ => Icons.water_drop_outlined,
                }),
                title: Text(
                    '${displayRoundLabel(s.records[i].roundLabel)}${s.records[i].edited ? tr("（修正済み）", " (edited)") : ""}'),
                subtitle: Text(s.records[i].description),
                trailing: IconButton(
                  tooltip: tr('この局を修正', 'Edit this round'),
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _openEdit(context, sessionId, i),
                ),
                onTap: () => _openEdit(context, sessionId, i),
              ),
            ),
        ],
      ),
    );
  }
}

/// 祝儀の枚数の表示（例: +3枚、-2枚、0枚）
String _chipText(int n) => tr('${n > 0 ? '+' : ''}$n枚', '${n > 0 ? '+' : ''}$n');

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
          content: Text(tr('ウマを ${formatUma(result)} に変更し、ポイントを計算し直しました',
              'Uma changed to ${formatUma(result)} and points recalculated'))));
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
    final error = validateUma(_uma, playerCount: widget.initial.length);
    return AlertDialog(
      title: Text(tr('ウマを変更', 'Change uma')),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('変更できるのはウマだけです。最終ポイント（ウマ・オカ込み）がすぐに計算し直されます。',
                      'Only uma can be changed. Final points (incl. uma and oka) are recalculated immediately.'),
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
            onPressed: () => Navigator.pop(context), child: Text(tr('キャンセル', 'Cancel'))),
        FilledButton(
          onPressed: error == null
              ? () => Navigator.pop(context, [for (final v in _uma) v!])
              : null,
          child: Text(tr('変更する', 'Change')),
        ),
      ],
    );
  }
}

Future<void> _openEdit(BuildContext context, String sessionId, int index) async {
  final saved = await Navigator.of(context).push<Object>(MaterialPageRoute(
    builder: (_) => RoundEditScreen(sessionId: sessionId, index: index),
  ));
  if (context.mounted) _showUndo(context, sessionId, saved);
}

/// 局の修正・削除・追加のあとに「元に戻す」を出す（[result] が true: 修正、'deleted': 削除、'inserted': 追加）
void _showUndo(BuildContext context, String sessionId, Object? result) {
  final message = switch (result) {
    true => tr('局を修正しました', 'Round edited'),
    'deleted' => tr('局を削除しました', 'Round deleted'),
    'inserted' => tr('局を追加しました', 'Round added'),
    _ => null,
  };
  if (message != null) {
    final container = ProviderScope.containerOf(context, listen: false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: tr('元に戻す', 'Undo'),
          onPressed: () => container.read(sessionsProvider.notifier).undo(sessionId),
        ),
      ));
  }
}
