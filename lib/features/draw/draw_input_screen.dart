import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';
import '../session/domain/models.dart';
import '../session/domain/session_logic.dart';
import '../session/session_providers.dart';

/// 流局入力画面（7種類の流局に対応）
class DrawInputScreen extends ConsumerStatefulWidget {
  final String sessionId;
  const DrawInputScreen({super.key, required this.sessionId});

  @override
  ConsumerState<DrawInputScreen> createState() => _DrawInputScreenState();
}

class _DrawInputScreenState extends ConsumerState<DrawInputScreen> {
  DrawType _type = DrawType.exhaustive;
  final List<bool> _tenpai = [false, false, false, false];
  int? _nagashi;

  @override
  void initState() {
    super.initState();
    // 立直者はテンパイとして初期選択
    final s = ref.read(sessionProvider(widget.sessionId));
    if (s != null) {
      for (var i = 0; i < 4; i++) {
        _tenpai[i] = s.riichi[i];
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider(widget.sessionId));
    if (s == null) return const Scaffold();
    final theme = Theme.of(context);
    final needsTenpai = !_type.isAbortive;
    final deltas = SessionLogic.drawDeltas(s,
        type: _type, tenpai: _tenpai, nagashiPlayer: _nagashi);
    final renchan = _type.isAbortive || _tenpai[s.dealer];
    final canConfirm = _type != DrawType.nagashiMangan || _nagashi != null;

    return Scaffold(
      appBar: AppBar(title: Text('流局入力  ${s.roundLabel}')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('流局の種類', style: theme.textTheme.titleSmall),
            for (final t in DrawType.values)
              if ((t != DrawType.nagashiMangan || s.settings.nagashiMangan) &&
                  (!t.isAbortive || s.settings.abortiveDraws))
              ListTile(
                dense: true,
                leading: Icon(
                  _type == t ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: _type == t ? theme.colorScheme.primary : null,
                ),
                title: Text(t.label),
                subtitle: t.isAbortive ? const Text('途中流局（親の連荘・本場+1）') : null,
                onTap: () => setState(() => _type = t),
              ),
            if (_type == DrawType.nagashiMangan) ...[
              const SizedBox(height: 8),
              Text('流し満貫を達成した人', style: theme.textTheme.titleSmall),
              Wrap(
                spacing: 6,
                children: [
                  for (var p = 0; p < 4; p++)
                    ChoiceChip(
                      label: Text(s.playerNames[p]),
                      selected: _nagashi == p,
                      onSelected: (_) => setState(() => _nagashi = p),
                    ),
                ],
              ),
            ],
            if (needsTenpai) ...[
              const SizedBox(height: 8),
              Text('テンパイしていた人', style: theme.textTheme.titleSmall),
              for (var p = 0; p < 4; p++)
                CheckboxListTile(
                  dense: true,
                  title: Text(
                      '${GameSession.windNames[s.seatWindIndexOf(p)]} ${s.playerNames[p]}'
                      '${s.riichi[p] ? "（立直）" : ""}'),
                  value: _tenpai[p],
                  onChanged: (v) => setState(() => _tenpai[p] = v ?? false),
                ),
            ],
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  for (var p = 0; p < 4; p++)
                    ListTile(
                      dense: true,
                      title: Text(s.playerNames[p]),
                      trailing: Text(formatDelta(deltas[p]),
                          style: theme.textTheme.titleMedium),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '次局: ${renchan ? "親の連荘" : "親流れ"}・${s.honba + 1}本場'
                '（供託${s.riichiSticks}本は持ち越し）',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            FilledButton(
              onPressed: !canConfirm
                  ? null
                  : () {
                      ref.read(sessionsProvider.notifier).applyDraw(
                            widget.sessionId,
                            type: _type,
                            tenpai: List.of(_tenpai),
                            nagashiPlayer: _nagashi,
                          );
                      popToDashboard(context);
                    },
              child: const Text('確定'),
            ),
          ],
        ),
      ),
    );
  }
}
