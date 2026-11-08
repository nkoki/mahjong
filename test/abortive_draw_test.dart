import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_app/features/session/domain/models.dart';
import 'package:mahjong_app/features/session/domain/session_logic.dart';

import 'player_stats_test.dart' show start, win;

/// 途中流局（四家立直など）
void main() {
  test('四家立直: 4人の立直棒（供託4本）はすべて場に残り、親はそのままで1本場になる', () {
    var s = start('x', ['A', 'B', 'C', 'D']);
    for (var p = 0; p < 4; p++) {
      s = SessionLogic.toggleRiichi(s, p);
    }
    expect(s.riichiSticks, 4);
    expect(s.scores, [24000, 24000, 24000, 24000]);
    final next = SessionLogic.applyDraw(s, type: DrawType.suucha, tenpai: [false, false, false, false]);
    expect(next.riichiSticks, 4, reason: '供託は次の局に持ち越し');
    expect(next.scores, [24000, 24000, 24000, 24000], reason: 'テンパイ料のやり取りはない');
    expect(next.roundLabel, '東1局 1本場', reason: '親は連荘、本場が1つ増える');
    expect(next.riichi, [false, false, false, false], reason: '次の局は立直なしから');

    // 次の局で和了した人が、供託4本（4,000点）をまとめて受け取る
    final won = win(next, 1, loser: 2);
    expect(won.riichiSticks, 0);
    expect(won.scores[1] - next.scores[1], 5200 + 300 + 4000, reason: '和了点 + 1本場300点 + 供託4,000点');
  });
}
