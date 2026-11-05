import 'package:mahjong_score_engine/mahjong_score_engine.dart';

import '../../../core/l10n.dart';

/// 対局ルール設定
class GameSettings {
  /// 配給原点（持ち点）
  final int startingPoints;

  /// 返し点（オカの基準）
  final int returnPoints;

  /// ウマ（1位〜4位、千点単位）
  final List<int> uma;

  /// 東風戦なら true、半荘戦なら false
  final bool tonpuu;

  /// 0点未満で終了（トビあり）
  final bool tobi;

  // ---- 点数計算のルール ----

  /// 喰いタン（鳴いた断么九）あり
  final bool kuitan;

  /// 切り上げ満貫（4翻30符・3翻60符を満貫）あり
  final bool kiriageMangan;

  /// 数え役満（13翻以上を役満）あり
  final bool kazoeYakuman;

  /// ダブル役満・役満の複合あり
  final bool doubleYakuman;

  /// 連風牌の雀頭の符（4 か 2）
  final int renpuuPairFu;

  // ---- 進行・流局・牌のルール ----

  /// ダブロンあり（なしなら頭ハネ: 放銃者から見て打つ順番が近い1人だけが和了）
  final bool doubleRon;

  /// 和了止めあり（オーラスで親が和了してトップなら終局）
  final bool agariYame;

  /// 西入あり（東風戦は南入）。最終局が終わって誰も返し点に届いていなければ次の場に入る。
  /// 延長中は誰かが返し点に届いた局で終了（サドンデス）、届かなくても延長の4局目で終了
  final bool westRound;

  /// 包（責任払い）あり。大三元・大四喜を確定させる牌を鳴かせた人が払う
  final bool pao;

  /// 流し満貫あり
  final bool nagashiMangan;

  /// 途中流局（九種九牌・四風連打・四家立直・四開槓・三家和）あり
  final bool abortiveDraws;

  /// 赤ドラあり（和了入力の牌に赤5を表示する）
  final bool redDora;

  /// 祝儀（チップ）を記録する。和了ごとに枚数を入れ、ロンは放銃者が、ツモはほかの全員が払う
  final bool chips;

  // ---- ローカルルール（精算ポイント、千点単位。0 ならなし）----

  /// 焼き鳥: 1回も和了しなかった人が払うポイント。和了した人で等分する
  final int yakitori;

  /// トビ賞: 0点未満になって対局が終わったとき、飛んだ人が飛ばした人（最後の局の和了者）に払うポイント
  final int tobiBonus;

  // ---- 人数・3人打ちのルール ----

  /// 人数（4人打ち: 4 / 3人打ち: 3）
  final int playerCount;

  /// 3人打ちの北抜き（抜きドラ）あり。なしの場合、北は普通の字牌
  final bool nukiDora;

  /// 3人打ちのツモの支払い。false: ツモ損 / true: 折半（北家の分を2人で分ける）
  final bool sanmaTsumoSplit;

  const GameSettings({
    this.startingPoints = 25000,
    this.returnPoints = 30000,
    this.uma = const [20, 10, -10, -20],
    this.tonpuu = false,
    this.tobi = true,
    this.kuitan = true,
    this.kiriageMangan = false,
    this.kazoeYakuman = true,
    this.doubleYakuman = true,
    this.renpuuPairFu = 4,
    this.doubleRon = true,
    this.agariYame = true,
    this.westRound = false,
    this.pao = true,
    this.nagashiMangan = true,
    this.abortiveDraws = true,
    this.redDora = true,
    this.chips = false,
    this.yakitori = 0,
    this.tobiBonus = 0,
    this.playerCount = 4,
    this.nukiDora = true,
    this.sanmaTsumoSplit = false,
  });

  /// 3人打ちの初期値（35,000点持ち・40,000点返し・ウマ +15/0/-15・赤ドラは筒子と索子のみ）
  const GameSettings.sanma({
    this.startingPoints = 35000,
    this.returnPoints = 40000,
    this.uma = const [15, 0, -15],
    this.tonpuu = false,
    this.tobi = true,
    this.kuitan = true,
    this.kiriageMangan = false,
    this.kazoeYakuman = true,
    this.doubleYakuman = true,
    this.renpuuPairFu = 4,
    this.doubleRon = true,
    this.agariYame = true,
    this.westRound = false,
    this.pao = true,
    this.nagashiMangan = true,
    this.abortiveDraws = true,
    this.redDora = true,
    this.chips = false,
    this.yakitori = 0,
    this.tobiBonus = 0,
    this.nukiDora = true,
    this.sanmaTsumoSplit = false,
  }) : playerCount = 3;

  /// 3人打ちか
  bool get isSanma => playerCount == 3;

