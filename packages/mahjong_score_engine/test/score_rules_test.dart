import 'package:mahjong_score_engine/mahjong_score_engine.dart';
import 'package:test/test.dart';

List<Tile> t(String s) {
  final out = <Tile>[];
  final buf = <String>[];
  for (final ch in s.split('')) {
    if ('mpsz'.contains(ch)) {
      for (final n in buf) {
        out.add(n == '0' ? '5${ch}r' : '$n$ch');
      }
      buf.clear();
    } else {
      buf.add(ch);
    }
  }
  return out;
}

ScoreResult calc(String hand, String win,
    {String type = 'ron',
    List<Meld> melds = const [],
    bool riichi = false,
    String dora = '',
    String round = '1z',
    String seat = '2z',
    ScoreRules rules = const ScoreRules()}) {
  return ScoreCalculator.calculate(
    WinInput(
      handTiles: t(hand),
      winningTile: t(win).single,
      melds: melds,
      winType: type,
      isRiichi: riichi,
      isIppatsu: false,
      isDoubleRiichi: false,
      doraTiles: t(dora),
      uraDoraTiles: const [],
      roundWind: round,
      playerWind: seat,
    ),
    rules: rules,
  );
}

void main() {
  test('喰いタン: なしのルールでは鳴いた断么九は役にならない', () {
    const meld = Meld(type: MeldType.chi, tiles: ['2s', '3s', '4s']);
    final ari = calc('234m567m456p6s', '6s', melds: [meld]);
    expect(ari.yakuList.map((y) => y.name), contains('断么九'));
    final nashi = calc('234m567m456p6s', '6s', melds: [meld], rules: const ScoreRules(kuitan: false));
    expect(nashi.isValid, isFalse); // 役がない
    // 門前の断么九はどちらでも役になる
    final menzen = calc('234m567m456p234s6s', '6s', rules: const ScoreRules(kuitan: false));
    expect(menzen.yakuList.map((y) => y.name), contains('断么九'));
  });

  test('切り上げ満貫: 4翻30符（子 7700点）が満貫 8000点になる', () {
    // 立直 平和 ドラ2（表示牌 1m→2m・8p→9p）= 4翻30符（ロン）
    const hand = '23m456m789p234s55s';
    final normal = calc(hand, '4m', riichi: true, dora: '1m8p');
    expect(normal.han, 4);
    expect(normal.fu, 30);
    expect(normal.totalScore, 7700);
    final kiriage = calc(hand, '4m', riichi: true, dora: '1m8p', rules: const ScoreRules(kiriageMangan: true));
    expect(kiriage.totalScore, 8000);
    expect(kiriage.limitName, '満貫');
  });

  test('数え役満: なしのルールでは13翻以上も三倍満', () {
    // 立直1 ツモ1 清一色6 一盃口1 一気通貫2 ドラ3 = 14翻
    final ari = calc('1122334567899m', '9m', type: 'tsumo', riichi: true, dora: '8m');
    expect(ari.limitName, '数え役満');
    final nashi = calc('1122334567899m', '9m',
        type: 'tsumo', riichi: true, dora: '8m', rules: const ScoreRules(kazoeYakuman: false));
    expect(nashi.limitName, '三倍満');
    expect(nashi.totalScore, 24000);
  });

  test('ダブル役満: なしのルールでは四暗刻単騎も役満1倍', () {
    final ari = calc('111m222p333s666z5z', '5z');
    expect(ari.totalScore, 64000);
    final nashi = calc('111m222p333s666z5z', '5z', rules: const ScoreRules(doubleYakuman: false));
    expect(nashi.totalScore, 32000);
    expect(nashi.yakumanCount, 1);
    // 役満の複合（四暗刻単騎＋大三元＋字一色）も1倍
    final fukugou = calc('555z666z777z111z2z', '2z', rules: const ScoreRules(doubleYakuman: false));
    expect(fukugou.totalScore, 32000);
  });

  test('連風牌の雀頭: 2符のルール', () {
    // 東場の東家（親）が東の単騎待ち。門前ロン: 20+10 / 9p暗刻8 / 雀頭 / 単騎2
    const hand = '234m567m999p345s1z';
    final four = calc(hand, '1z', seat: '1z', riichi: true);
    final two = calc(hand, '1z', seat: '1z', riichi: true, rules: const ScoreRules(renpuuPairFu: 2));
    expect(four.fuDetails.map((f) => f.toString()), contains('雀頭(連風牌): 4符'));
    expect(two.fuDetails.map((f) => f.toString()), contains('雀頭(連風牌): 2符'));
    expect(four.fu, 50); // 44 → 50
    expect(two.fu, 50); // 42 → 50
  });
}
