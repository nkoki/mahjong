import 'types.dart';
import 'tile_utils.dart';

/// 面子の種類（内部表現）
enum GroupType { sequence, triplet, kan, pair }

/// 面子・雀頭（内部表現）。[tile] は 0〜33 の牌インデックス（順子は先頭牌）。
class Group {
  final GroupType type;
  final int tile;

  /// 鳴いた面子かどうか（暗槓は false）
  final bool open;

  /// 鳴き（副露・暗槓）由来かどうか
  final bool fromMeld;

  const Group(this.type, this.tile, {this.open = false, this.fromMeld = false});

  bool get isSequence => type == GroupType.sequence;
  bool get isTripletLike => type == GroupType.triplet || type == GroupType.kan;

  /// 面子に含まれる牌インデックス
  List<int> get tiles {
    switch (type) {
      case GroupType.sequence:
        return [tile, tile + 1, tile + 2];
      case GroupType.triplet:
        return [tile, tile, tile];
      case GroupType.kan:
        return [tile, tile, tile, tile];
      case GroupType.pair:
        return [tile, tile];
    }
  }

  /// 么九牌を含むか
  bool get containsYaochu => tiles.any(isYaochuIndex);

  /// 全て么九牌か
  bool get allYaochu => tiles.every(isYaochuIndex);

  @override
  String toString() =>
      '${type.name}(${tiles.map(indexToTile).join()}${open ? ",open" : ""})';
}

bool isHonorIndex(int i) => i >= 27;
bool isYaochuIndex(int i) => i >= 27 || i % 9 == 0 || i % 9 == 8;

/// 牌リスト → 34要素のカウント配列
List<int> toCounts(List<Tile> tiles) {
  final counts = List<int>.filled(34, 0);
  for (final t in tiles) {
    counts[tileToIndex(t)]++;
  }
  return counts;
}

/// カウント配列を「雀頭1 + 面子n」に分解する（全パターン）。
/// 各結果は [雀頭, 面子...] の順の Group リスト。
List<List<Group>> decomposeCounts(List<int> counts) {
  final results = <List<Group>>[];
  final total = counts.fold<int>(0, (a, b) => a + b);
  if (total % 3 != 2) return results;
  for (var i = 0; i < 34; i++) {
    if (counts[i] >= 2) {
      counts[i] -= 2;
      for (final melds in _decomposeMelds(counts)) {
        results.add([Group(GroupType.pair, i), ...melds]);
      }
      counts[i] += 2;
    }
  }
  return results;
}

/// 雀頭なしで面子だけに分解（最小インデックスの牌から順に確定させるので重複しない）
List<List<Group>> _decomposeMelds(List<int> counts) {
  var i = 0;
  while (i < 34 && counts[i] == 0) {
    i++;
  }
  if (i == 34) return [<Group>[]];

  final results = <List<Group>>[];
  // 刻子
  if (counts[i] >= 3) {
    counts[i] -= 3;
    for (final rest in _decomposeMelds(counts)) {
      results.add([Group(GroupType.triplet, i), ...rest]);
    }
    counts[i] += 3;
  }
  // 順子
  if (i < 27 && i % 9 <= 6 && counts[i + 1] > 0 && counts[i + 2] > 0) {
    counts[i]--;
    counts[i + 1]--;
    counts[i + 2]--;
    for (final rest in _decomposeMelds(counts)) {
      results.add([Group(GroupType.sequence, i), ...rest]);
    }
    counts[i]++;
    counts[i + 1]++;
    counts[i + 2]++;
  }
  return results;
}

/// 手牌を面子に分解（公開API）。
///
/// [tiles] は 3n+2 枚の牌。雀頭1つと面子n個への分解を全て返す。
/// 赤ドラは通常牌として扱う。分解できない場合は空リスト。
List<Decomposition> decompose(List<Tile> tiles) {
  return decomposeCounts(toCounts(tiles)).map((groups) {
    return Decomposition(
      head: groups.first.tiles.map(indexToTile).toList(),
      melds: groups.skip(1).map((g) => g.tiles.map(indexToTile).toList()).toList(),
    );
  }).toList();
}

/// 七対子判定（14枚: 異なる7種の対子）
bool isChiitoitsu(List<Tile> tiles) {
  if (tiles.length != 14) return false;
  final counts = countTiles(tiles);
  return counts.length == 7 && counts.values.every((c) => c == 2);
}

/// 国士無双判定（14枚: 么九牌13種＋いずれか1枚）
bool isKokushi(List<Tile> tiles) {
  if (tiles.length != 14) return false;
  const yaochuTiles = [
    '1m', '9m', '1p', '9p', '1s', '9s',
    '1z', '2z', '3z', '4z', '5z', '6z', '7z',
  ];
  final counts = countTiles(tiles);
  if (counts.length != 13) return false;
  return yaochuTiles.every(counts.containsKey);
}
