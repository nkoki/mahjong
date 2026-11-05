import '../session/domain/models.dart';

/// 1人分の個人成績
class PlayerStats {
  final String name;

  /// 順位ごとの回数（[0] が1位）
  final List<int> rankCounts;

  /// ウマ・オカ込みのポイントの合計（千点単位）
  final double totalPoints;

  /// 和了率などを集計できる局の数（version 4 以降に記録した局）
  final int rounds;
  final int wins;
  final int dealIns;
  final int riichi;

  /// 和了点の合計（本場・供託を含まない）
  final int winPointsTotal;

  const PlayerStats({
    required this.name,
    required this.rankCounts,
    required this.totalPoints,
    required this.rounds,
    required this.wins,
    required this.dealIns,
    required this.riichi,
    required this.winPointsTotal,
  });

  int get games => rankCounts.fold(0, (a, v) => a + v);

  double get averageRank {
    if (games == 0) return 0;
    var sum = 0;
    for (var r = 0; r < rankCounts.length; r++) {
      sum += (r + 1) * rankCounts[r];
    }
    return sum / games;
  }

  double get averagePoints => games == 0 ? 0 : totalPoints / games;
  double get topRate => games == 0 ? 0 : rankCounts.first / games;
  double get lastRate => games == 0 ? 0 : rankCounts.last / games;

  /// 和了率・放銃率・立直率（集計できる局がなければ null）
  double? get winRate => rounds == 0 ? null : wins / rounds;
  double? get dealInRate => rounds == 0 ? null : dealIns / rounds;
  double? get riichiRate => rounds == 0 ? null : riichi / rounds;

  /// 平均打点（和了がなければ null）
  double? get averageWinPoints => wins == 0 ? null : winPointsTotal / wins;
}

/// 個人成績の集計結果
class StatsSummary {
  /// 合計ポイントの多い順
  final List<PlayerStats> players;

  /// 集計した対局の数
  final int games;

  /// 和了者などの記録が無く、和了率などに含めなかった局の数（以前の版で記録した局）
  final int roundsWithoutDetails;

  const StatsSummary({required this.players, required this.games, required this.roundsWithoutDetails});
}

/// 個人成績を集計する（UI に依存しない）。
///
/// - 終局した対局だけを集計する（対局中の対局は順位が決まっていないため）
/// - 名前が同じなら同じ人として集計する
/// - 和了率・放銃率・立直率・平均打点は、和了者などを記録している局（version 4 以降）だけで計算する
class PlayerStatsCalculator {
  PlayerStatsCalculator._();

  static StatsSummary compute(List<GameSession> sessions, {required int playerCount, DateTime? since}) {
    final target = [
      for (final s in sessions)
        if (s.finished && s.playerCount == playerCount && (since == null || !s.createdAt.isBefore(since))) s
    ];
    final acc = <String, _Acc>{};
    var noDetails = 0;
    for (final s in target) {
      for (final r in s.finalResults) {
        final a = acc.putIfAbsent(s.playerNames[r.player], () => _Acc(playerCount));
        a.ranks[r.rank - 1]++;
        a.points += r.point;
      }
      for (final rec in s.records) {
        if (!rec.hasPlayDetails) {
          noDetails++;
          continue;
        }
        for (var p = 0; p < s.playerCount; p++) {
          final a = acc[s.playerNames[p]]!;
          a.rounds++;
          final wi = rec.winners!.indexOf(p);
          if (wi >= 0) {
            a.wins++;
            final pts = rec.winPoints;
            if (pts != null && wi < pts.length) a.winPoints += pts[wi];
          }
          if (rec.loser == p) a.dealIns++;
          if (rec.riichi!.contains(p)) a.riichi++;
        }
      }
    }
    final players = [
      for (final e in acc.entries)
        PlayerStats(
          name: e.key,
          rankCounts: List.unmodifiable(e.value.ranks),
          totalPoints: e.value.points,
          rounds: e.value.rounds,
          wins: e.value.wins,
          dealIns: e.value.dealIns,
          riichi: e.value.riichi,
          winPointsTotal: e.value.winPoints,
        )
    ]..sort((a, b) {
        final c = b.totalPoints.compareTo(a.totalPoints);
        return c != 0 ? c : a.name.compareTo(b.name);
      });
    return StatsSummary(players: players, games: target.length, roundsWithoutDetails: noDetails);
  }
}

class _Acc {
  final List<int> ranks;
  double points = 0;
  int rounds = 0, wins = 0, dealIns = 0, riichi = 0, winPoints = 0;
  _Acc(int playerCount) : ranks = List.filled(playerCount, 0);
}
