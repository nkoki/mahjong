import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mahjong_app/features/camera/recognition_pipeline.dart';
import 'package:mahjong_app/features/camera/recognizer_factory.dart';
import 'package:mahjong_app/features/camera/tflite_assets.dart';
import 'package:mahjong_app/features/camera/tflite_tile_recognizer.dart';

/// モデルの代わり。検出は呼ばれた回ごとに決めた牌を返し、分類は決めた順に種類を答える
class _FakeRunner implements TileModelRunner {
  /// 検出の答え（呼ばれた回ごと）。牌ごとに (アンカーの番号, 種類の番号)
  final List<List<(int, int)>> detections;

  /// 分類の答え（呼ばれた順）
  final List<String> classes;
  final List<String> classifierLabels;
  final int numAnchors, numClasses;
  final detectInputs = <Float32List>[];
  var classifyCalls = 0;

  _FakeRunner(this.detections, this.classes, this.classifierLabels, {required this.numAnchors, required this.numClasses});

  @override
  int get detectorSize => 32;

  @override
  Future<({Float32List boxes, Float32List scores})> detect(Float32List input) async {
    final found = detections[detectInputs.length];
    detectInputs.add(input);
    final scores = Float32List(numAnchors * numClasses);
    // 書いた順に確信度を少しずつ下げる（確信度の高い順に分類モデルへ渡るので、順番が決まる）
    for (var i = 0; i < found.length; i++) {
      final (anchor, cls) = found[i];
      scores[anchor * numClasses + cls] = 0.9 - i * 0.01;
    }
    return (boxes: Float32List(numAnchors * 4), scores: scores);
  }

  @override
  Future<Float32List> classify(Float32List input) async {
    final probs = Float32List(classifierLabels.length);
    probs[classifierLabels.indexOf(classes[classifyCalls++])] = 1;
    return probs;
  }
}