  /// 総局数（4人打ち: 東風4 / 半荘8、3人打ち: 東風3 / 半荘6）。西入の延長は含まない
  int get totalRounds => tonpuu ? playerCount : playerCount * 2;

  /// 延長の呼び方（半荘戦は西入、東風戦は南入）
  String get extensionName => tonpuu ? tr('南入', 'South extension') : tr('西入', 'West extension');

  /// オカ（トップ取り、千点単位）
  double get oka => (returnPoints - startingPoints) * playerCount / 1000;

  /// ウマの表記（例: [20, 10, -10, -20] → "10-20"、全部0 → "なし"）
  String get umaLabel => formatUma(uma);

  /// 点数計算エンジンに渡すルール
  ScoreRules get scoreRules => ScoreRules(
        kuitan: kuitan,
        kiriageMangan: kiriageMangan,
        kazoeYakuman: kazoeYakuman,
        doubleYakuman: doubleYakuman,
        renpuuPairFu: renpuuPairFu,
        playerCount: playerCount,
        sanmaTsumoSplit: sanmaTsumoSplit,
      );

  /// ルールの要約（画面表示用）
  List<String> get ruleSummary => [
        if (isSanma) ...[
          tr('北抜き${nukiDora ? "あり" : "なし"}', 'Nuki dora (North) ${nukiDora ? "on" : "off"}'),
          sanmaTsumoSplit ? tr('ツモ折半', 'Tsumo split') : tr('ツモ損', 'Tsumo loss'),
        ],
        tr('喰いタン${kuitan ? "あり" : "なし"}', 'Kuitan ${kuitan ? "on" : "off"}'),
        tr('切り上げ満貫${kiriageMangan ? "あり" : "なし"}', 'Kiriage mangan ${kiriageMangan ? "on" : "off"}'),
        tr('数え役満${kazoeYakuman ? "あり" : "なし"}', 'Kazoe yakuman ${kazoeYakuman ? "on" : "off"}'),
        tr('ダブル役満${doubleYakuman ? "あり" : "なし"}', 'Double yakuman ${doubleYakuman ? "on" : "off"}'),
        tr('連風牌の雀頭$renpuuPairFu符', 'Double wind pair $renpuuPairFu fu'),
        doubleRon ? tr('ダブロンあり', 'Double ron on') : tr('ダブロンなし（頭ハネ）', 'Double ron off (head bump)'),
        tr('和了止め${agariYame ? "あり" : "なし"}', 'Agari-yame ${agariYame ? "on" : "off"}'),
        tr('$extensionName${westRound ? "あり" : "なし"}', '$extensionName ${westRound ? "on" : "off"}'),
        tr('包${pao ? "あり" : "なし"}', 'Pao ${pao ? "on" : "off"}'),
        tr('流し満貫${nagashiMangan ? "あり" : "なし"}', 'Nagashi mangan ${nagashiMangan ? "on" : "off"}'),
        tr('途中流局${abortiveDraws ? "あり" : "なし"}', 'Abortive draws ${abortiveDraws ? "on" : "off"}'),
        tr('赤ドラ${redDora ? "あり" : "なし"}', 'Red dora ${redDora ? "on" : "off"}'),
        if (chips) tr('祝儀あり', 'Chips on'),
        if (yakitori > 0) tr('焼き鳥 ${yakitori}P', 'Yakitori ${yakitori}P'),
        if (tobiBonus > 0) tr('トビ賞 ${tobiBonus}P', 'Bust bonus ${tobiBonus}P'),
      ];

  GameSettings copyWith({
    int? startingPoints,
    int? returnPoints,
    List<int>? uma,
    bool? tonpuu,
    bool? tobi,
    bool? kuitan,
    bool? kiriageMangan,
    bool? kazoeYakuman,
    bool? doubleYakuman,
    int? renpuuPairFu,
    bool? doubleRon,
    bool? agariYame,
    bool? westRound,
    bool? pao,
    bool? nagashiMangan,
    bool? abortiveDraws,
    bool? redDora,
    bool? chips,
    int? yakitori,
    int? tobiBonus,
    bool? nukiDora,
    bool? sanmaTsumoSplit,
  }) =>
      GameSettings(
        startingPoints: startingPoints ?? this.startingPoints,
        returnPoints: returnPoints ?? this.returnPoints,
        uma: uma ?? this.uma,
        tonpuu: tonpuu ?? this.tonpuu,
        tobi: tobi ?? this.tobi,
        kuitan: kuitan ?? this.kuitan,
        kiriageMangan: kiriageMangan ?? this.kiriageMangan,
        kazoeYakuman: kazoeYakuman ?? this.kazoeYakuman,
        doubleYakuman: doubleYakuman ?? this.doubleYakuman,
        renpuuPairFu: renpuuPairFu ?? this.renpuuPairFu,
        doubleRon: doubleRon ?? this.doubleRon,
        agariYame: agariYame ?? this.agariYame,
        westRound: westRound ?? this.westRound,
        pao: pao ?? this.pao,
        nagashiMangan: nagashiMangan ?? this.nagashiMangan,
        abortiveDraws: abortiveDraws ?? this.abortiveDraws,
        redDora: redDora ?? this.redDora,
        chips: chips ?? this.chips,
        yakitori: yakitori ?? this.yakitori,
        tobiBonus: tobiBonus ?? this.tobiBonus,
        playerCount: playerCount,
        nukiDora: nukiDora ?? this.nukiDora,
        sanmaTsumoSplit: sanmaTsumoSplit ?? this.sanmaTsumoSplit,
      );

