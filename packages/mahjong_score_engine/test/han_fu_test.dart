import 'package:mahjong_score_engine/mahjong_score_engine.dart';
import 'package:test/test.dart';

/// 翻・符から点数を出す簡易入力（ScoreCalculator.calculateFromHanFu）
void main() {
  ScoreResult calc(int han, int fu,
          {bool tsumo = false,
          bool dealer = false,
          int yakuman = 0,
          int honba = 0,
          int sticks = 0,
          ScoreRules rules = const ScoreRules()}) =>
      ScoreCalculator.calculateFromHanFu(
        han: han,
        fu: fu,
        yakuman: yakuman,
        isTsumo: tsumo,
        playerWind: dealer ? '1z' : '2z',
        honba: honba,
        riichiSticks: sticks,
        rules: rules,
      );

  String score(ScoreResult r, {bool tsumo = false, bool dealer = false}) =>
      ScoreCalculator.formatScore(r, isDealer: dealer, isTsumo: tsumo);

  group('点数表どおり', () {
    test('子のロン', () {
      expect(calc(1, 30).totalScore, 1000);
      expect(calc(2, 25).totalScore, 1600);
      expect(calc(3, 40).totalScore, 5200);
      expect(calc(4, 30).totalScore, 7700);
      expect(calc(3, 60).totalScore, 7700);
      expect(calc(2, 110).totalScore, 7100);
    });

    test('親のロン', () {
      expect(calc(1, 30, dealer: true).totalScore, 1500);
      expect(calc(3, 30, dealer: true).totalScore, 5800);
      expect(calc(4, 30, dealer: true).totalScore, 11600);
    });

    test('ツモ', () {
      final pinfuTsumo = calc(2, 20, tsumo: true);
      expect(score(pinfuTsumo, tsumo: true), '400-700');
      expect(pinfuTsumo.totalScore, 1500);
      expect(score(calc(3, 40, tsumo: true, dealer: true), tsumo: true, dealer: true), '2600オール');
      expect(score(calc(4, 25, tsumo: true), tsumo: true), '1600-3200');
    });

    test('満貫以上は符に関係ない', () {
      expect(calc(5, 0).totalScore, 8000);
      expect(calc(5, 0).limitName, '満貫');
      expect(calc(4, 40).limitName, '満貫');
      expect(calc(6, 0).totalScore, 12000);
      expect(calc(8, 0).totalScore, 16000);
      expect(calc(11, 0).totalScore, 24000);
      expect(calc(13, 0).totalScore, 32000);
      expect(calc(13, 0).limitName, '数え役満');
      expect(calc(6, 0, dealer: true).totalScore, 18000);
    });

    test('切り上げ満貫・数え役満のルール', () {
      const kiriage = ScoreRules(kiriageMangan: true);
      expect(calc(4, 30, rules: kiriage).totalScore, 8000);
      expect(calc(3, 60, rules: kiriage).limitName, '満貫');
      const noKazoe = ScoreRules(kazoeYakuman: false);
      expect(calc(13, 0, rules: noKazoe).totalScore, 24000);
      expect(calc(13, 0, rules: noKazoe).limitName, '三倍満');
    });

    test('役満', () {
      final r = calc(0, 0, yakuman: 1);
      expect(r.isYakuman, isTrue);
      expect(r.totalScore, 32000);
      expect(r.limitName, '役満');
      expect(calc(0, 0, yakuman: 2).totalScore, 64000);
      expect(calc(0, 0, yakuman: 2, dealer: true).totalScore, 96000);
      // ダブル役満なしのルールでは1倍まで
      expect(calc(0, 0, yakuman: 2, rules: const ScoreRules(doubleYakuman: false)).totalScore, 32000);
    });
  });

  test('本場・供託も付く', () {
    final r = calc(1, 30, honba: 2, sticks: 1);
    expect(r.totalScore, 1000);
    expect(r.paymentDetails.loserPayment, 1600);
    expect(r.paymentDetails.winnerGain, 2600);
    final t = calc(1, 30, tsumo: true, honba: 1);
    expect(t.paymentDetails.playerPayments!.map((p) => p.amount), [600, 400, 400]);
  });

  test('3人打ちのツモ（ツモ損・折半）', () {
    const loss = ScoreRules(playerCount: 3);
    const split = ScoreRules(playerCount: 3, sanmaTsumoSplit: true);
    final a = calc(5, 0, tsumo: true, rules: loss);
    expect(a.paymentDetails.playerPayments!.map((p) => p.amount), [4000, 2000]);
    final b = calc(5, 0, tsumo: true, rules: split);
    expect(b.paymentDetails.playerPayments!.map((p) => p.amount), [5000, 3000]);
  });

  test('ありえない翻・符は計算しない', () {
    expect(calc(0, 30).isValid, isFalse);
    expect(calc(2, 35).isValid, isFalse);
    expect(calc(2, 20).error, contains('ツモ'));
    expect(calc(1, 20, tsumo: true).error, contains('2翻以上'));
    expect(calc(1, 25).error, contains('2翻以上'));
    expect(calc(2, 20, tsumo: true).isValid, isTrue);
  });

  test('結果の表示用の値', () {
    final r = calc(3, 40);
    expect(r.han, 3);
    expect(r.fu, 40);
    expect(r.yakuList.single.name, '翻・符で入力');
    expect(r.fuDetails, isEmpty);
    final m = calc(6, 30);
    expect(m.fu, 0, reason: '5翻以上は符を使わない');
  });
}
