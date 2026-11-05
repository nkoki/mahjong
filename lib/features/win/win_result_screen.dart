import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mahjong_score_engine/mahjong_score_engine.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../shared/widgets/tile_view.dart';
import '../session/domain/models.dart';
import '../session/domain/session_logic.dart';
import '../session/session_providers.dart';
import 'win_input_screen.dart';

/// 和了の計算結果の確認画面（ダブロンのときは2人分をまとめて確認・確定する）
class WinResultScreen extends ConsumerStatefulWidget {
  final String sessionId;

  /// 和了者と手の入力内容（ダブロンなら2人分）
  final List<WinEntry> entries;

  /// 放銃者（ツモなら null）
  final int? loser;

  const WinResultScreen({
    super.key,
    required this.sessionId,
    required this.entries,
    required this.loser,
  });

  static String headlineOf(ScoreResult r) => r.isYakuman
      ? r.limitName ?? '役満'
      : '${r.han}翻 ${r.fu}符${r.limitName != null ? "  ${r.limitName}" : ""}';

  @override
  ConsumerState<WinResultScreen> createState() => _WinResultScreenState();
}

class _WinResultScreenState extends ConsumerState<WinResultScreen> {
  /// 和了者ごとの包（責任払い）の人
  final Map<int, int?> _pao = {};

  String get sessionId => widget.sessionId;
  List<WinEntry> get entries => widget.entries;
  int? get loser => widget.loser;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider(sessionId));
    if (s == null) return const Scaffold();
    final theme = Theme.of(context);
    final wins = [
      for (final w in SessionLogic.scoreWins(s, entries, loser: loser))
        SessionLogic.canChoosePao(s, w) ? w.withPao(_pao[w.winner]) : w,
    ];
    final deltas = SessionLogic.winsDeltas(s, wins, loser: loser);
    final isDouble = wins.length > 1;
    final taker = SessionLogic.honbaTaker([for (final w in wins) w.winner],
        loser: loser, playerCount: s.playerCount);
    final canAddRon = loser != null &&
        s.settings.doubleRon &&
        wins.length < SessionLogic.maxRonWinners;

    return Scaffold(
      appBar: AppBar(title: Text(isDouble ? '計算結果（ダブロン）' : '計算結果')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final w in wins) ...[
              _WinCard(
                session: s,
                win: w,
                loser: loser,
                onPaoChanged: SessionLogic.canChoosePao(s, w)
                    ? (p) => setState(() => _pao[w.winner] = p)
                    : null,
              ),
              const SizedBox(height: 12),
            ],
            if (isDouble && (s.honba > 0 || s.riichiSticks > 0))
              Card(
                color: theme.colorScheme.tertiaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '本場（${s.honba}本場）と供託（${s.riichiSticks}本）は、放銃者から見て打つ順番が近い '
                    '${s.playerNames[taker]} が受け取ります（上家取り）。',
                    style: TextStyle(color: theme.colorScheme.onTertiaryContainer),
                  ),
                ),
              ),
            const SizedBox(height: 4),
            Text(isDouble ? '点数移動（2人分の合計）' : '点数移動', style: theme.textTheme.titleSmall),
            Card(
              child: Column(
                children: [
                  for (var p = 0; p < s.playerCount; p++)
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
            if (!isDouble && (s.honba > 0 || s.riichiSticks > 0))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '本場 ${s.honba}（+${wins.single.result.paymentDetails.honbaGain}点） / '
                  '供託 ${s.riichiSticks}本（+${wins.single.result.paymentDetails.riichiStickGain}点）を含む',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () {
                ref.read(sessionsProvider.notifier).applyWins(
                      sessionId,
                      wins: wins,
                      loser: loser,
                      description: _description(s, wins),
                    );
                popToDashboard(context);
              },
              child: Text(isDouble ? '2人分の結果で確定' : 'この結果で確定'),
            ),
            if (canAddRon) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                icon: const Icon(Icons.group_add_outlined),
                label: const Text('ダブロン：もう1人のロン和了を入力'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => WinInputScreen(
                    sessionId: sessionId,
                    previousWins: entries,
                    fixedLoser: loser,
                  ),
                )),
              ),
            ],
            if (loser != null && !s.settings.doubleRon)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'ダブロンなし（頭ハネ）のルールです。2人がロンした場合は、'
                  '放銃者から見て打つ順番が近い人だけを入力してください。',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: () => Navigator.pop(context),
              child: Text(isDouble ? '2人目の入力に戻る' : '入力に戻る'),
            ),
          ],
        ),
      ),
    );
  }

  String _description(GameSession s, List<ScoredWin> wins) {
    final parts = [
      for (final w in wins)
        '${s.playerNames[w.winner]} '
            '${w.input.isTsumo ? "ツモ" : "ロン ← ${s.playerNames[loser!]}"} '
            '${WinResultScreen.headlineOf(w.result)} '
            '${ScoreCalculator.formatScore(w.result, isDealer: w.input.isDealer, isTsumo: w.input.isTsumo)}  '
            '[${w.result.yakuList.map((y) => y.name).join(' ')}]'
            '${w.pao != null ? '（包: ${s.playerNames[w.pao!]}）' : ''}'
    ];
    return wins.length > 1 ? 'ダブロン: ${parts.join(' / ')}' : parts.single;
  }
}

