import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../session/domain/session_logic.dart';
import '../session/session_providers.dart';

/// 過去の局の修正画面（点数の増減と内容）
class RoundEditScreen extends ConsumerStatefulWidget {
  final String sessionId;
  final int index;

  const RoundEditScreen({super.key, required this.sessionId, required this.index});

  @override
  ConsumerState<RoundEditScreen> createState() => _RoundEditScreenState();
}

class _RoundEditScreenState extends ConsumerState<RoundEditScreen> {
  late final List<TextEditingController> _deltaControllers;
  late final TextEditingController _descController;

  /// 和了者・放銃者（和了の局で記録があるときだけ。放銃者が null ならツモ）
  List<int>? _winners;
  int? _loser;

  @override
  void initState() {
    super.initState();
    final record = ref.read(sessionProvider(widget.sessionId))!.records[widget.index];
    _deltaControllers = [
      for (final d in record.deltas) TextEditingController(text: '$d')
    ];
    _descController = TextEditingController(text: record.description);
    if (SessionLogic.canEditWinners(record)) {
      _winners = [...record.winners!];
      _loser = record.loser;
    }
  }

  @override
  void dispose() {
    for (final c in _deltaControllers) {
      c.dispose();
    }
    _descController.dispose();
    super.dispose();
  }

