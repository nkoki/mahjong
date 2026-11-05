import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../session/session_providers.dart';
import 'tile_recognizer.dart';

/// カメラ認識の設定
final cameraSettingsProvider =
    NotifierProvider<CameraSettingsNotifier, CameraSettings>(CameraSettingsNotifier.new);

class CameraSettingsNotifier extends Notifier<CameraSettings> {
  @override
  CameraSettings build() => ref.read(sessionRepositoryProvider).loadCameraSettings();

  Future<void> save(CameraSettings settings) async {
    state = settings;
    await ref.read(sessionRepositoryProvider).saveCameraSettings(settings);
  }
}

/// 牌の読み取り（テストでは差し替える）
final tileRecognizerProvider = Provider<TileRecognizer>(
  (ref) => QwenTileRecognizer(ref.watch(cameraSettingsProvider)),
);

/// 写真の撮影・選択（テストでは差し替える）
abstract class PhotoPicker {
  /// 写真を撮る（[fromCamera] が false ならアルバムから選ぶ）。キャンセルしたら null
  Future<Uint8List?> pick({required bool fromCamera});
}

/// image_picker を使った実装（Android・iOS はカメラ・写真アプリ、Web はファイル選択）
class ImagePickerPhotoPicker implements PhotoPicker {
  const ImagePickerPhotoPicker();

  @override
  Future<Uint8List?> pick({required bool fromCamera}) async {
    final file = await ImagePicker().pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      // 送るデータを小さくする（牌が読める程度の大きさ・画質）
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
    return file?.readAsBytes();
  }
}

final photoPickerProvider = Provider<PhotoPicker>((ref) => const ImagePickerPhotoPicker());
