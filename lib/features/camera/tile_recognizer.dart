import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:mahjong_score_engine/mahjong_score_engine.dart';

/// 読み取りに失敗したときのエラー（[message] は利用者向けの説明）
class RecognitionException implements Exception {
  final String message;
  const RecognitionException(this.message);

  @override
  String toString() => message;
}

/// 画像から手牌を認識するインターフェース
abstract class TileRecognizer {
  /// 画像（JPEG/PNG）から牌を左から順に認識する。失敗したら [RecognitionException]
  Future<List<Tile>> recognize(Uint8List imageBytes);
}

/// カメラ認識（Qwen API）の設定。端末の中にだけ保存し、バックアップには入れない
class CameraSettings {
  /// 国際版（シンガポール）の接続先
  static const intlEndpoint =
      'https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions';

  /// 中国本土版（北京）の接続先
  static const chinaEndpoint =
      'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions';

  static const defaultModel = 'qwen-vl-max';

  /// Alibaba Cloud Model Studio（DashScope）の API キー
  final String apiKey;
  final String endpoint;
  final String model;

  const CameraSettings({
    this.apiKey = '',
    this.endpoint = intlEndpoint,
    this.model = defaultModel,
  });

  /// API キーが設定されているか
  bool get isConfigured => apiKey.trim().isNotEmpty;

  CameraSettings copyWith({String? apiKey, String? endpoint, String? model}) => CameraSettings(
        apiKey: apiKey ?? this.apiKey,
        endpoint: endpoint ?? this.endpoint,
        model: model ?? this.model,
      );

  Map<String, dynamic> toJson() => {'apiKey': apiKey, 'endpoint': endpoint, 'model': model};

  factory CameraSettings.fromJson(Map<String, dynamic> j) => CameraSettings(
        apiKey: j['apiKey'] as String? ?? '',
        endpoint: j['endpoint'] as String? ?? intlEndpoint,
        model: j['model'] as String? ?? defaultModel,
      );
}

/// Qwen（画像を理解する AI）の API を使った認識。
///
/// Alibaba Cloud Model Studio の OpenAI 互換 API（chat/completions）に、
/// 画像（data URL）と指示文を送り、"1m 2m 3m ..." 形式のテキストで答えてもらう。
class QwenTileRecognizer implements TileRecognizer {
  final CameraSettings settings;
  final http.Client client;

  /// 応答を待つ最長時間
  final Duration timeout;

  QwenTileRecognizer(this.settings, {http.Client? client, this.timeout = const Duration(seconds: 60)})
      : client = client ?? http.Client();

  /// モデルに送る指示文
  static const prompt = '''
この画像に写っている麻雀牌を、左から右へ順番にすべて読み取ってください。
次の表記だけを、半角スペース区切りで1行に出力してください（説明文は書かないでください）。
萬子: 1m〜9m / 筒子: 1p〜9p / 索子: 1s〜9s
字牌: 1z=東 2z=南 3z=西 4z=北 5z=白 6z=發 7z=中
赤い5の牌は 5mr / 5pr / 5sr
麻雀牌が写っていない場合は NONE とだけ出力してください。''';

  /// 画像の種類（PNG か JPEG）
  static String mimeTypeOf(Uint8List bytes) =>
      bytes.length >= 4 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47
          ? 'image/png'
          : 'image/jpeg';

