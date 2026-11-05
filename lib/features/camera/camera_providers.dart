import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'recognizer_factory.dart';
import 'tile_recognizer.dart';

/// この端末でカメラ認識を使えるか（Android・iOS のアプリ版だけ。テストでは差し替える）
final cameraSupportedProvider = Provider<bool>((ref) => cameraRecognitionSupported);

/// 牌の読み取り（端末の中で動く認識モデル。テストでは差し替える）
final tileRecognizerProvider = Provider<TileRecognizer>((ref) => createTileRecognizer());

/// 写真の撮影・選択（テストでは差し替える）
abstract class PhotoPicker {
  /// 写真を撮る（[fromCamera] が false ならアルバムから選ぶ）。キャンセルしたら null
  Future<Uint8List?> pick({required bool fromCamera});
}

/// image_picker を使った実装（Android・iOS はカメラ・写真アプリ）
class ImagePickerPhotoPicker implements PhotoPicker {
  const ImagePickerPhotoPicker();

  @override
  Future<Uint8List?> pick({required bool fromCamera}) async {
    final file = await ImagePicker().pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      // 読み取りにかかる時間を短くする（牌が読める程度の大きさ・画質）
      maxWidth: 2000,
      maxHeight: 2000,
      imageQuality: 90,
    );
    return file?.readAsBytes();
  }
}

final photoPickerProvider = Provider<PhotoPicker>((ref) => const ImagePickerPhotoPicker());
