import '../session/domain/models.dart';

/// 1対局分の成績（推移グラフ用）
class PlayerGame {
  final String sessionId;
  final DateTime at;
  final int rank;

  /// その対局のポイント
  final double point;

  /// この対局までの合計ポイント
  final double cumulative;

  const PlayerGame({
    required this.sessionId,
    required this.at,
    required this.rank,
    required this.point,
    required this.cumulative,
  });
}

/// 対戦相手との成績
class OpponentStats {
  final String name;

  /// 同じ卓で終局まで打った対局の数
  final int games;

  /// 相手より上の順位だった回数・下だった回数
  final int above, below;

  /// 同卓したときの自分・相手の順位の合計（平均を出すため）
  final int myRankSum, theirRankSum;

  /// 同卓したときの自分・相手のポイントの合計
  final double myPoints, theirPoints;

  const OpponentStats({
    required this.name,
    required this.games,
    required this.above,
    required this.below,
    required this.myRankSum,
    required this.theirRankSum,
    required this.myPoints,
    required this.theirPoints,
  });

  double get myAverageRank => myRankSum / games;
  double get theirAverageRank => theirRankSum / games;
}

/// プレイヤー1人の詳しい成績（推移・対戦相手・役の出現回数）
class PlayerDetail {
  final String name;

  /// 古い順
  final List<PlayerGame> games;

  /// 同卓が多い順
  final List<OpponentStats> opponents;

  /// 役の名前と和了の回数（多い順）
  final List<(String, int)> yaku;

  /// 役が分かる和了（手牌で入力した和了）の回数
  final int yakuWins;

  /// 役が分からない和了（翻・符で入力・以前の版で記録・後から追加）の回数
  final int unknownYakuWins;

  const PlayerDetail({
    required this.name,
    required this.games,
    required this.opponents,
    required this.yaku,
    required this.yakuWins,
    required this.unknownYakuWins,
  });

  /// 集計する（個人成績と同じく、終局した対局・人数・期間で絞る。UI に依存しない）
  static PlayerDetail compute(List<GameSession> sessions, String name,
      {required int playerCount, DateTime? since}) {
    final target = [
      for (final s in sessions)
        if (s.finished && s.playerCount == playerCount && (since == null || !s.createdAt.isBefore(since))) s
    ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final games = <PlayerGame>[];
    final opp = <String, _Opp>{};
    final yaku = <String, int>{};
    var yakuWins = 0, unknown = 0;
    var total = 0.0;
    for (final s in target) {
      final results = {for (final r in s.finalResults) r.player: r};
      final me = s.playerNames.indexOf(name);
      if (me >= 0) {
        final mine = results[me]!;
        total += mine.point;
        games.add(PlayerGame(sessionId: s.id, at: s.createdAt, rank: mine.rank, point: mine.point, cumulative: total));
        for (var p = 0; p < s.playerCount; p++) {
          if (p == me) continue;
          final theirs = results[p]!;
          final o = opp.putIfAbsent(s.playerNames[p], _Opp.new);
          o.games++;
          if (mine.rank < theirs.rank) o.above++;
          if (mine.rank > theirs.rank) o.below++;
          o.myRank += mine.rank;
          o.theirRank += theirs.rank;
          o.myPoints += mine.point;
          o.theirPoints += theirs.point;
        }
      }
      // 役は、その局を打っていた人で数える（途中で交代した対局も）
      for (var ri = 0; ri < s.records.length; ri++) {
        final rec = s.records[ri];
        final winners = rec.winners;
        if (rec.kind != 'win' || winners == null) continue;
        for (var wi = 0; wi < winners.length; wi++) {
          if (s.nameAt(ri, winners[wi]) != name) continue;
          final list = rec.yaku != null && wi < rec.yaku!.length ? rec.yaku![wi] : const <String>[];
          if (list.isEmpty) {
            unknown++;
            continue;
          }
          yakuWins++;
          for (final y in list.toSet()) {
            yaku[y] = (yaku[y] ?? 0) + 1;
          }
        }
      }
    }
    final opponents = [
      for (final e in opp.entries)
        OpponentStats(
          name: e.key,
          games: e.value.games,
          above: e.value.above,
          below: e.value.below,
          myRankSum: e.value.myRank,
          theirRankSum: e.value.theirRank,
          myPoints: e.value.myPoints,
          theirPoints: e.value.theirPoints,
        )
    ]..sort((a, b) {
        final c = b.games.compareTo(a.games);
        return c != 0 ? c : a.name.compareTo(b.name);
      });
    final yakuList = [for (final e in yaku.entries) (e.key, e.value)]..sort((a, b) {
        final c = b.$2.compareTo(a.$2);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
    return PlayerDetail(
      name: name,
      games: games,
      opponents: opponents,
      yaku: yakuList,
      yakuWins: yakuWins,
      unknownYakuWins: unknown,
    );
  }
}

class _Opp {
  int games = 0, above = 0, below = 0, myRank = 0, theirRank = 0;
  double myPoints = 0, theirPoints = 0;
}
