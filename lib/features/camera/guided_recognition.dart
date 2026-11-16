import 'dart:math' as math;

import 'package:mahjong_score_engine/mahjong_score_engine.dart';

import '../../core/l10n.dart';
import 'tile_detection.dart';

/// 写真の中の範囲（写真の幅・高さを 1 とした割合）
class PhotoRegion {
  final double left, top, width, height;

  const PhotoRegion(this.left, this.top, this.width, this.height);

  double get right => left + width;
  double get bottom => top + height;

  /// 写真全体
  static const full = PhotoRegion(0, 0, 1, 1);

  /// 左右を反転した写真の中での、同じ場所
  PhotoRegion get mirrored => PhotoRegion(1 - right, top, width, height);

  @override
  String toString() => 'PhotoRegion($left, $top, $width, $height)';
}

/// 枠つきの撮影画面の4つのエリア（カメラの映像の幅・高さを 1 とした割合。縦向きで持つ）。
///
/// 上から、ドラ表示牌（上の段）と裏ドラ表示牌（下の段）、鳴いた牌、手牌（左）と和了牌（右）
class GuideFrames {
  // 映像の全体を、少しのすき間を空けて3段に分ける（置く場所に余裕を持たせる）
  // ドラ表示牌のエリアは、上の段にドラ表示牌、下の段に裏ドラ表示牌を置けるように高めにする
  static const dora = PhotoRegion(0.02, 0.02, 0.96, 0.30);
  static const melds = PhotoRegion(0.02, 0.34, 0.96, 0.28);
  static const hand = PhotoRegion(0.02, 0.64, 0.78, 0.34);
  static const win = PhotoRegion(0.82, 0.64, 0.16, 0.34);

  /// 読み取りに渡す順（[interpretGuided] に渡す順と同じ）
  static const all = [hand, win, melds, dora];

  /// ドラ表示牌の枚数の上限（槓ドラを含めて5枚）
  static const maxDora = 5;
}

/// カメラの映像（縦横比 [viewAspect] = 幅 ÷ 高さ）の中の範囲を、写真（[photoWidth] × [photoHeight]）の中の範囲に直す。
///
/// 映像と写真で縦横比が違う端末がある（映像は 16:9、写真は 4:3 など）。そのときは、
/// 狭いほうが広いほうの真ん中を切り取ったものとして位置を合わせ、写真からはみ出す分は切り捨てる
PhotoRegion mapViewRegionToPhoto(PhotoRegion r, double viewAspect, int photoWidth, int photoHeight) {
  final photoAspect = photoWidth / photoHeight;
  var sx = 1.0, sy = 1.0; // 映像の幅・高さが、写真の幅・高さの何倍か
  if ((photoAspect - viewAspect).abs() / viewAspect > 0.02) {
    if (photoAspect > viewAspect) {
      sx = viewAspect / photoAspect; // 写真のほうが横に広い: 映像は写真の左右を切り取ったもの
    } else {
      sy = photoAspect / viewAspect; // 写真のほうが縦に長い: 映像は写真の上下を切り取ったもの
    }
  }
  final left = ((1 - sx) / 2 + r.left * sx).clamp(0.0, 1.0);
  final top = ((1 - sy) / 2 + r.top * sy).clamp(0.0, 1.0);
  final right = ((1 - sx) / 2 + r.right * sx).clamp(0.0, 1.0);
  final bottom = ((1 - sy) / 2 + r.bottom * sy).clamp(0.0, 1.0);
  return PhotoRegion(left, top, right - left, bottom - top);
}

/// 範囲を切り抜くピクセルの位置（少なくとも 1 ピクセル）
({int x, int y, int width, int height}) regionPixels(PhotoRegion r, int photoWidth, int photoHeight) {
  final x = (r.left * photoWidth).floor().clamp(0, photoWidth - 1);
  final y = (r.top * photoHeight).floor().clamp(0, photoHeight - 1);
  final w = (r.width * photoWidth).ceil().clamp(1, photoWidth - x);
  final h = (r.height * photoHeight).ceil().clamp(1, photoHeight - y);
  return (x: x, y: y, width: w, height: h);
}

/// 1つの範囲から読み取った牌。位置は、切り抜いた範囲の幅・高さを 1 とした割合
class RegionTiles {
  /// 切り抜いた範囲の大きさ（ピクセル）
  final int width, height;
  final List<TileDetection> detections;

