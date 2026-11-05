import 'package:mahjong_score_engine/mahjong_score_engine.dart';

import 'models.dart';
import 'session_logic.dart';

/// 和了の仕方
enum WinWay {
  ron('ロン'),
  direct('直撃'),
  tsumo('ツモ');

  final String label;
  const WinWay(this.label);
}

/// トップになるのに必要な、いちばん安い和了
class WinCondition {
  final WinWay way;

  /// 必要な翻・符（役満なら yakuman が 1）
  final HanFuEntry hand;

  /// 点数の計算結果（totalScore は本場・供託を含まない。トップになるかの判定では含めている）
  final ScoreResult result;

  /// 点数の表示（例: 3900、1000-2000、2000オール）。本場・供託を含まない
  final String score;

  /// 符の高い（50符以上の）手なら、もっと安く届くとき、そのいちばん安い手
  final WinCondition? highFu;

  const WinCondition(this.way, this.hand, this.result, this.score, {this.highFu});

  /// よくある符（40符まで）か、満貫以上の手
  bool get isCommon => hand.fu <= commonMaxFu || result.limitName != null;

  static const commonMaxFu = 40;

  /// 必要な手の表示（例: 2翻40符、満貫、役満）
  String get handLabel {
    if (hand.yakuman > 0) return '役満';
    if (result.limitName != null) return result.limitName!;
    return '${hand.han}翻${hand.fu}符';
  }
}

/// 1人分のオーラスの条件
class PlayerCondition {
  final int player;

  /// ロン（トップ以外から）・直撃（トップから）・ツモ。役満でも届かなければ null
  final WinCondition? ron, direct, tsumo;

  const PlayerCondition(this.player, {this.ron, this.direct, this.tsumo});
}

/// オーラス（と延長戦）で、トップ以外の人がトップになるのに必要な和了を求める（UI に依存しない）。
///
/// 翻・符の組み合わせを点数の安い順に試し、本場・供託も含めて点数を動かしてみて、トップになるかで判定する
/// （同点なら起家に近い人が上位）。流局のテンパイ料での逆転は含めない。
class AllLastConditions {
  AllLastConditions._();

  /// 条件を表示する局か（オーラス・延長戦。終局していない）
  static bool applies(GameSession s) => !s.finished && (s.isAllLast || s.isExtraRound);

  /// 試す手（1翻30符〜役満）
  static final List<HanFuEntry> _hands = [
    for (var han = 1; han <= 4; han++)
      for (final fu in ScoreCalculator.hanFuChoices) HanFuEntry(han: han, fu: fu),
    for (final han in [5, 6, 8, 11]) HanFuEntry(han: han),
    const HanFuEntry(yakuman: 1),
  ];

  static List<PlayerCondition> compute(GameSession s) {
    final top = s.ranking.first;
    return [
      for (final p in s.ranking.skip(1))
        PlayerCondition(
          p,
          ron: _cheapest(s, p, WinWay.ron, top),
          direct: _cheapest(s, p, WinWay.direct, top),
          tsumo: _cheapest(s, p, WinWay.tsumo, top),
        ),
    ];
  }

  static WinCondition? _cheapest(GameSession s, int p, WinWay way, int top) {
    int? loser;
    if (way == WinWay.direct) loser = top;
    if (way == WinWay.ron) {
      // トップでも自分でもない人からのロン（いなければ条件なし）
      final others = [for (var q = 0; q < s.playerCount; q++) if (q != p && q != top) q];
      if (others.isEmpty) return null;
      loser = others.first;
    }
    final tsumo = way == WinWay.tsumo;
    final candidates = <WinCondition>[];
    for (final hand in _hands) {
      final entry = WinEntry.hanFu(session: s, winner: p, isTsumo: tsumo, hanFu: hand);
      final wins = SessionLogic.scoreWins(s, [entry], loser: loser);
      final r = wins.single.result;
      if (!r.isValid) continue;
      final deltas = SessionLogic.winsDeltas(s, wins, loser: loser);
      final after = [for (var i = 0; i < s.playerCount; i++) s.scores[i] + deltas[i]];
      if (GameSession.rankingOf(after).first != p) continue;
      final isDealer = p == s.dealer;
      final plain = ScoreCalculator.calculateFromHanFu(
          han: hand.han,
          fu: hand.fu,
          yakuman: hand.yakuman,
          isTsumo: tsumo,
          playerWind: s.seatWindTileOf(p),
          rules: s.settings.scoreRules);
      candidates.add(WinCondition(way, hand, r,
          tsumo ? ScoreCalculator.formatScore(plain, isDealer: isDealer, isTsumo: true) : '${plain.totalScore}'));
    }
    if (candidates.isEmpty) return null;
    // 安い順（点数が小さい。同じなら符が少なく、次に翻が少ない。満貫以上は符を数えない）。
    // 例: 5200点なら 2翻80符 より 3翻40符
    candidates.sort((a, b) {
      final c = a.result.totalScore.compareTo(b.result.totalScore);
      if (c != 0) return c;
      final f = a.hand.fu.compareTo(b.hand.fu);
      return f != 0 ? f : a.hand.han.compareTo(b.hand.han);
    });
    // 2翻110符のような手は実際にはめったに無いので、よくある手（40符まで・満貫以上）のいちばん安いものを示し、
    // 符の高い手でもっと安く届くなら、それも添える
    final cheapest = candidates.first;
    final common = candidates.firstWhere((c) => c.isCommon, orElse: () => cheapest);
    if (identical(common, cheapest) || common.result.totalScore == cheapest.result.totalScore) return common;
    return WinCondition(way, common.hand, common.result, common.score, highFu: cheapest);
  }
}
