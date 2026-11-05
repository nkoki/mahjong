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
    final deltas = List<int>.filled(s.playerCount, 0);
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
    final scores = [for (var i = 0; i < s.playerCount; i++) s.scores[i] + deltas[i]];
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

  /// 1回のロンで同時に和了できる人数（ダブロンまで。3人は「三家和」の流局として扱う）
  static const maxRonWinners = 2;

  /// 本場・供託を受け取る和了者。
  /// ロンが2人のときは、放銃者から見て打つ順番が近い方（上家取り）。
  static int honbaTaker(List<int> winners, {int? loser, int playerCount = 4}) {
    if (loser == null) return winners.single;
    for (var k = 1; k < playerCount; k++) {
      final p = (loser + k) % playerCount;
      if (winners.contains(p)) return p;
    }
    throw ArgumentError('和了者がいません');
  }

  /// 和了者ごとの点数を計算する。本場・供託は [honbaTaker] の人にだけ付ける。
  static List<ScoredWin> scoreWins(GameSession s, List<WinEntry> entries, {int? loser}) {
    final taker = honbaTaker([for (final e in entries) e.winner],
        loser: loser, playerCount: s.playerCount);
    return [
      for (final e in entries)
        ScoredWin(
          winner: e.winner,
          input: e.input,
          hanFu: e.hanFu,
          result: e.hanFu != null
              ? ScoreCalculator.calculateFromHanFu(
                  han: e.hanFu!.han,
                  fu: e.hanFu!.fu,
                  yakuman: e.hanFu!.yakuman,
                  isTsumo: e.input.isTsumo,
                  playerWind: e.input.playerWind,
                  honba: e.winner == taker ? s.honba : 0,
                  riichiSticks: e.winner == taker ? s.riichiSticks : 0,
                  rules: s.settings.scoreRules,
                )
              : ScoreCalculator.calculate(
                  e.input,
                  honba: e.winner == taker ? s.honba : 0,
                  riichiSticks: e.winner == taker ? s.riichiSticks : 0,
                  rules: s.settings.scoreRules,
                ),
        ),
    ];
  }

  /// 複数人の和了の点数移動（和了者ごとの点数移動の合計）
  static List<int> winsDeltas(GameSession s, List<ScoredWin> wins, {int? loser}) {
    final total = List<int>.filled(s.playerCount, 0);
    for (final w in wins) {
      final d = paoDeltas(s, w, loser: loser);
      for (var i = 0; i < s.playerCount; i++) {
        total[i] += d[i];
      }
    }
    return total;
  }

  /// 包（責任払い）の対象になる役満
  static const paoYakuman = ['大三元', '大四喜'];

  /// 包の対象になる役満の倍数（大三元なら1、大四喜はダブル役満ありなら2）。対象がなければ 0
  static int paoUnits(ScoreResult r) {
    if (!r.isValid || !r.isYakuman) return 0;
    return r.yakuList
        .where((y) => y.isYakuman && paoYakuman.contains(y.name))
        .fold<int>(0, (a, y) => a + y.han);
  }

  /// 包を選べる和了か
  static bool canChoosePao(GameSession s, ScoredWin w) =>
      s.settings.pao && paoUnits(w.result) > 0;

  /// 包を考えた、和了1人分の点数移動。
  /// - ツモ: 包の対象の役満の分と本場を、包の人が全額払う
  /// - ほかの人からのロン: 包の対象の役満の分を、包の人と放銃者で半分ずつ払う（本場は放銃者）
  /// - 包の人からのロン: 普段どおり（放銃者が全額）
  static List<int> paoDeltas(GameSession s, ScoredWin w, {int? loser}) {
    final d = winDeltas(s, winner: w.winner, loser: loser, result: w.result);
    final pao = w.pao;
    final units = paoUnits(w.result);
    if (pao == null || pao == w.winner || units == 0 || pao == loser) return d;

    final isDealer = w.winner == s.dealer;
    final paoBase = 8000 * units;
    final paoPoints = paoBase * (isDealer ? 6 : 4);
    if (loser != null) {
      // ロン: 放銃者の支払いから半分を包の人に回す
      d[loser] += paoPoints ~/ 2;
      d[pao] -= paoPoints ~/ 2;
      return d;
    }
    // ツモ: 包の分の各自の支払いと本場を、包の人にまとめる
    // （3人打ちで折半のときは、いない北家の分を2人で分けた額も含める）
    final missing = s.settings.isSanma && s.settings.sanmaTsumoSplit
        ? paoBase * (isDealer ? 2 : 1)
        : 0;
    for (var p = 0; p < s.playerCount; p++) {
      if (p == w.winner) continue;
      final share =
          paoBase * ((isDealer || p == s.dealer) ? 2 : 1) + missing ~/ 2 + s.honba * 100;
      d[p] += share;
      d[pao] -= share;
    }
    return d;
  }

  /// 和了の入力内容のチェック（問題なければ null）
  static String? validateWins(List<int> winners, {int? loser, bool doubleRon = true}) {
    if (winners.isEmpty) return '和了者を選択してください';
    if (winners.toSet().length != winners.length) return '同じ人が2回和了しています';
    if (loser == null && winners.length > 1) return 'ツモ和了は1人だけです';
    if (loser != null && winners.contains(loser)) return '放銃者は和了できません';
    if (!doubleRon && winners.length > 1) {
      return 'ダブロンなし（頭ハネ）のルールなので、和了できるのは1人だけです';
    }
    if (winners.length > maxRonWinners) {
      return '同時にロンできるのは$maxRonWinners人までです（3人の場合は流局の「三家和」を使ってください）';
    }
    return null;
  }

  /// 和了を適用する（ダブロンにも対応）。
  /// 和了者に親がいれば連荘（本場+1）、いなければ親流れ（0本場）。
  static GameSession applyWins(
    GameSession s, {
    required List<ScoredWin> wins,
    int? loser,
    required String description,
  }) {
    final error = validateWins([for (final w in wins) w.winner],
        loser: loser, doubleRon: s.settings.doubleRon);
    if (error != null) throw ArgumentError(error);
    if (wins.any((w) => !w.result.isValid)) throw ArgumentError('計算できていない和了があります');
    final deltas = winsDeltas(s, wins, loser: loser);
    final scores = [for (var i = 0; i < s.playerCount; i++) s.scores[i] + deltas[i]];
    final dealerWon = wins.any((w) => w.winner == s.dealer);
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
    final deltas = List<int>.filled(s.playerCount, 0);
    if (type == DrawType.exhaustive) {
      // ノーテン罰符は場に3,000点（3人打ちも同じ）
      final n = s.playerCount;
      final k = tenpai.where((t) => t).length;
      if (k > 0 && k < n) {
        for (var i = 0; i < n; i++) {
          deltas[i] = tenpai[i] ? 3000 ~/ k : -(3000 ~/ (n - k));
        }
      }
    } else if (type == DrawType.nagashiMangan && nagashiPlayer != null) {
      // 満貫ツモ相当（本場は付かない。3人打ちはツモ損／折半のルールに従う）
      final isDealer = nagashiPlayer == s.dealer;
      final missing = s.settings.isSanma && s.settings.sanmaTsumoSplit
          ? (isDealer ? 4000 : 2000)
          : 0;
      for (var i = 0; i < s.playerCount; i++) {
        if (i == nagashiPlayer) continue;
        final pay = ((isDealer || i == s.dealer) ? 4000 : 2000) + missing ~/ 2;
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
    final scores = [for (var i = 0; i < s.playerCount; i++) s.scores[i] + deltas[i]];
    final renchan = type.isAbortive || tenpai[s.dealer];
    final buf = StringBuffer(type.label);
    if (!type.isAbortive) {
      final names = [
        for (var i = 0; i < s.playerCount; i++)
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
      deltas: [for (var i = 0; i < s.playerCount; i++) scores[i] - s.roundStartScores[i]],
      scoresAfter: scores,
    );
    final nextRound = renchan ? s.roundIndex : s.roundIndex + 1;
    var next = s.copyWith(
      scores: scores,
      roundIndex: nextRound,
      honba: nextHonba,
      riichiSticks: clearSticks ? 0 : s.riichiSticks,
      riichi: List.filled(s.playerCount, false),
      roundStartScores: scores,
      records: [...s.records, record],
      previous: s,
    );

    final rules = s.settings;
    final busted = rules.tobi && scores.any((p) => p < 0);
    // 返し点に届いた人がいるか（西入するか・延長を終えるかの判定に使う）
    final reached = scores.any((p) => p >= rules.returnPoints);
    final total = rules.totalRounds;
    // 西入ありなら延長の4局目まで
    final maxRounds = rules.westRound ? total + 4 : total;

    bool overLast;
    if (s.roundIndex >= total) {
      // 延長中: 誰かが返し点に届いたら終了（サドンデス）。延長の4局目が終わっても終了
      overLast = reached || nextRound >= maxRounds;
    } else if (nextRound >= total) {
      // 最終局が終わった: 西入なしなら終了。西入ありなら、返し点に届いた人がいれば終了
      overLast = !rules.westRound || reached;
    } else {
      overLast = false;
    }

    // オーラスで親が連荘してもトップなら和了止め（親がトップのとき終了）。
    // 西入ありのときは、親が返し点に届いている場合だけ
    final allLastDealerTop = rules.agariYame &&
        renchan &&
        s.isAllLast &&
        next.ranking.first == s.dealer &&
        kind == 'win' &&
        (!rules.westRound || scores[s.dealer] >= rules.returnPoints);
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
    return s.copyWith(
        scores: scores, riichiSticks: 0, finished: true, settledSticks: s.riichiSticks);
  }

  /// 局の修正内容のチェック（問題なければ null）。
  /// 合計を元と同じにするのは、供託リーチ棒の出入り（場に出した分・受け取った分）を変えないため。
  static String? validateRoundEdit(GameSession s, int index, List<int?> deltas) {
    if (index < 0 || index >= s.records.length) return '修正する局が見つかりません';
    if (deltas.length != s.playerCount || deltas.any((d) => d == null)) {
      return '${s.playerCount}人すべての増減を入力してください';
    }
    if (deltas.any((d) => d! % 100 != 0)) return '100点単位で入力してください';
    final original = s.records[index].deltas.fold<int>(0, (a, d) => a + d);
    final sum = deltas.fold<int>(0, (a, d) => a + d!);
    if (sum != original) {
      return '${s.playerCount}人の合計を${_signed(original)}にしてください（今の合計: ${_signed(sum)}）';
    }
    return null;
  }

  static String _signed(int v) => v > 0 ? '+$v' : '$v';

  /// 過去の局の点数増減と内容を修正する。
  ///
  /// 修正した差分は、その局以降の「局終了後の点数」と今の点数にそのまま反映する。
  /// 局の進行（親・本場・終局したかどうか）は変えない。
  /// 終局時にトップへ渡した供託は、修正後のトップに付け替える。
  /// 修正前の状態は「元に戻す」で戻せる。
  static GameSession editRound(
    GameSession s,
    int index, {
    required List<int> deltas,
    String? description,
  }) {
    final error = validateRoundEdit(s, index, deltas);
    if (error != null) throw ArgumentError(error);

    final old = s.records[index];
    final n = s.playerCount;
    final diff = [for (var i = 0; i < n; i++) deltas[i] - old.deltas[i]];
    List<int> add(List<int> a) => [for (var i = 0; i < n; i++) a[i] + diff[i]];

    final records = <RoundRecord>[
      for (var j = 0; j < s.records.length; j++)
        if (j < index)
          s.records[j]
        else if (j == index)
          old.copyWith(
            deltas: List.unmodifiable(deltas),
            scoresAfter: List.unmodifiable(add(old.scoresAfter)),
            description: description,
            edited: true,
          )
        else
          s.records[j].copyWith(scoresAfter: List.unmodifiable(add(s.records[j].scoresAfter))),
    ];

    var scores = add(s.scores);
    if (s.finished && s.settledSticks > 0) {
      // 供託を一度もとのトップから外し、修正後の点数でのトップに渡し直す
      final bonus = s.settledSticks * 1000;
      scores[s.ranking.first] -= bonus;
      scores[GameSession.rankingOf(scores).first] += bonus;
    }

    return s.copyWith(
      records: List.unmodifiable(records),
      scores: List.unmodifiable(scores),
      roundStartScores: List.unmodifiable(add(s.roundStartScores)),
      previous: s,
    );
  }

  /// 元に戻す（お気に入り・ウマは対局の進行とは別に変えられるので、今の設定を残す）
  static GameSession undo(GameSession s) =>
      s.previous?.copyWith(favorite: s.favorite, settings: s.settings) ?? s;

  /// ウマの変更（最終ポイントは表示のたびに計算するので、ウマを変えるだけで反映される）
  static GameSession updateUma(GameSession s, List<int> uma) =>
      s.copyWith(settings: s.settings.copyWith(uma: List.unmodifiable(uma)));

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

/// 和了者と、その手の入力内容
class WinEntry {
  final int winner;

  /// 手の入力内容。翻・符で入力したとき（[hanFu] があるとき）は、ロン／ツモと自風・場風だけを使う
  final WinInput input;

  /// 翻・符で入力したときの翻・符（手牌で入力したときは null）
  final HanFuEntry? hanFu;

  const WinEntry({required this.winner, required this.input, this.hanFu});

  /// 翻・符で入力した和了（手牌は入れない）
  factory WinEntry.hanFu({
    required GameSession session,
    required int winner,
    required bool isTsumo,
    required HanFuEntry hanFu,
  }) =>
      WinEntry(
        winner: winner,
        hanFu: hanFu,
        input: WinInput(
          handTiles: const [],
          winningTile: '',
          melds: const [],
          winType: isTsumo ? 'tsumo' : 'ron',
          isRiichi: false,
          isIppatsu: false,
          isDoubleRiichi: false,
          doraTiles: const [],
          uraDoraTiles: const [],
          roundWind: session.roundWindTile,
          playerWind: session.seatWindTileOf(winner),
        ),
      );
}

/// 翻・符で入力した手（ドラなども含めた翻数）。[yakuman] が 1 以上なら役満（倍数）で、翻・符は使わない
class HanFuEntry {
  final int han;
  final int fu;
  final int yakuman;
  const HanFuEntry({this.han = 0, this.fu = 0, this.yakuman = 0});
}

/// 点数を計算した和了
class ScoredWin {
  final int winner;
  final WinInput input;
  final ScoreResult result;

  /// 包（責任払い）の人。いなければ null
  final int? pao;

  /// 翻・符で入力した和了なら、その翻・符（手牌で入力したときは null）
  final HanFuEntry? hanFu;

  const ScoredWin({
    required this.winner,
    required this.input,
    required this.result,
    this.pao,
    this.hanFu,
  });

  ScoredWin withPao(int? pao) =>
      ScoredWin(winner: winner, input: input, result: result, pao: pao, hanFu: hanFu);
}
