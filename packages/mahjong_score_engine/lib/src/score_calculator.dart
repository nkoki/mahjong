import 'decomposer.dart';
import 'fu_calculator.dart';
import 'hand_context.dart';
import 'tile_utils.dart';
import 'types.dart';
import 'yaku_judge.dart';

/// 点数計算のメインクラス
class ScoreCalculator {
  ScoreCalculator._();

  /// 和了の点数を計算する。
  ///
  /// [honba] 本場数（1本場につきロン300点 / ツモ各100点）
  /// [riichiSticks] 供託リーチ棒の本数（1本1000点を和了者が獲得）
  /// [rules] 点数計算のルール（喰いタン・切り上げ満貫など）
  static ScoreResult calculate(
    WinInput input, {
    int honba = 0,
    int riichiSticks = 0,
    ScoreRules rules = const ScoreRules(),
  }) {
    final error = _validate(input, rules);
    if (error != null) return ScoreResult.error(error);

    final contexts = _buildContexts(input, rules);
    if (contexts.isEmpty) {
      return ScoreResult.error('和了形になっていません');
    }

    ScoreResult? best;
    for (final ctx in contexts) {
      final r = _scoreContext(ctx, input, honba, riichiSticks);
      if (r == null) continue;
      if (best == null ||
          r.totalScore > best.totalScore ||
          (r.totalScore == best.totalScore && r.han > best.han) ||
          (r.totalScore == best.totalScore &&
              r.han == best.han &&
              r.fu > best.fu)) {
        best = r;
      }
    }
    return best ?? ScoreResult.error('役がありません（ドラのみでは和了できません）');
  }

  // ---------------------------------------------------------------------
  // 入力チェック
  // ---------------------------------------------------------------------
  static String? _validate(WinInput input, ScoreRules rules) {
    if (input.winType != 'ron' && input.winType != 'tsumo') {
      return '和了方法は ron か tsumo を指定してください';
    }
    final all = [
      ...input.handTiles,
      input.winningTile,
      for (final m in input.melds) ...m.tiles,
      ...input.doraTiles,
      ...input.uraDoraTiles,
      input.roundWind,
      input.playerWind,
    ];
    for (final t in all) {
      if (!isValidTile(t)) return '不正な牌があります: $t';
    }
    for (final w in [input.roundWind, input.playerWind]) {
      final i = tileToIndex(w);
      if (i < 27 || i > 30) return '風は 1z〜4z で指定してください: $w';
    }
    if (input.melds.length > 4) return '鳴きは4つまでです';
    if (rules.isSanma) {
      if (tileToIndex(input.playerWind) > 29) return '3人打ちの自風は東・南・西のどれかです';
      final all = [
        ...input.handTiles,
        input.winningTile,
        for (final m in input.melds) ...m.tiles,
        ...input.doraTiles,
        ...input.uraDoraTiles,
      ];
      if (all.any((t) => tileSuit(t) == 'm' && tileNumber(t) >= 2 && tileNumber(t) <= 8)) {
        return '3人打ちでは二萬〜八萬は使いません';
      }
      if (input.melds.any((m) => m.type == MeldType.chi)) return '3人打ちではチーはできません';
      if (input.nukiDora < 0 || input.nukiDora > 4) return '抜きドラ（北）は0〜4枚です';
    } else if (input.nukiDora != 0) {
      return '抜きドラ（北）は3人打ちだけです';
    }
    final need = 13 - 3 * input.melds.length;
    if (input.handTiles.length != need) {
      return '手牌の枚数が正しくありません（$need枚必要、現在${input.handTiles.length}枚）';
    }
    for (final m in input.melds) {
      final e = _validateMeld(m);
      if (e != null) return e;
    }
    final counts = toCounts([
      ...input.handTiles,
      input.winningTile,
      for (final m in input.melds) ...m.tiles,
      for (var i = 0; i < input.nukiDora; i++) '4z',
    ]);
    for (var i = 0; i < 34; i++) {
      if (counts[i] > 4) return '${tileName(indexToTile(i))}が5枚以上あります';
    }
    final menzen = input.melds.every((m) => !m.isOpen);
    if ((input.isRiichi || input.isDoubleRiichi) && !menzen) {
      return '鳴いている場合は立直できません';
    }
    return null;
  }

