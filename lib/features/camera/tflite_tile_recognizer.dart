import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:mahjong_score_engine/mahjong_score_engine.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../../core/l10n.dart';
import 'tile_classifier.dart';
import 'tile_detection.dart';
import 'tile_recognizer.dart';

/// 端末の中で動く牌の認識モデル（TensorFlow Lite）を使った読み取り（Android・iOS）。
///
/// 写真はどこにも送らない。モデルは assets/models/ に入っている。
/// 検出モデルで牌を見つけたあと、分類モデルで1枚ずつ種類を見分け直す。
class TfliteTileRecognizer implements TileRecognizer {
  static const modelAsset = 'assets/models/tile_detector.tflite';
  static const anchorsAsset = 'assets/models/tile_anchors.bin';
  static const labelsAsset = 'assets/models/tile_labels.txt';
  static const classifierAsset = 'assets/models/tile_classifier.tflite';
  static const classifierLabelsAsset = 'assets/models/tile_classifier_labels.txt';

  /// 検出モデルの確信度がこれ以上なら牌の候補にする。低めにして見落としを減らし、
  /// 牌でないものは分類モデルが「牌ではない」と答えて捨てる（tools/tile_model/evaluate.py で決めた値）
  static const detectionThreshold = 0.2;

  final AssetBundle bundle;

  TfliteTileRecognizer({AssetBundle? bundle}) : bundle = bundle ?? rootBundle;

  _ModelFiles? _files;

  Future<_ModelFiles> _load() async {
    if (_files != null) return _files!;
    final model = await bundle.load(modelAsset);
    final anchors = await bundle.load(anchorsAsset);
    final labels = await bundle.loadString(labelsAsset);
    final classifier = await bundle.load(classifierAsset);
    final classifierLabels = await bundle.loadString(classifierLabelsAsset);
    List<String> lines(String s) => s.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    return _files = _ModelFiles(
      model.buffer.asUint8List(model.offsetInBytes, model.lengthInBytes),
      anchors.buffer.asFloat32List(anchors.offsetInBytes, anchors.lengthInBytes ~/ 4),
      lines(labels),
      classifier.buffer.asUint8List(classifier.offsetInBytes, classifier.lengthInBytes),
      lines(classifierLabels),
    );
  }

  @override
  Future<List<Tile>> recognize(Uint8List imageBytes) async {
    final _ModelFiles files;
    try {
      files = await _load();
    } catch (e) {
      throw RecognitionException(tr('認識モデルを読み込めませんでした（$e）。', 'Could not load the recognition model ($e).'));
    }
    // 画像の処理とモデルの実行は時間がかかるので、画面が固まらないよう別の Isolate で行う
    final result = await Isolate.run(() => _run(files, imageBytes));
    if (result.error != null) {
      // 別の Isolate では言語の設定が引き継がれないので、ここで今の言語にする
      throw RecognitionException(
          result.error == _photoLoadError ? tr(_photoLoadError, 'Could not load the photo.') : result.error!);
    }
    if (result.tiles.isEmpty) {
      throw RecognitionException(tr('麻雀牌を見つけられませんでした。牌が大きく、はっきり写るように撮り直してください。',
          'No mahjong tiles found. Retake the photo so the tiles are large and clear.'));
    }
    return result.tiles;
  }
}

class _ModelFiles {
  final Uint8List model;
  final Float32List anchors;
  final List<String> labels;
  final Uint8List classifier;
  final List<String> classifierLabels;

  const _ModelFiles(this.model, this.anchors, this.labels, this.classifier, this.classifierLabels);
}

/// 写真を読み込めなかったときの文（別の Isolate から返す）
const _photoLoadError = '写真を読み込めませんでした。';

class _Result {
  final List<Tile> tiles;
  final String? error;

  const _Result(this.tiles, [this.error]);
}

_Result _run(_ModelFiles files, Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return const _Result([], _photoLoadError);
  // スマホの写真は向きの情報（EXIF）で回転していることがあるので、見たままの向きにする
  final photo = img.bakeOrientation(decoded);

  final interpreter = Interpreter.fromBuffer(files.model, options: InterpreterOptions()..threads = 2);
  try {
    final size = interpreter.getInputTensor(0).shape[1];
    // 1回目: 写真全体から牌を探す
    var detections = _detect(interpreter, files, photo, size);
    // 2回目: 牌が写っている所だけを切り抜いて、大きくしてからもう一度読み取る
    final region = cropRegion(detections);
    if (region != null) {
      final x = (region.left * photo.width).floor();
      final y = (region.top * photo.height).floor();
      final w = math.max(1, (region.width * photo.width).ceil());
      final h = math.max(1, (region.height * photo.height).ceil());
      final crop = img.copyCrop(photo, x: x, y: y, width: w, height: h);
      final again = _detect(interpreter, files, crop, size);
      if (again.length >= detections.length * 0.8) {
        detections = again
            .map((d) => d.mapFromCrop(x / photo.width, y / photo.height, w / photo.width, h / photo.height))
            .toList();
      }
    }
    // 3回目: 見つけた牌を1枚ずつ切り抜いて大きくし、分類モデルで種類を見分け直す（牌でないものは捨てる）
    detections = _classify(files, photo, detections);
    final arranged = arrangeTiles(detections);
    return _Result(arranged.tiles);
  } finally {
    interpreter.close();
  }
}

/// 見つけた牌の種類を、分類モデルの答えに置き換える。「牌ではない」と答えた検出は捨てる
List<TileDetection> _classify(_ModelFiles files, img.Image photo, List<TileDetection> detections) {
  if (detections.isEmpty) return detections;
  final interpreter = Interpreter.fromBuffer(files.classifier, options: InterpreterOptions()..threads = 2);
  try {
    final output = Float32List(files.classifierLabels.length);
    final result = <TileDetection>[];
    for (final d in detections) {
      final input = classifierInput(photo, d);
      interpreter.runForMultipleInputs([input.buffer.asUint8List()], {0: output.buffer.asUint8List()});
      final relabeled = relabelWithClassifier(d, output, files.classifierLabels);
      if (relabeled != null) result.add(relabeled);
    }
    return result;
  } finally {
    interpreter.close();
  }
}

/// 画像1枚を読み取る。座標は [image] を 1 とした割合
List<TileDetection> _detect(Interpreter interpreter, _ModelFiles files, img.Image image, int size) {
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

  final numAnchors = files.anchors.length ~/ 4;
  final out0 = interpreter.getOutputTensor(0).shape;
  final boxesIndex = out0.last == 4 ? 0 : 1;
  final numClasses = interpreter.getOutputTensor(1 - boxesIndex).shape.last;
  final rawBoxes = Float32List(numAnchors * 4);
  final rawScores = Float32List(numAnchors * numClasses);
  interpreter.runForMultipleInputs(
    [input.buffer.asUint8List()],
    {boxesIndex: rawBoxes.buffer.asUint8List(), 1 - boxesIndex: rawScores.buffer.asUint8List()},
  );
  final detections = decodeDetections(
    rawBoxes: rawBoxes,
    rawScores: rawScores,
    anchors: files.anchors,
    labels: files.labels,
    scoreThreshold: TfliteTileRecognizer.detectionThreshold,
  );
  return nonMaxSuppression(detections).map(box.toImage).toList();
}
