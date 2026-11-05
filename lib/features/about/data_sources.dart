import 'package:flutter/foundation.dart';

/// カメラ認識のモデルの学習に使ったデータ・道具の出典
class DataSource {
  final String title;
  final String author;
  final String url;
  final String license;
  final String licenseUrl;

  /// 元のデータから変えたこと（CC BY では変更の有無を示す）
  final String? changes;

  const DataSource({
    required this.title,
    required this.author,
    required this.url,
    required this.license,
    required this.licenseUrl,
    this.changes,
  });

  /// ライセンス画面（showLicensePage）に載せる文
  String get licenseText => [
        title,
        '作成者: $author',
        '出典: $url',
        'ライセンス: $license（$licenseUrl）',
        if (changes != null) '変更: $changes',
      ].join('\n');
}

/// 学習データ
///
/// Roboflow Universe の CC BY 4.0 のデータセットを使って学習し直したときは、ここに
/// 作品名・作成者・出典 URL・ライセンス・変更内容を追加する（tools/tile_model/ の attribution.json を参照）。
const trainingDataSources = [
  DataSource(
    title: 'riichi-mahjong-tiles',
    author: 'FluffyStuff',
    url: 'https://github.com/FluffyStuff/riichi-mahjong-tiles',
    license: 'CC0 1.0（パブリックドメイン）',
    licenseUrl: 'https://creativecommons.org/publicdomain/zero/1.0/',
    changes: '牌の画像を組み合わせて、学習用の合成写真を作りました。',
  ),
];

/// モデルの作成に使った道具
const modelToolSources = [
  DataSource(
    title: 'MediaPipe Model Maker',
    author: 'Google',
    url: 'https://github.com/google-ai-edge/mediapipe',
    license: 'Apache License 2.0',
    licenseUrl: 'https://www.apache.org/licenses/LICENSE-2.0',
    changes: '学習済みの MobileNet（TensorFlow Model Garden, Apache License 2.0）をもとに、牌の検出を学習させました。',
  ),
];

/// 標準のライセンス画面にも出典を載せる（main で1回だけ呼ぶ）
void registerDataSourceLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final s in trainingDataSources) {
      yield LicenseEntryWithLineBreaks(['牌の認識モデルの学習データ'], s.licenseText);
    }
    for (final s in modelToolSources) {
      yield LicenseEntryWithLineBreaks(['牌の認識モデルの作成'], s.licenseText);
    }
  });
}
