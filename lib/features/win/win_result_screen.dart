import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mahjong_score_engine/mahjong_score_engine.dart';

import '../../core/l10n.dart';
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
      : '${r.han}翻${r.fu > 0 ? " ${r.fu}符" : ""}${r.limitName != null ? "  ${r.limitName}" : ""}';

  /// 画面に出す見出し（英語のときは英語。記録に残す文は [headlineOf] で日本語のまま）
  static String displayHeadlineOf(ScoreResult r) {
    if (!L10n.isEnglish) return headlineOf(r);
    if (r.isYakuman) return limitName(r.limitName ?? '役満');
    return '${r.han} han${r.fu > 0 ? " ${r.fu} fu" : ""}${r.limitName != null ? "  ${limitName(r.limitName!)}" : ""}';
  }

  @override
  ConsumerState<WinResultScreen> createState() => _WinResultScreenState();
}

class _WinResultScreenState extends ConsumerState<WinResultScreen> {
  /// 和了者ごとの包（責任払い）の人
  final Map<int, int?> _pao = {};

  /// 和了者ごとの祝儀の枚数（変えていなければ目安の枚数）
  final Map<int, int> _chips = {};

  int _chipsOf(GameSession s, ScoredWin w) => _chips[w.winner] ?? SessionLogic.suggestedChips(s, w);

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
      appBar: AppBar(title: Text(isDouble ? tr('計算結果（ダブロン）', 'Result (double ron)') : tr('計算結果', 'Result'))),
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
              if (s.settings.chips && w.result.isValid) _chipRow(s, w),
              const SizedBox(height: 12),
            ],
            if (isDouble && (s.honba > 0 || s.riichiSticks > 0))
              Card(
                color: theme.colorScheme.tertiaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    tr(
                        '本場（${s.honba}本場）と供託（${s.riichiSticks}本）は、放銃者から見て打つ順番が近い '
                            '${s.playerNames[taker]} が受け取ります（上家取り）。',
                        'Honba (${s.honba}) and riichi sticks (${s.riichiSticks}) go to '
                            '${s.playerNames[taker]}, the winner closest in turn order after the discarder.'),
                    style: TextStyle(color: theme.colorScheme.onTertiaryContainer),
                  ),
                ),
              ),
            const SizedBox(height: 4),
            Text(isDouble ? tr('点数移動（2人分の合計）', 'Point changes (both winners)') : tr('点数移動', 'Point changes'), style: theme.textTheme.titleSmall),
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
                          color: deltaColor(context, deltas[p]),
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
                  tr(
                      '本場 ${s.honba}（+${wins.single.result.paymentDetails.honbaGain}点） / '
                          '供託 ${s.riichiSticks}本（+${wins.single.result.paymentDetails.riichiStickGain}点）を含む',
                      'Includes ${s.honba} honba (+${wins.single.result.paymentDetails.honbaGain} pts) / '
                          '${s.riichiSticks} riichi sticks (+${wins.single.result.paymentDetails.riichiStickGain} pts)'),
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
                      chips: s.settings.chips ? {for (final w in wins) w.winner: _chipsOf(s, w)} : const {},
                    );
                popToDashboard(context);
              },
              child: Text(isDouble ? tr('2人分の結果で確定', 'Confirm both results') : tr('この結果で確定', 'Confirm')),
            ),
            if (canAddRon) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                icon: const Icon(Icons.group_add_outlined),
                label: Text(tr('ダブロン：もう1人のロン和了を入力', 'Double ron: enter another ron winner')),
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
                  tr(
                      'ダブロンなし（頭ハネ）のルールです。2人がロンした場合は、'
                          '放銃者から見て打つ順番が近い人だけを入力してください。',
                      'Double ron is off (head bump). If two players ron, '
                          'enter only the one closest in turn order after the discarder.'),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: () => Navigator.pop(context),
              child: Text(isDouble ? tr('2人目の入力に戻る', 'Back to 2nd winner') : tr('入力に戻る', 'Back to input')),
            ),
          ],
        ),
      ),
    );
  }

  /// 祝儀の枚数を入れる欄（祝儀ありのルールのとき）
  Widget _chipRow(GameSession s, ScoredWin w) {
    final theme = Theme.of(context);
    final n = _chipsOf(s, w);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('祝儀（${s.playerNames[w.winner]}）', 'Chips (${s.playerNames[w.winner]})'), style: theme.textTheme.titleSmall),
                  Text(
                    w.hanFu != null
                        ? tr('翻・符で入力したときは自動で数えません', 'Not counted automatically for han/fu input')
                        : tr(
                            '目安: 赤ドラ・裏ドラ・一発の数（${SessionLogic.suggestedChips(s, w)}枚）。'
                                '${loser == null ? 'ツモなので、ほかの全員が$n枚ずつ払います' : '放銃者が払います'}',
                            'Suggested: red fives, ura dora, ippatsu (${SessionLogic.suggestedChips(s, w)}). '
                                '${loser == null ? 'Tsumo: everyone else pays $n each' : 'The discarder pays'}'),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton.outlined(
              tooltip: tr('祝儀を減らす', 'Fewer chips'),
              onPressed: n > 0 ? () => setState(() => _chips[w.winner] = n - 1) : null,
              icon: const Icon(Icons.remove),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(tr('$n枚', '$n'), key: ValueKey('chips-${w.winner}'), style: theme.textTheme.titleMedium),
            ),
            IconButton.outlined(
              tooltip: tr('祝儀を増やす', 'More chips'),
              onPressed: n < 99 ? () => setState(() => _chips[w.winner] = n + 1) : null,
              icon: const Icon(Icons.add),
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
            '${s.settings.chips && _chipsOf(s, w) > 0 ? '（祝儀${_chipsOf(s, w)}枚）' : ''}'
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
      return Card(child: ListTile(title: Text(r.error != null ? engineError(r.error!) : tr('計算できませんでした', 'Could not calculate'))));
    }
    final scoreText = ScoreCalculator.formatScore(r, isDealer: input.isDealer, isTsumo: input.isTsumo)
        .replaceAll('オール', tr('オール', ' all'));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${session.playerNames[win.winner]} ${input.isTsumo ? tr("ツモ", "Tsumo") : tr("ロン", "Ron")}'
          '${loser != null ? tr("（放銃: ${session.playerNames[loser!]}）", " (from ${session.playerNames[loser!]})") : ""}',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (win.hanFu != null)
          Text(tr('翻・符で入力（手牌は入力していません）', 'Entered as han/fu (no hand entered)'), style: theme.textTheme.bodySmall)
        else
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
                  Text(WinResultScreen.displayHeadlineOf(r), style: theme.textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    input.isTsumo ? scoreText : tr('${formatPoints(r.totalScore)}点', '${formatPoints(r.totalScore)} pts'),
                    style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  if (input.isTsumo) Text(tr('（合計 ${formatPoints(r.totalScore)}点）', '(total ${formatPoints(r.totalScore)} pts)')),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(tr('役', 'Yaku'), style: theme.textTheme.titleSmall),
        Card(
          child: Column(
            children: [
              for (final y in r.yakuList)
                ListTile(
                  dense: true,
                  title: Text(yakuName(y.name)),
                  trailing: Text(
                    y.isYakuman
                        ? (y.han >= 2 ? tr('${y.han}倍役満', '${y.han}x yakuman') : tr('役満', 'Yakuman'))
                        : tr('${y.han}翻', '${y.han} han'),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
            ],
          ),
        ),
        if (onPaoChanged != null) _paoSection(context),
        if (!r.isYakuman && r.fuDetails.isNotEmpty)
          ExpansionTile(
            title: Text(tr('符の内訳（${r.fu}符）', 'Fu breakdown (${r.fu} fu)')),
            children: [
              for (final f in r.fuDetails)
                ListTile(dense: true, title: Text(fuName(f.name)), trailing: Text(tr('${f.fu}符', '${f.fu} fu'))),
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
        .map((y) => yakuName(y.name))
        .join(tr('・', ', '));
    return Card(
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('包（責任払い）', 'Pao (liability)'), style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              tr(
                  '$yaku を確定させる牌を鳴かせた人がいれば選んでください。'
                      '${loser == null ? 'ツモなので、$yaku の分と本場をその人が全額払います。' : 'ロンなので、$yaku の分をその人と放銃者で半分ずつ払います（本場は放銃者）。放銃者が包の人なら普段どおりです。'}',
                  'Select the player who fed the tile that completed $yaku, if any. '
                      '${loser == null ? 'Tsumo: that player pays all of $yaku and the honba.' : 'Ron: that player and the discarder split $yaku (the discarder pays the honba). If the discarder is the pao player, it is a normal payment.'}'),
              style: TextStyle(color: theme.colorScheme.onTertiaryContainer, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                ChoiceChip(
                  label: Text(tr('なし', 'None')),
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
