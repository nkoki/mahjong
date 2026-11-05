/// 牌の型（例: "1m", "5mr"(赤5萬), "1z"(東)）
///
/// - m: 萬子 / p: 筒子 / s: 索子 / z: 字牌
/// - 字牌: 1z=東 2z=南 3z=西 4z=北 5z=白 6z=發 7z=中
/// - 末尾 r は赤ドラ（"5mr", "5pr", "5sr"）
typedef Tile = String;

/// 鳴きの種類
enum MeldType {
  pon, // ポン
  chi, // チー
  minkan, // 明槓（大明槓）
  ankan, // 暗槓
  kakan, // 加槓
}

/// 鳴き情報
class Meld {
  final MeldType type;
  final List<Tile> tiles;
  final Tile? calledTile;

  const Meld({
    required this.type,
    required this.tiles,
    this.calledTile,
  });

  /// 槓子かどうか
  bool get isKan =>
      type == MeldType.minkan ||
      type == MeldType.ankan ||
      type == MeldType.kakan;

  /// 門前を崩す鳴きかどうか（暗槓は門前扱い）
  bool get isOpen => type != MeldType.ankan;
}

/// 点数計算のルール（初期値は一般的なリーチ麻雀のルール）
class ScoreRules {
  /// 喰いタン（鳴いた手の断么九）を認める
  final bool kuitan;

  /// 切り上げ満貫（4翻30符・3翻60符を満貫として扱う）
  final bool kiriageMangan;

  /// 数え役満（役満以外で13翻以上を役満にする）。なしの場合は三倍満止まり
  final bool kazoeYakuman;

  /// ダブル役満・役満の複合（四暗刻単騎などの2倍、役満どうしの足し算）。なしの場合は役満1倍止まり
  final bool doubleYakuman;

  /// 連風牌（場風かつ自風）の雀頭の符。4 か 2
  final int renpuuPairFu;

  /// 人数（4人打ち: 4 / 3人打ち: 3）
  final int playerCount;

  /// 3人打ちのツモの支払い。false: ツモ損（北家の分はもらえない） / true: 折半（北家の分を2人で分ける）
  final bool sanmaTsumoSplit;

  const ScoreRules({
    this.kuitan = true,
    this.kiriageMangan = false,
    this.kazoeYakuman = true,
    this.doubleYakuman = true,
    this.renpuuPairFu = 4,
    this.playerCount = 4,
    this.sanmaTsumoSplit = false,
  });

  /// 3人打ちか
  bool get isSanma => playerCount == 3;
}

/// 和了入力
class WinInput {
  /// 鳴いていない手牌（和了牌は含めない）。枚数は 13 - 3×鳴き数。
  final List<Tile> handTiles;

  /// 和了牌
  final Tile winningTile;
  final List<Meld> melds;

  /// 'ron' | 'tsumo'
  final String winType;
  final bool isRiichi;
  final bool isIppatsu;
  final bool isDoubleRiichi;

  /// ドラ表示牌
  final List<Tile> doraTiles;

  /// 裏ドラ表示牌（立直時のみ有効）
  final List<Tile> uraDoraTiles;

  /// 場風 "1z"(東), "2z"(南) など
  final Tile roundWind;

  /// 自風 "1z"(東=親), "2z"(南) など
  final Tile playerWind;

  final bool isRinshan; // 嶺上開花
  final bool isChankan; // 槍槓
  final bool isHaitei; // 海底摸月
  final bool isHoutei; // 河底撈魚
  final bool isTenho; // 天和
  final bool isChiho; // 地和

  /// 3人打ちで抜いた北の枚数（抜きドラ。1枚につきドラ1）
  final int nukiDora;

