import 'package:mahjong_score_engine/mahjong_score_engine.dart';
import 'package:test/test.dart';

const sanma = ScoreRules(playerCount: 3);

WinInput input(List<Tile> hand, Tile win,
        {String type = 'tsumo',
        String seat = '2z',
        List<Meld> melds = const [],
        List<Tile> dora = const [],
        int nuki = 0,
        bool riichi = false}) =>
    WinInput(
      handTiles: hand,
      winningTile: win,
      melds: melds,
      winType: type,
      isRiichi: riichi,
      isIppatsu: false,
      isDoubleRiichi: false,
      doraTiles: dora,
      uraDoraTiles: const [],
      roundWind: '1z',
      playerWind: seat,
      nukiDora: nuki,
    );

/// 筒子・索子だけの平和の手（23p の両面待ち）
const pinfu = ['2p', '3p', '4p', '5p', '6p', '7s', '8s', '9s', '2s', '3s', '4s', '5s', '5s'];

void main() {
  group('ツモの支払い', () {
    test('ツモ損: 子の満貫ツモは 親4000・子2000 の 6000点（北家の分はもらえない）', () {
      // 立直 ツモ 平和 ドラ2（表示牌 1p→2p、6s→7s） = 5翻 満貫
      final r = ScoreCalculator.calculate(
          input(pinfu, '1p', riichi: true, dora: ['1p', '6s']), rules: sanma);
      expect(r.limitName, '満貫');
      final pays = r.paymentDetails.playerPayments!;
      expect(pays.map((p) => p.playerId), [0, 2]); // 東家と西家だけが払う
      expect(pays.map((p) => p.amount), [4000, 2000]);
      expect(r.totalScore, 6000);
      expect(ScoreCalculator.formatScore(r, isDealer: false, isTsumo: true), '2000-4000');
    });

    test('折半: 北家の分を2人で分ける（子の満貫ツモは 親5000・子3000）', () {
      final r = ScoreCalculator.calculate(input(pinfu, '1p', riichi: true, dora: ['1p', '6s']),
          rules: const ScoreRules(playerCount: 3, sanmaTsumoSplit: true));
      expect(r.paymentDetails.playerPayments!.map((p) => p.amount), [5000, 3000]);
      expect(r.totalScore, 8000);
    });

    test('親のツモは2人から（満貫 4000オール）。本場は各100点', () {
      final r = ScoreCalculator.calculate(
          input(pinfu, '1p', seat: '1z', riichi: true, dora: ['1p', '6s']),
          rules: sanma,
          honba: 2);
      expect(r.paymentDetails.playerPayments!.map((p) => p.amount), [4200, 4200]);
      expect(r.paymentDetails.honbaGain, 400);
      expect(ScoreCalculator.formatScore(r, isDealer: true, isTsumo: true), '4000オール');
    });

    test('ロンは4人打ちと同じ', () {
      final r = ScoreCalculator.calculate(input(pinfu, '4p', type: 'ron'), rules: sanma);
      expect(r.totalScore, 1000);
    });
  });

  group('北抜き・ドラ', () {
    test('抜いた北1枚につき抜きドラ1', () {
      final r = ScoreCalculator.calculate(input(pinfu, '1p', nuki: 2), rules: sanma);
      expect({for (final y in r.yakuList) y.name: y.han}['抜きドラ'], 2);
    });

    test('ドラ表示牌が西なら、抜いた北もドラになる', () {
      final r = ScoreCalculator.calculate(input(pinfu, '1p', nuki: 1, dora: ['3z']), rules: sanma);
      final m = {for (final y in r.yakuList) y.name: y.han};
      expect(m['抜きドラ'], 1);
      expect(m['ドラ'], 1);
    });

    test('3人打ちのドラ表示牌は 1萬→9萬、9萬→1萬', () {
      expect(getNextDora('1m', sanma: true), '9m');
      expect(getNextDora('9m', sanma: true), '1m');
      expect(getNextDora('1m'), '2m'); // 4人打ちは普段どおり
      // 9萬の刻子があり、表示牌が1萬ならドラ3
      final r = ScoreCalculator.calculate(
          input(['9m', '9m', '9m', '2p', '3p', '4p', '5p', '6p', '7s', '8s', '9s', '5s', '5s'], '7p',
              riichi: true, dora: ['1m']),
          rules: sanma);
      expect({for (final y in r.yakuList) y.name: y.han}['ドラ'], 3);
    });
  });

  group('3人打ちで使えないもの', () {
    test('二萬〜八萬は使えない', () {
      final r = ScoreCalculator.calculate(
          input(['2m', '3m', '4m', '5p', '6p', '7s', '8s', '9s', '2s', '3s', '4s', '5s', '5s'], '4p'),
          rules: sanma);
      expect(r.error, contains('二萬〜八萬'));
    });

    test('チーはできない', () {
      final r = ScoreCalculator.calculate(
          input(['5p', '6p', '7s', '8s', '9s', '2s', '3s', '4s', '5s', '5s'], '4p',
              melds: const [Meld(type: MeldType.chi, tiles: ['2p', '3p', '4p'])]),
          rules: sanma);
      expect(r.error, contains('チー'));
    });

    test('自風に北はない・4人打ちでは抜きドラは使えない', () {
      expect(ScoreCalculator.calculate(input(pinfu, '1p', seat: '4z'), rules: sanma).error,
          contains('自風'));
      expect(ScoreCalculator.calculate(input(pinfu, '1p', nuki: 1)).error, contains('3人打ちだけ'));
    });

    test('抜いた北も含めて同じ牌は4枚まで', () {
      final r = ScoreCalculator.calculate(
          input(['4z', '4z', '2p', '3p', '4p', '5p', '6p', '7p', '7s', '8s', '9s', '5s', '5s'], '1p',
              nuki: 3),
          rules: sanma);
      expect(r.error, contains('5枚以上'));
    });
  });
}
