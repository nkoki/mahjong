import 'types.dart';

const _suits = ['m', 'p', 's', 'z'];

/// 赤ドラ表記を外した通常の牌（"5mr" → "5m"）
Tile normalizeTile(Tile tile) =>
    tile.endsWith('r') ? tile.substring(0, tile.length - 1) : tile;

/// 赤ドラかどうか
bool isRedDora(Tile tile) => tile.endsWith('r');

/// 牌の種類（m/p/s/z）
String tileSuit(Tile tile) {
  final t = normalizeTile(tile);
  return t.substring(t.length - 1);
}

/// 牌の数字（字牌は 1〜7）
int tileNumber(Tile tile) {
  final t = normalizeTile(tile);
  return int.parse(t.substring(0, t.length - 1));
}

/// 牌として正しい表記かどうか
bool isValidTile(Tile tile) {
  final m = RegExp(r'^([1-9])([mpsz])(r?)$').firstMatch(tile);
  if (m == null) return false;
  final n = int.parse(m.group(1)!);
  final suit = m.group(2)!;
  final red = m.group(3)!.isNotEmpty;
  if (suit == 'z' && n > 7) return false;
  if (red && (suit == 'z' || n != 5)) return false;
  return true;
}

/// 牌 → 0〜33 のインデックス（萬子0-8, 筒子9-17, 索子18-26, 字牌27-33）
int tileToIndex(Tile tile) =>
    _suits.indexOf(tileSuit(tile)) * 9 + tileNumber(tile) - 1;

/// 0〜33 のインデックス → 牌
Tile indexToTile(int index) => '${index % 9 + 1}${_suits[index ~/ 9]}';

/// 牌が数牌かどうか
bool isNumberTile(Tile tile) => tileSuit(tile) != 'z';

/// 牌が字牌かどうか
bool isHonorTile(Tile tile) => tileSuit(tile) == 'z';

/// 牌が么九牌かどうか（1, 9, 字牌）
bool isYaochuTile(Tile tile) {
  if (isHonorTile(tile)) return true;
  final n = tileNumber(tile);
  return n == 1 || n == 9;
}

/// 牌が老頭牌かどうか（1, 9）
bool isLaoTouTile(Tile tile) {
  if (isHonorTile(tile)) return false;
  final n = tileNumber(tile);
  return n == 1 || n == 9;
}

/// 牌が中張牌かどうか（2-8）
bool isChunZhangTile(Tile tile) {
  if (isHonorTile(tile)) return false;
  final n = tileNumber(tile);
  return n >= 2 && n <= 8;
}

/// 牌が役牌かどうか（場風・自風・三元牌）
bool isYakuHai(Tile tile, Tile roundWind, Tile playerWind) {
  final t = normalizeTile(tile);
  if (t == roundWind || t == playerWind) return true;
  if (!isHonorTile(t)) return false;
  final n = tileNumber(t);
  return n >= 5 && n <= 7;
}

/// 牌の数をカウント（赤ドラは通常牌として数える）
Map<Tile, int> countTiles(List<Tile> tiles) {
  final counts = <Tile, int>{};
  for (final tile in tiles) {
    final t = normalizeTile(tile);
    counts[t] = (counts[t] ?? 0) + 1;
  }
  return counts;
}

/// 牌を除去（1枚ずつ）
List<Tile> removeTiles(List<Tile> tiles, List<Tile> toRemove) {
  final result = List<Tile>.from(tiles);
  for (final tile in toRemove) {
    final index = result.indexOf(tile);
    if (index != -1) {
      result.removeAt(index);
    }
  }
  return result;
}

/// 牌をソート（萬子→筒子→索子→字牌、赤5は通常5の直後）
List<Tile> sortTiles(List<Tile> tiles) {
  final sorted = List<Tile>.from(tiles);
  sorted.sort((a, b) {
    final c = tileToIndex(a).compareTo(tileToIndex(b));
    if (c != 0) return c;
    return (isRedDora(a) ? 1 : 0).compareTo(isRedDora(b) ? 1 : 0);
  });
  return sorted;
}

/// 赤牌を分離した結果
class SeparatedTiles {
  final List<Tile> normalTiles;
  final int redDoraCount;

  const SeparatedTiles({
    required this.normalTiles,
    required this.redDoraCount,
  });
}

/// 赤牌を分離
SeparatedTiles separateRedDora(List<Tile> tiles) {
  final normalTiles = <Tile>[];
  var redDoraCount = 0;
  for (final tile in tiles) {
    if (isRedDora(tile)) redDoraCount++;
    normalTiles.add(normalizeTile(tile));
  }
  return SeparatedTiles(normalTiles: normalTiles, redDoraCount: redDoraCount);
}

/// ドラ表示牌から実際のドラを取得
/// 数牌: 9の次は1 / 風牌: 東→南→西→北→東 / 三元牌: 白→發→中→白
///
/// [sanma] が true（3人打ち）のときは、萬子の 2〜8 がないので 1萬 → 9萬 → 1萬 となる
Tile getNextDora(Tile indicator, {bool sanma = false}) {
  final t = normalizeTile(indicator);
  final n = tileNumber(t);
  final suit = tileSuit(t);
  if (sanma && suit == 'm') return n == 1 ? '9m' : '1m';
  if (suit == 'z') {
    if (n <= 4) return '${n % 4 + 1}z';
    return '${(n - 5 + 1) % 3 + 5}z';
  }
  return '${n % 9 + 1}$suit';
}

/// ドラ数を計算（tiles は和了形の全牌）
int countDora(List<Tile> tiles, List<Tile> doraIndicators, {bool sanma = false}) {
  var count = 0;
  final tileCounts = countTiles(tiles);
  for (final indicator in doraIndicators) {
    count += tileCounts[getNextDora(indicator, sanma: sanma)] ?? 0;
  }
  return count;
}

/// 牌の日本語名
String tileName(Tile tile) {
  const honors = ['東', '南', '西', '北', '白', '發', '中'];
  const nums = ['一', '二', '三', '四', '五', '六', '七', '八', '九'];
  final n = tileNumber(tile);
  final red = isRedDora(tile) ? '(赤)' : '';
  switch (tileSuit(tile)) {
    case 'm':
      return '${nums[n - 1]}萬$red';
    case 'p':
      return '$n筒$red';
    case 's':
      return '$n索$red';
    default:
      return honors[n - 1];
  }
}
