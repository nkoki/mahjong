import 'tile_recognizer.dart';
import 'recognizer_factory_stub.dart'
    if (dart.library.ffi) 'recognizer_factory_native.dart' as impl;

/// この端末でカメラ認識を使えるか（Android・iOS のアプリ版だけ。Web 版では使えない）
bool get cameraRecognitionSupported => impl.cameraRecognitionSupported;

/// 端末の中で動く認識モデルを使った読み取り
TileRecognizer createTileRecognizer() => impl.createTileRecognizer();
