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

  @override
  void initState() {
    super.initState();
    final record = ref.read(sessionProvider(widget.sessionId))!.records[widget.index];
    _deltaControllers = [
      for (final d in record.deltas) TextEditingController(text: '$d')
    ];
    _descController = TextEditingController(text: record.description);
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
    final error = SessionLogic.validateRoundEdit(s, widget.index, deltas);
    final originalSum = record.deltas.fold<int>(0, (a, d) => a + d);
    // 修正後の点数の見込み
    final preview = error == null
        ? SessionLogic.editRound(s, widget.index,
            deltas: [for (final d in deltas) d!], description: _descController.text)
        : null;
    final changed = error == null &&
        (List.generate(4, (i) => deltas[i] != record.deltas[i]).any((c) => c) ||
            _descController.text != record.description);

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
                  '・修正できるのは、この局の点数の増減と内容のメモです（手牌は記録していないため、入力し直すことはできません）。\n'
                  '・修正した差分は、この局より後のすべての局の点数と、今の点数に反映されます。\n'
                  '・局の進行（親・本場・終局したかどうか）は変わりません。'
                  'トビの有無が変わる修正をしても、対局が途中で終わったり再開したりはしません。\n'
                  '・保存した直後に表示される「元に戻す」で取り消せます'
                  '（対局中の対局なら、対局画面の元に戻すボタンでも取り消せます）。',
                  style: TextStyle(color: theme.colorScheme.onTertiaryContainer, fontSize: 13),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('点数の増減', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            for (var p = 0; p < 4; p++)
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
              error ??
                  '4人の合計: ${formatDelta(originalSum)}'
                      '${originalSum != 0 ? "（供託リーチ棒の出入りの分。修正前と同じにしてください）" : "（修正前と同じ0にしてください）"}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: error != null ? theme.colorScheme.error : null),
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
                    for (var p = 0; p < 4; p++)
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
                          );
                      Navigator.pop(context, true);
                    }
                  : null,
              child: const Text('修正を保存'),
            ),
          ],
        ),
      ),
    );
  }
}