  static String? _validateMeld(Meld m) {
    final idx = m.tiles.map(tileToIndex).toList()..sort();
    switch (m.type) {
      case MeldType.chi:
        if (idx.length != 3 ||
            idx[0] >= 27 ||
            idx[0] ~/ 9 != idx[2] ~/ 9 ||
            idx[1] != idx[0] + 1 ||
            idx[2] != idx[0] + 2) {
          return 'チーは同じ種類の連続した3枚で指定してください';
        }
        return null;
      case MeldType.pon:
        if (idx.length != 3 || idx.toSet().length != 1) {
          return 'ポンは同じ牌3枚で指定してください';
        }
        return null;
      case MeldType.minkan:
      case MeldType.ankan:
      case MeldType.kakan:
        if (idx.length != 4 || idx.toSet().length != 1) {
          return '槓子は同じ牌4枚で指定してください';
        }
        return null;
    }
  }

  static Group _meldToGroup(Meld m) {
    final idx = m.tiles.map(tileToIndex).toList()..sort();
    switch (m.type) {
      case MeldType.chi:
        return Group(GroupType.sequence, idx.first, open: true, fromMeld: true);
      case MeldType.pon:
        return Group(GroupType.triplet, idx.first, open: true, fromMeld: true);
      case MeldType.minkan:
      case MeldType.kakan:
        return Group(GroupType.kan, idx.first, open: true, fromMeld: true);
      case MeldType.ankan:
        return Group(GroupType.kan, idx.first, open: false, fromMeld: true);
    }
  }

  // ---------------------------------------------------------------------
  // 解釈（面子分解 × 和了牌の位置）の列挙
  // ---------------------------------------------------------------------
  static List<HandContext> _buildContexts(WinInput input, ScoreRules rules) {
    final closedTiles = [...input.handTiles, input.winningTile];
    final closedCounts = toCounts(closedTiles);
    final meldGroups = input.melds.map(_meldToGroup).toList();
    final allCounts = List<int>.from(closedCounts);
    for (final g in meldGroups) {
      for (final t in g.tiles) {
        allCounts[t]++;
      }
    }
    final menzen = input.melds.every((m) => !m.isOpen);
    final winTile = tileToIndex(input.winningTile);
    final contexts = <HandContext>[];

    HandContext make({
      required HandShape shape,
      List<Group> groups = const [],
      Group? pair,
      required WaitType wait,
      int winGroupIndex = -1,
    }) =>
        HandContext(
          input: input,
          shape: shape,
          groups: groups,
          pair: pair,
          winTile: winTile,
          wait: wait,
          winGroupIndex: winGroupIndex,
          allCounts: allCounts,
          closedCounts: closedCounts,
          menzen: menzen,
          rules: rules,
        );

    if (input.melds.isEmpty) {
      // 国士無双
      if (isKokushi(closedTiles)) {
        final before = List<int>.from(closedCounts);
        before[winTile]--;
        final is13 = before.where((c) => c == 1).length == 13;
        contexts.add(make(
          shape: HandShape.kokushi,
          wait: is13 ? WaitType.kokushi13 : WaitType.kokushi,
        ));
        return contexts;
      }
      // 七対子
      if (isChiitoitsu(closedTiles)) {
        contexts.add(make(shape: HandShape.chiitoitsu, wait: WaitType.chiitoitsu));
      }
    }

    // 通常形
    for (final d in decomposeCounts(List<int>.from(closedCounts))) {
      final pair = d.first;
      final closedGroups = d.sublist(1);
      final groups = [...closedGroups, ...meldGroups];
      // 和了牌が雀頭に含まれる → 単騎
      if (pair.tile == winTile) {
        contexts.add(make(
          shape: HandShape.standard,
          groups: groups,
          pair: pair,
          wait: WaitType.tanki,
        ));
      }
      // 和了牌が門前の面子に含まれる
      final seenKeys = <String>{};
      for (var i = 0; i < closedGroups.length; i++) {
        final g = closedGroups[i];
        if (!g.tiles.contains(winTile)) continue;
        final wait = _waitOf(g, winTile);
        // 同じ形の面子で同じ待ちは重複になるのでスキップ
        final key = '${g.type}-${g.tile}-$wait';
        if (!seenKeys.add(key)) continue;
        contexts.add(make(
          shape: HandShape.standard,
          groups: groups,
          pair: pair,
          wait: wait,
          winGroupIndex: i,
        ));
      }
    }
    return contexts;
  }

