import 'decomposer.dart';
import 'hand_context.dart';
import 'types.dart';
import 'yaku_judge.dart';

/// 符計算の結果
class FuResult {
  /// 切り上げ後の符
  final int fu;

  /// 切り上げ前の符
  final int rawFu;
  final List<FuDetail> details;

  const FuResult(this.fu, this.rawFu, this.details);
}

/// 符計算
class FuCalculator {
  FuCalculator._();

  static FuResult calculate(HandContext ctx) {
    if (ctx.shape == HandShape.chiitoitsu) {
      return const FuResult(25, 25, [FuDetail('七対子', 25)]);
    }
    if (ctx.shape == HandShape.kokushi) {
      // 役満なので符は使わないが表示用に 30 符とする
      return const FuResult(30, 30, [FuDetail('副底', 30)]);
    }

    final pinfu = YakuJudge.isPinfu(ctx);
    if (pinfu && ctx.isTsumo) {
      return const FuResult(20, 20, [FuDetail('平和ツモ', 20)]);
    }

    final details = <FuDetail>[const FuDetail('副底', 20)];
    if (ctx.menzen && !ctx.isTsumo) {
      details.add(const FuDetail('門前ロン', 10));
    }
    if (ctx.isTsumo) details.add(const FuDetail('ツモ', 2));

    // 面子
    for (var i = 0; i < ctx.groups.length; i++) {
      final g = ctx.groups[i];
      if (!g.isTripletLike) continue;
      final concealed = ctx.isConcealedTriplet(i);
      final yaochu = isYaochuIndex(g.tile);
      int fu;
      String name;
      if (g.type == GroupType.kan) {
        fu = concealed ? 16 : 8;
        name = concealed ? '暗槓' : '明槓';
      } else {
        fu = concealed ? 4 : 2;
        name = concealed ? '暗刻' : '明刻';
      }
      if (yaochu) fu *= 2;
      details.add(FuDetail('$name(${yaochu ? "么九牌" : "中張牌"})', fu));
    }

    // 雀頭
    final p = ctx.pair!.tile;
    if (p >= 31) details.add(const FuDetail('雀頭(三元牌)', 2));
    if (p == ctx.roundWind && p == ctx.seatWind) {
      // 連風牌（場風かつ自風）はルールによって 4符 か 2符
      details.add(FuDetail('雀頭(連風牌)', ctx.rules.renpuuPairFu));
    } else {
      if (p == ctx.roundWind) details.add(const FuDetail('雀頭(場風)', 2));
      if (p == ctx.seatWind) details.add(const FuDetail('雀頭(自風)', 2));
    }

    // 待ち
    switch (ctx.wait) {
      case WaitType.kanchan:
        details.add(const FuDetail('嵌張待ち', 2));
        break;
      case WaitType.penchan:
        details.add(const FuDetail('辺張待ち', 2));
        break;
      case WaitType.tanki:
        details.add(const FuDetail('単騎待ち', 2));
        break;
      default:
        break;
    }

    var raw = details.fold<int>(0, (a, d) => a + d.fu);
    // 鳴き平和形のロン（20符）は30符に
    if (raw == 20 && !ctx.isTsumo) {
      details.add(const FuDetail('喰い平和形', 10));
      raw = 30;
    }
    final fu = ((raw + 9) ~/ 10) * 10;
    return FuResult(fu, raw, details);
  }
}