  Map<String, dynamic> toJson() => {
        'startingPoints': startingPoints,
        'returnPoints': returnPoints,
        'uma': uma,
        'tonpuu': tonpuu,
        'tobi': tobi,
        if (isSanma) 'playerCount': playerCount,
        'rules': {
          'kuitan': kuitan,
          'kiriageMangan': kiriageMangan,
          'kazoeYakuman': kazoeYakuman,
          'doubleYakuman': doubleYakuman,
          'renpuuPairFu': renpuuPairFu,
          'doubleRon': doubleRon,
          'agariYame': agariYame,
          'westRound': westRound,
          'pao': pao,
          'nagashiMangan': nagashiMangan,
          'abortiveDraws': abortiveDraws,
          'redDora': redDora,
          if (chips) 'chips': true,
          if (yakitori > 0) 'yakitori': yakitori,
          if (tobiBonus > 0) 'tobiBonus': tobiBonus,
          if (isSanma) 'nukiDora': nukiDora,
          if (isSanma) 'sanmaTsumoSplit': sanmaTsumoSplit,
        },
      };

  /// ルール設定を入れる前に保存したデータには 'rules' がないので、
  /// その場合はそれまでの動き（初期値）として読み込む
  factory GameSettings.fromJson(Map<String, dynamic> j) {
    final r = (j['rules'] as Map<String, dynamic>?) ?? const {};
    const d = GameSettings();
    return GameSettings(
      startingPoints: j['startingPoints'] as int,
      returnPoints: j['returnPoints'] as int,
      uma: _intList(j['uma']),
      tonpuu: j['tonpuu'] as bool,
      tobi: j['tobi'] as bool,
      kuitan: r['kuitan'] as bool? ?? d.kuitan,
      kiriageMangan: r['kiriageMangan'] as bool? ?? d.kiriageMangan,
      kazoeYakuman: r['kazoeYakuman'] as bool? ?? d.kazoeYakuman,
      doubleYakuman: r['doubleYakuman'] as bool? ?? d.doubleYakuman,
      renpuuPairFu: r['renpuuPairFu'] as int? ?? d.renpuuPairFu,
      doubleRon: r['doubleRon'] as bool? ?? d.doubleRon,
      agariYame: r['agariYame'] as bool? ?? d.agariYame,
      westRound: r['westRound'] as bool? ?? d.westRound,
      pao: r['pao'] as bool? ?? d.pao,
      nagashiMangan: r['nagashiMangan'] as bool? ?? d.nagashiMangan,
      abortiveDraws: r['abortiveDraws'] as bool? ?? d.abortiveDraws,
      redDora: r['redDora'] as bool? ?? d.redDora,
      // version 4 以前のデータには無い（祝儀なし）
      chips: r['chips'] as bool? ?? false,
      // version 5 以前のデータには無い（なし）
      yakitori: r['yakitori'] as int? ?? 0,
      tobiBonus: r['tobiBonus'] as int? ?? 0,
      // 3人打ちを入れる前のデータは4人打ち
      playerCount: j['playerCount'] as int? ?? 4,
      nukiDora: r['nukiDora'] as bool? ?? d.nukiDora,
      sanmaTsumoSplit: r['sanmaTsumoSplit'] as bool? ?? d.sanmaTsumoSplit,
    );
  }
}

/// よく使われるウマ（1位〜4位、千点単位）
List<(String, List<int>)> get umaPresets => [
  (tr('なし', 'None'), [0, 0, 0, 0]),
  ('5-10', [10, 5, -5, -10]),
  ('10-20', [20, 10, -10, -20]),
  ('10-30', [30, 10, -10, -30]),
  ('20-30', [30, 20, -20, -30]),
];

/// 3人打ちでよく使われるウマ（1位〜3位、千点単位）
List<(String, List<int>)> get umaPresetsSanma => [
  (tr('なし', 'None'), [0, 0, 0]),
  ('±10', [10, 0, -10]),
  ('±15', [15, 0, -15]),
  ('±20', [20, 0, -20]),
  ('±30', [30, 0, -30]),
];

