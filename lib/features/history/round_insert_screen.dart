import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../session/domain/session_logic.dart';
import '../session/session_providers.dart';

/// 入れ忘れた局を追加する画面
class RoundInsertScreen extends ConsumerStatefulWidget {
  final String sessionId;
  const RoundInsertScreen({super.key, required this.sessionId});

  @override
  ConsumerState<RoundInsertScreen> createState() => _RoundInsertScreenState();
}

class _RoundInsertScreenState extends ConsumerState<RoundInsertScreen> {
  late final List<TextEditingController> _deltas;
  final _label = TextEditingController();
  final _desc = TextEditingController();

  /// 追加する場所（この番号の局の前。局の数なら最後）
  late int _index;

  /// 和了の局か（false なら流局など）
  bool _win = true;
  List<int> _winners = [];
  int? _loser;

  @override
  void initState() {
    super.initState();
    final s = ref.read(sessionProvider(widget.sessionId))!;
    _deltas = [for (var i = 0; i < s.playerCount; i++) TextEditingController()];
    _index = s.records.length;
    _label.text = s.finished ? '' : s.roundLabel;
  }

  @override
  void dispose() {
    for (final c in _deltas) {
      c.dispose();
    }
    _label.dispose();
    _desc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider(widget.sessionId));
    if (s == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('対局が見つかりません')));
    final theme = Theme.of(context);
    final deltas = [for (final c in _deltas) c.text.trim().isEmpty ? 0 : int.tryParse(c.text.trim())];
    final error = SessionLogic.validateInsertRound(s, _index, deltas,
        winners: _win ? _winners : null, loser: _win ? _loser : null);

    return Scaffold(
      appBar: AppBar(title: const Text('入れ忘れた局を追加')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: theme.colorScheme.tertiaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '・入れ忘れた局の点数の増減を入れます。合計は0にしてください（立直棒の出入りは含めません）。\n'
                  '・追加した局より後の局の点数と、今の点数に反映されます。\n'
                  '・今の局・本場・供託は変わりません。ずれたときは対局画面のメニュー「局・本場・供託を直す」で直してください。\n'
                  '・保存した直後に表示される「元に戻す」で取り消せます。',
                  style: TextStyle(color: theme.colorScheme.onTertiaryContainer, fontSize: 13),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('追加する場所', style: theme.textTheme.titleSmall),
            DropdownButton<int>(
              key: const ValueKey('insert-position'),
              isExpanded: true,
              value: _index,
              items: [
                for (var i = 0; i < s.records.length; i++)
                  DropdownMenuItem(value: i, child: Text('${s.records[i].roundLabel}（${s.records[i].description}）の前')),
                DropdownMenuItem(value: s.records.length, child: const Text('最後（いちばん新しい局のあと）')),
              ],
              onChanged: (v) => setState(() => _index = v!),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('insert-label'),
              controller: _label,
              decoration: const InputDecoration(labelText: '局の名前（例: 東2局 1本場）', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('和了')),
                ButtonSegment(value: false, label: Text('流局など')),
              ],
              selected: {_win},
              onSelectionChanged: (v) => setState(() => _win = v.first),
            ),
            if (_win) ...[
              const SizedBox(height: 12),
              Text('和了した人', style: theme.textTheme.titleSmall),
              Wrap(
                spacing: 8,
                children: [
                  for (var p = 0; p < s.playerCount; p++)
                    FilterChip(
                      key: ValueKey('insert-winner-$p'),
                      label: Text(s.playerNames[p]),
                      selected: _winners.contains(p),
                      onSelected: (v) => setState(() {
                        _winners = v ? ([..._winners, p]..sort()) : [..._winners.where((w) => w != p)];
                        if (v && _loser == p) _loser = null;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text('放銃した人', style: theme.textTheme.titleSmall),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('なし（ツモ）'),
                    selected: _loser == null,
                    onSelected: (_) => setState(() => _loser = null),
                  ),
                  for (var p = 0; p < s.playerCount; p++)
                    if (!_winners.contains(p))
                      ChoiceChip(
                        key: ValueKey('insert-loser-$p'),
                        label: Text(s.playerNames[p]),
                        selected: _loser == p,
                        onSelected: (_) => setState(() => _loser = p),
                      ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Text('点数の増減（動かない人は空欄か0）', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            for (var p = 0; p < s.playerCount; p++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(child: Text(s.playerNames[p], overflow: TextOverflow.ellipsis)),
                    SizedBox(
                      width: 140,
                      child: TextField(
                        key: ValueKey('insert-delta-$p'),
                        controller: _deltas[p],
                        keyboardType: const TextInputType.numberWithOptions(signed: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*'))],
                        textAlign: TextAlign.end,
                        decoration: const InputDecoration(isDense: true, suffixText: '点', border: OutlineInputBorder()),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
              ),
            if (error != null)
              Text(error, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error))
            else
              Text('合計 ${formatDelta(0)}', style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            TextField(
              controller: _desc,
              decoration: const InputDecoration(labelText: '内容のメモ（省略可）', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: error != null
                  ? null
                  : () {
                      ref.read(sessionsProvider.notifier).insertRound(
                            widget.sessionId,
                            _index,
                            roundLabel: _label.text,
                            deltas: [for (final d in deltas) d!],
                            winners: _win ? _winners : null,
                            loser: _win ? _loser : null,
                            description: _desc.text,
                          );
                      Navigator.pop(context, 'inserted');
                    },
              child: const Text('局を追加'),
            ),
          ],
        ),
      ),
    );
  }
}
