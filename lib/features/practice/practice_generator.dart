import 'dart:math';

import 'package:mahjong_score_engine/mahjong_score_engine.dart';

/// 点数計算の練習の1問
class PracticeQuestion {
  final WinInput input;
  final ScoreResult result;

  /// 正しい答え（例: 7700点、2000-3900、3900オール）
  final String answer;

  /// 選択肢（答えを含む4つ）
  final List<String> choices;

  const PracticeQuestion({required this.input, required this.result, required this.answer, required this.choices});

  bool get isDealer => input.isDealer;
  bool get isTsumo => input.isTsumo;
}

/// 練習問題を作る（UI に依存しない）。
///
/// 4面子1雀頭のあがった形をでたらめに作り、点数計算エンジンで役があるか確かめてから出す。
/// 鳴きは1つまで（槓は無し）。赤ドラは使わない
class PracticeGenerator {
  PracticeGenerator._();

  static final _all = [
    for (final s in ['m', 'p', 's']) for (var i = 1; i <= 9; i++) '$i$s',
    for (var i = 1; i <= 7; i++) '${i}z',
  ];

  static PracticeQuestion generate(Random rng, {ScoreRules rules = const ScoreRules()}) {
    for (var attempt = 0; attempt < 500; attempt++) {
      final q = _try(rng, rules);
      if (q != null) return q;
    }
    throw StateError('練習問題を作れませんでした');
  }

  static String _format(ScoreResult r, bool dealer, bool tsumo) =>
      tsumo ? ScoreCalculator.formatScore(r, isDealer: dealer, isTsumo: true) : '${r.totalScore}点';

  static PracticeQuestion? _try(Random rng, ScoreRules rules) {
    final count = <String, int>{};
    bool take(List<String> tiles) {
      final add = <String, int>{};
      for (final t in tiles) {
        add[t] = (add[t] ?? 0) + 1;
      }
      if (add.entries.any((e) => (count[e.key] ?? 0) + e.value > 4)) return false;
      add.forEach((k, v) => count[k] = (count[k] ?? 0) + v);
      return true;
    }

    // 面子（順子か刻子）を4つ
    final sets = <List<String>>[];
    final isSeq = <bool>[];
    while (sets.length < 4) {
      List<String> m;
      final seq = rng.nextDouble() < 0.65;
      if (seq) {
        final suit = ['m', 'p', 's'][rng.nextInt(3)];
        final start = 1 + rng.nextInt(7);
        m = ['$start$suit', '${start + 1}$suit', '${start + 2}$suit'];
      } else {
        final t = _all[rng.nextInt(_all.length)];
        m = [t, t, t];
      }
      if (take(m)) {
        sets.add(m);
        isSeq.add(seq);
      }
    }
    // 雀頭
    List<String> pair;
    do {
      final t = _all[rng.nextInt(_all.length)];
      pair = [t, t];
    } while (!take(pair));

    // 鳴き（3割で1つ）
    final melds = <Meld>[];
    var openIndex = -1;
    if (rng.nextDouble() < 0.3) {
      openIndex = rng.nextInt(4);
      final m = sets[openIndex];
      melds.add(isSeq[openIndex]
          ? Meld(type: MeldType.chi, tiles: m, calledTile: m[rng.nextInt(3)])
          : Meld(type: MeldType.pon, tiles: m, calledTile: m.first));
    }
    final closed = [
      for (var i = 0; i < 4; i++) if (i != openIndex) ...sets[i],
      ...pair,
    ];
    final winTile = closed[rng.nextInt(closed.length)];
    final hand = [...closed]..remove(winTile);
    hand.sort(_order);

    final tsumo = rng.nextBool();
    final menzen = melds.isEmpty;
    final riichi = menzen && rng.nextDouble() < 0.5;
    final dora = _all[rng.nextInt(_all.length)];
    final ura = riichi ? [_all[rng.nextInt(_all.length)]] : const <String>[];
    if (!take([dora, ...ura])) return null;
    final input = WinInput(
      handTiles: hand,
      winningTile: winTile,
      melds: melds,
      winType: tsumo ? 'tsumo' : 'ron',
      isRiichi: riichi,
      isIppatsu: false,
      isDoubleRiichi: false,
      doraTiles: [dora],
      uraDoraTiles: ura,
      roundWind: rng.nextDouble() < 0.6 ? '1z' : '2z',
      playerWind: '${1 + rng.nextInt(4)}z',
    );
    final r = ScoreCalculator.calculate(input, rules: rules);
    // 役が無い・役満（練習には向かない）は作り直す
    if (!r.isValid || r.isYakuman) return null;
    final dealer = input.isDealer;
    final answer = _format(r, dealer, tsumo);

    // 選択肢: 翻・符を少しずらした点数
    final wrong = <String>{};
    final hanList = [r.han - 1, r.han, r.han + 1, r.han + 2].where((h) => h >= 1);
    final fuList = [r.fu - 10, r.fu, r.fu + 10, r.fu + 20].where((f) => ScoreCalculator.hanFuChoices.contains(f));
    for (final h in hanList) {
      for (final f in fuList) {
        final x = ScoreCalculator.calculateFromHanFu(
            han: h, fu: f, isTsumo: tsumo, playerWind: input.playerWind, rules: rules);
        if (!x.isValid) continue;
        final s = _format(x, dealer, tsumo);
        if (s != answer) wrong.add(s);
      }
    }
    if (wrong.length < 3) return null;
    final picks = (wrong.toList()..shuffle(rng)).take(3).toList();
    final choices = [answer, ...picks]..shuffle(rng);
    return PracticeQuestion(input: input, result: r, answer: answer, choices: choices);
  }

  /// 萬子・筒子・索子・字牌の順、数字の順
  static int _order(String a, String b) {
    const suits = 'mpsz';
    final c = suits.indexOf(a[a.length - 1]).compareTo(suits.indexOf(b[b.length - 1]));
    return c != 0 ? c : a.compareTo(b);
  }
}
