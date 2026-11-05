import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mahjong_score_engine/mahjong_score_engine.dart';

import '../../shared/widgets/tile_view.dart';
import '../session/domain/models.dart';
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
    final seat = GameSession.windNames[int.parse(input.playerWind[0]) - 1];
    final round = GameSession.windNames[int.parse(input.roundWind[0]) - 1];
    final small = theme.textTheme.bodySmall;
    final done = _picked != null;
    final r = q.result;

    return Scaffold(
      appBar: AppBar(title: const Text('点数計算の練習')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('正解 $_correct / $_answered問${_streak >= 2 ? '（$_streak問連続正解）' : ''}',
              key: const ValueKey('practice-score'), style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              Chip(label: Text('$round場')),
              Chip(label: Text('$seat家（${q.isDealer ? "親" : "子"}）')),
              Chip(label: Text(q.isTsumo ? 'ツモ' : 'ロン')),
              if (input.isRiichi) const Chip(label: Text('立直')),
            ],
          ),
          const SizedBox(height: 8),
          Text('手牌', style: theme.textTheme.titleSmall),
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
                  Text(q.isTsumo ? 'ツモ' : 'ロン', style: small),
                  TileView(input.winningTile, width: 26, selected: true),
                ],
              ),
            ],
          ),
          if (input.melds.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('鳴き', style: small),
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
                      Text(m.type == MeldType.chi ? 'チー' : 'ポン', style: small),
                    ],
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Text('ドラ表示牌 ', style: small),
              for (final t in input.doraTiles) TileView(t, width: 22),
              if (input.uraDoraTiles.isNotEmpty) ...[
                Text('  裏ドラ表示牌 ', style: small),
                for (final t in input.uraDoraTiles) TileView(t, width: 22),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Text('この和了の点数は？（本場・供託なし）', style: theme.textTheme.titleMedium),
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
                    Text(_picked == q.answer ? '正解！' : '不正解。正しくは ${q.answer}',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text(
                        '${r.han}翻 ${r.fu}符${r.limitName != null ? '（${r.limitName}）' : ''}'
                        '・${q.isDealer ? "親" : "子"}の${q.isTsumo ? "ツモ" : "ロン"}'),
                    const SizedBox(height: 4),
                    Text('役: ${r.yakuList.map((y) => y.toString()).join('、')}', style: small),
                    if (r.limitName == null || r.han < 5) ...[
                      const SizedBox(height: 4),
                      Text('符: ${r.fuDetails.map((f) => f.toString()).join('、')}', style: small),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(key: const ValueKey('practice-next'), onPressed: _next, child: const Text('次の問題')),
          ],
          const SizedBox(height: 12),
          Text('問題はでたらめに作ったあがり形です（鳴きは1つまで、赤ドラ・槓・役満は出ません）。'
              'ルール設定（4人打ち）の喰いタン・切り上げ満貫などに従って計算しています。', style: small),
        ],
      ),
    );
  }
}
