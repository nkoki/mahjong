import 'tile_recognizer.dart';
import 'web_tile_recognizer.dart';

/// Web 版: ブラウザの中で認識モデルを動かす（LiteRT.js）
bool get cameraRecognitionSupported => true;

TileRecognizer createTileRecognizer() => WebTileRecognizer();

/// 初めて使うときに、認識モデルなどをダウンロードする大きさ（MB。圧縮して送られる大きさのめやす）
int? get cameraFirstUseDownloadMb => 11;
