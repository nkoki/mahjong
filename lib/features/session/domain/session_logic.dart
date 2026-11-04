import 'package:mahjong_score_engine/mahjong_score_engine.dart';

import 'models.dart';

/// 対局進行のロジック（UIに依存しない純粋な関数群）
class SessionLogic {
  SessionLogic._();

  /// 立直の宣言／取り消し（1000点を供託）
  static GameSession toggleRiichi(GameSession s, int player) {
    if (s.finished) return s;
    final riichi = List<bool>.from(s.riichi);
    final scores = List<int>.from(s.scores);
    var sticks = s.riichiSticks;
    if (riichi[player]) {
      riichi[player] = false;
      scores[player] += 1000;
      sticks -= 1;
    } else {
      if (scores[player] < 1000) return s;
      riichi[player] = true;
      scores[player] -= 1000;
      sticks += 1;
    }
    return s.copyWith(riichi: riichi, scores: scores, riichiSticks: sticks);
  }

  /// 和了の点数移動を計算する（各プレイヤーの増減を返す）
  static List<int> winDeltas(
    GameSession s, {
    required int winner,
    int? loser,
    required ScoreResult result,
  }) {
    final deltas = List<int>.filled(4, 0);
    final p = result.paymentDetails;
    if (p.loserPayment != null) {
      deltas[loser!] -= p.loserPayment!;
      deltas[winner] += p.loserPayment!;
    } else {
      for (final pay in p.playerPayments ?? const <PlayerPayment>[]) {
        final payer = s.playerOfSeat(pay.playerId);
        deltas[payer] -= pay.amount;
        deltas[winner] += pay.amount;
      }
    }
    deltas[winner] += p.riichiStickGain;
    return deltas;
  }

  /// 和了を適用する
  static GameSession applyWin(
    GameSession s, {
    required int winner,
    int? loser,
    required ScoreResult result,
    required String description,
  }) {
    final deltas = winDeltas(s, winner: winner, loser: loser, result: result);
    final scores = [for (var i = 0; i < 4; i++) s.scores[i] + deltas[i]];
    final dealerWon = winner == s.dealer;
    return _finishRound(
      s,
      scores: scores,
      kind: 'win',
      description: description,
      renchan: dealerWon,
      nextHonba: dealerWon ? s.honba + 1 : 0,
      clearSticks: true,
    );
  }

  /// 流局の点数移動を計算する
  static List<int> drawDeltas(
    GameSession s, {
    required DrawType type,
    required List<bool> tenpai,
    int? nagashiPlayer,
  }) {
    final deltas = List<int>.filled(4, 0);
    if (type == DrawType.exhaustive) {
      final k = tenpai.where((t) => t).length;
      if (k > 0 && k < 4) {
        for (var i = 0; i < 4; i++) {
          deltas[i] = tenpai[i] ? 3000 ~/ k : -(3000 ~/ (4 - k));
        }
      }
    } else if (type == DrawType.nagashiMangan && nagashiPlayer != null) {
      // 満貫ツモ相当（本場は付かない）
      final isDealer = nagashiPlayer == s.dealer;
      for (var i = 0; i < 4; i++) {
        if (i == nagashiPlayer) continue;
        final pay = (isDealer || i == s.dealer) ? 4000 : 2000;
        deltas[i] -= pay;
        deltas[nagashiPlayer] += pay;
      }
    }
    return deltas;
  }

  /// 流局を適用する
  static GameSession applyDraw(
    GameSession s, {
    required DrawType type,
    required List<bool> tenpai,
    int? nagashiPlayer,
  }) {
    final deltas = drawDeltas(s,
        type: type, tenpai: tenpai, nagashiPlayer: nagashiPlayer);
    final scores = [for (var i = 0; i < 4; i++) s.scores[i] + deltas[i]];
    final renchan = type.isAbortive || tenpai[s.dealer];
    final buf = StringBuffer(type.label);
    if (!type.isAbortive) {
      final names = [
        for (var i = 0; i < 4; i++)
          if (tenpai[i]) s.playerNames[i]
      ];
      buf.write(names.isEmpty ? '（全員ノーテン）' : '（テンパイ: ${names.join("・")}）');
    }
    if (type == DrawType.nagashiMangan && nagashiPlayer != null) {
      buf.write(' ${s.playerNames[nagashiPlayer]}');
    }
    return _finishRound(
      s,
      scores: scores,
      kind: 'draw',
      description: buf.toString(),
      renchan: renchan,
      nextHonba: s.honba + 1,
      clearSticks: false,
    );
  }

  /// 対局を途中で終了する
  static GameSession finishManually(GameSession s) {
    if (s.finished) return s;
    return _settle(s.copyWith(previous: s));
  }

  static GameSession _finishRound(
    GameSession s, {
    required List<int> scores,
    required String kind,
    required String description,
    required bool renchan,
    required int nextHonba,
    required bool clearSticks,
  }) {
    final record = RoundRecord(
      roundLabel: s.roundLabel,
      kind: kind,
      description: description,
      deltas: [for (var i = 0; i < 4; i++) scores[i] - s.roundStartScores[i]],
      scoresAfter: scores,
    );
    final nextRound = renchan ? s.roundIndex : s.roundIndex + 1;
    var next = s.copyWith(
      scores: scores,
      roundIndex: nextRound,
      honba: nextHonba,
      riichiSticks: clearSticks ? 0 : s.riichiSticks,
      riichi: const [false, false, false, false],
      roundStartScores: scores,
      records: [...s.records, record],
      previous: s,
    );

    final busted = s.settings.tobi && scores.any((p) => p < 0);
    final overLast = nextRound >= s.settings.totalRounds;
    // オーラスで親が連荘してもトップなら和了止め（親がトップのとき終了）
    final allLastDealerTop = renchan &&
        s.isAllLast &&
        next.ranking.first == s.dealer &&
        kind == 'win';
    if (busted || overLast || allLastDealerTop) {
      next = _settle(next.copyWith(roundIndex: s.roundIndex));
    }
    return next;
  }

  /// 終局処理（供託はトップ取り）
  static GameSession _settle(GameSession s) {
    final scores = List<int>.from(s.scores);
    if (s.riichiSticks > 0) {
      scores[s.ranking.first] += s.riichiSticks * 1000;
    }
    return s.copyWith(scores: scores, riichiSticks: 0, finished: true);
  }

  /// 元に戻す（お気に入りの設定は対局の進行とは別なので、今の設定を残す）
  static GameSession undo(GameSession s) =>
      s.previous?.copyWith(favorite: s.favorite) ?? s;

  /// お気に入りの切り替え
  static GameSession toggleFavorite(GameSession s) =>
      s.copyWith(favorite: !s.favorite);

  /// 保存しておく対局の最大数
  static const maxSavedSessions = 100;

  /// 自動で削除してよい対局か（お気に入りでも対局中でもない）
  static bool isDeletable(GameSession s) => !s.favorite && s.finished;

  /// 対局が [max] 件を超えている分、削除する対局を古い順に返す。
  /// お気に入りと対局中の対局は削除しないので、それらが多い場合は [max] 件を超えて残る。
  static List<GameSession> sessionsToPrune(
    List<GameSession> sessions, {
    int max = maxSavedSessions,
  }) {
    final over = sessions.length - max;
    if (over <= 0) return const [];
    final candidates = sessions.where(isDeletable).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return candidates.take(over).toList();
  }
}
