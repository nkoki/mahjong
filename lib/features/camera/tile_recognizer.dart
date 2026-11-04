import 'dart:typed_data';

import 'package:mahjong_score_engine/mahjong_score_engine.dart';

/// 画像から手牌を認識するインターフェース（カメラ認識機能の設計）
///
/// 実装予定: Qwen（Vision Language Model）APIに手牌の写真を送り、
/// 牌の並びを "1m 2m 3m ..." 形式のテキストで返してもらう。
abstract class TileRecognizer {
  static const notAvailableMessage = 'カメラ認識は準備中です（今後のアップデートで対応予定）';

  /// 画像（JPEG/PNG）から牌を左から順に認識する
  Future<List<Tile>> recognize(Uint8List imageBytes);
}

/// Qwen API を使った認識（未実装。プロンプトと応答の解析のみ用意）
class QwenTileRecognizer implements TileRecognizer {
  final String endpoint;
  final String apiKey;
  final String model;

  const QwenTileRecognizer({
    required this.endpoint,
    required this.apiKey,
    this.model = 'qwen-vl-max',
  });

  /// モデルに送る指示文
  static const prompt = '''
この画像に写っている麻雀牌を左から順に読み取ってください。
次の表記で、半角スペース区切りで出力してください（説明文は不要）。
萬子: 1m〜9m / 筒子: 1p〜9p / 索子: 1s〜9s
字牌: 1z=東 2z=南 3z=西 4z=北 5z=白 6z=發 7z=中
赤5は 5mr / 5pr / 5sr''';

  @override
  Future<List<Tile>> recognize(Uint8List imageBytes) {
    // TODO: HTTP で endpoint に画像(base64)と prompt を送り、応答テキストを parseResponse に渡す
    throw UnimplementedError(TileRecognizer.notAvailableMessage);
  }

  /// モデルの応答テキストから牌を取り出す（不正な表記は無視）
  static List<Tile> parseResponse(String text) {
    return RegExp(r'[1-9][mpsz]r?')
        .allMatches(text)
        .map((m) => m.group(0)!)
        .where(isValidTile)
        .toList();
  }
}
