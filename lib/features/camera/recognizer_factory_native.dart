import 'dart:io' show Platform;

import 'tflite_tile_recognizer.dart';
import 'tile_recognizer.dart';

/// Android・iOS のアプリ版で使える（パソコン向けのアプリは対象外）
bool get cameraRecognitionSupported => Platform.isAndroid || Platform.isIOS;

TileRecognizer createTileRecognizer() => TfliteTileRecognizer();