/// 人数に合ったウマの候補
List<(String, List<int>)> umaPresetsFor(int playerCount) =>
    playerCount == 3 ? umaPresetsSanma : umaPresets;

/// ウマの表記。4人打ちで「1位+大 / 2位+小 / 3位-小 / 4位-大」の形なら "小-大"、
/// 3人打ちで「1位+a / 2位0 / 3位-a」の形なら "±a"、
/// それ以外は "+30 / +10 / -10 / -30" のように並べる
String formatUma(List<int> uma) {
  if (uma.every((v) => v == 0)) return tr('なし', 'None');
  if (uma.length == 4) {
    final big = uma[0], small = uma[1];
    if (uma[2] == -small && uma[3] == -big && big >= small && small >= 0) {
      return '$small-$big';
    }
  }
  if (uma.length == 3 && uma[1] == 0 && uma[2] == -uma[0] && uma[0] > 0) {
    return '±${uma[0]}';
  }
  return uma.map((v) => v > 0 ? '+$v' : '$v').join(' / ');
}

/// 持ち点・返しの入力チェック（問題なければ null）
String? validatePoints(int? v) {
  if (v == null) return tr('数字を入力してください', 'Enter a number');
  if (v < 1000 || v > 1000000) return tr('1,000〜1,000,000点の範囲で入力してください', 'Enter a value from 1,000 to 1,000,000 pts');
  if (v % 100 != 0) return tr('100点単位で入力してください', 'Enter in units of 100 pts');
  return null;
}

/// 返しの入力チェック（持ち点より小さいとオカがマイナスになるので不可）
String? validateReturnPoints(int? ret, int? starting) {
  final e = validatePoints(ret);
  if (e != null) return e;
  if (starting != null && ret! < starting) return tr('持ち点以上の値を入力してください', 'Enter a value at least the starting points');
  return null;
}

/// ウマの入力チェック（問題なければ null）
String? validateUma(List<int?> uma, {int playerCount = 4}) {
  if (uma.length != playerCount || uma.any((v) => v == null)) {
    return tr('1位〜$playerCount位のすべてに数字を入力してください', 'Enter a number for every place from 1st to ${playerCount == 3 ? "3rd" : "${playerCount}th"}');
  }
  if (uma.any((v) => v!.abs() > 1000)) return tr('-1000〜1000の範囲で入力してください', 'Enter a value from -1000 to 1000');
  final sum = uma.fold<int>(0, (a, v) => a + v!);
  if (sum != 0) {
    return tr('合計が0になるようにしてください（今の合計: ${sum > 0 ? "+" : ""}$sum）',
        'The total must be 0 (current total: ${sum > 0 ? "+" : ""}$sum)');
  }
  return null;
}

List<int> _intList(Object? v) =>
    List<int>.unmodifiable((v as List).map((e) => e as int));

List<bool> _boolList(Object? v) =>
    List<bool>.unmodifiable((v as List).map((e) => e as bool));

/// 流局の種類
enum DrawType {
  exhaustive('荒牌平局（通常流局）', 'Exhaustive draw'),
  nagashiMangan('流し満貫', 'Nagashi mangan'),
  kyuushu('九種九牌', 'Kyuushu kyuuhai'),
  suufon('四風連打', 'Suufon renda'),
  suucha('四家立直', 'Suucha riichi'),
  suukan('四開槓', 'Suukaikan'),
  sanchaho('三家和', 'Sanchahou');

  final String _ja;
  final String _en;
  const DrawType(this._ja, this._en);

  /// 表示名（今の言語）
  String get label => tr(_ja, _en);

  /// 途中流局（親が連荘・テンパイ料なし）
  bool get isAbortive =>
      this != DrawType.exhaustive && this != DrawType.nagashiMangan;

  /// ルールで使える流局の種類。
  /// 3人打ちでは四風連打・四家立直・三家和は起こらないので、途中流局は九種九牌と四開槓だけ
  static List<DrawType> availableFor(GameSettings settings) => [
        for (final t in DrawType.values)
          if (t == DrawType.exhaustive ||
              (t == DrawType.nagashiMangan && settings.nagashiMangan) ||
              (t.isAbortive &&
                  settings.abortiveDraws &&
                  (!settings.isSanma || t == DrawType.kyuushu || t == DrawType.suukan)))
            t,
      ];
}

/// 1局の記録
class RoundRecord {
  /// "東1局 0本場" のような表記
  final String roundLabel;

  /// 'win' | 'draw'
  final String kind;

  /// 内容（例: "Aさん ロン ← Bさん 立直 平和 3900"）
  final String description;

  /// この局の点数増減（リーチ棒の支払いを含む）
  final List<int> deltas;

  /// 局終了後の点数
  final List<int> scoresAfter;

  /// あとから修正した局かどうか
  final bool edited;

