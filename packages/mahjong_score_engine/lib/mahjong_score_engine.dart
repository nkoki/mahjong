/// 麻雀点数計算エンジン（4人打ち・リーチ麻雀）
///
/// 使い方:
/// ```dart
/// final result = ScoreCalculator.calculate(input, honba: 1, riichiSticks: 0);
/// ```
library mahjong_score_engine;

export 'src/types.dart';
export 'src/tile_utils.dart';
export 'src/decomposer.dart';
export 'src/hand_context.dart';
export 'src/yaku_judge.dart';
export 'src/fu_calculator.dart';
export 'src/score_calculator.dart';
