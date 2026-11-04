import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mahjong_score_engine/mahjong_score_engine.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../shared/widgets/tile_view.dart';
import '../session/domain/session_logic.dart';
import '../session/session_providers.dart';

/// 和了の計算結果の確認画面
class WinResultScreen extends ConsumerWidget {
  final String sessionId;
  final int winner;
  final int? loser;
  final WinInput input;
  final ScoreResult result;

  const WinResultScreen({
    super.key,
    required this.sessionId,
    required this.winner,
    required this.loser,
    required this.input,
    required this.result,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider(sessionId));
    if (s == null) return const Scaffold();
    final theme = Theme.of(context);
    final deltas =
        SessionLogic.winDeltas(s, winner: winner, loser: loser, result: result);
    final scoreText = ScoreCalculator.formatScore(result,
        isDealer: input.isDealer, isTsumo: input.isTsumo);
    final headline = result.isYakuman
        ? result.limitName ?? '役満'
        : '${result.han}翻 ${result.fu}符${result.limitName != null ? "  ${result.limitName}" : ""}';

    return Scaffold(
      appBar: AppBar(title: const Text('計算結果')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              '${s.playerNames[winner]} ${input.isTsumo ? "ツモ" : "ロン"}'
              '${loser != null ? "（放銃: ${s.playerNames[loser!]}）" : ""}',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 2,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                for (final t in input.handTiles) TileView(t, width: 24),
                const SizedBox(width: 6),
                TileView(input.winningTile, width: 24, selected: true),
                for (final m in input.melds) ...[
                  const SizedBox(width: 8),
                  for (final t in m.tiles) TileView(t, width: 20),
                ],
              ],
            ),
            const SizedBox(height: 16),
            Card(
              color: theme.colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(headline, style: theme.textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                      input.isTsumo ? scoreText : '${formatPoints(result.totalScore)}点',
                      style: theme.textTheme.displaySmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    if (input.isTsumo)
                      Text('（合計 ${formatPoints(result.totalScore)}点）'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text('役', style: theme.textTheme.titleSmall),
            Card(
              child: Column(
                children: [
                  for (final y in result.yakuList)
                    ListTile(
                      dense: true,
                      title: Text(y.name),
                      trailing: Text(
                        y.isYakuman
                            ? (y.han >= 2 ? '${y.han}倍役満' : '役満')
                            : '${y.han}翻',
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                ],
              ),
            ),
            if (!result.isYakuman && result.fuDetails.isNotEmpty)
              ExpansionTile(
                title: Text('符の内訳（${result.fu}符）'),
                children: [
                  for (final f in result.fuDetails)
                    ListTile(
                      dense: true,
                      title: Text(f.name),
                      trailing: Text('${f.fu}符'),
                    ),
                ],
              ),
            const SizedBox(height: 12),
            Text('点数移動', style: theme.textTheme.titleSmall),
            Card(
              child: Column(
                children: [
                  for (var p = 0; p < 4; p++)
                    ListTile(
                      dense: true,
                      title: Text(s.playerNames[p]),
                      subtitle: Text(
                          '${formatPoints(s.scores[p])} → ${formatPoints(s.scores[p] + deltas[p])}'),
                      trailing: Text(
                        formatDelta(deltas[p]),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: deltas[p] > 0
                              ? Colors.green.shade700
                              : deltas[p] < 0
                                  ? Colors.red.shade700
                                  : null,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (s.honba > 0 || s.riichiSticks > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '本場 ${s.honba}（+${result.paymentDetails.honbaGain}点） / '
                  '供託 ${s.riichiSticks}本（+${result.paymentDetails.riichiStickGain}点）を含む',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () {
                final yaku = result.yakuList.map((y) => y.name).join(' ');
                final desc = '${s.playerNames[winner]} '
                    '${input.isTsumo ? "ツモ" : "ロン ← ${s.playerNames[loser!]}"} '
                    '$headline $scoreText  [$yaku]';
                ref.read(sessionsProvider.notifier).applyWin(
                      sessionId,
                      winner: winner,
                      loser: loser,
                      result: result,
                      description: desc,
                    );
                popToDashboard(context);
              },
              child: const Text('この結果で確定'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: () => Navigator.pop(context),
              child: const Text('入力に戻る'),
            ),
          ],
        ),
      ),
    );
  }
}