  static WaitType _waitOf(Group g, int winTile) {
    if (g.isTripletLike) return WaitType.shanpon;
    final pos = winTile - g.tile; // 0,1,2
    if (pos == 1) return WaitType.kanchan;
    final n = g.tile % 9; // 順子の先頭の数字-1
    if (pos == 2 && n == 0) return WaitType.penchan; // 12 + 3
    if (pos == 0 && n == 6) return WaitType.penchan; // 7 + 89
    return WaitType.ryanmen;
  }

  // ---------------------------------------------------------------------
  // 1解釈の点数
  // ---------------------------------------------------------------------
  static ScoreResult? _scoreContext(
    HandContext ctx,
    WinInput input,
    int honba,
    int riichiSticks,
  ) {
    var yakuList = YakuJudge.judge(ctx);
    if (yakuList.isEmpty) return null;
    final rules = ctx.rules;

    final isYakuman = yakuList.first.isYakuman;
    final fuResult = FuCalculator.calculate(ctx);
    final allYaku = List<Yaku>.from(yakuList);
    int han;
    int yakumanCount = 0;
    int base;
    String? limitName;

    if (isYakuman) {
      yakumanCount = yakuList.fold<int>(0, (a, y) => a + y.han);
      if (!rules.doubleYakuman && yakumanCount > 1) {
        // ダブル役満・役満の複合なし: 役満1倍止まり
        yakumanCount = 1;
        yakuList = [for (final y in yakuList) Yaku(name: y.name, han: 1, isYakuman: true)];
        allYaku
          ..clear()
          ..addAll(yakuList);
      }
      han = 13 * yakumanCount;
      base = 8000 * yakumanCount;
      limitName = yakumanCount == 1 ? '役満' : '${_kanjiNum(yakumanCount)}倍役満';
    } else {
      // ドラ
      // 抜いた北もドラの数え方では「北」として数える（表示牌が西なら抜いた北もドラ）
      final allTiles = [
        ...input.handTiles,
        input.winningTile,
        for (final m in input.melds) ...m.tiles,
        for (var i = 0; i < input.nukiDora; i++) '4z',
      ];
      final sanma = rules.isSanma;
      final dora = countDora(allTiles, input.doraTiles, sanma: sanma);
      final aka = allTiles.where(isRedDora).length;
      final ura = (input.isRiichi || input.isDoubleRiichi)
          ? countDora(allTiles, input.uraDoraTiles, sanma: sanma)
          : 0;
      if (input.nukiDora > 0) {
        allYaku.add(Yaku(name: '抜きドラ', han: input.nukiDora, isYakuman: false));
      }
      if (dora > 0) allYaku.add(Yaku(name: 'ドラ', han: dora, isYakuman: false));
      if (aka > 0) allYaku.add(Yaku(name: '赤ドラ', han: aka, isYakuman: false));
      if (ura > 0) allYaku.add(Yaku(name: '裏ドラ', han: ura, isYakuman: false));

      han = allYaku.fold<int>(0, (a, y) => a + y.han);
      base = fuResult.fu * (1 << (han + 2));
      if (han >= 13 && rules.kazoeYakuman) {
        base = 8000;
        limitName = '数え役満';
        yakumanCount = 1;
      } else if (han >= 11) {
        base = 6000;
        limitName = '三倍満';
      } else if (han >= 8) {
        base = 4000;
        limitName = '倍満';
      } else if (han >= 6) {
        base = 3000;
        limitName = '跳満';
      } else if (han >= 5 || base >= 2000) {
        base = 2000;
        limitName = '満貫';
      } else if (rules.kiriageMangan &&
          ((han == 4 && fuResult.fu == 30) || (han == 3 && fuResult.fu == 60))) {
        // 切り上げ満貫（基本点 1920 を 2000 に切り上げる）
        base = 2000;
        limitName = '満貫';
      }
    }

    final payment = _payments(
      base: base,
      isDealer: input.isDealer,
      isTsumo: input.isTsumo,
      winnerSeat: tileToIndex(input.playerWind) - 27,
      honba: honba,
      riichiSticks: riichiSticks,
      playerCount: rules.playerCount,
      tsumoSplit: rules.sanmaTsumoSplit,
    );

    return ScoreResult(
      isValid: true,
      yakuList: allYaku,
      han: han,
      fu: fuResult.fu,
      baseScore: base,
      totalScore: payment.$1,
      paymentDetails: payment.$2,
      isYakuman: isYakuman,
      yakumanCount: yakumanCount,
      limitName: limitName,
      fuDetails: fuResult.details,
    );
  }

