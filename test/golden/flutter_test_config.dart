import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// 画面の画像の比較（ゴールデンテスト）の設定。
///
/// Flutter の版が変わると、文字の縁などの描き方がわずかに変わることがあるので、
/// 画素の [tolerance]（1%）までの違いは同じとみなす。
/// 画面を変えたときは `flutter test --update-goldens test/golden` で画像を作り直す。
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final current = goldenFileComparator;
  if (current is LocalFileComparator) {
    goldenFileComparator = _TolerantComparator(Uri.parse('${current.basedir}golden_test.dart'));
  }
  await testMain();
}

class _TolerantComparator extends LocalFileComparator {
  static const tolerance = 0.01;

  _TolerantComparator(super.testFile);

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(imageBytes, await getGoldenBytes(golden));
    if (result.passed || result.diffPercent <= tolerance) {
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}
