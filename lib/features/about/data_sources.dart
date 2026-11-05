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

const _ccBy4 = 'https://creativecommons.org/licenses/by/4.0/';

/// 学習データ（Roboflow のものは tools/tile_model/fetch_roboflow.py が書いた attribution.json に合わせる）
const trainingDataSources = [
  DataSource(
    title: 'Riichi Mahjong（バージョン 8）',
    author: 'HUST（Roboflow Universe）',
    url: 'https://universe.roboflow.com/hust-xq5rx/riichi-mahjong',
    license: 'CC BY 4.0',
    licenseUrl: _ccBy4,
    changes: 'クラス名をこのアプリの牌の表記に変換しました（赤5のクラスが無いため、5萬・5筒・5索は普通の5として扱いました）。'
        'ほかのデータと合わせて牌の認識モデルの学習・確認に使いました。画像そのものはアプリに含めていません。',
  ),
  DataSource(
    title: 'Riichi Mahjong Detection（バージョン 3）',
    author: 'riichimahjongdetection（Roboflow Universe）',
    url: 'https://universe.roboflow.com/riichimahjongdetection/riichi-mahjong-detection',
    license: 'CC BY 4.0',
    licenseUrl: _ccBy4,
    changes: 'クラス名をこのアプリの牌の表記に変換し（0m・0p・0s は赤5）、牌の裏（0z）のラベルを外しました。'
        'ほかのデータと合わせて牌の認識モデルの学習・確認に使いました。画像そのものはアプリに含めていません。',
  ),
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