  static int _ceil100(int x) => ((x + 99) ~/ 100) * 100;

  /// (和了点, 支払詳細) を返す
  static (int, PaymentDetail) _payments({
    required int base,
    required bool isDealer,
    required bool isTsumo,
    required int winnerSeat,
    required int honba,
    required int riichiSticks,
    int playerCount = 4,
    bool tsumoSplit = false,
  }) {
    final stickGain = riichiSticks * 1000;
    if (!isTsumo) {
      final honbaGain = honba * 300;
      final score = _ceil100(base * (isDealer ? 6 : 4));
      final loser = score + honbaGain;
      return (
        score,
        PaymentDetail(
          winnerGain: loser + stickGain,
          loserPayment: loser,
          riichiStickGain: stickGain,
          honbaGain: honbaGain,
        ),
      );
    }
    // 3人打ちで折半のときは、いない北家の分（子の支払い分、親の和了なら親の支払い分）を2人で分ける
    final missing = playerCount == 3 && tsumoSplit ? base * (isDealer ? 2 : 1) : 0;
    final payments = <PlayerPayment>[];
    var score = 0;
    for (var seat = 0; seat < playerCount; seat++) {
      if (seat == winnerSeat) continue;
      final p = _ceil100(base * ((isDealer || seat == 0) ? 2 : 1) + missing ~/ 2);
      score += p;
      payments.add(PlayerPayment(playerId: seat, amount: p + honba * 100));
    }
    final honbaGain = honba * 100 * payments.length;
    final gain = payments.fold<int>(0, (a, p) => a + p.amount);
    return (
      score,
      PaymentDetail(
        winnerGain: gain + stickGain,
        playerPayments: payments,
        riichiStickGain: stickGain,
        honbaGain: honbaGain,
      ),
    );
  }

  static String _kanjiNum(int n) =>
      const ['', '', '二', '三', '四', '五', '六'][n.clamp(0, 6)];

  /// 点数表記（例: "1300-2600", "4000オール", "8000"）
  static String formatScore(ScoreResult r, {required bool isDealer, required bool isTsumo}) {
    if (!isTsumo) return '${r.totalScore}';
    final pays = r.paymentDetails.playerPayments ?? const [];
    final honbaEach = pays.isEmpty ? 0 : r.paymentDetails.honbaGain ~/ pays.length;
    if (isDealer) {
      final each = pays.isEmpty ? 0 : pays.first.amount - honbaEach;
      return '$eachオール';
    }
    final dealer = pays.firstWhere((p) => p.playerId == 0).amount - honbaEach;
    final child = pays.firstWhere((p) => p.playerId != 0).amount - honbaEach;
    return '$child-$dealer';
  }
}