  List<int?> get _deltas => [for (final c in _deltaControllers) int.tryParse(c.text)];

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider(widget.sessionId));
    if (s == null || widget.index >= s.records.length) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('局が見つかりません')));
    }
    final theme = Theme.of(context);
    final record = s.records[widget.index];
    final deltas = _deltas;
    final winners = _winners;
    final whoError = winners == null ? null : SessionLogic.validateWinners(s, winners, _loser);
    final whoChanged = winners != null &&
        (winners.length != record.winners!.length ||
            winners.any((w) => !record.winners!.contains(w)) ||
            _loser != record.loser);
    final who = whoChanged && whoError == null ? (winners: winners, loser: _loser) : null;
    final deltaError = SessionLogic.validateRoundEdit(s, widget.index, deltas);
    final error = deltaError ?? whoError;
    final originalSum = record.deltas.fold<int>(0, (a, d) => a + d);
    // 修正後の点数の見込み
    final preview = error == null
        ? SessionLogic.editRound(s, widget.index,
            deltas: [for (final d in deltas) d!], description: _descController.text, who: who)
        : null;
    final changed = error == null &&
        (List.generate(s.playerCount, (i) => deltas[i] != record.deltas[i]).any((c) => c) ||
            _descController.text != record.description ||
            whoChanged);

    return Scaffold(
      appBar: AppBar(title: Text('局の修正  ${record.roundLabel}')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: theme.colorScheme.tertiaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '・修正できるのは、この局の点数の増減・内容のメモと、和了の局なら和了した人・放銃した人です'
                  '（手牌は記録していないため、入力し直すことはできません）。\n'
                  '・和了した人・放銃した人は個人成績（和了率・放銃率・平均打点）に使います。点数の増減は自動では変わらないので、合わせて直してください。\n'
                  '・修正した差分は、この局より後のすべての局の点数と、今の点数に反映されます。\n'
                  '・局の進行（親・本場・終局したかどうか）は変わりません。'
                  'トビの有無が変わる修正をしても、対局が途中で終わったり再開したりはしません。\n'
                  '・保存した直後に表示される「元に戻す」で取り消せます'
                  '（対局中の対局なら、対局画面の元に戻すボタンでも取り消せます）。',
                  style: TextStyle(color: theme.colorScheme.onTertiaryContainer, fontSize: 13),
                ),
              ),
            ),
            if (winners != null) ...[
              const SizedBox(height: 16),
              Text('和了した人', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: [
                  for (var p = 0; p < s.playerCount; p++)
                    FilterChip(
                      key: ValueKey('winner-$p'),
                      label: Text(s.playerNames[p]),
                      selected: winners.contains(p),
                      onSelected: (v) => setState(() {
                        _winners = v ? ([...winners, p]..sort()) : [...winners.where((w) => w != p)];
                        if (v && _loser == p) _loser = null;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text('放銃した人', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    key: const ValueKey('loser-tsumo'),
                    label: const Text('なし（ツモ）'),
                    selected: _loser == null,
                    onSelected: (_) => setState(() => _loser = null),
                  ),
                  for (var p = 0; p < s.playerCount; p++)
                    if (!winners.contains(p))
                      ChoiceChip(
                        key: ValueKey('loser-$p'),
                        label: Text(s.playerNames[p]),
                        selected: _loser == p,
                        onSelected: (_) => setState(() => _loser = p),
                      ),
                ],
              ),
              if (whoError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(whoError, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
                )
              else if (whoChanged && winners.length != record.winners!.length)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('和了した人の人数を変えると、この局の和了点は分からなくなるので、個人成績の平均打点に含めません。',
                      style: theme.textTheme.bodySmall),
                ),
            ],
            const SizedBox(height: 16),
            Text('点数の増減', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            for (var p = 0; p < s.playerCount; p++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(child: Text(s.playerNames[p], overflow: TextOverflow.ellipsis)),
                    Text('修正前 ${formatDelta(record.deltas[p])}  →  ',
                        style: theme.textTheme.bodySmall),
                    SizedBox(
                      width: 120,
                      child: TextField(
                        key: ValueKey('delta-$p'),
                        controller: _deltaControllers[p],
                        keyboardType: const TextInputType.numberWithOptions(signed: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*'))],
                        textAlign: TextAlign.end,
                        decoration: const InputDecoration(
                          isDense: true,
                          suffixText: '点',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
              ),
            Text(
              deltaError ??
                  '${s.playerCount}人の合計: ${formatDelta(originalSum)}'
                      '${originalSum != 0 ? "（供託リーチ棒の出入りの分。修正前と同じにしてください）" : "（修正前と同じ0にしてください）"}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: deltaError != null ? theme.colorScheme.error : null),
            ),
            const SizedBox(height: 16),
            Text('内容のメモ', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            TextField(
              controller: _descController,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              onChanged: (_) => setState(() {}),
            ),
            if (preview != null) ...[
              const SizedBox(height: 16),
              Text(s.finished ? '修正後の最終点数' : '修正後の今の点数',
                  style: theme.textTheme.titleSmall),
              Card(
                child: Column(
                  children: [
                    for (var p = 0; p < s.playerCount; p++)
                      ListTile(
                        dense: true,
                        title: Text(s.playerNames[p]),
                        subtitle: Text(
                            '${formatPoints(s.scores[p])} → ${formatPoints(preview.scores[p])}'),
                        trailing: Text(formatDelta(preview.scores[p] - s.scores[p]),
                            style: theme.textTheme.titleSmall),
                      ),
                  ],
                ),
              ),
              if (preview.scores.any((v) => v < 0) && s.settings.tobi)
                Text('修正後に0点未満の人がいますが、局の進行は変わらないので対局は終わりません。',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: changed
                  ? () {
                      ref.read(sessionsProvider.notifier).editRound(
                            widget.sessionId,
                            widget.index,
                            deltas: [for (final d in deltas) d!],
                            description: _descController.text,
                            who: who,
                          );
                      Navigator.pop(context, true);
                    }
                  : null,
              child: const Text('修正を保存'),
            ),
            const SizedBox(height: 32),
            const Divider(),
            Text('この局を削除', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              '二重に入れた局などを消します。この局の点数の増減を取り消し、後の局の点数と今の点数をずらします'
              '（この局で場に出た立直棒は持ち主に戻ります）。今の局・本場は変わらないので、'
              'ずれたときは対局画面のメニュー「局・本場・供託を直す」で直してください。',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const ValueKey('delete-round'),
              style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
              icon: const Icon(Icons.delete_outline),
              label: const Text('この局を削除'),
              onPressed: () async {
                final why = SessionLogic.validateDeleteRound(s, widget.index);
                if (why != null) {
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(content: Text(why)));
                  return;
                }
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    content: Text('${record.roundLabel}（${record.description}）を削除しますか？'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
                      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('削除')),
                    ],
                  ),
                );
                if (ok != true || !context.mounted) return;
                ref.read(sessionsProvider.notifier).deleteRound(widget.sessionId, widget.index);
                Navigator.pop(context, 'deleted');
              },
            ),
          ],
        ),
      ),
    );
  }
}