  const RegionTiles(this.width, this.height, this.detections);

  static const empty = RegionTiles(1, 1, []);
}

/// 枠つきの撮影で読み取った内容
class GuidedReading {
  /// 手牌（並べ替え済み）
  final List<Tile> hand;
  final Tile? winningTile;

  /// 鳴き（槓は明槓として入れる。暗槓かどうかは写真からは分からない）
  final List<Meld> melds;

  /// ドラ表示牌（左から順）
  final List<Tile> dora;

  /// 裏ドラ表示牌（左から順。ドラ表示牌のエリアの下の段）
  final List<Tile> ura;

  /// 利用者に知らせること
  final List<String> notes;

  const GuidedReading(
      {required this.hand,
      required this.winningTile,
      required this.melds,
      this.dora = const [],
      this.ura = const [],
      required this.notes});

  int get needHand => 13 - 3 * melds.length;
}

/// 鳴いた牌のエリアの牌を、鳴き1組ずつに分ける（組にできなかった牌は [leftover] に数える）。
///
/// 牌同士を離さずに並べてよい。段（横の列）ごとに左から並べ、同じ牌4枚 → 槓、同じ牌3枚 → ポン、
/// 同じ色の続きの3枚 → チー、の組み合わせのうち、組にできない牌がいちばん少なくなる分け方を選ぶ
/// （例: 3索 3索 3索 3索 4索 5索 は、槓＋余り2枚ではなく、ポン＋チーにする）。
/// 組にできない牌が残り、牌の間に広いすき間があるときは、すき間で区切った分け方も試して、余りの少ないほうを使う
({List<Meld> melds, int leftover}) groupMelds(RegionTiles region) {
  if (region.detections.isEmpty) return (melds: const <Meld>[], leftover: 0);
  final w = region.width.toDouble();
  final unit = _tileUnit(region);

  final melds = <Meld>[];
  var leftover = 0;
  for (final row in tileRows(region)) {
    final tiles = [for (final d in row) d.tile];
    var best = _partition(tiles);
    if (best.leftover > 0) {
      // 広いすき間で区切って、区切りごとに分ける
      final groups = <List<Tile>>[
        [tiles.first]
      ];
      for (var i = 1; i < row.length; i++) {
        if ((row[i].left - row[i - 1].right) * w > unit * 0.5) groups.add([]);
        groups.last.add(tiles[i]);
      }
      if (groups.length > 1) {
        final parts = groups.map(_partition).toList();
        final split = (
          melds: [for (final p in parts) ...p.melds],
          leftover: parts.fold<int>(0, (a, p) => a + p.leftover),
        );
        if (split.leftover < best.leftover) best = split;
      }
    }
    melds.addAll(best.melds);
    leftover += best.leftover;
  }
  return (melds: melds, leftover: leftover);
}

/// 牌1枚の大きさのめやす（短いほうの辺の中央値。ピクセル）
double _tileUnit(RegionTiles region) {
  final w = region.width.toDouble(), h = region.height.toDouble();
  final sizes = region.detections.map((d) => math.min(d.width * w, d.height * h)).toList()..sort();
  return sizes[sizes.length ~/ 2];
}

/// エリアの中の牌を、段（横の列）に分ける。段は上から順、段の中は左から順
List<List<TileDetection>> tileRows(RegionTiles region) {
  final ds = region.detections;
  if (ds.isEmpty) return const [];
  final h = region.height.toDouble();
  final unit = _tileUnit(region);
  final byY = [...ds]..sort((a, b) => a.centerY.compareTo(b.centerY));
  final rows = <List<TileDetection>>[
    [byY.first]
  ];
  for (final d in byY.skip(1)) {
    final row = rows.last;
    final rowY = row.map((e) => e.centerY * h).reduce((a, b) => a + b) / row.length;
    if ((d.centerY * h - rowY).abs() < unit * 0.8) {
      row.add(d);
    } else {
      rows.add([d]);
    }
  }
  for (final row in rows) {
    row.sort((a, b) => a.centerX.compareTo(b.centerX));
  }
  return rows;
}

