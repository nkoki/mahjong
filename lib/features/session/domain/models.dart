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

  const GameSettings({
    this.startingPoints = 25000,
    this.returnPoints = 30000,
    this.uma = const [20, 10, -10, -20],
    this.tonpuu = false,
    this.tobi = true,
  });

  /// 総局数（東風4 / 半荘8）
  int get totalRounds => tonpuu ? 4 : 8;

  /// オカ（トップ取り、千点単位）
  double get oka => (returnPoints - startingPoints) * 4 / 1000;

  Map<String, dynamic> toJson() => {
        'startingPoints': startingPoints,
        'returnPoints': returnPoints,
        'uma': uma,
        'tonpuu': tonpuu,
        'tobi': tobi,
      };

  factory GameSettings.fromJson(Map<String, dynamic> j) => GameSettings(
        startingPoints: j['startingPoints'] as int,
        returnPoints: j['returnPoints'] as int,
        uma: _intList(j['uma']),
        tonpuu: j['tonpuu'] as bool,
        tobi: j['tobi'] as bool,
      );
}

List<int> _intList(Object? v) =>
    List<int>.unmodifiable((v as List).map((e) => e as int));

List<bool> _boolList(Object? v) =>
    List<bool>.unmodifiable((v as List).map((e) => e as bool));

/// 流局の種類
enum DrawType {
  exhaustive('荒牌平局（通常流局）'),
  nagashiMangan('流し満貫'),
  kyuushu('九種九牌'),
  suufon('四風連打'),
  suucha('四家立直'),
  suukan('四開槓'),
  sanchaho('三家和');

  final String label;
  const DrawType(this.label);

  /// 途中流局（親が連荘・テンパイ料なし）
  bool get isAbortive =>
      this != DrawType.exhaustive && this != DrawType.nagashiMangan;
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

  const RoundRecord({
    required this.roundLabel,
    required this.kind,
    required this.description,
    required this.deltas,
    required this.scoresAfter,
  });

  Map<String, dynamic> toJson() => {
        'roundLabel': roundLabel,
        'kind': kind,
        'description': description,
        'deltas': deltas,
        'scoresAfter': scoresAfter,
      };

  factory RoundRecord.fromJson(Map<String, dynamic> j) => RoundRecord(
        roundLabel: j['roundLabel'] as String,
        kind: j['kind'] as String,
        description: j['description'] as String,
        deltas: _intList(j['deltas']),
        scoresAfter: _intList(j['scoresAfter']),
      );
}

/// 最終結果（1人分）
class FinalResult {
  final int player;
  final int rank; // 1〜4
  final int score;

  /// ウマ・オカ込みのポイント（千点単位）
  final double point;

