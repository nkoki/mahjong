/// 認識モデルのファイルの場所と設定（Web 版用。アプリ版の TfliteTileRecognizer と同じ値）
///
/// アプリ版のファイル（tflite_tile_recognizer.dart）は dart:isolate などを使うので Web 版から読み込めない。
/// そのため同じ値をここにも書き、test/web_recognizer_test.dart で合っていることを確かめる
class TileModelAssets {
  static const detector = 'assets/models/tile_detector.tflite';
  static const anchors = 'assets/models/tile_anchors.bin';
  static const labels = 'assets/models/tile_labels.txt';
  static const classifier = 'assets/models/tile_classifier.tflite';
  static const classifierLabels = 'assets/models/tile_classifier_labels.txt';

  /// 検出モデルの確信度がこれ以上なら牌の候補にする
  static const detectionThreshold = 0.2;

  /// 1行に1つずつ書かれた名前を読む
  static List<String> lines(String s) => s.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
}