/// 左から並んだ牌を鳴きに分ける。組にできない牌がいちばん少ない分け方（同じなら、先に槓・ポンを取る分け方）
({List<Meld> melds, int leftover}) _partition(List<Tile> tiles) {
  final n = tiles.length;
  // best[i] = i 枚目から後ろを分けたときの (余りの枚数, そこで取る組。null なら1枚余らせる)
  final left = List<int>.filled(n + 1, 0);
  final take = List<Meld?>.filled(n + 1, null);
  for (var i = n - 1; i >= 0; i--) {
    left[i] = left[i + 1] + 1;
    take[i] = null;
    // 候補を後ろから比べ、余りが同じなら先に書いたもの（槓 → ポン → チー）を残す
    for (final m in _meldsAt(tiles, i).reversed) {
      final rest = left[i + m.tiles.length];
      if (rest <= left[i]) {
        left[i] = rest;
        take[i] = m;
      }
    }
  }
  final melds = <Meld>[];
  for (var i = 0; i < n;) {
    final m = take[i];
    if (m == null) {
      i++;
    } else {
      melds.add(m);
      i += m.tiles.length;
    }
  }
  return (melds: melds, leftover: left[0]);
}

/// [tiles] の [i] 枚目から始められる鳴き（槓・ポン・チーの順）
List<Meld> _meldsAt(List<Tile> tiles, int i) {
  bool same(int n) =>
      i + n <= tiles.length &&
      tiles.sublist(i, i + n).every((t) => normalizeTile(t) == normalizeTile(tiles[i]));
  final result = <Meld>[];
  if (same(4)) result.add(Meld(type: MeldType.minkan, tiles: tiles.sublist(i, i + 4)));
  if (same(3)) result.add(Meld(type: MeldType.pon, tiles: tiles.sublist(i, i + 3)));
  if (i + 3 <= tiles.length) {
    final three = tiles.sublist(i, i + 3);
    final suit = tileSuit(three.first);
    if (suit != 'z' && three.every((t) => tileSuit(t) == suit)) {
      final sorted = [...three]..sort((a, b) => tileNumber(a).compareTo(tileNumber(b)));
      if (tileNumber(sorted[1]) == tileNumber(sorted[0]) + 1 && tileNumber(sorted[2]) == tileNumber(sorted[0]) + 2) {
        result.add(Meld(type: MeldType.chi, tiles: sorted));
      }
    }
  }
  return result;
}