  const FinalResult({
    required this.player,
    required this.rank,
    required this.score,
    required this.point,
  });
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
    this.previous,
  });

  factory GameSession.start({
    required String id,
    required List<String> playerNames,
    required GameSettings settings,
    DateTime? now,
  }) {
    final scores = List<int>.filled(4, settings.startingPoints);
    return GameSession(
      id: id,
      createdAt: now ?? DateTime.now(),
      playerNames: List.unmodifiable(playerNames),
      settings: settings,
      scores: scores,
      roundIndex: 0,
      honba: 0,
      riichiSticks: 0,
      riichi: const [false, false, false, false],
      roundStartScores: scores,
      records: const [],
      finished: false,
    );
  }

  /// 保存用の JSON に変換する。
  ///
  /// 「元に戻す」用の [previous] は直近 [undoDepth] 段までを含める
  /// （古い履歴まで全部保存するとデータが大きくなるため）。
  Map<String, dynamic> toJson({int undoDepth = 10}) => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'playerNames': playerNames,
        'settings': settings.toJson(),
        'scores': scores,
        'roundIndex': roundIndex,
        'honba': honba,
        'riichiSticks': riichiSticks,
        'riichi': riichi,
        'roundStartScores': roundStartScores,
        'records': [for (final r in records) r.toJson()],
        'finished': finished,
        if (previous != null && undoDepth > 0)
          'previous': previous!.toJson(undoDepth: undoDepth - 1),
      };

  factory GameSession.fromJson(Map<String, dynamic> j) => GameSession(
        id: j['id'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        playerNames: List<String>.unmodifiable(
            (j['playerNames'] as List).map((e) => e as String)),
        settings: GameSettings.fromJson(j['settings'] as Map<String, dynamic>),
        scores: _intList(j['scores']),
        roundIndex: j['roundIndex'] as int,
        honba: j['honba'] as int,
        riichiSticks: j['riichiSticks'] as int,
        riichi: _boolList(j['riichi']),
        roundStartScores: _intList(j['roundStartScores']),
        records: List<RoundRecord>.unmodifiable((j['records'] as List)
            .map((e) => RoundRecord.fromJson(e as Map<String, dynamic>))),
        finished: j['finished'] as bool,
        previous: j['previous'] == null
            ? null
            : GameSession.fromJson(j['previous'] as Map<String, dynamic>),
      );

  GameSession copyWith({
    List<int>? scores,
    int? roundIndex,
    int? honba,
    int? riichiSticks,
    List<bool>? riichi,
    List<int>? roundStartScores,
    List<RoundRecord>? records,
    bool? finished,
    GameSession? previous,
    bool clearPrevious = false,
  }) {
    return GameSession(
      id: id,
      createdAt: createdAt,
      playerNames: playerNames,
      settings: settings,
      scores: scores ?? this.scores,
      roundIndex: roundIndex ?? this.roundIndex,
      honba: honba ?? this.honba,
      riichiSticks: riichiSticks ?? this.riichiSticks,
      riichi: riichi ?? this.riichi,
      roundStartScores: roundStartScores ?? this.roundStartScores,
      records: records ?? this.records,
      finished: finished ?? this.finished,
      previous: clearPrevious ? null : (previous ?? this.previous),
    );
  }

  /// 親（東家）のプレイヤー番号
  int get dealer => roundIndex % 4;

  /// 場風インデックス（0=東, 1=南, 2=西, 3=北）
  int get roundWindIndex => (roundIndex ~/ 4) % 4;

  /// 場風の牌（"1z" など）
  String get roundWindTile => '${roundWindIndex + 1}z';

  /// プレイヤーの自風インデックス（0=東 ... 3=北）
  int seatWindIndexOf(int player) => (player - dealer + 4) % 4;

  /// プレイヤーの自風の牌
  String seatWindTileOf(int player) => '${seatWindIndexOf(player) + 1}z';

  /// 自風インデックス → プレイヤー番号
  int playerOfSeat(int seat) => (dealer + seat) % 4;

  static const windNames = ['東', '南', '西', '北'];

  /// "東1局"
  String get roundName =>
      '${windNames[roundWindIndex]}${roundIndex % 4 + 1}局';

  /// "東1局 0本場"
  String get roundLabel => '$roundName $honba本場';

  /// オーラスかどうか
  bool get isAllLast => roundIndex == settings.totalRounds - 1;

  /// 順位（同点は起家に近い方が上位）。返り値は player 番号の順位順リスト。
  List<int> get ranking {
    final order = [0, 1, 2, 3];
    order.sort((a, b) {
      final c = scores[b].compareTo(scores[a]);
      return c != 0 ? c : a.compareTo(b);
    });
    return order;
  }

  /// 最終結果（ウマ・オカ込み）
  List<FinalResult> get finalResults {
    final order = ranking;
    final results = <FinalResult>[];
    for (var r = 0; r < 4; r++) {
      final p = order[r];
      var point = (scores[p] - settings.returnPoints) / 1000 + settings.uma[r];
      if (r == 0) point += settings.oka;
      results.add(FinalResult(player: p, rank: r + 1, score: scores[p], point: point));
    }
    return results;
  }
}
