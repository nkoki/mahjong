import 'dart:math' as math;

import 'package:mahjong_score_engine/mahjong_score_engine.dart';

/// 認識モデルが見つけた牌1枚（座標は画像の幅・高さを 1 とした割合）
class TileDetection {
  final Tile tile;
  final double score;
  final double left, top, right, bottom;

  const TileDetection(this.tile, this.score, this.left, this.top, this.right, this.bottom);

  double get width => right - left;
  double get height => bottom - top;
  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;
  double get area => math.max(0, width) * math.max(0, height);

  /// 重なりの割合（IoU: 重なった面積 ÷ 合わせた面積）
  double iou(TileDetection o) {
    final w = math.min(right, o.right) - math.max(left, o.left);
    final h = math.min(bottom, o.bottom) - math.max(top, o.top);
    if (w <= 0 || h <= 0) return 0;
    final inter = w * h;
    return inter / (area + o.area - inter);
  }

  /// 切り抜いた画像の中の座標を、元の画像の座標に戻す
  TileDetection mapFromCrop(double cropLeft, double cropTop, double cropWidth, double cropHeight) =>
      TileDetection(
        tile,
        score,
        cropLeft + left * cropWidth,
        cropTop + top * cropHeight,
        cropLeft + right * cropWidth,
        cropTop + bottom * cropHeight,
      );

  @override
  String toString() => '$tile(${score.toStringAsFixed(2)})';
}

/// 同じ牌に重なった検出を1つにまとめる（NMS: Non-Maximum Suppression）。
///
/// 1枚の牌に違う種類の答えが重なることもあるので、種類に関係なく、
/// 重なりが [iouThreshold] 以上なら確信度（score）の高いほうだけを残す。
List<TileDetection> nonMaxSuppression(List<TileDetection> detections,
    {double iouThreshold = 0.45, int maxCount = 40}) {
  final sorted = [...detections]..sort((a, b) => b.score.compareTo(a.score));
  final kept = <TileDetection>[];
  for (final d in sorted) {
    if (kept.length >= maxCount) break;
    if (kept.every((k) => k.iou(d) < iouThreshold)) kept.add(d);
  }
  return kept;
}

/// 並べ替えた結果
class ArrangedTiles {
  /// 手牌の列の牌（左から順）
  final List<Tile> tiles;

  /// 手牌の列から外れていたので使わなかった牌の数
  final int ignored;

  const ArrangedTiles(this.tiles, this.ignored);
}

/// 見つけた牌を、手牌の列ごとに分けて左から順に並べる。
///
/// 牌の中心の並びから列の向き（写真が少し傾いていても）を求め、
/// 列と直角の方向に離れた牌は別の列とする。一番多くの牌が並んだ列を手牌とする。
ArrangedTiles arrangeTiles(List<TileDetection> detections) {
  if (detections.isEmpty) return const ArrangedTiles([], 0);
  if (detections.length == 1) return ArrangedTiles([detections.single.tile], 0);

  // 列の向き: それぞれの牌から一番近い牌への向き（隣の牌）の中央値。
  // 手牌は横に並べて撮る前提なので、45度より傾いた向きは使わない
  final n = detections.length;
  final angles = <double>[];
  for (final d in detections) {
    TileDetection? nearest;
    var best = double.infinity;
    for (final o in detections) {
      if (identical(o, d)) continue;
      final dist = math.pow(o.centerX - d.centerX, 2) + math.pow(o.centerY - d.centerY, 2);
      if (dist < best) {
        best = dist.toDouble();
        nearest = o;
      }
    }
    var a = math.atan2(nearest!.centerY - d.centerY, nearest.centerX - d.centerX);
    if (a > math.pi / 2) a -= math.pi;
    if (a < -math.pi / 2) a += math.pi;
    if (a.abs() < math.pi / 4) angles.add(a);
  }
  angles.sort();
  final angle = angles.isEmpty ? 0.0 : angles[angles.length ~/ 2];
  final ux = math.cos(angle), uy = math.sin(angle);
  double along(TileDetection d) => d.centerX * ux + d.centerY * uy;
  double across(TileDetection d) => -d.centerX * uy + d.centerY * ux;

  // 牌の大きさ（短いほうの辺の中央値）を基準に列を分ける
  final sizes = detections.map((d) => math.min(d.width, d.height)).toList()..sort();
  final unit = sizes[sizes.length ~/ 2];
  final byAcross = [...detections]..sort((a, b) => across(a).compareTo(across(b)));
  final rows = <List<TileDetection>>[
    [byAcross.first]
  ];
  for (final d in byAcross.skip(1)) {
    final row = rows.last;
    final rowCenter = row.map(across).reduce((a, b) => a + b) / row.length;
    if ((across(d) - rowCenter).abs() < unit * 0.8) {
      row.add(d);
    } else {
      rows.add([d]);
    }
  }
  // 牌が一番多い列（同じ数なら、写真の下のほう＝手前の列）
  rows.sort((a, b) {
    final c = b.length.compareTo(a.length);
    if (c != 0) return c;
    return (b.map(across).reduce(math.max)).compareTo(a.map(across).reduce(math.max));
  });
  final hand = rows.first..sort((a, b) => along(a).compareTo(along(b)));
  return ArrangedTiles(hand.map((d) => d.tile).toList(), n - hand.length);
}