/// FNV-1a（32ビット）。tools/tile_model/make_web_classifier.py と同じ計算
int fnv1a(List<int> data) {
  var h = 0x811C9DC5;
  for (final b in data) {
    h = ((h ^ b) * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}

/// Web 版のカメラ認識（ブラウザの中で認識モデルを動かす）
void main() {
  group('検出モデルの入力', () {
    test('縦横比を保って縮めて左上に置き、画素値を -1〜1 にする（余白は 0）', () {
      // 横 8 × 縦 4 の写真を、1辺 4 の入力にする → 横 4 × 縦 2 に縮めて上に置く
      final photo = img.Image(width: 8, height: 4)..clear(img.ColorRgb8(255, 0, 51));
      final r = detectorInput(photo, 4);
      expect(r.box.resizedWidth, 4);
      expect(r.box.resizedHeight, 2);
      expect(r.input, hasLength(4 * 4 * 3));
      expect(r.input.sublist(0, 3), [1.0, -1.0, closeTo((51 - 127.5) / 127.5, 1e-6)]);
      expect(r.input.sublist(2 * 4 * 3).every((v) => v == 0), isTrue, reason: '下の半分は余白');
    });
  });

  group('読み取りの手順', () {
    // アンカーは横に10個ずつ2段（幅 0.04・高さ 0.06 の牌）。
    // 0〜9 番は真ん中の高さ（写真全体を読む1回目で使う）、10〜19 番は上のほう
    // （切り抜いた横長の画像は入力の上に寄せて置かれるので、2回目で使う）
    final anchors = Float32List.fromList([
      for (final y in [0.5, 0.2])
        for (var i = 0; i < 10; i++) ...[y, 0.05 + i * 0.1, 0.06, 0.04]
    ]);
    const labels = ['1m', '2m', '3m'];
    const classifierLabels = ['1m', '2m', '3m', '7z', 'bg'];
    final photo = img.Image(width: 100, height: 100);

    test('2回読み取り、分類モデルの答えで種類を置き換え、牌でないものを捨てて左から並べる', () async {
      final runner = _FakeRunner(
        [
          // 1回目: 写真の左のほうに3枚。背景のクラス（0番）は使わない
          [(3, 2), (2, 1), (1, 3)],
          // 2回目（切り抜いたあと）: 4枚見つかる（左から順）
          [(11, 1), (13, 1), (15, 1), (17, 1)],
        ],
        // 分類モデルには、確信度の高い順（上に書いた順）に聞かれる
        ['7z', 'bg', '2m', '1m'],
        classifierLabels,
        numAnchors: 20,
        numClasses: 4,
      );
      var pauses = 0;
      final tiles = await recognizeTiles(
        photo: photo,
        runner: runner,
        anchors: anchors,
        labels: labels,
        classifierLabels: classifierLabels,
        detectionThreshold: TileModelAssets.detectionThreshold,
        pause: () async => pauses++,
      );
      expect(runner.detectInputs, hasLength(2), reason: '写真全体と、牌のまわりを切り抜いたもの');
      expect(runner.classifyCalls, 4);
      expect(tiles, ['7z', '2m', '1m'], reason: '2枚目は「牌ではない」なので捨てる');
      expect(pauses, greaterThan(0), reason: '読み取り中の表示を描き直す時間を作る');
    });

    test('2回目に見つかる牌が大きく減ったら、1回目の結果を使う', () async {
      final runner = _FakeRunner(
        [
          [(1, 1), (2, 2), (3, 3)],
          [(15, 1)],
        ],
        ['3m', '2m', '1m'],
        classifierLabels,
        numAnchors: 20,
        numClasses: 4,
      );
      final tiles = await recognizeTiles(
        photo: photo,
        runner: runner,
        anchors: anchors,
        labels: labels,
        classifierLabels: classifierLabels,
        detectionThreshold: TileModelAssets.detectionThreshold,
      );
      expect(tiles, ['3m', '2m', '1m'], reason: '1回目の3枚を、左から順に');
      expect(runner.detectInputs, hasLength(2));
      expect(runner.classifyCalls, 3);
    });

    test('牌が見つからなければ空', () async {
      final runner = _FakeRunner([[]], [], classifierLabels, numAnchors: 20, numClasses: 4);
      final tiles = await recognizeTiles(
        photo: photo,
        runner: runner,
        anchors: anchors,
        labels: labels,
        classifierLabels: classifierLabels,
        detectionThreshold: TileModelAssets.detectionThreshold,
      );
      expect(tiles, isEmpty);
      expect(runner.detectInputs, hasLength(1));
    });
  });

  group('アプリ版と同じ設定・同じモデル', () {
    test('モデルの場所としきい値は、アプリ版（TfliteTileRecognizer）と同じ', () {
      expect(TileModelAssets.detector, TfliteTileRecognizer.modelAsset);
      expect(TileModelAssets.anchors, TfliteTileRecognizer.anchorsAsset);
      expect(TileModelAssets.labels, TfliteTileRecognizer.labelsAsset);
      expect(TileModelAssets.classifier, TfliteTileRecognizer.classifierAsset);
      expect(TileModelAssets.classifierLabels, TfliteTileRecognizer.classifierLabelsAsset);
      expect(TileModelAssets.detectionThreshold, TfliteTileRecognizer.detectionThreshold);
    });

    test('Web 版の分類モデルは、今のアプリ版の分類モデルから作ったもの', () {
      final source = File(TileModelAssets.classifier).readAsBytesSync();
      final recorded = File('web/models/tile_classifier_web.source.txt').readAsStringSync().trim();
      expect(recorded, '${source.length} ${fnv1a(source).toRadixString(16).padLeft(8, '0')}',
          reason: '分類モデルを作り直したら python tools/tile_model/make_web_classifier.py を実行する');
      // 形の情報だけを変えた写しなので、大きさはほぼ同じ
      final web = File('web/models/tile_classifier_web.tflite').lengthSync();
      expect((web - source.length).abs(), lessThan(4096));
    });
  });

  group('Web 版の作り', () {
    test('index.html は LiteRT.js を初めて使うときにだけ読み込み、場所は相対で書く', () {
      final html = File('web/index.html').readAsStringSync();
      expect(html, contains('window.mahjongLoadTileModels'));
      expect(html, contains("new URL('litert/tile_models.js', base)"));
      expect(html, isNot(contains('<script src="litert/')), reason: 'ふだんの起動では読み込まない');
      expect(html, isNot(contains("'/litert")), reason: '絶対パスにしない（/<リポジトリ名>/ の下で動くように）');
    });

    test('LiteRT.js の版は固定し、外のサーバー（CDN）からは読み込まない', () {
      final pkg = File('tools/web_litert/package.json').readAsStringSync();
      expect(pkg, contains('"@litertjs/core": "2.6.0"'));
      expect(File('tools/web_litert/package-lock.json').existsSync(), isTrue);
      final glue = File('tools/web_litert/src/tile_models.js').readAsStringSync();
      expect(glue, isNot(contains('http')));
      expect(glue, contains("accelerator: 'wasm'"));
      expect(File('.gitignore').readAsStringSync(), contains('web/litert/'));
    });

    test('公開の手順（GitHub Actions）で、Web 版のビルドの前に LiteRT.js を用意する', () {
      final yml = File('.github/workflows/deploy-pages.yml').readAsStringSync();
      final prepare = yml.indexOf('working-directory: tools/web_litert');
      expect(prepare, greaterThan(0));
      expect(prepare, lessThan(yml.indexOf('flutter build web')));
    });

    test('テスト（Web 版ではない環境）では、Web 版用の読み取りは選ばれない', () {
      expect(cameraFirstUseDownloadMb, isNull);
    });
  });
}
