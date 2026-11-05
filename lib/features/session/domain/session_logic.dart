import 'package:mahjong_score_engine/mahjong_score_engine.dart';

import '../../../core/l10n.dart';
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
      winners: [winner],
      loser: loser,
      winPoints: [result.totalScore],
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
    throw ArgumentError(tr('和了者がいません', 'No winner'));
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

  /// 祝儀（チップ）の枚数の増減。[chips] は和了者ごとの枚数。
  /// ロンは放銃者が払い、ツモはほかの全員がその枚数ずつ払う
  static List<int> chipDeltas(GameSession s, Map<int, int> chips, {int? loser}) {
    final d = List<int>.filled(s.playerCount, 0);
    chips.forEach((winner, n) {
      if (n <= 0) return;
      if (loser != null) {
        d[loser] -= n;
        d[winner] += n;
      } else {
        for (var p = 0; p < s.playerCount; p++) {
          if (p == winner) continue;
          d[p] -= n;
          d[winner] += n;
        }
      }
    });
    return d;
  }

  /// 祝儀の枚数の目安（赤ドラ・裏ドラ・一発の数）。翻・符で入力した和了は 0
  static int suggestedChips(GameSession s, ScoredWin w) {
    if (w.hanFu != null || !w.result.isValid) return 0;
    final input = w.input;
    final tiles = [
      ...input.handTiles,
      input.winningTile,
      for (final m in input.melds) ...m.tiles,
    ];
    final aka = tiles.where(isRedDora).length;
    final ura = (input.isRiichi || input.isDoubleRiichi)
        ? countDora(tiles, input.uraDoraTiles, sanma: s.settings.isSanma)
        : 0;
    return aka + ura + (input.isIppatsu ? 1 : 0);
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
    if (winners.isEmpty) return tr('和了者を選択してください', 'Select the winner');
    if (winners.toSet().length != winners.length) return tr('同じ人が2回和了しています', 'The same player is selected twice as a winner');
    if (loser == null && winners.length > 1) return tr('ツモ和了は1人だけです', 'Only one player can win by tsumo');
    if (loser != null && winners.contains(loser)) return tr('放銃者は和了できません', 'The player who dealt in cannot win');
    if (!doubleRon && winners.length > 1) {
      return tr('ダブロンなし（頭ハネ）のルールなので、和了できるのは1人だけです',
          'Double ron is off (head bump), so only one player can win');
    }
    if (winners.length > maxRonWinners) {
      return tr('同時にロンできるのは$maxRonWinners人までです（3人の場合は流局の「三家和」を使ってください）',
          'Up to $maxRonWinners players can ron at once (for 3 players, use the abortive draw "Sanchahou")');
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
    Map<int, int> chips = const {},
  }) {
    final error = validateWins([for (final w in wins) w.winner],
        loser: loser, doubleRon: s.settings.doubleRon);
    if (error != null) throw ArgumentError(error);
    if (wins.any((w) => !w.result.isValid)) throw ArgumentError(tr('計算できていない和了があります', 'Some wins have not been calculated'));
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
      winners: [for (final w in wins) w.winner],
      loser: loser,
      winPoints: [for (final w in wins) w.result.totalScore],
      chips: s.settings.chips ? chipDeltas(s, chips, loser: loser) : null,
      // 役（ドラは除く）。翻・符で入力した和了は役が分からないので空
      yaku: [
        for (final w in wins)
          w.hanFu != null ? const <String>[] : [for (final y in w.result.yakuList) if (!y.name.contains('ドラ')) y.name]
      ],
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
      buf.write(names.isEmpty
          ? tr('（全員ノーテン）', ' (all noten)')
          : tr('（テンパイ: ${names.join("・")}）', ' (tenpai: ${names.join(", ")})'));
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

  /// チョンボ（錯和）の罰符（満貫払い）。子は親に4000点・子に2000点ずつ、親は全員に4000点ずつ払う
  static List<int> chomboDeltas(GameSession s, int player) {
    final d = List<int>.filled(s.playerCount, 0);
    final dealer = player == s.dealer;
    for (var p = 0; p < s.playerCount; p++) {
      if (p == player) continue;
      final pay = (dealer || p == s.dealer) ? 4000 : 2000;
      d[p] += pay;
      d[player] -= pay;
    }
    return d;
  }

  /// チョンボ（錯和）を適用する。罰符を払い、同じ局・同じ本場をやり直す。
  /// この局で出した立直棒は本人に戻す（前の局から持ち越した供託はそのまま）
  static GameSession applyChombo(GameSession s, int player) {
    if (s.finished) return s;
    final penalty = chomboDeltas(s, player);
    final riichiCount = s.riichi.where((r) => r).length;
    final scores = [
      for (var i = 0; i < s.playerCount; i++) s.scores[i] + penalty[i] + (s.riichi[i] ? 1000 : 0)
    ];
    return _finishRound(
      s.copyWith(riichiSticks: s.riichiSticks - riichiCount),
      scores: scores,
      kind: 'chombo',
      description: tr('チョンボ ${s.playerNames[player]}（満貫払い）', 'Chombo ${s.playerNames[player]} (mangan payment)'),
      renchan: true,
      nextHonba: s.honba,
      clearSticks: false,
      loser: player,
      undoTo: s,
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
    List<int> winners = const [],
    int? loser,
    List<int>? winPoints,
    List<int>? chips,
    List<List<String>>? yaku,
    GameSession? undoTo,
  }) {
    final record = RoundRecord(
      roundLabel: s.roundLabel,
      kind: kind,
      description: description,
      deltas: [for (var i = 0; i < s.playerCount; i++) scores[i] - s.roundStartScores[i]],
      scoresAfter: scores,
      winners: List.unmodifiable(winners),
      loser: loser,
      riichi: List.unmodifiable([for (var i = 0; i < s.playerCount; i++) if (s.riichi[i]) i]),
      winPoints: List.unmodifiable(winPoints ?? const <int>[]),
      chips: chips == null || chips.every((c) => c == 0) ? null : List.unmodifiable(chips),
      yaku: yaku == null ? null : List.unmodifiable([for (final y in yaku) List<String>.unmodifiable(y)]),
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
      previous: undoTo ?? s,
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
    if (index < 0 || index >= s.records.length) return tr('修正する局が見つかりません', 'The round to edit was not found');
    if (deltas.length != s.playerCount || deltas.any((d) => d == null)) {
      return tr('${s.playerCount}人すべての増減を入力してください', 'Enter the change for all ${s.playerCount} players');
    }
    if (deltas.any((d) => d! % 100 != 0)) return tr('100点単位で入力してください', 'Enter in units of 100 pts');
    final original = s.records[index].deltas.fold<int>(0, (a, d) => a + d);
    final sum = deltas.fold<int>(0, (a, d) => a + d!);
    if (sum != original) {
      return tr('${s.playerCount}人の合計を${_signed(original)}にしてください（今の合計: ${_signed(sum)}）',
          'The total for ${s.playerCount} players must be ${_signed(original)} (current total: ${_signed(sum)})');
    }
    return null;
  }

  static String _signed(int v) => v > 0 ? '+$v' : '$v';

  /// 局の修正で和了者・放銃者を直せる局か（和了の局で、和了者を記録している局）
  static bool canEditWinners(RoundRecord r) => r.kind == 'win' && r.winners != null;

  /// 和了者・放銃者の修正の確認（問題なければ null）。[loser] が null ならツモ
  static String? validateWinners(GameSession s, List<int> winners, int? loser) {
    if (winners.isEmpty) return tr('和了した人を選んでください', 'Select the winner');
    if (winners.any((w) => w < 0 || w >= s.playerCount) || winners.toSet().length != winners.length) {
      return tr('和了した人が正しくありません', 'Invalid winner');
    }
    if (loser != null && winners.contains(loser)) return tr('和了した人と放銃した人が同じです', 'The winner and the player who dealt in are the same');
    if (winners.length > 1 && loser == null) return tr('2人以上の和了（ダブロン）は放銃した人を選んでください', 'For a double ron, select the player who dealt in');
    return null;
  }

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
    ({List<int> winners, int? loser})? who,
  }) {
    final error = validateRoundEdit(s, index, deltas);
    if (error != null) throw ArgumentError(error);
    final old = s.records[index];
    if (who != null) {
      if (!canEditWinners(old)) throw ArgumentError(tr('この局は和了者を修正できません', 'The winners of this round cannot be edited'));
      final e = validateWinners(s, who.winners, who.loser);
      if (e != null) throw ArgumentError(e);
    }
    // 和了者の人数が同じなら、和了点はそのまま新しい和了者に付け替える（選び間違いの修正）。
    // 人数が変わったら和了点は分からないので消す（個人成績の平均打点に含めない）
    final newWho = who == null || (_sameList(who.winners, old.winners!) && who.loser == old.loser)
        ? null
        : (
            winners: List<int>.unmodifiable(who.winners),
            loser: who.loser,
            winPoints: old.winPoints != null && old.winPoints!.length == who.winners.length ? old.winPoints : null,
            yaku: old.yaku != null && old.yaku!.length == who.winners.length ? old.yaku : null,
          );

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
            who: newWho,
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

  // ---- 局の削除・追加（局の進行は変えず、点数だけ動かす）----

  /// 局の記録を差し替え、[from] 番目以降の局の点数と今の点数を [diff] だけずらす。
  /// [stickChange] は供託の本数の増減（終局していれば、トップに渡した供託を付け替える）。
  /// 供託がマイナスになるなら null
  static GameSession? _shiftRecords(
    GameSession s,
    List<RoundRecord> records,
    int from,
    List<int> diff,
    int stickChange,
  ) {
    final n = s.playerCount;
    List<int> add(List<int> a) => List.unmodifiable([for (var i = 0; i < n; i++) a[i] + diff[i]]);
    final shifted = [
      for (var j = 0; j < records.length; j++)
        j < from ? records[j] : records[j].copyWith(scoresAfter: add(records[j].scoresAfter)),
    ];
    if (s.finished) {
      final pot = s.settledSticks + stickChange;
      if (pot < 0) return null;
      final base = List<int>.from(s.scores);
      base[s.ranking.first] -= s.settledSticks * 1000;
      final scores = add(base).toList();
      scores[GameSession.rankingOf(scores).first] += pot * 1000;
      return s.copyWith(
        records: List.unmodifiable(shifted),
        scores: List.unmodifiable(scores),
        roundStartScores: add(s.roundStartScores),
        settledSticks: pot,
        previous: s,
      );
    }
    final sticks = s.riichiSticks + stickChange;
    if (sticks < 0) return null;
    return s.copyWith(
      records: List.unmodifiable(shifted),
      scores: add(s.scores),
      roundStartScores: add(s.roundStartScores),
      riichiSticks: sticks,
      previous: s,
    );
  }

  /// 局の削除のチェック（問題なければ null）
  static String? validateDeleteRound(GameSession s, int index) {
    if (index < 0 || index >= s.records.length) return tr('削除する局が見つかりません', 'The round to delete was not found');
    if (_deleteRound(s, index) == null) {
      return tr(
          'この局で場に出た立直棒を、後の局で和了した人が受け取っているため削除できません。'
              '先に後の局の点数を直してください',
          'This round cannot be deleted because its riichi sticks were collected by a winner in a later round. '
              'Fix the points of the later round first');
    }
    return null;
  }

  /// 局の記録を削除する（二重に入れた局など）。
  ///
  /// その局の点数の増減を取り消し、後の局の点数と今の点数をずらす。
  /// その局で場に出た立直棒は持ち主に戻し（供託から減らし）、その局で受け取った供託は場に戻す。
  /// 局の進行（今の局・本場）は変えないので、ずれたときは「局・本場・供託の修正」で直す。
  static GameSession deleteRound(GameSession s, int index) {
    final e = validateDeleteRound(s, index);
    if (e != null) throw ArgumentError(e);
    return _deleteRound(s, index)!;
  }

  static GameSession? _deleteRound(GameSession s, int index) {
    final old = s.records[index];
    final sum = old.deltas.fold<int>(0, (a, d) => a + d);
    final records = [...s.records]..removeAt(index);
    return _shiftRecords(s, records, index, [for (final d in old.deltas) -d], sum ~/ 1000)
        ?.copyWith(substitutions: _shiftSubstitutions(s.substitutions, index, -1));
  }

  /// 局の追加のチェック（問題なければ null）。[winners] が null なら流局
  static String? validateInsertRound(GameSession s, int index, List<int?> deltas,
      {List<int>? winners, int? loser}) {
    if (index < 0 || index > s.records.length) return tr('追加する場所が正しくありません', 'Invalid position to insert');
    if (deltas.length != s.playerCount || deltas.any((d) => d == null)) {
      return tr('${s.playerCount}人すべての増減を入力してください（動かない人は0）',
          'Enter the change for all ${s.playerCount} players (0 if unchanged)');
    }
    if (deltas.any((d) => d! % 100 != 0)) return tr('100点単位で入力してください', 'Enter in units of 100 pts');
    final sum = deltas.fold<int>(0, (a, d) => a + d!);
    if (sum != 0) {
      return tr('${s.playerCount}人の合計を0にしてください（今の合計: ${_signed(sum)}）',
          'The total for ${s.playerCount} players must be 0 (current total: ${_signed(sum)})');
    }
    if (deltas.every((d) => d == 0)) return tr('点数の増減を入力してください', 'Enter the point changes');
    if (winners != null) return validateWinners(s, winners, loser);
    return null;
  }

  /// 入れ忘れた局を [index] 番目に追加する（[index] が局の数なら最後）。
  ///
  /// 点数の増減の合計は0（立直棒の出入りは含めない）。後の局の点数と今の点数をずらす。
  /// 局の進行（今の局・本場）は変えないので、ずれたときは「局・本場・供託の修正」で直す。
  static GameSession insertRound(
    GameSession s,
    int index, {
    required String roundLabel,
    required List<int> deltas,
    List<int>? winners,
    int? loser,
    String description = '',
  }) {
    final e = validateInsertRound(s, index, deltas, winners: winners, loser: loser);
    if (e != null) throw ArgumentError(e);
    final n = s.playerCount;
    final before = index == 0 ? List.filled(n, s.settings.startingPoints) : s.records[index - 1].scoresAfter;
    final record = RoundRecord(
      roundLabel: roundLabel.trim().isEmpty ? tr('追加した局', 'Added round') : roundLabel.trim(),
      kind: winners == null ? 'draw' : 'win',
      description: description.trim().isEmpty ? tr('後から追加した局', 'Round added later') : description.trim(),
      deltas: List.unmodifiable(deltas),
      scoresAfter: List.unmodifiable([for (var i = 0; i < n; i++) before[i] + deltas[i]]),
      edited: true,
      winners: List.unmodifiable(winners ?? const <int>[]),
      loser: winners == null ? null : loser,
      riichi: const [],
    );
    final records = [...s.records]..insert(index, record);
    return _shiftRecords(s, records, index + 1, deltas, 0)!
        .copyWith(substitutions: _shiftSubstitutions(s.substitutions, index, 1));
  }

  // ---- 局・本場・供託の修正 ----

  /// 局の通し番号として選べる最後の番号（西入ありなら延長の4局目まで）
  static int maxRoundIndex(GameSettings rules) =>
      (rules.westRound ? rules.totalRounds + rules.playerCount : rules.totalRounds) - 1;

  /// 今の局・本場・供託を直す（数え間違いなど）。点数は変えない。元に戻すで戻せる
  static GameSession adjustProgress(GameSession s, {required int roundIndex, required int honba, required int riichiSticks}) {
    if (s.finished) throw ArgumentError(tr('終局した対局は直せません', 'A finished game cannot be edited'));
    if (roundIndex < 0 || roundIndex > maxRoundIndex(s.settings)) throw ArgumentError(tr('局が正しくありません', 'Invalid round'));
    if (honba < 0 || honba > 99 || riichiSticks < 0 || riichiSticks > 99) throw ArgumentError(tr('0〜99で入力してください', 'Enter a value from 0 to 99'));
    return s.copyWith(roundIndex: roundIndex, honba: honba, riichiSticks: riichiSticks, previous: s);
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

  /// 名前を入れなかったときの名前（「プレイヤー1」など）。名前の候補には出さない
  static String defaultPlayerName(int index) => tr('プレイヤー${index + 1}', 'Player ${index + 1}');
  // どちらの言語の形も「名前を入れなかったときの名前」として扱う
  static final _defaultNamePattern = RegExp(r'^(プレイヤー\d+|Player \d+)$');
  static bool isDefaultPlayerName(String name) => _defaultNamePattern.hasMatch(name);

  /// 過去の対局で使った名前（最近使った順・重複なし。「プレイヤー1」などは除く）
  static List<String> recentPlayerNames(List<GameSession> sessions, {int limit = 16}) {
    final sorted = [...sessions]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final names = <String>[];
    for (final s in sorted) {
      for (final n in s.playerNames) {
        final name = n.trim();
        if (name.isEmpty || isDefaultPlayerName(name) || names.contains(name)) continue;
        names.add(name);
        if (names.length >= limit) return names;
      }
    }
    return names;
  }

  /// 同じ人数で一番最近の対局のメンバー（座順のまま）。なければ null
  static List<String>? lastMembers(List<GameSession> sessions, int playerCount) {
    GameSession? last;
    for (final s in sessions) {
      if (s.playerCount != playerCount) continue;
      if (last == null || s.createdAt.isAfter(last.createdAt)) last = s;
    }
    return last?.playerNames;
  }

  /// 名前の入力のチェック（問題なければ null）。空の欄は「プレイヤー1」などになる
  static String? validatePlayerNames(List<String> names) {
    final filled = [
      for (var i = 0; i < names.length; i++) names[i].trim().isEmpty ? defaultPlayerName(i) : names[i].trim()
    ];
    if (filled.toSet().length != filled.length) {
      return tr('同じ名前の人がいます。個人成績を正しく集計できるように、別の名前にしてください',
          'Two players have the same name. Use different names so that player stats are counted correctly');
    }
    return null;
  }

  /// 名前の変更の確認（問題なければ null）
  static String? validateRename(String from, String to) {
    final t = to.trim();
    if (t.isEmpty) return tr('名前を入力してください', 'Enter a name');
    if (t == from) return tr('今と同じ名前です', 'The name is unchanged');
    return null;
  }

  /// すべての対局で、プレイヤーの名前 [from] を [to] に変える（[to] が既にあれば、同じ人としてまとめる）。
  ///
  /// 同じ対局に [from] と [to] の両方がいる対局は、別の人なので変えない（skipped に数える）。
  /// 変えない対局は同じオブジェクトのまま返す（保存処理は同じオブジェクトかどうかで変更を判定している）。
  /// 局の内容のメモに書かれた名前は変えない。
  static ({List<GameSession> sessions, int renamed, int skipped}) renamePlayer(
      List<GameSession> sessions, String from, String to) {
    final error = validateRename(from, to);
    if (error != null) throw ArgumentError(error);
    final t = to.trim();
    var renamed = 0, skipped = 0;
    final out = [
      for (final s in sessions)
        if (!s.allNames.contains(from))
          s
        else if (s.allNames.contains(t))
          () {
            skipped++;
            return s;
          }()
        else
          () {
            renamed++;
            return _renameDeep(s, from, t);
          }(),
    ];
    return (sessions: out, renamed: renamed, skipped: skipped);
  }

  /// 名前を変える（元に戻す用の前の状態も同じように変える。元に戻しても名前が戻らないように）
  static GameSession _renameDeep(GameSession s, String from, String to) {
    String r(String n) => n == from ? to : n;
    return s.copyWith(
      playerNames: List.unmodifiable([for (final n in s.playerNames) r(n)]),
      substitutions: List.unmodifiable([for (final x in s.substitutions) x.copyWith(from: r(x.from), to: r(x.to))]),
      previous: s.previous == null ? null : _renameDeep(s.previous!, from, to),
    );
  }

  // ---- プレイヤーの交代 ----

  /// 交代のチェック（問題なければ null）
  static String? validateSubstitute(GameSession s, int seat, String name) {
    if (s.finished) return tr('終局した対局では交代できません', 'Players cannot be substituted in a finished game');
    if (seat < 0 || seat >= s.playerCount) return tr('席が正しくありません', 'Invalid seat');
    final t = name.trim();
    if (t.isEmpty) return tr('入る人の名前を入力してください', 'Enter the name of the incoming player');
    if (s.playerNames.contains(t)) return tr('「$t」は今この対局で打っています。別の名前にしてください', '"$t" is already playing in this game. Use a different name');
    return null;
  }

  /// 席 [seat] の人を [name] に交代する。点数・席（風）はそのまま引き継ぐ。
  ///
  /// これより前の局は抜けた人、これからの局は入った人の成績として個人成績に数える。
  /// 最終結果（順位・ポイント）は、終局したときに打っていた人の成績になる。元に戻すで取り消せる
  static GameSession substitute(GameSession s, int seat, String name) {
    final e = validateSubstitute(s, seat, name);
    if (e != null) throw ArgumentError(e);
    final t = name.trim();
    final from = s.records.length;
    final subs = [...s.substitutions];
    // まだ1局も打たないうちにもう一度交代したら、1回の交代にまとめる
    final i = subs.lastIndexWhere((x) => x.seat == seat && x.fromRecord == from);
    if (i >= 0) {
      final first = subs.removeAt(i);
      if (first.from != t) subs.add(first.copyWith(to: t));
    } else {
      subs.add(Substitution(fromRecord: from, seat: seat, from: s.playerNames[seat], to: t));
    }
    return s.copyWith(
      playerNames: List.unmodifiable([for (var p = 0; p < s.playerCount; p++) p == seat ? t : s.playerNames[p]]),
      substitutions: List.unmodifiable(subs),
      previous: s,
    );
  }

  /// 局を [index] に追加・削除したときに、交代の局の番号をずらす
  static List<Substitution> _shiftSubstitutions(List<Substitution> subs, int index, int by) => List.unmodifiable([
        for (final x in subs)
          x.fromRecord > index || (by > 0 && x.fromRecord == index) ? x.copyWith(fromRecord: x.fromRecord + by) : x
      ]);

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

bool _sameList(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
