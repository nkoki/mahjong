import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../session/domain/session_logic.dart';
import '../session/session_providers.dart';
import 'player_detail_screen.dart';
import 'player_stats.dart';

/// 集計する期間
enum StatsPeriod {
  all('すべて'),
  days30('直近30日'),
  thisYear('今年');

  final String label;
  const StatsPeriod(this.label);

  DateTime? since(DateTime now) => switch (this) {
        StatsPeriod.all => null,
        StatsPeriod.days30 => now.subtract(const Duration(days: 30)),
        StatsPeriod.thisYear => DateTime(now.year),
      };
}

/// 個人成績（プレイヤーごとの順位・ポイント・和了率など）
class StatsScreen extends ConsumerStatefulWidget {
  /// 集計の基準の日時（テスト用。null なら今）
  final DateTime? now;

  const StatsScreen({super.key, this.now});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  int _playerCount = 4;
  StatsPeriod _period = StatsPeriod.all;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sessions = ref.watch(sessionsProvider);
    final summary = PlayerStatsCalculator.compute(sessions,
        playerCount: _playerCount, since: _period.since(widget.now ?? DateTime.now()));
    final small = theme.textTheme.bodySmall;

    return Scaffold(
      appBar: AppBar(title: const Text('個人成績')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 4, label: Text('4人打ち')),
              ButtonSegment(value: 3, label: Text('3人打ち')),
            ],
            selected: {_playerCount},
            onSelectionChanged: (v) => setState(() => _playerCount = v.first),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final p in StatsPeriod.values)
                ChoiceChip(
                  label: Text(p.label),
                  selected: _period == p,
                  onSelected: (_) => setState(() => _period = p),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '終局した対局（${summary.games}対局）を集計しています。対局中の対局は含みません。'
            '名前が同じなら同じ人として集計します。保存している対局（最新100対局まで）が対象なので、'
            '自動で削除された古い対局は含みません。'
            '名前の横の ✎ から、名前の変更や、表記ゆれの名前をまとめることができます。'
            'カードを押すと、合計ポイントの推移・対戦相手との成績・役の出現回数を見られます。',
            style: small,
          ),
          if (summary.roundsWithoutDetails > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '以前の版で記録した${summary.roundsWithoutDetails}局は、和了者などの記録が無いため、'
                '和了率・放銃率・立直率・平均打点に含めていません（順位・ポイントには含みます）。',
                style: small?.copyWith(color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: 8),
          if (summary.players.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text('この条件で終局した対局はまだありません', textAlign: TextAlign.center),
            ),
          for (var i = 0; i < summary.players.length; i++)
            _PlayerCard(
              rank: i + 1,
              stats: summary.players[i],
              showChips: summary.hasChips,
              onRename: () => _rename(summary.players[i].name),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PlayerDetailScreen(
                  name: summary.players[i].name,
                  playerCount: _playerCount,
                  since: _period.since(widget.now ?? DateTime.now()),
                  periodLabel: _period.label,
                ),
              )),
            ),
        ],
      ),
    );
  }
}

extension on _StatsScreenState {
  Future<void> _rename(String from) async {
    final names = {for (final s in ref.read(sessionsProvider)) ...s.playerNames}.toList()..sort();
    final to = await showDialog<String>(context: context, builder: (_) => _RenameDialog(from: from, names: names));
    if (to == null || !mounted) return;
    final r = ref.read(sessionsProvider.notifier).renamePlayer(from, to);
    final merged = names.contains(to.trim());
    final msg = StringBuffer('${r.renamed}対局で「$from」を「${to.trim()}」${merged ? "にまとめました" : "に変えました"}');
    if (r.skipped > 0) msg.write('（「$from」と「${to.trim()}」が一緒に打った${r.skipped}対局は、別の人なので変えていません）');
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg.toString())));
  }
}

/// 名前を変える（まとめる）ダイアログ。新しい名前を返す
class _RenameDialog extends StatefulWidget {
  final String from;
  final List<String> names;
  const _RenameDialog({required this.from, required this.names});

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _controller = TextEditingController(text: widget.from);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final to = _controller.text.trim();
    final error = SessionLogic.validateRename(widget.from, to);
    final merge = error == null && widget.names.contains(to);
    final others = widget.names.where((n) => n != widget.from).toList();
    return AlertDialog(
      title: Text('「${widget.from}」の名前を変える'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const ValueKey('rename-field'),
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: '新しい名前', border: OutlineInputBorder()),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Text(
              merge
                  ? '「$to」はほかの対局にいるので、同じ人としてまとめます。'
                  : '保存しているすべての対局（4人打ち・3人打ち、対局中も含む）で名前を変えます。',
              style: theme.textTheme.bodySmall?.copyWith(color: merge ? theme.colorScheme.primary : null),
            ),
            const SizedBox(height: 4),
            Text(
              '同じ対局に両方の名前がいる対局は、別の人なので変えません。局の内容のメモに書かれた名前は変わりません。'
              'バックアップから読み込んだ古い対局には反映されないので、必要ならもう一度変えてください。',
              style: theme.textTheme.bodySmall,
            ),
            if (others.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('ほかの名前にまとめる', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final n in others)
                    ActionChip(label: Text(n), onPressed: () => setState(() => _controller.text = n)),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
        FilledButton(
          onPressed: error == null ? () => Navigator.pop(context, to) : null,
          child: Text(merge ? 'まとめる' : '変更'),
        ),
      ],
    );
  }
}

String _percent(double? v) => v == null ? '－' : '${(v * 100).toStringAsFixed(1)}%';

class _PlayerCard extends StatelessWidget {
  final int rank;
  final PlayerStats stats;
  final bool showChips;
  final VoidCallback? onRename;
  final VoidCallback? onTap;

  const _PlayerCard({required this.rank, required this.stats, this.showChips = false, this.onRename, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = stats;
    final pointColor = deltaColor(context, s.totalPoints);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('player-${s.name}'),
        onTap: onTap,
        child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(radius: 14, child: Text('$rank', style: const TextStyle(fontSize: 13))),
                const SizedBox(width: 8),
                Flexible(child: Text(s.name, style: theme.textTheme.titleMedium)),
                if (onRename != null)
                  IconButton(
                    key: ValueKey('rename-${s.name}'),
                    tooltip: '名前を変える・まとめる',
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: onRename,
                  ),
                const Spacer(),
                Text(formatPoint(s.totalPoints),
                    style: theme.textTheme.titleMedium?.copyWith(color: pointColor, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _Stat('対局数', '${s.games}'),
                _Stat('平均順位', s.averageRank.toStringAsFixed(2)),
                _Stat('平均ポイント', formatPoint(s.averagePoints)),
                _Stat('トップ率', _percent(s.topRate)),
                _Stat('ラス率', _percent(s.lastRate)),
                _Stat('和了率', _percent(s.winRate)),
                _Stat('放銃率', _percent(s.dealInRate)),
                _Stat('立直率', _percent(s.riichiRate)),
                _Stat('平均打点', s.averageWinPoints == null ? '－' : formatPoints(s.averageWinPoints!.round())),
                if (showChips) _Stat('祝儀', '${s.chips > 0 ? '+' : ''}${s.chips}枚'),
                if (s.chombo > 0) _Stat('チョンボ', '${s.chombo}回'),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              [for (var r = 0; r < s.rankCounts.length; r++) '${r + 1}位 ${s.rankCounts[r]}回'].join('  ') +
                  (s.rounds > 0 ? '  （和了率などは${s.rounds}局で集計）' : ''),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 96,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelSmall),
          Text(value, style: theme.textTheme.titleSmall),
        ],
      ),
    );
  }
}
