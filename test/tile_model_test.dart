import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mahjong_app/features/camera/tile_classifier.dart';
import 'package:mahjong_app/features/camera/tile_detection.dart';

/// 学習したモデルのファイルと、アプリの後処理が合っているかを確かめる
void main() {
  test('アプリに入れたモデル・アンカー・クラス名の大きさが合っている', () {
    final labels = File('assets/models/tile_labels.txt')
        .readAsLinesSync()
        .where((l) => l.trim().isNotEmpty)
        .toList();
    expect(labels, hasLength(37));
    expect(labels, containsAll(['1m', '9p', '7s', '1z', '7z', '5mr', '5pr', '5sr']));
    final anchors = File('assets/models/tile_anchors.bin').readAsBytesSync();
    expect(anchors.lengthInBytes % 16, 0);
    final values = Uint8List.fromList(anchors).buffer.asFloat32List();
    // アンカーは入力画像を 1 とした割合（中心は 0〜1）
    for (var i = 0; i < values.length; i += 4) {
      expect(values[i], inInclusiveRange(0, 1));
      expect(values[i + 1], inInclusiveRange(0, 1));
    }
    expect(File('assets/models/tile_detector.tflite').lengthSync(), greaterThan(1000000));
  });

  test('モデルの生の出力から求めた箱が、学習の道具（Python）で求めたものと同じ', () {
    // tools/tile_model/evaluate.py --dump-fixture で作ったデータ
    final f = jsonDecode(File('test/fixtures/tile_decode_fixture.json').readAsStringSync())
        as Map<String, dynamic>;
    List<double> nums(String k) => (f[k] as List).map((e) => (e as num).toDouble()).toList();
    final labels = (f['labels'] as List).cast<String>();
    final result = decodeDetections(
      rawBoxes: nums('raw_boxes'),
      rawScores: nums('raw_scores'),
      anchors: nums('anchors'),
      labels: labels,
      scoreThreshold: 0,
    );
    final expected = (f['expected'] as List).cast<Map<String, dynamic>>();
    expect(result, hasLength(expected.length));
    for (var i = 0; i < expected.length; i++) {
      final e = expected[i], d = result[i];
      expect(d.tile, e['tile']);
      expect(d.score, closeTo(e['score'] as num, 1e-5));
      expect(d.left, closeTo(e['left'] as num, 1e-4));
      expect(d.top, closeTo(e['top'] as num, 1e-4));
      expect(d.right, closeTo(e['right'] as num, 1e-4));
      expect(d.bottom, closeTo(e['bottom'] as num, 1e-4));
    }
  });

  group('分類モデル（牌を1枚ずつ見分け直す）', () {
    test('アプリに入れた分類モデルとクラス名が合っている', () {
      final labels = File('assets/models/tile_classifier_labels.txt')
          .readAsLinesSync()
          .where((l) => l.trim().isNotEmpty)
          .toList();
      final detectorLabels = File('assets/models/tile_labels.txt')
          .readAsLinesSync()
          .where((l) => l.trim().isNotEmpty)
          .toList();
      // 37種類の牌と、最後に「牌ではない」
      expect(labels, hasLength(38));
      expect(labels.last, TileClassifierInput.notATile);
      expect(labels.take(37).toSet(), detectorLabels.toSet());
      expect(File('assets/models/tile_classifier.tflite').lengthSync(), greaterThan(100000));
    });

    // tools/tile_model/tile_crop.py --dump-fixture test/fixtures で作ったデータ
    final f = jsonDecode(File('test/fixtures/classifier_crop_fixture.json').readAsStringSync())
        as Map<String, dynamic>;
    final cases = (f['cases'] as List).cast<Map<String, dynamic>>();
    final photo = img.decodePng(File('test/fixtures/classifier_crop_image.png').readAsBytesSync())!;

    test('入力の大きさが学習の道具と同じ', () {
      expect(TileClassifierInput.height, f['input_height']);
      expect(TileClassifierInput.width, f['input_width']);
      expect(photo.width, f['image_width']);
      expect(photo.height, f['image_height']);
    });

    TileDetection box(Map<String, dynamic> c) {
      final b = (c['box'] as List).map((e) => (e as num).toDouble()).toList();
      return TileDetection('1m', 0.9, b[0], b[1], b[2], b[3]);
    }

    test('切り抜く範囲と回すかどうかが、学習の道具（Python）と同じ', () {
      for (final c in cases) {
        final r = classifierCropRect(box(c), photo.width, photo.height);
        expect([r.x, r.y, r.width, r.height, r.rotate], [c['x'], c['y'], c['width'], c['height'], c['rotate']],
            reason: '${c['box']}');
      }
      expect(cases.where((c) => c['rotate'] == true), isNotEmpty, reason: '横向きの牌の例も確かめる');
    });

    test('分類モデルへの入力（切り抜き・回転・縮小）が、学習の道具とほぼ同じ', () {
      const h = TileClassifierInput.height, w = TileClassifierInput.width;
      for (final c in cases) {
        final input = classifierInput(photo, box(c));
        expect(input, hasLength(h * w * 3));
        // 4×3 のマスごとの平均を比べる（回す向きや上下左右が違えば大きくずれる）
        final grid = List<double>.filled(4 * 3 * 3, 0);
        for (var y = 0; y < h; y++) {
          for (var x = 0; x < w; x++) {
            for (var ch = 0; ch < 3; ch++) {
              grid[((y * 4 ~/ h) * 3 + (x * 3 ~/ w)) * 3 + ch] += input[(y * w + x) * 3 + ch];
            }
          }
        }
        final expected = (c['input_grid'] as List).map((e) => (e as num).toDouble()).toList();
        for (var i = 0; i < grid.length; i++) {
          expect(grid[i] / (h ~/ 4 * (w ~/ 3)), closeTo(expected[i], 3), reason: '${c['box']} のマス $i');
        }
      }
    });

    test('分類モデルの答えで種類を置き換え、位置と確信度はそのまま。牌ではないなら捨てる', () {
      const d = TileDetection('8m', 0.8, 0.1, 0.2, 0.3, 0.4);
      final r = relabelWithClassifier(d, [0.1, 0.7, 0.2], ['8m', '6m', '9m'])!;
      expect(r.tile, '6m');
      expect([r.score, r.left, r.top, r.right, r.bottom], [0.8, 0.1, 0.2, 0.3, 0.4]);
      expect(() => relabelWithClassifier(d, [1], ['1m', '2m']), throwsArgumentError);
      // 「牌ではない」と答えたら捨てる
      expect(relabelWithClassifier(d, [0.2, 0.1, 0.7], ['8m', '6m', 'bg']), isNull);
    });
  });
}
