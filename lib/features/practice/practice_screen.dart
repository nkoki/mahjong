import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mahjong_score_engine/mahjong_score_engine.dart';

import '../../core/l10n.dart';
import '../../shared/widgets/tile_view.dart';
import '../session/session_providers.dart';
import 'practice_generator.dart';

/// 点数計算の練習（あがった手を見て、点数を4つから選ぶ）
class PracticeScreen extends ConsumerStatefulWidget {
  /// 問題を作る乱数（テスト用。null なら毎回ちがう問題）
  final Random? random;

  const PracticeScreen({super.key, this.random});

  @override
  ConsumerState<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends ConsumerState<PracticeScreen> {
  late final Random _rng = widget.random ?? Random();
  late PracticeQuestion _q;
  String? _picked;
  int _answered = 0, _correct = 0, _streak = 0;

  ScoreRules get _rules => ref.read(defaultSettingsProvider).scoreRules;

  @override
  void initState() {
    super.initState();
    _q = PracticeGenerator.generate(_rng, rules: _rules);
  }

  void _pick(String c) {
    if (_picked != null) return;
    setState(() {
      _picked = c;
      _answered++;
      if (c == _q.answer) {
        _correct++;
        _streak++;
      } else {
        _streak = 0;
      }
    });
  }

  void _next() => setState(() {
        _q = PracticeGenerator.generate(_rng, rules: _rules);
        _picked = null;
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = _q;
    final input = q.input;
    final seat = windName(int.parse(input.playerWind[0]) - 1);
    final round = windName(int.parse(input.roundWind[0]) - 1);
    final small = theme.textTheme.bodySmall;
    final done = _picked != null;
    final r = q.result;

    return Scaffold(
      appBar: AppBar(title: Text(tr('点数計算の練習', 'Scoring practice'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
              tr('正解 $_correct / $_answered問${_streak >= 2 ? '（$_streak問連続正解）' : ''}',
                  'Correct $_correct / $_answered${_streak >= 2 ? ' ($_streak in a row)' : ''}'),
              key: const ValueKey('practice-score'), style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              Chip(label: Text(tr('$round場', '$round round'))),
              Chip(label: Text(tr('$seat家（${q.isDealer ? "親" : "子"}）', '$seat seat (${q.isDealer ? "dealer" : "non-dealer"})'))),
              Chip(label: Text(q.isTsumo ? tr('ツモ', 'Tsumo') : tr('ロン', 'Ron'))),
              if (input.isRiichi) Chip(label: Text(tr('立直', 'Riichi'))),
            ],
          ),
          const SizedBox(height: 8),
          Text(tr('手牌', 'Hand'), style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Wrap(
            spacing: 2,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              for (final t in input.handTiles) TileView(t, width: 26),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(q.isTsumo ? tr('ツモ', 'Tsumo') : tr('ロン', 'Ron'), style: small),
                  TileView(input.winningTile, width: 26, selected: true),
                ],
              ),
            ],
          ),
          if (input.melds.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(tr('鳴き', 'Calls'), style: small),
            Wrap(
              spacing: 10,
              children: [
                for (final m in input.melds)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 0; i < m.tiles.length; i++)
                        TileView(m.tiles[i], width: 26, sideways: i == 0),
                      const SizedBox(width: 4),
                      Text(m.type == MeldType.chi ? tr('チー', 'Chi') : tr('ポン', 'Pon'), style: small),
                    ],
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Text(tr('ドラ表示牌 ', 'Dora indicator '), style: small),
              for (final t in input.doraTiles) TileView(t, width: 22),
              if (input.uraDoraTiles.isNotEmpty) ...[
                Text(tr('  裏ドラ表示牌 ', '  Ura dora indicator '), style: small),
                for (final t in input.uraDoraTiles) TileView(t, width: 22),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Text(tr('この和了の点数は？（本場・供託なし）', 'How many points is this win? (no honba or deposits)'), style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final c in q.choices)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OutlinedButton(
                key: ValueKey('choice-$c'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  backgroundColor: !done
                      ? null
                      : c == q.answer
                          ? Colors.green.withAlpha(60)
                          : c == _picked
                              ? Colors.red.withAlpha(60)
                              : null,
                ),
                onPressed: done ? null : () => _pick(c),
                child: Text(c, style: theme.textTheme.titleMedium),
              ),
            ),
          if (done) ...[
            Card(
              color: _picked == q.answer ? Colors.green.withAlpha(40) : Colors.red.withAlpha(40),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_picked == q.answer ? tr('正解！', 'Correct!') : tr('不正解。正しくは ${q.answer}', 'Wrong. The answer is ${q.answer}'),
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text(tr(
                        '${r.han}翻 ${r.fu}符${r.limitName != null ? '（${r.limitName}）' : ''}'
                            '・${q.isDealer ? "親" : "子"}の${q.isTsumo ? "ツモ" : "ロン"}',
                        '${r.han} han ${r.fu} fu${r.limitName != null ? ' (${limitName(r.limitName!)})' : ''}'
                            ', ${q.isDealer ? "dealer" : "non-dealer"} ${q.isTsumo ? "tsumo" : "ron"}')),
                    const SizedBox(height: 4),
                    Text(tr('役: ${r.yakuList.map((y) => y.toString()).join('、')}', 'Yaku: ${r.yakuList.map(_yakuEn).join(', ')}'),
                        style: small),
                    if (r.limitName == null || r.han < 5) ...[
                      const SizedBox(height: 4),
                      Text(
                          tr('符: ${r.fuDetails.map((f) => f.toString()).join('、')}',
                              'Fu: ${r.fuDetails.map((f) => '${fuName(f.name)}: ${f.fu} fu').join(', ')}'),
                          style: small),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(key: const ValueKey('practice-next'), onPressed: _next, child: Text(tr('次の問題', 'Next question'))),
          ],
          const SizedBox(height: 12),
          Text(
              tr(
                  '問題はでたらめに作ったあがり形です（鳴きは1つまで、赤ドラ・槓・役満は出ません）。'
                      'ルール設定（4人打ち）の喰いタン・切り上げ満貫などに従って計算しています。',
                  'Questions are randomly generated winning hands (at most one call; no red dora, kans or yakuman). '
                      'Scores follow the rule settings (4-player), such as open tanyao and rounded-up mangan.'),
              style: small),
        ],
      ),
    );
  }
}

/// 役の英語の表示（例: Riichi (1 han)）
String _yakuEn(Yaku y) {
  final name = yakuName(y.name);
  if (!y.isYakuman) return '$name (${y.han} han)';
  return y.han >= 2 ? '$name (${y.han}x yakuman)' : '$name (yakuman)';
}
