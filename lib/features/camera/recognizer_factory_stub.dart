import 'dart:typed_data';

import '../../core/l10n.dart';
import 'guided_recognition.dart';
import 'tile_recognizer.dart';

/// アプリ版でも Web 版でもない環境: 認識モデルを動かす仕組みがないので、カメラ認識はなし
bool get cameraRecognitionSupported => false;

TileRecognizer createTileRecognizer() => const _UnsupportedRecognizer();

int? get cameraFirstUseDownloadMb => null;

class _UnsupportedRecognizer implements TileRecognizer {
  const _UnsupportedRecognizer();

  @override
  Future<Never> recognizeRegions(Uint8List imageBytes, List<PhotoRegion> regions,
          {double? viewAspect, bool mirrored = false}) =>
      recognize(imageBytes);

  @override
  Future<Never> recognize(Uint8List imageBytes) async =>
      throw RecognitionException(
          tr('この環境ではカメラ認識を使えません。', 'Camera recognition is not available in this environment.'));
}
