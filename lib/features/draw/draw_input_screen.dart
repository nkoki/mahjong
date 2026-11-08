import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
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
  late final List<bool> _tenpai;
  int? _nagashi;

  @override
  void initState() {
    super.initState();
    // 立直者はテンパイとして初期選択
    final s = ref.read(sessionProvider(widget.sessionId));
    _tenpai = s == null ? List.filled(4, false) : List.of(s.riichi);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider(widget.sessionId));
    if (s == null) return const Scaffold();
    final theme = Theme.of(context);
    final needsTenpai = !_type.isAbortive;
    final deltas = SessionLogic.drawDeltas(s,
        type: _type, tenpai: _tenpai, nagashiPlayer: _nagashi);
    // 四家立直: 立直を押していない人からも、供託を1本ずつ取る（すでに立直している人からは取らない）
    final suuchaMissing = _type == DrawType.suucha ? SessionLogic.suuchaMissingRiichi(s) : const <int>[];
    for (final p in suuchaMissing) {
      deltas[p] -= 1000;
    }
    final sticksAfter = s.riichiSticks + suuchaMissing.length;
    final renchan = _type.isAbortive || _tenpai[s.dealer];
    final canConfirm = _type != DrawType.nagashiMangan || _nagashi != null;

    return Scaffold(
      appBar: AppBar(title: Text(tr('流局入力  ${s.roundLabel}', 'Draw  ${displayRoundLabel(s.roundLabel)}'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(tr('流局の種類', 'Draw type'), style: theme.textTheme.titleSmall),
            for (final t in DrawType.availableFor(s.settings))
              ListTile(
                dense: true,
                leading: Icon(
                  _type == t ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: _type == t ? theme.colorScheme.primary : null,
                ),
                title: Text(t.label),
                subtitle: t.isAbortive ? Text(tr('途中流局（親の連荘・本場+1）', 'Abortive draw (dealer renchan, +1 honba)')) : null,
                onTap: () => setState(() => _type = t),
              ),
            if (_type == DrawType.nagashiMangan) ...[
              const SizedBox(height: 8),
              Text(tr('流し満貫を達成した人', 'Who got nagashi mangan'), style: theme.textTheme.titleSmall),
              Wrap(
                spacing: 6,
                children: [
                  for (var p = 0; p < s.playerCount; p++)
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
              Text(tr('テンパイしていた人', 'Who was tenpai'), style: theme.textTheme.titleSmall),
              for (var p = 0; p < s.playerCount; p++)
                CheckboxListTile(
                  dense: true,
                  title: Text(
                      '${windName(s.seatWindIndexOf(p))} ${s.playerNames[p]}'
                      '${s.riichi[p] ? tr("（立直）", " (riichi)") : ""}'),
                  value: _tenpai[p],
                  onChanged: (v) => setState(() => _tenpai[p] = v ?? false),
                ),
            ],
            if (_type == DrawType.suucha)
              Padding(
                key: const ValueKey('suucha-note'),
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  suuchaMissing.isEmpty
                      ? tr('4人とも立直の供託を出しているので、追加では取りません。',
                          'All four players have already put in a riichi stick, so nothing more is taken.')
                      : tr(
                          '四家立直は全員が立直しているので、立直を押していない '
                              '${suuchaMissing.map((p) => s.playerNames[p]).join("・")} からも供託を1本（1,000点）ずつ取ります。'
                              'すでに立直している人からは取りません。',
                          'Everyone is in riichi, so 1 stick (1,000 pts) each is also taken from '
                              '${suuchaMissing.map((p) => s.playerNames[p]).join(", ")}, who had not pressed riichi. '
                              'Players already in riichi are not charged again.'),
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
                ),
              ),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  for (var p = 0; p < s.playerCount; p++)
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
                tr(
                    '次局: ${renchan ? "親の連荘" : "親流れ"}・${s.honba + 1}本場'
                        '（供託$sticksAfter本は持ち越し）',
                    'Next: ${renchan ? "dealer renchan" : "dealer passes"}, ${s.honba + 1} honba'
                        ' ($sticksAfter riichi sticks carried over)'),
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
              child: Text(tr('確定', 'Confirm')),
            ),
          ],
        ),
      ),
    );
  }
}