/// 枠つきの撮影で読み取った牌を、今のルールに合わせて手牌・和了牌・鳴きに分ける。
///
/// - 鳴きは4組まで。3人打ちではチーを使わない
/// - 3人打ちでは二萬〜八萬を除く。赤ドラなしなら赤5は普通の5にする
/// - 同じ牌が5枚以上（鳴きの牌も数える）なら、5枚目からは除く
/// - 手牌は 13 - 3×鳴きの数 枚。和了牌の枠が空で、手牌の枠に1枚多くあれば、右端を和了牌にする
GuidedReading interpretGuided({
  required RegionTiles hand,
  required RegionTiles win,
  required RegionTiles melds,
  RegionTiles dora = RegionTiles.empty,
  bool sanma = false,
  bool redDora = true,
}) {
  final notes = <String>[];
  final counts = <String, int>{};
  var removedSanma = 0, removedOver = 0, normalizedRed = 0;

  /// ルールで使えない牌を除く・直す。使えなければ null
  Tile? usable(Tile t, {bool count = true}) {
    if (sanma && tileSuit(t) == 'm' && tileNumber(t) >= 2 && tileNumber(t) <= 8) {
      removedSanma++;
      return null;
    }
    if (isRedDora(t) && (!redDora || (sanma && tileSuit(t) == 'm'))) {
      t = normalizeTile(t);
      normalizedRed++;
    }
    if (count) {
      final key = normalizeTile(t);
      if ((counts[key] ?? 0) >= 4) {
        removedOver++;
        return null;
      }
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return t;
  }

  // 鳴き
  final grouped = groupMelds(melds);
  final resultMelds = <Meld>[];
  var droppedChi = 0, droppedMelds = 0;
  for (final m in grouped.melds) {
    if (sanma && m.type == MeldType.chi) {
      droppedChi++;
      continue;
    }
    if (resultMelds.length >= 4) {
      droppedMelds++;
      continue;
    }
    final tiles = [for (final t in m.tiles) usable(t)];
    if (tiles.contains(null)) {
      droppedMelds++;
      continue;
    }
    resultMelds.add(Meld(type: m.type, tiles: tiles.cast<Tile>()));
  }
  if (grouped.leftover > 0) {
    notes.add(tr('鳴いた牌のエリアに、ポン・チー・槓の組にできない牌が${grouped.leftover}枚ありました。鳴きは手で直してください',
        '${grouped.leftover} tiles in the calls area could not be grouped into pon/chi/kan. Fix the calls manually'));
  }
  if (droppedChi > 0) notes.add(tr('3人打ちではチーができないので、チー$droppedChi組は入れませんでした', 'Chi is not allowed in 3-player, so $droppedChi chi were not entered'));
  if (droppedMelds > 0) notes.add(tr('入れられない鳴きが$droppedMelds組ありました', '$droppedMelds calls could not be entered'));
  if (resultMelds.any((m) => m.type == MeldType.minkan)) {
    notes.add(tr('槓は明槓として入れます。暗槓のときは、下の「暗槓にする」を押してください',
        'Kans are entered as open kans. For a closed kan, press "Closed kan" below'));
  }

  // 手牌と和了牌
  final needHand = 13 - 3 * resultMelds.length;
  final handTiles = <Tile>[
    for (final t in arrangeTiles(hand.detections).tiles)
      if (usable(t) case final u?) u
  ];
  Tile? winningTile;
  if (win.detections.isNotEmpty) {
    // 和了牌の枠にいくつか見つかったら、いちばん確信度の高いもの
    final best = win.detections.reduce((a, b) => a.score >= b.score ? a : b);
    winningTile = usable(best.tile);
  }
  if (winningTile == null && handTiles.length == needHand + 1) {
    winningTile = handTiles.removeLast();
    notes.add(tr('和了牌のエリアが空だったので、手牌の右端の牌を和了牌にしました', 'The winning tile area was empty, so the rightmost hand tile is used as the winning tile'));
  }
  // ドラ表示牌（上の段）と裏ドラ表示牌（下の段）。どちらも左から順に5枚まで
  final doraRows = tileRows(dora);
  List<Tile> indicators(int row, String ja, String en) {
    if (doraRows.length <= row) return [];
    final tiles = <Tile>[
      for (final d in doraRows[row])
        if (usable(d.tile) case final u?) u
    ];
    if (tiles.length > GuideFrames.maxDora) {
      notes.add(tr('$jaが多すぎたので、右の${tiles.length - GuideFrames.maxDora}枚は使いませんでした',
          'Too many $en; the rightmost ${tiles.length - GuideFrames.maxDora} were not used'));
      tiles.removeRange(GuideFrames.maxDora, tiles.length);
    }
    return tiles;
  }

  final doraTiles = indicators(0, 'ドラ表示牌', 'dora indicators');
  final uraTiles = indicators(1, '裏ドラ表示牌', 'ura dora indicators');
  if (doraRows.length > 2) {
    notes.add(tr('ドラ表示牌のエリアに3段以上の牌がありました。上の2段（ドラ表示牌・裏ドラ表示牌）だけを使いました',
        'The dora area had 3 or more rows; only the top two (dora and ura dora indicators) were used'));
  }
  if (removedSanma > 0) notes.add(tr('3人打ちでは使わない二萬〜八萬を$removedSanma枚除きました', 'Removed $removedSanma tiles of 2m-8m (not used in 3-player)'));
  if (normalizedRed > 0) notes.add(tr('赤5を$normalizedRed枚、普通の5として入れました', 'Entered $normalizedRed red fives as normal fives'));
  if (removedOver > 0) notes.add(tr('同じ牌が5枚以上あったので、$removedOver枚除きました', 'Removed $removedOver tiles (5+ copies of the same tile)'));

  if (handTiles.length > needHand) {
    notes.add(tr('手牌のエリアの牌が多すぎたので、右の${handTiles.length - needHand}枚は使いませんでした',
        'Too many tiles in the hand area; the rightmost ${handTiles.length - needHand} were not used'));
    handTiles.removeRange(needHand, handTiles.length);
  } else if (handTiles.length < needHand) {
    notes.add(tr('手牌が${needHand - handTiles.length}枚足りません。残りは手で入力してください',
        'Hand is ${needHand - handTiles.length} tiles short. Enter the rest manually'));
  }
  if (winningTile == null) notes.add(tr('和了牌は手で選んでください', 'Select the winning tile manually'));

  return GuidedReading(
      hand: sortTiles(handTiles),
      winningTile: winningTile,
      melds: resultMelds,
      dora: doraTiles,
      ura: uraTiles,
      notes: notes);
}
