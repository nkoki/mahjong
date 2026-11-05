import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'tile_detection.dart';

/// 牌を1枚ずつ見分ける分類モデル（assets/models/tile_classifier.tflite）に渡す画像の作り方。
///
/// 検出モデルは写真全体を縮めて読むので、萬子の漢数字（六と八など）のような細かい違いが潰れやすい。
/// そこで、見つけた牌を1枚ずつ切り抜いて大きくし、分類モデルで種類を見分け直す。
///
/// 切り抜き方は学習の道具（tools/tile_model/tile_crop.py）と同じにする。変えるときは両方直す。
class TileClassifierInput {
  /// 分類モデルの入力の高さ・幅（ピクセル）
  static const height = 128;
  static const width = 96;

  /// 検出した箱を、上下左右に箱の幅・高さのこの割合ずつ広げて切り抜く
  static const margin = 0.08;

  /// 箱の幅が高さのこの倍より大きければ、横向きの牌として時計回りに 90 度回す
  static const landscapeRatio = 1.15;

  /// 分類モデルの「牌ではない」（検出モデルが間違えて見つけたもの・背景）のクラス名
  static const notATile = 'bg';
}

/// 写真の中で切り抜く範囲（ピクセル）と、時計回りに 90 度回すかどうか
typedef ClassifierCrop = ({int x, int y, int width, int height, bool rotate});

/// 検出した牌（座標は写真を 1 とした割合）から、分類モデルに渡すために切り抜く範囲を求める
ClassifierCrop classifierCropRect(TileDetection d, int imageWidth, int imageHeight) {
  final left = d.left * imageWidth, top = d.top * imageHeight;
  final right = d.right * imageWidth, bottom = d.bottom * imageHeight;
  final bw = right - left, bh = bottom - top;
  const m = TileClassifierInput.margin;
  final l = math.max(0, (left - bw * m).floor());
  final t = math.max(0, (top - bh * m).floor());
  final r = math.min(imageWidth, (right + bw * m).ceil());
  final b = math.min(imageHeight, (bottom + bh * m).ceil());
  return (
    x: l,
    y: t,
    width: math.max(1, r - l),
    height: math.max(1, b - t),
    rotate: bw > bh * TileClassifierInput.landscapeRatio,
  );
}

/// 分類モデルの入力（高さ × 幅 × RGB、画素値は 0〜255 のまま）を作る
Float32List classifierInput(img.Image photo, TileDetection d) {
  final c = classifierCropRect(d, photo.width, photo.height);
  var crop = img.copyCrop(photo, x: c.x, y: c.y, width: c.width, height: c.height);
  if (c.rotate) crop = img.copyRotate(crop, angle: 90); // 時計回り
  final resized = img.copyResize(crop,
      width: TileClassifierInput.width,
      height: TileClassifierInput.height,
      interpolation: img.Interpolation.average);
  final input = Float32List(TileClassifierInput.height * TileClassifierInput.width * 3);
  var i = 0;
  for (var y = 0; y < TileClassifierInput.height; y++) {
    for (var x = 0; x < TileClassifierInput.width; x++) {
      final p = resized.getPixel(x, y);
      input[i++] = p.r.toDouble();
      input[i++] = p.g.toDouble();
      input[i++] = p.b.toDouble();
    }
  }
  return input;
}

/// 分類モデルの答え（クラスごとの確率）で、検出した牌の種類を置き換える。位置と確信度はそのまま。
/// 分類モデルが「牌ではない」と答えたら null（その検出は捨てる）
TileDetection? relabelWithClassifier(TileDetection d, List<double> probs, List<String> labels) {
  if (probs.length != labels.length) {
    throw ArgumentError('分類モデルの出力の数（${probs.length}）とクラス名の数（${labels.length}）が合いません');
  }
  var best = 0;
  for (var i = 1; i < probs.length; i++) {
    if (probs[i] > probs[best]) best = i;
  }
  if (labels[best] == TileClassifierInput.notATile) return null;
  return TileDetection(labels[best], d.score, d.left, d.top, d.right, d.bottom);
}