  /// 和了者（流局なら空）。個人成績（和了率など）の集計に使う。
  /// 保存データの version 3 以前に記録した局には無い（null）
  final List<int>? winners;

  /// 放銃者（ツモ・流局なら null）
  final int? loser;

  /// この局で立直した人（version 3 以前に記録した局は null）
  final List<int>? riichi;

  /// 和了者ごとの和了点（本場・供託を含まない。[winners] と同じ順）
  final List<int>? winPoints;

  /// この局の祝儀（チップ）の枚数の増減（祝儀なし・祝儀の動きが無い局は null）
  final List<int>? chips;

  /// 和了者ごとの役の名前（ドラは除く。[winners] と同じ順）。
  /// 翻・符で入力した和了は空。version 7 以前に記録した局・後から追加した局は null
  final List<List<String>>? yaku;

  const RoundRecord({
    required this.roundLabel,
    required this.kind,
    required this.description,
    required this.deltas,
    required this.scoresAfter,
    this.edited = false,
    this.winners,
    this.loser,
    this.riichi,
    this.winPoints,
    this.chips,
    this.yaku,
  });

  /// 和了者・放銃者・立直の記録がある局か（version 4 以降に記録した局）
  bool get hasPlayDetails => winners != null && riichi != null;

  RoundRecord copyWith({
    String? description,
    List<int>? deltas,
    List<int>? scoresAfter,
    bool? edited,
    ({List<int> winners, int? loser, List<int>? winPoints, List<List<String>>? yaku})? who,
  }) =>
      RoundRecord(
        roundLabel: roundLabel,
        kind: kind,
        description: description ?? this.description,
        deltas: deltas ?? this.deltas,
        scoresAfter: scoresAfter ?? this.scoresAfter,
        edited: edited ?? this.edited,
        winners: who != null ? who.winners : winners,
        loser: who != null ? who.loser : loser,
        riichi: riichi,
        winPoints: who != null ? who.winPoints : winPoints,
        chips: chips,
        yaku: who != null ? who.yaku : yaku,
      );

  Map<String, dynamic> toJson() => {
        'roundLabel': roundLabel,
        'kind': kind,
        'description': description,
        'deltas': deltas,
        'scoresAfter': scoresAfter,
        // 修正していない局（ほとんど）は保存しない。古いデータにも無いので、無ければ false
        if (edited) 'edited': true,
        if (winners != null) 'winners': winners,
        if (loser != null) 'loser': loser,
        if (riichi != null) 'riichi': riichi,
        if (winPoints != null) 'winPoints': winPoints,
        if (chips != null) 'chips': chips,
        if (yaku != null) 'yaku': yaku,
      };

  factory RoundRecord.fromJson(Map<String, dynamic> j) => RoundRecord(
        roundLabel: j['roundLabel'] as String,
        kind: j['kind'] as String,
        description: j['description'] as String,
        deltas: _intList(j['deltas']),
        scoresAfter: _intList(j['scoresAfter']),
        edited: j['edited'] as bool? ?? false,
        // version 3 以前のデータには無い
        winners: j['winners'] == null ? null : _intList(j['winners']),
        loser: j['loser'] as int?,
        riichi: j['riichi'] == null ? null : _intList(j['riichi']),
        winPoints: j['winPoints'] == null ? null : _intList(j['winPoints']),
        chips: j['chips'] == null ? null : _intList(j['chips']),
        yaku: j['yaku'] == null
            ? null
            : List.unmodifiable([
                for (final y in j['yaku'] as List) List<String>.unmodifiable((y as List).map((e) => e as String))
              ]),
      );
}

/// 最終結果（1人分）
class FinalResult {
  final int player;
  final int rank; // 1〜4
  final int score;

  /// ウマ・オカ込みのポイント（千点単位。焼き鳥・トビ賞も含む）
  final double point;

  /// [point] のうち焼き鳥・トビ賞の分
  final double adjustment;

  const FinalResult({
    required this.player,
    required this.rank,
    required this.score,
    required this.point,
    this.adjustment = 0,
  });
}

/// 対局の途中のプレイヤーの交代
class Substitution {
  /// 交代した人が最初に打った局（局の記録の番号。まだ打っていなければ局の記録の数）
  final int fromRecord;

  /// 交代した席（起家から順の番号）
  final int seat;

  /// 抜けた人・入った人の名前
  final String from, to;

  const Substitution({required this.fromRecord, required this.seat, required this.from, required this.to});

  Substitution copyWith({int? fromRecord, String? from, String? to}) =>
      Substitution(fromRecord: fromRecord ?? this.fromRecord, seat: seat, from: from ?? this.from, to: to ?? this.to);

  Map<String, dynamic> toJson() => {'fromRecord': fromRecord, 'seat': seat, 'from': from, 'to': to};