  /// API に送る本文
  Map<String, dynamic> buildRequest(Uint8List imageBytes) => {
        'model': settings.model,
        'temperature': 0,
        'messages': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'image_url',
                'image_url': {'url': 'data:${mimeTypeOf(imageBytes)};base64,${base64Encode(imageBytes)}'},
              },
              {'type': 'text', 'text': prompt},
            ],
          },
        ],
      };

  @override
  Future<List<Tile>> recognize(Uint8List imageBytes) async {
    if (!settings.isConfigured) {
      throw const RecognitionException('API キーが設定されていません。カメラ認識の設定画面で入力してください。');
    }
    final http.Response res;
    try {
      res = await client
          .post(
            Uri.parse(settings.endpoint),
            headers: {
              'Authorization': 'Bearer ${settings.apiKey.trim()}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(buildRequest(imageBytes)),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const RecognitionException('時間内に応答がありませんでした。通信環境を確認して、もう一度お試しください。');
    } catch (e) {
      throw RecognitionException('Qwen API に接続できませんでした（$e）。'
          'Web 版では、ブラウザの安全上の制限で接続できないことがあります。その場合はスマホのアプリ版をお使いください。');
    }

    if (res.statusCode != 200) {
      throw RecognitionException(_errorMessage(res));
    }
    final String content;
    try {
      final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      content = ((data['choices'] as List).first as Map<String, dynamic>)['message']['content'] as String;
    } catch (_) {
      throw const RecognitionException('Qwen API の応答を読み取れませんでした。');
    }
    final tiles = parseResponse(content);
    if (tiles.isEmpty) {
      throw const RecognitionException('麻雀牌を読み取れませんでした。牌が大きく、はっきり写るように撮り直してください。');
    }
    return tiles;
  }

  static String _errorMessage(http.Response res) {
    String? detail;
    try {
      final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      detail = (data['error'] as Map<String, dynamic>?)?['message'] as String? ?? data['message'] as String?;
    } catch (_) {}
    final suffix = detail == null ? '' : '（$detail）';
    switch (res.statusCode) {
      case 401:
      case 403:
        return 'API キーが正しくないか、このモデルを使う権限がありません$suffix。設定を確認してください。';
      case 404:
        return '接続先かモデル名が正しくありません$suffix。設定を確認してください。';
      case 429:
        return '利用の上限に達したか、短い間に使いすぎました$suffix。しばらく待ってからお試しください。';
      default:
        return 'Qwen API でエラーが起きました（${res.statusCode}）$suffix。';
    }
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

/// 読み取った牌を手牌に入れるときの結果
class RecognizedHand {
  /// 手牌（並べ替え済み）
  final List<Tile> hand;

  /// 和了牌（読み取った牌が手牌より1枚多いときの最後の牌）
  final Tile? winningTile;

  /// 利用者に知らせること（使えない牌を除いた、など）
  final List<String> notes;

  const RecognizedHand({required this.hand, required this.winningTile, required this.notes});
}

/// 読み取った牌を、今のルール・鳴きの数に合わせて手牌と和了牌に分ける。
///
/// - [needHand] 手牌の枚数（13 - 3×鳴きの数）
/// - 3人打ちでは二萬〜八萬を除く。赤ドラなしなら赤5は普通の5にする
/// - 同じ牌が5枚以上なら、5枚目からは除く
/// - 手牌より1枚多ければ最後の1枚を和了牌に、それより多い分は使わない
RecognizedHand applyRecognition(
  List<Tile> tiles, {
  required int needHand,
  bool sanma = false,
  bool redDora = true,
}) {
  final notes = <String>[];
  final usable = <Tile>[];
  final counts = <String, int>{};
  var removedSanma = 0, removedOver = 0, normalizedRed = 0;
  for (var t in tiles) {
    if (sanma && tileSuit(t) == 'm' && tileNumber(t) >= 2 && tileNumber(t) <= 8) {
      removedSanma++;
      continue;
    }
    if (isRedDora(t) && (!redDora || (sanma && tileSuit(t) == 'm'))) {
      t = normalizeTile(t);
      normalizedRed++;
    }
    final key = normalizeTile(t);
    if ((counts[key] ?? 0) >= 4) {
      removedOver++;
      continue;
    }
    counts[key] = (counts[key] ?? 0) + 1;
    usable.add(t);
  }
  if (removedSanma > 0) notes.add('3人打ちでは使わない二萬〜八萬を$removedSanma枚除きました');
  if (normalizedRed > 0) notes.add('赤5を$normalizedRed枚、普通の5として入れました');
  if (removedOver > 0) notes.add('同じ牌が5枚以上あったので、$removedOver枚除きました');

  final hand = usable.take(needHand).toList();
  final winningTile = usable.length > needHand ? usable[needHand] : null;
  if (usable.length > needHand + 1) {
    notes.add('読み取った牌が多すぎたので、後ろの${usable.length - needHand - 1}枚は使いませんでした');
  }
  if (hand.length < needHand) {
    notes.add('手牌が${needHand - hand.length}枚足りません。残りは手で入力してください');
  } else if (winningTile == null) {
    notes.add('和了牌は手で選んでください');
  }
  return RecognizedHand(hand: sortTiles(hand), winningTile: winningTile, notes: notes);
}
