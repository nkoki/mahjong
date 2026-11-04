import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_app/features/session/domain/models.dart';
import 'package:mahjong_app/features/session/domain/session_logic.dart';
import 'package:mahjong_score_engine/mahjong_score_engine.dart';

GameSession newGame({GameSettings settings = const GameSettings()}) =>
    GameSession.start(id: 't', playerNames: ['A', 'B', 'C', 'D'], settings: settings);

ScoreResult score(WinInput input, GameSession s) => ScoreCalculator.calculate(
    input, honba: s.honba, riichiSticks: s.riichiSticks);

WinInput pinfu({required String type, required String seat, bool riichi = false}) =>
    WinInput(
      handTiles: const ['2m', '3m', '4m', '5m', '6m', '7p', '8p', '9p', '2s', '3s', '4s', '5s', '5s'],
      winningTile: '1m',
      melds: const [],
      winType: type,
      isRiichi: riichi,
      isIppatsu: false,
      isDoubleRiichi: false,
      doraTiles: const [],
      uraDoraTiles: const [],
      roundWind: '1z',
      playerWind: seat,
    );

void main() {
  test('立直で1000点供託、取り消しで戻る', () {
    var s = newGame();
    s = SessionLogic.toggleRiichi(s, 1);
    expect(s.scores[1], 24000);
    expect(s.riichiSticks, 1);
    s = SessionLogic.toggleRiichi(s, 1);
    expect(s.scores[1], 25000);
    expect(s.riichiSticks, 0);
  });

  test('子のロン和了: 点数移動・供託獲得・親流れ', () {
    var s = newGame();
    s = SessionLogic.toggleRiichi(s, 1); // B 立直
    final input = pinfu(type: 'ron', seat: s.seatWindTileOf(1), riichi: true);
    final r = score(input, s);
    expect(r.isValid, isTrue, reason: r.error);
    s = SessionLogic.applyWin(s, winner: 1, loser: 2, result: r, description: '');
    // 立直 平和 2翻30符 = 2000
    expect(s.scores, [25000, 24000 + 2000 + 1000, 23000, 25000]);
    expect(s.riichiSticks, 0);
    expect(s.roundIndex, 1);
    expect(s.dealer, 1);
    expect(s.honba, 0);
    expect(s.records.single.deltas, [0, 2000, -2000, 0]);
  });

  test('親のツモ和了は連荘して本場+1', () {
    var s = newGame();
    final r = score(pinfu(type: 'tsumo', seat: '1z'), s);
    s = SessionLogic.applyWin(s, winner: 0, result: r, description: '');
    // 門前ツモ 平和 2翻20符 親 700オール
    expect(s.scores, [27100, 24300, 24300, 24300]);
    expect(s.roundIndex, 0);
    expect(s.honba, 1);
  });

  test('子のツモで親が多く払う（本場込み）', () {
    var s = newGame().copyWith(honba: 1);
    final r = score(pinfu(type: 'tsumo', seat: s.seatWindTileOf(2)), s);
    s = SessionLogic.applyWin(s, winner: 2, result: r, description: '');
    // 2翻20符 子ツモ 400-700 + 1本場
    expect(s.scores, [25000 - 800, 25000 - 500, 25000 + 1800, 25000 - 500]);
  });

  test('通常流局: ノーテン罰符と親流れ', () {
    var s = newGame();
    s = SessionLogic.applyDraw(s,
        type: DrawType.exhaustive, tenpai: [false, true, false, false]);
    expect(s.scores, [24000, 28000, 24000, 24000]);
    expect(s.roundIndex, 1);
    expect(s.honba, 1);
  });

  test('途中流局は親の連荘・供託持ち越し', () {
    var s = newGame();
    s = SessionLogic.toggleRiichi(s, 3);
    s = SessionLogic.applyDraw(s,
        type: DrawType.kyuushu, tenpai: [false, false, false, false]);
    expect(s.roundIndex, 0);
    expect(s.honba, 1);
    expect(s.riichiSticks, 1);
    expect(s.riichi, [false, false, false, false]);
  });

  test('流し満貫（子）', () {
    var s = newGame();
    s = SessionLogic.applyDraw(s,
        type: DrawType.nagashiMangan,
        tenpai: [true, false, false, false],
        nagashiPlayer: 2);
    expect(s.scores, [21000, 23000, 33000, 23000]);
    expect(s.roundIndex, 0); // 親テンパイで連荘
  });

  test('東風戦は東4局の親流れで終局し、ウマ・オカを計算', () {
    var s = newGame(settings: const GameSettings(tonpuu: true));
    for (var i = 0; i < 4; i++) {
      s = SessionLogic.applyDraw(s,
          type: DrawType.exhaustive, tenpai: [false, false, false, false]);
    }
    expect(s.finished, isTrue);
    final results = s.finalResults;
    // 全員25000点 → 起家が1位（同点は起家優先）
    expect(results.first.player, 0);
    expect(results.first.point, closeTo(-5 + 20 + 20, 0.001));
    expect(results.fold<double>(0, (a, r) => a + r.point), closeTo(0, 0.001));
  });

  test('トビで終局・元に戻す', () {
    var s = newGame().copyWith(scores: [25000, 25000, 1000, 49000]);
    final before = s;
    s = SessionLogic.applyDraw(s,
        type: DrawType.exhaustive, tenpai: [true, true, false, true]);
    expect(s.finished, isTrue);
    expect(SessionLogic.undo(s).scores, before.scores);
  });
}
