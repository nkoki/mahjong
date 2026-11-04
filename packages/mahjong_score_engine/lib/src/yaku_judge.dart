import 'decomposer.dart';
import 'hand_context.dart';
import 'types.dart';

/// 役判定
class YakuJudge {
  YakuJudge._();

  static const _dragons = [31, 32, 33]; // 白發中
  static const _winds = [27, 28, 29, 30]; // 東南西北
  static const _windNames = ['東', '南', '西', '北'];
  static const _dragonNames = ['白', '發', '中'];

  /// 役の一覧を返す。役満があれば役満のみを返す。
  /// ドラ（ドラ・裏ドラ・赤ドラ）は含まない。
  static List<Yaku> judge(HandContext ctx) {
    final yakuman = _judgeYakuman(ctx);
    if (yakuman.isNotEmpty) return yakuman;
    return _judgeNormal(ctx);
  }

  // ---------------------------------------------------------------------
  // 役満
  // ---------------------------------------------------------------------
  static List<Yaku> _judgeYakuman(HandContext ctx) {
    final list = <Yaku>[];
    final input = ctx.input;
    void add(String name, [int times = 1]) =>
        list.add(Yaku(name: name, han: times, isYakuman: true));

    final noMelds = input.melds.isEmpty;
    if (input.isTenho && ctx.isTsumo && ctx.isDealer && noMelds) add('天和');
    if (input.isChiho && ctx.isTsumo && !ctx.isDealer && noMelds) add('地和');

    if (ctx.shape == HandShape.kokushi) {
      if (ctx.wait == WaitType.kokushi13) {
        add('国士無双十三面待ち', 2);
      } else {
        add('国士無双');
      }
      return list;
    }

    final tiles = ctx.presentTiles.toList();

    // 字一色
    if (tiles.every(isHonorIndex)) add('字一色');
    // 緑一色（2,3,4,6,8索 と 發）
    const green = {19, 20, 21, 23, 25, 32};
    if (tiles.every(green.contains)) add('緑一色');
    // 清老頭
    if (tiles.every((t) => !isHonorIndex(t) && isYaochuIndex(t))) add('清老頭');

    if (ctx.shape == HandShape.chiitoitsu) return list;

    final groups = ctx.groups;
    final pair = ctx.pair!;

    // 四暗刻
    if (ctx.concealedTripletCount == 4) {
      if (ctx.wait == WaitType.tanki) {
        add('四暗刻単騎', 2);
      } else {
        add('四暗刻');
      }
    }
    // 大三元
    final dragonTriplets =
        groups.where((g) => g.isTripletLike && _dragons.contains(g.tile)).length;
    if (dragonTriplets == 3) add('大三元');
    // 四喜和
    final windTriplets =
        groups.where((g) => g.isTripletLike && _winds.contains(g.tile)).length;
    if (windTriplets == 4) {
      add('大四喜', 2);
    } else if (windTriplets == 3 && _winds.contains(pair.tile)) {
      add('小四喜');
    }
    // 四槓子
    if (groups.where((g) => g.type == GroupType.kan).length == 4) add('四槓子');
    // 九蓮宝燈（鳴き・暗槓なし）
    if (noMelds) {
      final c = ctx.closedCounts;
      for (var s = 0; s < 3; s++) {
        final base = s * 9;
        final suitCount = c.sublist(base, base + 9).fold<int>(0, (a, b) => a + b);
        if (suitCount != 14) continue;
        const need = [3, 1, 1, 1, 1, 1, 1, 1, 3];
        var ok = true;
        for (var i = 0; i < 9; i++) {
          if (c[base + i] < need[i]) ok = false;
        }
        if (!ok) continue;
        // 和了牌を除いた13枚が 1112345678999 なら純正
        final before = List<int>.from(c.sublist(base, base + 9));
        before[ctx.winTile - base]--;
        var junsei = true;
        for (var i = 0; i < 9; i++) {
          if (before[i] != need[i]) junsei = false;
        }
        if (junsei) {
          add('純正九蓮宝燈', 2);
        } else {
          add('九蓮宝燈');
        }
      }
    }
    return list;
  }

