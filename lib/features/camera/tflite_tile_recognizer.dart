import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:mahjong_score_engine/mahjong_score_engine.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'tile_detection.dart';
import 'tile_recognizer.dart';

/// 端末の中で動く牌の認識モデル（TensorFlow Lite）を使った読み取り（Android・iOS）。
///
/// 写真はどこにも送らない。モデルは assets/models/ に入っている。
class TfliteTileRecognizer implements TileRecognizer {
  static const modelAsset = 'assets/models/tile_detector.tflite';
  static const anchorsAsset = 'assets/models/tile_anchors.bin';
  static const labelsAsset = 'assets/models/tile_labels.txt';

  final AssetBundle bundle;

  TfliteTileRecognizer({AssetBundle? bundle}) : bundle = bundle ?? rootBundle;

  _ModelFiles? _files;

  Future<_ModelFiles> _load() async {
    if (_files != null) return _files!;
    final model = await bundle.load(modelAsset);
    final anchors = await bundle.load(anchorsAsset);
    final labels = await bundle.loadString(labelsAsset);
    return _files = _ModelFiles(
      model.buffer.asUint8List(model.offsetInBytes, model.lengthInBytes),
      anchors.buffer.asFloat32List(anchors.offsetInBytes, anchors.lengthInBytes ~/ 4),
      labels.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
    );
  }

  @override
  Future<List<Tile>> recognize(Uint8List imageBytes) async {
    final _ModelFiles files;
    try {
      files = await _load();
    } catch (e) {
      throw RecognitionException('認識モデルを読み込めませんでした（$e）。');
    }
    // 画像の処理とモデルの実行は時間がかかるので、画面が固まらないよう別の Isolate で行う
    final result = await Isolate.run(() => _run(files, imageBytes));
    if (result.error != null) throw RecognitionException(result.error!);
    if (result.tiles.isEmpty) {
      throw const RecognitionException('麻雀牌を見つけられませんでした。牌が大きく、はっきり写るように撮り直してください。');
    }
    return result.tiles;
  }
}

class _ModelFiles {
  final Uint8List model;
  final Float32List anchors;
  final List<String> labels;

  const _ModelFiles(this.model, this.anchors, this.labels);
}

class _Result {
  final List<Tile> tiles;
  final String? error;

  const _Result(this.tiles, [this.error]);
}

_Result _run(_ModelFiles files, Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return const _Result([], '写真を読み込めませんでした。');
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
    final arranged = arrangeTiles(detections);
    return _Result(arranged.tiles);
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
  );
  return nonMaxSuppression(detections).map(box.toImage).toList();
}
