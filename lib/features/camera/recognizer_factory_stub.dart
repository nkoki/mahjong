import 'dart:typed_data';

import 'tile_recognizer.dart';

/// Web 版: 端末の中で動く認識モデル（TensorFlow Lite）を使えないので、カメラ認識はなし
bool get cameraRecognitionSupported => false;

TileRecognizer createTileRecognizer() => const _UnsupportedRecognizer();

class _UnsupportedRecognizer implements TileRecognizer {
  const _UnsupportedRecognizer();

  @override
  Future<Never> recognize(Uint8List imageBytes) async =>
      throw const RecognitionException('カメラ認識はスマホのアプリ版（Android・iOS）で使えます。');
}