/// 次に、牌の写っている範囲だけを切り抜いてもう一度読み取るときの範囲
/// （割合 left, top, width, height）。切り抜く意味がないほど広ければ null
({double left, double top, double width, double height})? cropRegion(List<TileDetection> detections,
    {double margin = 0.6, double maxAreaRatio = 0.5}) {
  if (detections.isEmpty) return null;
  final sizes = detections.map((d) => math.max(d.width, d.height)).toList()..sort();
  final pad = sizes[sizes.length ~/ 2] * margin;
  final l = math.max(0.0, detections.map((d) => d.left).reduce(math.min) - pad);
  final t = math.max(0.0, detections.map((d) => d.top).reduce(math.min) - pad);
  final r = math.min(1.0, detections.map((d) => d.right).reduce(math.max) + pad);
  final b = math.min(1.0, detections.map((d) => d.bottom).reduce(math.max) + pad);
  if ((r - l) * (b - t) > maxAreaRatio) return null;
  return (left: l, top: t, width: r - l, height: b - t);
}

/// 認識モデル（MediaPipe Model Maker の SSD 形式）の出力を、牌の検出結果に変換する。
///
/// - [rawBoxes]: アンカーごとの箱のずれ（y中心, x中心, 高さ, 幅）× アンカー数
/// - [rawScores]: アンカーごと・クラスごとの確信度（0〜1）× アンカー数
/// - [anchors]: アンカー（y中心, x中心, 高さ, 幅。モデルの入力画像を 1 とした割合）× アンカー数
///
/// 座標はモデルの入力画像（正方形）を 1 とした割合で返す。
List<TileDetection> decodeDetections({
  required List<double> rawBoxes,
  required List<double> rawScores,
  required List<double> anchors,
  required List<Tile> labels,
  double scoreThreshold = 0.3,
}) {
  final numAnchors = anchors.length ~/ 4;
  final numClasses = rawScores.length ~/ numAnchors;
  if (rawBoxes.length != numAnchors * 4 || numClasses * numAnchors != rawScores.length) {
    throw ArgumentError('モデルの出力の大きさがアンカーの数と合いません');
  }
  // ラベルの数がクラス数より1つ少なければ、先頭が background
  final offset = numClasses - labels.length;
  final result = <TileDetection>[];
  for (var i = 0; i < numAnchors; i++) {
    var best = -1;
    var bestScore = scoreThreshold;
    for (var c = offset; c < numClasses; c++) {
      final s = rawScores[i * numClasses + c];
      if (s > bestScore) {
        bestScore = s;
        best = c;
      }
    }
    if (best < 0) continue;
    final ay = anchors[i * 4], ax = anchors[i * 4 + 1], ah = anchors[i * 4 + 2], aw = anchors[i * 4 + 3];
    final yc = rawBoxes[i * 4] * ah + ay;
    final xc = rawBoxes[i * 4 + 1] * aw + ax;
    final h = math.exp(rawBoxes[i * 4 + 2]) * ah;
    final w = math.exp(rawBoxes[i * 4 + 3]) * aw;
    result.add(TileDetection(labels[best - offset], bestScore, xc - w / 2, yc - h / 2, xc + w / 2, yc + h / 2));
  }
  return result;
}

/// 画像を縦横比を保って正方形に縮め、右と下を余白で埋めたとき（モデルの学習時と同じ）の倍率
class Letterbox {
  /// 元の画像の幅・高さ（ピクセル）
  final int width, height;

  /// モデルの入力の一辺（ピクセル）
  final int size;

  const Letterbox(this.width, this.height, this.size);

  double get scale => size / math.max(width, height);
  int get resizedWidth => math.max(1, (width * scale).round());
  int get resizedHeight => math.max(1, (height * scale).round());

  /// モデルの入力の座標（割合）→ 元の画像の座標（割合）
  TileDetection toImage(TileDetection d) {
    final sx = size / resizedWidth, sy = size / resizedHeight;
    return TileDetection(d.tile, d.score, (d.left * sx).clamp(0.0, 1.0), (d.top * sy).clamp(0.0, 1.0),
        (d.right * sx).clamp(0.0, 1.0), (d.bottom * sy).clamp(0.0, 1.0));
  }
}
