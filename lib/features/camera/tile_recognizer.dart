import 'dart:typed_data';

import 'package:mahjong_score_engine/mahjong_score_engine.dart';

import '../../core/l10n.dart';

/// 読み取りに失敗したときのエラー（[message] は利用者向けの説明）
class RecognitionException implements Exception {
  final String message;
  const RecognitionException(this.message);

  @override
  String toString() => message;
}

/// 画像から手牌を認識するインターフェース
abstract class TileRecognizer {
  /// 画像（JPEG/PNG）から牌を左から順に認識する。失敗したら [RecognitionException]
  Future<List<Tile>> recognize(Uint8List imageBytes);
}

/// 読み取った牌を手牌に入れるときの結果
class RecognizedHand {
  /// 手牌（並べ替え済み）
  final List<Tile> hand;

  /// 和了牌（読み取った牌が手牌より1枚多いときの最後の牌）
  final Tile? winningTile;

  /// 利用者に知らせること（使えない牌を除いた、など）
  final List<String> notes;

  const RecognizedHand({required this.hand, required this.winningTile, required this.notes});
}

/// 読み取った牌を、今のルール・鳴きの数に合わせて手牌と和了牌に分ける。
///
/// - [needHand] 手牌の枚数（13 - 3×鳴きの数）
/// - 3人打ちでは二萬〜八萬を除く。赤ドラなしなら赤5は普通の5にする
/// - 同じ牌が5枚以上なら、5枚目からは除く
/// - 手牌より1枚多ければ最後の1枚を和了牌に、それより多い分は使わない
RecognizedHand applyRecognition(
  List<Tile> tiles, {
  required int needHand,
  bool sanma = false,
  bool redDora = true,
}) {
  final notes = <String>[];
  final usable = <Tile>[];
  final counts = <String, int>{};
  var removedSanma = 0, removedOver = 0, normalizedRed = 0;
  for (var t in tiles) {
    if (sanma && tileSuit(t) == 'm' && tileNumber(t) >= 2 && tileNumber(t) <= 8) {
      removedSanma++;
      continue;
    }
    if (isRedDora(t) && (!redDora || (sanma && tileSuit(t) == 'm'))) {
      t = normalizeTile(t);
      normalizedRed++;
    }
    final key = normalizeTile(t);
    if ((counts[key] ?? 0) >= 4) {
      removedOver++;
      continue;
    }
    counts[key] = (counts[key] ?? 0) + 1;
    usable.add(t);
  }
  if (removedSanma > 0) notes.add(tr('3人打ちでは使わない二萬〜八萬を$removedSanma枚除きました', 'Removed $removedSanma tiles of 2m-8m (not used in 3-player)'));
  if (normalizedRed > 0) notes.add(tr('赤5を$normalizedRed枚、普通の5として入れました', 'Entered $normalizedRed red fives as normal fives'));
  if (removedOver > 0) notes.add(tr('同じ牌が5枚以上あったので、$removedOver枚除きました', 'Removed $removedOver tiles (5+ copies of the same tile)'));

  final hand = usable.take(needHand).toList();
  final winningTile = usable.length > needHand ? usable[needHand] : null;
  if (usable.length > needHand + 1) {
    notes.add(tr('読み取った牌が多すぎたので、後ろの${usable.length - needHand - 1}枚は使いませんでした',
        'Too many tiles read; the last ${usable.length - needHand - 1} were not used'));
  }
  if (hand.length < needHand) {
    notes.add(tr('手牌が${needHand - hand.length}枚足りません。残りは手で入力してください',
        'Hand is ${needHand - hand.length} tiles short. Enter the rest manually'));
  } else if (winningTile == null) {
    notes.add(tr('和了牌は手で選んでください', 'Select the winning tile manually'));
  }
  return RecognizedHand(hand: sortTiles(hand), winningTile: winningTile, notes: notes);
}