/// 和了者1人分の結果
class _WinCard extends StatelessWidget {
  final GameSession session;
  final ScoredWin win;
  final int? loser;

  /// 包の人を選んだとき（包を選べない和了なら null）
  final ValueChanged<int?>? onPaoChanged;

  const _WinCard({
    required this.session,
    required this.win,
    required this.loser,
    this.onPaoChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = win.result;
    final input = win.input;
    if (!r.isValid) {
      return Card(child: ListTile(title: Text(r.error ?? '計算できませんでした')));
    }
    final scoreText =
        ScoreCalculator.formatScore(r, isDealer: input.isDealer, isTsumo: input.isTsumo);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${session.playerNames[win.winner]} ${input.isTsumo ? "ツモ" : "ロン"}'
          '${loser != null ? "（放銃: ${session.playerNames[loser!]}）" : ""}',
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
        const SizedBox(height: 12),
        Card(
          color: theme.colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Column(
                children: [
                  Text(WinResultScreen.headlineOf(r), style: theme.textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    input.isTsumo ? scoreText : '${formatPoints(r.totalScore)}点',
                    style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  if (input.isTsumo) Text('（合計 ${formatPoints(r.totalScore)}点）'),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text('役', style: theme.textTheme.titleSmall),
        Card(
          child: Column(
            children: [
              for (final y in r.yakuList)
                ListTile(
                  dense: true,
                  title: Text(y.name),
                  trailing: Text(
                    y.isYakuman ? (y.han >= 2 ? '${y.han}倍役満' : '役満') : '${y.han}翻',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
            ],
          ),
        ),
        if (onPaoChanged != null) _paoSection(context),
        if (!r.isYakuman && r.fuDetails.isNotEmpty)
          ExpansionTile(
            title: Text('符の内訳（${r.fu}符）'),
            children: [
              for (final f in r.fuDetails)
                ListTile(dense: true, title: Text(f.name), trailing: Text('${f.fu}符')),
            ],
          ),
      ],
    );
  }

  /// 包（責任払い）の人を選ぶ欄
  Widget _paoSection(BuildContext context) {
    final theme = Theme.of(context);
    final names = session.playerNames;
    final yaku = win.result.yakuList
        .where((y) => SessionLogic.paoYakuman.contains(y.name))
        .map((y) => y.name)
        .join('・');
    return Card(
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('包（責任払い）', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              '$yaku を確定させる牌を鳴かせた人がいれば選んでください。'
              '${loser == null ? 'ツモなので、$yaku の分と本場をその人が全額払います。' : 'ロンなので、$yaku の分をその人と放銃者で半分ずつ払います（本場は放銃者）。放銃者が包の人なら普段どおりです。'}',
              style: TextStyle(color: theme.colorScheme.onTertiaryContainer, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                ChoiceChip(
                  label: const Text('なし'),
                  selected: win.pao == null,
                  onSelected: (_) => onPaoChanged!(null),
                ),
                for (var p = 0; p < session.playerCount; p++)
                  if (p != win.winner)
                    ChoiceChip(
                      label: Text(names[p]),
                      selected: win.pao == p,
                      onSelected: (_) => onPaoChanged!(p),
                    ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