  // ---------------------------------------------------------------------
  // 通常役
  // ---------------------------------------------------------------------
  static List<Yaku> _judgeNormal(HandContext ctx) {
    final list = <Yaku>[];
    final input = ctx.input;
    final menzen = ctx.menzen;
    void add(String name, int han) =>
        list.add(Yaku(name: name, han: han, isYakuman: false));

    // --- 状況役 ---
    if (menzen && input.isDoubleRiichi) {
      add('ダブル立直', 2);
    } else if (menzen && input.isRiichi) {
      add('立直', 1);
    }
    if (menzen && (input.isRiichi || input.isDoubleRiichi) && input.isIppatsu) {
      add('一発', 1);
    }
    if (menzen && ctx.isTsumo) add('門前清自摸和', 1);
    if (input.isRinshan && ctx.isTsumo) add('嶺上開花', 1);
    if (input.isChankan && !ctx.isTsumo) add('槍槓', 1);
    if (input.isHaitei && ctx.isTsumo && !input.isRinshan) add('海底摸月', 1);
    if (input.isHoutei && !ctx.isTsumo) add('河底撈魚', 1);

    final tiles = ctx.presentTiles.toList();
    final hasHonor = tiles.any(isHonorIndex);

    // 断么九（喰いタンあり）
    if (tiles.every((t) => !isYaochuIndex(t))) add('断么九', 1);

    // 混老頭（全て么九牌。順子なしは自動的に満たす）
    final allYaochu = tiles.every(isYaochuIndex);
    if (allYaochu && hasHonor) add('混老頭', 2);

    // 染め手
    final suits = tiles.where((t) => !isHonorIndex(t)).map((t) => t ~/ 9).toSet();
    if (suits.length == 1) {
      if (hasHonor) {
        add('混一色', menzen ? 3 : 2);
      } else {
        add('清一色', menzen ? 6 : 5);
      }
    }

    if (ctx.shape == HandShape.chiitoitsu) {
      add('七対子', 2);
      return list;
    }

    final groups = ctx.groups;
    final pair = ctx.pair!;
    final sequences = groups.where((g) => g.isSequence).toList();
    final triplets = groups.where((g) => g.isTripletLike).toList();

    // 平和
    if (isPinfu(ctx)) add('平和', 1);

    // 一盃口・二盃口（門前のみ）
    if (menzen) {
      final seqCount = <int, int>{};
      for (final g in sequences) {
        seqCount[g.tile] = (seqCount[g.tile] ?? 0) + 1;
      }
      final peiko = seqCount.values.fold<int>(0, (a, c) => a + c ~/ 2);
      if (peiko >= 2) {
        add('二盃口', 3);
      } else if (peiko == 1) {
        add('一盃口', 1);
      }
    }

    // 役牌
    for (final g in triplets) {
      final dIdx = _dragons.indexOf(g.tile);
      if (dIdx >= 0) add('役牌 ${_dragonNames[dIdx]}', 1);
      if (g.tile == ctx.roundWind) {
        add('役牌 場風${_windNames[g.tile - 27]}', 1);
      }
      if (g.tile == ctx.seatWind) {
        add('役牌 自風${_windNames[g.tile - 27]}', 1);
      }
    }

    // 三色同順
    for (var n = 0; n < 7; n++) {
      if ([0, 1, 2].every((s) => sequences.any((g) => g.tile == s * 9 + n))) {
        add('三色同順', menzen ? 2 : 1);
        break;
      }
    }
    // 三色同刻
    for (var n = 0; n < 9; n++) {
      if ([0, 1, 2].every((s) => triplets.any((g) => g.tile == s * 9 + n))) {
        add('三色同刻', 2);
        break;
      }
    }
    // 一気通貫
    for (var s = 0; s < 3; s++) {
      if ([0, 3, 6].every((n) => sequences.any((g) => g.tile == s * 9 + n))) {
        add('一気通貫', menzen ? 2 : 1);
        break;
      }
    }
    // 対々和
    if (triplets.length == 4) add('対々和', 2);
    // 三暗刻
    if (ctx.concealedTripletCount == 3) add('三暗刻', 2);
    // 三槓子
    if (groups.where((g) => g.type == GroupType.kan).length == 3) {
      add('三槓子', 2);
    }
    // 小三元
    final dragonTriplets = triplets.where((g) => _dragons.contains(g.tile)).length;
    if (dragonTriplets == 2 && _dragons.contains(pair.tile)) add('小三元', 2);

    // 全帯么九系（順子が1つ以上あるもの。順子なしは混老頭/清老頭）
    final allGroupsYaochu =
        groups.every((g) => g.containsYaochu) && pair.containsYaochu;
    if (allGroupsYaochu && sequences.isNotEmpty) {
      if (hasHonor) {
        add('混全帯么九', menzen ? 2 : 1);
      } else {
        add('純全帯么九', menzen ? 3 : 2);
      }
    }

    return list;
  }

  /// 平和の判定（門前・4順子・雀頭が役牌でない・両面待ち）
  static bool isPinfu(HandContext ctx) {
    if (ctx.shape != HandShape.standard) return false;
    if (!ctx.menzen || ctx.input.melds.isNotEmpty) return false;
    if (!ctx.groups.every((g) => g.isSequence)) return false;
    if (ctx.wait != WaitType.ryanmen) return false;
    final p = ctx.pair!.tile;
    if (_dragons.contains(p) || p == ctx.roundWind || p == ctx.seatWind) {
      return false;
    }
    return true;
  }
}
