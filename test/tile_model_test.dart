import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
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
}
