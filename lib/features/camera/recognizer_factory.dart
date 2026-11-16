import 'tile_recognizer.dart';
import 'recognizer_factory_stub.dart'
    if (dart.library.js_interop) 'recognizer_factory_web.dart'
    if (dart.library.ffi) 'recognizer_factory_native.dart' as impl;

/// この端末でカメラ認識を使えるか（Android・iOS のアプリ版と Web 版）
bool get cameraRecognitionSupported => impl.cameraRecognitionSupported;

/// 端末の中で動く認識モデルを使った読み取り。
/// アプリ版は TensorFlow Lite、Web 版はブラウザの中の LiteRT.js で、同じモデルを動かす
TileRecognizer createTileRecognizer() => impl.createTileRecognizer();

/// 初めて使うときに、認識モデルなどをダウンロードする大きさ（MB）。
/// アプリ版はアプリに入っているので null、Web 版だけ値がある
int? get cameraFirstUseDownloadMb => impl.cameraFirstUseDownloadMb;