  factory Substitution.fromJson(Map<String, dynamic> j) => Substitution(
        fromRecord: j['fromRecord'] as int,
        seat: j['seat'] as int,
        from: j['from'] as String,
        to: j['to'] as String,
      );
}

/// 対局（1半荘・1東風戦）の状態
class GameSession {
  final String id;
  final DateTime createdAt;

  /// 起家から順の4人の名前（0=起家）
  final List<String> playerNames;
  final GameSettings settings;

  /// 現在の点数
  final List<int> scores;

  /// 局の通し番号（0=東1局, 4=南1局 ...）
  final int roundIndex;
  final int honba;

  /// 供託リーチ棒の本数
  final int riichiSticks;

  /// この局で立直を宣言しているか
  final List<bool> riichi;

  /// この局の開始時点の点数（局ごとの増減計算用）
  final List<int> roundStartScores;
  final List<RoundRecord> records;
  final bool finished;

  /// お気に入り（保存件数の上限を超えても自動で削除されない）
  final bool favorite;

  /// 終局時にトップへ渡した供託リーチ棒の本数（局の修正でトップが変わったときに付け替える）
  final int settledSticks;

  /// 途中の交代（古い順）。[playerNames] は今打っている人
  final List<Substitution> substitutions;

  /// 1つ前の状態（「元に戻す」用）
  final GameSession? previous;

  const GameSession({
    required this.id,
    required this.createdAt,
    required this.playerNames,
    required this.settings,
    required this.scores,
    required this.roundIndex,
    required this.honba,
    required this.riichiSticks,
    required this.riichi,
    required this.roundStartScores,
    required this.records,
    required this.finished,
    this.favorite = false,
    this.settledSticks = 0,
    this.substitutions = const [],
    this.previous,
  });

  factory GameSession.start({
    required String id,
    required List<String> playerNames,
    required GameSettings settings,
    DateTime? now,
  }) {
    assert(playerNames.length == settings.playerCount);
    final scores = List<int>.filled(settings.playerCount, settings.startingPoints);
    return GameSession(
      id: id,
      createdAt: now ?? DateTime.now(),
      playerNames: List.unmodifiable(playerNames),
      settings: settings,
      scores: scores,
      roundIndex: 0,
      honba: 0,
      riichiSticks: 0,
      riichi: List.filled(settings.playerCount, false),
      roundStartScores: scores,
      records: const [],
      finished: false,
    );
  }

