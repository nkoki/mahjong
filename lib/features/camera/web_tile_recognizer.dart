import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:mahjong_score_engine/mahjong_score_engine.dart';

import '../../core/l10n.dart';
import 'guided_recognition.dart';
import 'recognition_pipeline.dart';
import 'tflite_assets.dart';
import 'tile_recognizer.dart';

/// web/index.html に置いた入口。web/litert/tile_models.js（LiteRT.js）を、初めて呼ばれたときに読み込む
@JS('mahjongLoadTileModels')
external JSFunction? get _loaderFunction;

@JS('mahjongLoadTileModels')
external JSPromise<_TileModelsJs> _loadTileModels();

/// tools/web_litert/src/tile_models.js が用意する関数
extension type _TileModelsJs._(JSObject _) implements JSObject {
  external JSPromise<JSArray<JSNumber>> loadModel(String name, JSAny source);
  external JSPromise<JSArray<_OutputJs>> run(String name, JSFloat32Array input, JSArray<JSNumber> shape);
}

extension type _OutputJs._(JSObject _) implements JSObject {
  external JSArray<JSNumber> get shape;
  external JSFloat32Array get data;
}

/// Web 版の牌の読み取り。アプリ版と同じ認識モデル（.tflite）を、ブラウザの中の LiteRT.js（WebAssembly）で動かす。
///
/// 写真はどこにも送らない。LiteRT.js とモデルは、初めて読み取るときにだけ、このアプリと同じ場所から読み込む。
class WebTileRecognizer implements TileRecognizer {
  /// Web 版だけの分類モデル（1度に読む枚数を 1 に決めた写し。tools/tile_model/make_web_classifier.py で作る）。
  /// ページからの相対の場所（絶対パスにしない）
  static const classifierUrl = 'models/tile_classifier_web.tflite';

  final AssetBundle bundle;

  WebTileRecognizer({AssetBundle? bundle}) : bundle = bundle ?? rootBundle;

  Future<_Loaded>? _loaded;

  Future<_Loaded> _load() async {
    if (_loaderFunction == null) {
      throw StateError('mahjongLoadTileModels is missing in index.html');
    }
    final js = await _loadTileModels().toDart;
    final model = await bundle.load(TileModelAssets.detector);
    final anchors = await bundle.load(TileModelAssets.anchors);
    final labels = await bundle.loadString(TileModelAssets.labels);
    final classifierLabels = await bundle.loadString(TileModelAssets.classifierLabels);
    final detectorShape = await js
        .loadModel('detector', model.buffer.asUint8List(model.offsetInBytes, model.lengthInBytes).toJS)
        .toDart;
    final classifierShape = await js.loadModel('classifier', classifierUrl.toJS).toDart;
    return _Loaded(
      _JsRunner(js, _shape(detectorShape), _shape(classifierShape)),
      // アンカーのファイルは 4 バイトの小数が並んだもの。位置がずれていても読めるように写しを作る
      Float32List.fromList(anchors.buffer.asFloat32List(anchors.offsetInBytes, anchors.lengthInBytes ~/ 4)),
      TileModelAssets.lines(labels),
      TileModelAssets.lines(classifierLabels),
    );
  }

  static List<int> _shape(JSArray<JSNumber> a) => [for (final n in a.toDart) n.toDartInt];

  /// モデルを読み込み、写真を開く（どちらも失敗したら [RecognitionException]）
  Future<(_Loaded, img.Image)> _prepare(Uint8List imageBytes) async {
    final _Loaded loaded;
    try {
      loaded = await (_loaded ??= _load());
    } catch (e) {
      _loaded = null; // 通信が切れていたときなどは、次にもう一度読み込めるようにする
      throw RecognitionException(tr(
          '認識モデルを読み込めませんでした。通信できる状態で、もう一度試してください（$e）。',
          'Could not load the recognition model. Check your connection and try again ($e).'));
    }
    await _pause();
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) {
      throw RecognitionException(tr('写真を読み込めませんでした。', 'Could not load the photo.'));
    }
    // スマホの写真は向きの情報（EXIF）で回転していることがあるので、見たままの向きにする
    final photo = img.bakeOrientation(decoded);
    await _pause();
    return (loaded, photo);
  }

  /// 重い処理の合間に、読み取り中の表示を描き直す時間を作る（Web 版は別の Isolate を使えない）
  static Future<void> _pause() => Future<void>.delayed(const Duration(milliseconds: 1));

  @override
  Future<List<Tile>> recognize(Uint8List imageBytes) async {
    final (loaded, photo) = await _prepare(imageBytes);
    final List<Tile> tiles;
    try {
      tiles = await recognizeTiles(
        photo: photo,
        runner: loaded.runner,
        anchors: loaded.anchors,
        labels: loaded.labels,
        classifierLabels: loaded.classifierLabels,
        detectionThreshold: TileModelAssets.detectionThreshold,
        pause: _pause,
      );
    } catch (e) {
      throw RecognitionException(tr('読み取りに失敗しました（$e）。', 'Recognition failed ($e).'));
    }
    if (tiles.isEmpty) {
      throw RecognitionException(tr('麻雀牌を見つけられませんでした。牌が大きく、はっきり写るように撮り直してください。',
          'No mahjong tiles found. Retake the photo so the tiles are large and clear.'));
    }
    return tiles;
  }

  @override
  Future<List<RegionTiles>> recognizeRegions(Uint8List imageBytes, List<PhotoRegion> regions,
      {double? viewAspect, bool mirrored = false}) async {
    final (loaded, photo) = await _prepare(imageBytes);
    try {
      return await detectRegions(
        photo: photo,
        regions: regions,
        viewAspect: viewAspect,
        mirrored: mirrored,
        runner: loaded.runner,
        anchors: loaded.anchors,
        labels: loaded.labels,
        classifierLabels: loaded.classifierLabels,
        detectionThreshold: TileModelAssets.detectionThreshold,
        pause: _pause,
      );
    } catch (e) {
      throw RecognitionException(tr('読み取りに失敗しました（$e）。', 'Recognition failed ($e).'));
    }
  }
}

class _Loaded {
  final TileModelRunner runner;
  final Float32List anchors;
  final List<String> labels;
  final List<String> classifierLabels;

  const _Loaded(this.runner, this.anchors, this.labels, this.classifierLabels);
}

/// ブラウザの中の LiteRT.js でモデルを動かす
class _JsRunner implements TileModelRunner {
  final _TileModelsJs js;
  final List<int> detectorShape;
  final List<int> classifierShape;

  _JsRunner(this.js, this.detectorShape, this.classifierShape);

  @override
  int get detectorSize => detectorShape[1];

  static JSArray<JSNumber> _js(List<int> shape) => [for (final d in shape) d.toJS].toJS;

  @override
  Future<({Float32List boxes, Float32List scores})> detect(Float32List input) async {
    final outputs = (await js.run('detector', input.toJS, _js(detectorShape)).toDart).toDart;
    if (outputs.length != 2) throw StateError('検出モデルの出力が ${outputs.length} 個です');
    // 出力の順はモデルの作り方で変わるので、最後の大きさが 4 のほうを箱とする
    final boxesFirst = outputs[0].shape.toDart.last.toDartInt == 4;
    return (
      boxes: outputs[boxesFirst ? 0 : 1].data.toDart,
      scores: outputs[boxesFirst ? 1 : 0].data.toDart,
    );
  }

  @override
  Future<Float32List> classify(Float32List input) async {
    final outputs = (await js.run('classifier', input.toJS, _js(classifierShape)).toDart).toDart;
    return outputs.single.data.toDart;
  }
}