  const WinInput({
    required this.handTiles,
    required this.winningTile,
    required this.melds,
    required this.winType,
    required this.isRiichi,
    required this.isIppatsu,
    required this.isDoubleRiichi,
    required this.doraTiles,
    required this.uraDoraTiles,
    required this.roundWind,
    required this.playerWind,
    this.isRinshan = false,
    this.isChankan = false,
    this.isHaitei = false,
    this.isHoutei = false,
    this.isTenho = false,
    this.isChiho = false,
    this.nukiDora = 0,
  });

  bool get isTsumo => winType == 'tsumo';
  bool get isDealer => playerWind == '1z';
}

/// 面子分解結果
class Decomposition {
  final List<Tile>? head;
  final List<List<Tile>> melds;

  const Decomposition({
    required this.head,
    required this.melds,
  });

  @override
  String toString() => 'Decomposition(head: $head, melds: $melds)';
}

/// 役情報
class Yaku {
  final String name;

  /// 翻数（役満の場合は役満の倍数: 1=役満, 2=ダブル役満）
  final int han;
  final bool isYakuman;

  const Yaku({
    required this.name,
    required this.han,
    required this.isYakuman,
  });

  @override
  String toString() => isYakuman
      ? (han >= 2 ? '$name($han倍役満)' : '$name(役満)')
      : '$name($han翻)';
}

/// プレイヤーごとの支払額
///
/// [playerId] は支払う人の自風インデックス（0=東家(親), 1=南家, 2=西家, 3=北家）。
class PlayerPayment {
  final int playerId;
  final int amount;

  const PlayerPayment({
    required this.playerId,
    required this.amount,
  });

  @override
  String toString() => 'PlayerPayment($playerId: $amount)';
}

/// 支払額詳細
class PaymentDetail {
  /// 和了者の収入合計（本場・供託込み）
  final int winnerGain;

  /// ロン時: 放銃者の支払額（本場込み）
  final int? loserPayment;

  /// ツモ時: 各プレイヤーの支払額（本場込み）
  final List<PlayerPayment>? playerPayments;

  /// 供託リーチ棒による収入
  final int riichiStickGain;

  /// 本場による収入
  final int honbaGain;

  const PaymentDetail({
    required this.winnerGain,
    this.loserPayment,
    this.playerPayments,
    required this.riichiStickGain,
    required this.honbaGain,
  });
}

/// 符の内訳
class FuDetail {
  final String name;
  final int fu;

  const FuDetail(this.name, this.fu);

  @override
  String toString() => '$name: $fu符';
}

/// 計算結果
class ScoreResult {
  final bool isValid;
  final String? error;
  final List<Yaku> yakuList;
  final int han;
  final int fu;

  /// 基本点（符 × 2^(翻+2)、満貫以上は上限値）
  final int baseScore;

  /// 和了点（本場・供託を含まない）
  final int totalScore;
  final PaymentDetail paymentDetails;
  final bool isYakuman;
  final int yakumanCount;

  /// "満貫" "跳満" "倍満" "三倍満" "役満" "数え役満" など（通常は null）
  final String? limitName;

  /// 符の内訳
  final List<FuDetail> fuDetails;

  const ScoreResult({
    required this.isValid,
    this.error,
    required this.yakuList,
    required this.han,
    required this.fu,
    required this.baseScore,
    required this.totalScore,
    required this.paymentDetails,
    required this.isYakuman,
    required this.yakumanCount,
    this.limitName,
    this.fuDetails = const [],
  });

  factory ScoreResult.error(String message) {
    return ScoreResult(
      isValid: false,
      error: message,
      yakuList: const [],
      han: 0,
      fu: 0,
      baseScore: 0,
      totalScore: 0,
      paymentDetails: const PaymentDetail(
        winnerGain: 0,
        riichiStickGain: 0,
        honbaGain: 0,
      ),
      isYakuman: false,
      yakumanCount: 0,
    );
  }

  @override
  String toString() => isValid
      ? 'ScoreResult(${yakuList.join(", ")} / $han翻$fu符 / $totalScore点'
          '${limitName != null ? " $limitName" : ""})'
      : 'ScoreResult(error: $error)';
}