  /// 保存用の JSON に変換する。
  ///
  /// 「元に戻す」用の [previous] は直近 [undoDepth] 段までを含める。
  /// 容量を抑えるため、[previous] には局ごとに変わる値だけを保存する:
  /// - 局の記録は、今の記録の先頭部分と同じなので「何局目まで」([recordCount]) だけ
  /// - 名前・ルール・作成日時は変わらないので保存しない（読み込み時に引き継ぐ）
  Map<String, dynamic> toJson({int undoDepth = 10}) => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'playerNames': playerNames,
        'settings': settings.toJson(),
        'favorite': favorite,
        'records': [for (final r in records) r.toJson()],
        ..._stateJson(),
        if (previous != null && undoDepth > 0)
          'previous': previous!._snapshotJson(records, undoDepth - 1, newerNames: playerNames),
      };

  /// 局ごとに変わる値
  Map<String, dynamic> _stateJson() => {
        'scores': scores,
        'roundIndex': roundIndex,
        'honba': honba,
        'riichiSticks': riichiSticks,
        'riichi': riichi,
        'roundStartScores': roundStartScores,
        'finished': finished,
        if (settledSticks > 0) 'settledSticks': settledSticks,
        if (substitutions.isNotEmpty) 'substitutions': [for (final x in substitutions) x.toJson()],
      };

  /// 「元に戻す」用のスナップショット。[newerRecords] は1つ新しい状態の記録。
  Map<String, dynamic> _snapshotJson(List<RoundRecord> newerRecords, int undoDepth, {List<String>? newerNames}) {
    final isPrefix = records.length <= newerRecords.length &&
        Iterable<int>.generate(records.length)
            .every((i) => identical(records[i], newerRecords[i]));
    final sameNames = newerNames == null ||
        (newerNames.length == playerNames.length &&
            Iterable<int>.generate(playerNames.length).every((i) => newerNames[i] == playerNames[i]));
    return {
      ..._stateJson(),
      // 名前は交代したときだけ変わるので、1つ新しい状態と違うときだけ保存する
      if (!sameNames) 'playerNames': playerNames,
      // 通常は先頭部分なので件数だけ。そうでない場合（想定外）は記録を丸ごと保存する
      if (isPrefix)
        'recordCount': records.length
      else
        'records': [for (final r in records) r.toJson()],
      if (previous != null && undoDepth > 0)
        'previous': previous!._snapshotJson(records, undoDepth - 1, newerNames: playerNames),
    };
  }

  factory GameSession.fromJson(Map<String, dynamic> j) {
    final records = List<RoundRecord>.unmodifiable((j['records'] as List)
        .map((e) => RoundRecord.fromJson(e as Map<String, dynamic>)));
    return GameSession._fromStateJson(
      j,
      id: j['id'] as String,
      createdAt: DateTime.parse(j['createdAt'] as String),
      playerNames: List<String>.unmodifiable(
          (j['playerNames'] as List).map((e) => e as String)),
      settings: GameSettings.fromJson(j['settings'] as Map<String, dynamic>),
      // お気に入り機能より前に保存したデータには無いので false とする
      favorite: j['favorite'] as bool? ?? false,
      records: records,
    );
  }

  /// [j] の局ごとの値と、親から引き継ぐ値から組み立てる
  factory GameSession._fromStateJson(
    Map<String, dynamic> j, {
    required String id,
    required DateTime createdAt,
    required List<String> playerNames,
    required GameSettings settings,
    required bool favorite,
    required List<RoundRecord> records,
  }) {
    GameSession? previous;
    final p = j['previous'] as Map<String, dynamic>?;
    if (p != null) {
      List<RoundRecord> prevRecords;
      if (p['recordCount'] != null) {
        prevRecords = List<RoundRecord>.unmodifiable(
            records.sublist(0, p['recordCount'] as int));
      } else if (p['records'] != null) {
        prevRecords = List<RoundRecord>.unmodifiable((p['records'] as List)
            .map((e) => RoundRecord.fromJson(e as Map<String, dynamic>)));
      } else {
        throw const FormatException('元に戻す履歴に局の記録がありません');
      }
      previous = GameSession._fromStateJson(
        p,
        // 旧形式（version 1）は名前・ルールも入っているが、内容は同じなので親のものを使う。
        // 名前は、交代する前の状態だけ入っている（version 7 以降）
        id: id,
        createdAt: createdAt,
        playerNames: p['playerNames'] != null
            ? List<String>.unmodifiable((p['playerNames'] as List).map((e) => e as String))
            : playerNames,
        settings: settings,
        favorite: favorite,
        records: prevRecords,
      );
    }
    return GameSession(
      id: id,
      createdAt: createdAt,
      playerNames: playerNames,
      settings: settings,
      scores: _intList(j['scores']),
      roundIndex: j['roundIndex'] as int,
      honba: j['honba'] as int,
      riichiSticks: j['riichiSticks'] as int,
      riichi: _boolList(j['riichi']),
      roundStartScores: _intList(j['roundStartScores']),
      records: records,
      finished: j['finished'] as bool,
      favorite: favorite,
      settledSticks: j['settledSticks'] as int? ?? 0,
      // version 6 以前のデータには無い（交代なし）
      substitutions: List.unmodifiable([
        for (final x in (j['substitutions'] as List?) ?? const []) Substitution.fromJson(x as Map<String, dynamic>)
      ]),
      previous: previous,
    );
  }

  GameSession copyWith({
    List<String>? playerNames,
    GameSettings? settings,
    List<int>? scores,
    int? roundIndex,
    int? honba,
    int? riichiSticks,
    List<bool>? riichi,
    List<int>? roundStartScores,
    List<RoundRecord>? records,
    bool? finished,
    bool? favorite,
    int? settledSticks,
    List<Substitution>? substitutions,
    GameSession? previous,
    bool clearPrevious = false,
  }) {
    return GameSession(
      id: id,
      createdAt: createdAt,
      playerNames: playerNames ?? this.playerNames,
      settings: settings ?? this.settings,
      scores: scores ?? this.scores,
      roundIndex: roundIndex ?? this.roundIndex,
      honba: honba ?? this.honba,
      riichiSticks: riichiSticks ?? this.riichiSticks,
      riichi: riichi ?? this.riichi,
      roundStartScores: roundStartScores ?? this.roundStartScores,
      records: records ?? this.records,
      finished: finished ?? this.finished,
      favorite: favorite ?? this.favorite,
      settledSticks: settledSticks ?? this.settledSticks,
      substitutions: substitutions ?? this.substitutions,
      previous: clearPrevious ? null : (previous ?? this.previous),
    );
  }

  /// [recordIndex] 番目の局で、席 [seat] で打っていた人の名前（交代があればそのときの人）
  String nameAt(int recordIndex, int seat) {
    var name = playerNames[seat];
    for (final x in substitutions.reversed) {
      if (x.seat == seat && recordIndex < x.fromRecord) name = x.from;
    }
    return name;
  }

  /// この対局で打ったすべての人の名前（交代で抜けた人も含む）
  Set<String> get allNames => {...playerNames, for (final x in substitutions) x.from};

  /// 親（東家）のプレイヤー番号
  int get dealer => roundIndex % playerCount;

  /// 人数（4人打ち: 4 / 3人打ち: 3）
  int get playerCount => playerNames.length;

  /// 場風インデックス（0=東, 1=南, 2=西, 3=北）
  int get roundWindIndex => (roundIndex ~/ playerCount) % 4;

  /// 場風の牌（"1z" など）
  String get roundWindTile => '${roundWindIndex + 1}z';

  /// プレイヤーの自風インデックス（0=東 ... 3=北）
  int seatWindIndexOf(int player) => (player - dealer + playerCount) % playerCount;

  /// プレイヤーの自風の牌
  String seatWindTileOf(int player) => '${seatWindIndexOf(player) + 1}z';

  /// 自風インデックス → プレイヤー番号
  int playerOfSeat(int seat) => (dealer + seat) % playerCount;

  static const windNames = ['東', '南', '西', '北'];

  /// "東1局"
  String get roundName =>
      '${windNames[roundWindIndex]}${roundIndex % playerCount + 1}局';

  /// "東1局 0本場"
  String get roundLabel => '$roundName $honba本場';

  /// オーラスかどうか
  bool get isAllLast => roundIndex == settings.totalRounds - 1;

  /// 西入（南入）の延長戦の局かどうか
  bool get isExtraRound => roundIndex >= settings.totalRounds;

  /// 順位（同点は起家に近い方が上位）。返り値は player 番号の順位順リスト。
  List<int> get ranking => rankingOf(scores);

  /// 点数から順位を求める（同点は起家に近い方が上位）
  static List<int> rankingOf(List<int> scores) {
    final order = [for (var i = 0; i < scores.length; i++) i];
    order.sort((a, b) {
      final c = scores[b].compareTo(scores[a]);
      return c != 0 ? c : a.compareTo(b);
    });
    return order;
  }

  /// 祝儀（チップ）の枚数の合計（プレイヤーごと）
  List<int> get chipTotals {
    final t = List<int>.filled(playerCount, 0);
    for (final r in records) {
      final c = r.chips;
      if (c == null) continue;
      for (var i = 0; i < playerCount && i < c.length; i++) {
        t[i] += c[i];
      }
    }
    return t;
  }

  /// 1回も和了していない人（焼き鳥）。和了者の記録が無い古い局（version 3 以前）があれば分からないので空
  List<int> get yakitoriPlayers {
    final won = List<bool>.filled(playerCount, false);
    for (final r in records) {
      if (r.kind != 'win') continue;
      final w = r.winners;
      if (w == null) return const [];
      for (final p in w) {
        if (p >= 0 && p < playerCount) won[p] = true;
      }
    }
    return [for (var p = 0; p < playerCount; p++) if (!won[p]) p];
  }

  /// 焼き鳥・トビ賞のポイントの増減（終局していなければ、またはルールがなしなら全員 0）
  List<double> get localRuleAdjustments {
    final adj = List<double>.filled(playerCount, 0);
    if (!finished) return adj;
    if (settings.yakitori > 0) {
      final birds = yakitoriPlayers;
      final others = [for (var p = 0; p < playerCount; p++) if (!birds.contains(p)) p];
      if (birds.isNotEmpty && others.isNotEmpty) {
        for (final p in birds) {
          adj[p] -= settings.yakitori;
        }
        for (final p in others) {
          adj[p] += settings.yakitori * birds.length / others.length;
        }
      }
    }
    if (settings.tobiBonus > 0 && settings.tobi && records.isNotEmpty) {
      // 最後の局が和了で、誰かが 0点未満になって終わった（トビ）とき、飛ばした人（和了者）がもらう
      final last = records.last;
      final busted = [for (var p = 0; p < playerCount; p++) if (scores[p] < 0) p];
      final winners = last.kind == 'win' ? (last.winners ?? const <int>[]) : const <int>[];
      final takers = winners.where((w) => !busted.contains(w)).toList();
      if (busted.isNotEmpty && takers.isNotEmpty) {
        for (final p in busted) {
          adj[p] -= settings.tobiBonus;
        }
        for (final w in takers) {
          adj[w] += settings.tobiBonus * busted.length / takers.length;
        }
      }
    }
    return adj;
  }

  /// 最終結果（ウマ・オカ、終局していれば焼き鳥・トビ賞も込み）
  List<FinalResult> get finalResults {
    final order = ranking;
    final adj = localRuleAdjustments;
    final results = <FinalResult>[];
    for (var r = 0; r < playerCount; r++) {
      final p = order[r];
      var point = (scores[p] - settings.returnPoints) / 1000 + settings.uma[r];
      if (r == 0) point += settings.oka;
      results.add(FinalResult(player: p, rank: r + 1, score: scores[p], point: point + adj[p], adjustment: adj[p]));
    }
    return results;
  }
}
