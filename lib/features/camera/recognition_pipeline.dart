import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:mahjong_score_engine/mahjong_score_engine.dart';

import 'guided_recognition.dart';
import 'tile_classifier.dart';
import 'tile_detection.dart';

/// 認識モデルを動かす部分（Web 版ではブラウザの中の LiteRT.js。テストでは差し替える）
abstract class TileModelRunner {
  /// 検出モデルの入力の1辺（ピクセル）
  int get detectorSize;

  /// 検出モデルを動かす。入力は 1辺 [detectorSize] の RGB（-1〜1）。
  /// 答えは、箱（アンカーごとに4つ）と、種類ごとの確信度
  Future<({Float32List boxes, Float32List scores})> detect(Float32List input);

  /// 分類モデルを動かす。入力は [classifierInput] の形。答えは種類ごとの確率
  Future<Float32List> classify(Float32List input);
}

/// 検出モデルの入力を作る。縦横比を保って縮め、左上に寄せて置く（右と下の余白は灰色）。
///
/// アプリ版（tflite_tile_recognizer.dart）と同じ作り方。変えるときは両方直す
({Float32List input, Letterbox box}) detectorInput(img.Image image, int size) {
  final box = Letterbox(image.width, image.height, size);
  final resized = img.copyResize(image,
      width: box.resizedWidth, height: box.resizedHeight, interpolation: img.Interpolation.average);
  // 学習時と同じく (画素値 - 127.5) / 127.5。右と下の余白は 0（灰色）
  final input = Float32List(size * size * 3);
  for (var y = 0; y < resized.height; y++) {
    for (var x = 0; x < resized.width; x++) {
      final p = resized.getPixel(x, y);
      final i = (y * size + x) * 3;
      input[i] = (p.r - 127.5) / 127.5;
      input[i + 1] = (p.g - 127.5) / 127.5;
      input[i + 2] = (p.b - 127.5) / 127.5;
    }
  }
  return (input: input, box: box);
}

/// 写真から手牌を読み取る手順（Web 版用。アプリ版の tflite_tile_recognizer.dart と同じ手順で、
/// モデルを動かす所だけ [runner] に任せる。手順を変えるときは両方直す）。
///
/// 1. 写真全体から牌を探す
/// 2. 牌が写っている所だけを切り抜いて、大きくしてからもう一度読み取る
/// 3. 見つけた牌を1枚ずつ切り抜いて、分類モデルで種類を見分け直す（牌でないものは捨てる）
/// 4. 一番多く牌が並んだ列を、左から順に並べる
///
/// [pause] は、重い処理の合間に画面を描き直す時間を作るために呼ぶ
Future<List<Tile>> recognizeTiles({
  required img.Image photo,
  required TileModelRunner runner,
  required Float32List anchors,
  required List<String> labels,
  required List<String> classifierLabels,
  required double detectionThreshold,
  Future<void> Function()? pause,
}) async =>
    arrangeTiles(await detectTiles(
      photo: photo,
      runner: runner,
      anchors: anchors,
      labels: labels,
      classifierLabels: classifierLabels,
      detectionThreshold: detectionThreshold,
      pause: pause,
    )).tiles;

/// [recognizeTiles] の 1〜3 まで（並べる前）。見つけた牌を、位置（[photo] を 1 とした割合）つきで返す
Future<List<TileDetection>> detectTiles({
  required img.Image photo,
  required TileModelRunner runner,
  required Float32List anchors,
  required List<String> labels,
  required List<String> classifierLabels,
  required double detectionThreshold,
  Future<void> Function()? pause,
}) async {
  Future<List<TileDetection>> detect(img.Image image) async {
    final prepared = detectorInput(image, runner.detectorSize);
    await pause?.call();
    final raw = await runner.detect(prepared.input);
    final detections = decodeDetections(
      rawBoxes: raw.boxes,
      rawScores: raw.scores,
      anchors: anchors,
      labels: labels,
      scoreThreshold: detectionThreshold,
    );
    return nonMaxSuppression(detections).map(prepared.box.toImage).toList();
  }

  var detections = await detect(photo);
  await pause?.call();
  final region = cropRegion(detections);
  if (region != null) {
    final x = (region.left * photo.width).floor();
    final y = (region.top * photo.height).floor();
    final w = math.max(1, (region.width * photo.width).ceil());
    final h = math.max(1, (region.height * photo.height).ceil());
    final crop = img.copyCrop(photo, x: x, y: y, width: w, height: h);
    final again = await detect(crop);
    if (again.length >= detections.length * 0.8) {
      detections = again
          .map((d) => d.mapFromCrop(x / photo.width, y / photo.height, w / photo.width, h / photo.height))
          .toList();
    }
  }
  await pause?.call();
  final classified = <TileDetection>[];
  for (final d in detections) {
    final probs = await runner.classify(classifierInput(photo, d));
    final relabeled = relabelWithClassifier(d, probs, classifierLabels);
    if (relabeled != null) classified.add(relabeled);
  }
  return classified;
}

/// 写真の中の範囲ごとに牌を読み取る（枠つきの撮影用）。範囲を切り抜いて、それぞれ [detectTiles] で読む
Future<List<RegionTiles>> detectRegions({
  required img.Image photo,
  required List<PhotoRegion> regions,
  double? viewAspect,
  bool mirrored = false,
  required TileModelRunner runner,
  required Float32List anchors,
  required List<String> labels,
  required List<String> classifierLabels,
  required double detectionThreshold,
  Future<void> Function()? pause,
}) async {
  final result = <RegionTiles>[];
  // 鏡のように反転した写真は、反転を戻してから読む（枠の位置も左右を入れ替える）
  if (mirrored) photo = img.flipHorizontal(photo.clone());
  for (final r0 in regions) {
    final region = mirrored ? r0.mirrored : r0;
    final r = viewAspect == null ? region : mapViewRegionToPhoto(region, viewAspect, photo.width, photo.height);
    final px = regionPixels(r, photo.width, photo.height);
    final crop = img.copyCrop(photo, x: px.x, y: px.y, width: px.width, height: px.height);
    final detections = await detectTiles(
      photo: crop,
      runner: runner,
      anchors: anchors,
      labels: labels,
      classifierLabels: classifierLabels,
      detectionThreshold: detectionThreshold,
      pause: pause,
    );
    result.add(RegionTiles(px.width, px.height, detections));
    await pause?.call();
  }
  return result;
}
