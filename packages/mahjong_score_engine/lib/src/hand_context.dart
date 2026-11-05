import 'decomposer.dart';
import 'tile_utils.dart';
import 'types.dart';

/// 待ちの形
enum WaitType {
  ryanmen, // 両面
  kanchan, // 嵌張
  penchan, // 辺張
  shanpon, // 双碰
  tanki, // 単騎
  kokushi, // 国士（単騎）
  kokushi13, // 国士13面
  chiitoitsu, // 七対子（単騎）
}

/// 和了形の種類
enum HandShape { standard, chiitoitsu, kokushi }

/// 1つの「解釈」（面子分解 + 和了牌の位置）をまとめたもの。
/// 役判定・符計算はこの単位で行い、最も高い解釈を採用する。
class HandContext {
  final WinInput input;
  final HandShape shape;

  /// 4面子（鳴き含む）。七対子・国士では空。
  final List<Group> groups;

  /// 雀頭。七対子・国士では null。
  final Group? pair;

  /// 和了牌（インデックス）
  final int winTile;
  final WaitType wait;

  /// 和了牌で完成した面子の [groups] 内インデックス（雀頭なら -1）
  final int winGroupIndex;

  /// 手牌全体のカウント（槓子は4枚）
  final List<int> allCounts;

  /// 門前部分（手牌 + 和了牌）のカウント
  final List<int> closedCounts;

  /// 門前かどうか（暗槓のみは門前）
  final bool menzen;

  /// 点数計算のルール
  final ScoreRules rules;

  const HandContext({
    required this.input,
    required this.shape,
    required this.groups,
    required this.pair,
    required this.winTile,
    required this.wait,
    required this.winGroupIndex,
    required this.allCounts,
    required this.closedCounts,
    required this.menzen,
    this.rules = const ScoreRules(),
  });

  bool get isTsumo => input.isTsumo;
  bool get isDealer => input.isDealer;
  int get roundWind => tileToIndex(input.roundWind);
  int get seatWind => tileToIndex(input.playerWind);

  /// 指定の面子が暗刻（暗槓含む）扱いかどうか。
  /// ロンで完成させた刻子（シャンポン待ち）は明刻扱い。
  bool isConcealedTriplet(int index) {
    final g = groups[index];
    if (!g.isTripletLike || g.open) return false;
    if (!isTsumo && index == winGroupIndex) return false;
    return true;
  }

  int get concealedTripletCount {
    var n = 0;
    for (var i = 0; i < groups.length; i++) {
      if (isConcealedTriplet(i)) n++;
    }
    return n;
  }

  /// 手牌に含まれる牌インデックス（種類）の一覧
  Iterable<int> get presentTiles sync* {
    for (var i = 0; i < 34; i++) {
      if (allCounts[i] > 0) yield i;
    }
  }
}
