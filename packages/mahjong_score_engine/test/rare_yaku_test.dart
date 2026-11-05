import 'package:mahjong_score_engine/mahjong_score_engine.dart';
import 'package:test/test.dart';

import 'score_calculator_test.dart' show t;

/// あまり出ない役・符の境目の点数（期待値は点数表から手で計算した値）
void main() {
  ScoreResult calc(
    String hand,
    String win, {
    String type = 'ron',
    List<Meld> melds = const [],
    bool riichi = false,
    bool doubleRiichi = false,
    String seat = '2z',
    bool rinshan = false,
    bool chankan = false,
    bool haitei = false,
    bool houtei = false,
    bool chiho = false,
  }) =>
      ScoreCalculator.calculate(WinInput(
        handTiles: t(hand),
        winningTile: t(win).single,
        melds: melds,
        winType: type,
        isRiichi: riichi || doubleRiichi,
        isIppatsu: false,
        isDoubleRiichi: doubleRiichi,
        doraTiles: const [],
        uraDoraTiles: const [],
        roundWind: '1z',
        playerWind: seat,
        isRinshan: rinshan,
        isChankan: chankan,
        isHaitei: haitei,
        isHoutei: houtei,
        isChiho: chiho,
      ));

  List<String> names(ScoreResult r) => r.yakuList.map((y) => y.name).toList();
  Meld pon(String s) => Meld(type: MeldType.pon, tiles: t(s));
  Meld chi(String s) => Meld(type: MeldType.chi, tiles: t(s));
  Meld minkan(String s) => Meld(type: MeldType.minkan, tiles: t(s));
  Meld ankan(String s) => Meld(type: MeldType.ankan, tiles: t(s));
  String tsumoScore(ScoreResult r, {bool dealer = false}) =>
      ScoreCalculator.formatScore(r, isDealer: dealer, isTsumo: true);

  group('2翻の役', () {
    test('三色同刻: 2翻50符 3200点', () {
      // 222m・222p は暗刻（4符ずつ）、222s はロンなので明刻（2符）、中の雀頭 2符、門前ロン 10符
      final r = calc('222m222p22s345m77z', '2s');
      expect(r.isValid, isTrue, reason: r.error);
      expect(names(r), ['三色同刻']);
      expect(r.fu, 50);
      expect(r.totalScore, 3200);
    });

    test('三槓子: 2翻70符 4500点', () {
      // 暗槓（中張）16符×2・明槓（中張）8符・単騎 2符。鳴いているので門前ロンの10符は無い
      final r = calc('456s9p', '9p', melds: [ankan('2222p'), minkan('3333s'), ankan('7777m')]);
      expect(r.isValid, isTrue, reason: r.error);
      expect(names(r), ['三槓子']);
      expect(r.fu, 70);
      expect(r.totalScore, 4500);
    });

    test('小三元: 白・發の役牌とあわせて4翻50符で満貫', () {
      final r = calc('555z666z77z234m56p', '4p');
      expect(r.isValid, isTrue, reason: r.error);
      expect(names(r), containsAll(['小三元', '役牌 白', '役牌 發']));
      expect(r.han, 4);
      expect(r.fu, 50);
      expect(r.limitName, '満貫');
      expect(r.totalScore, 8000);
    });

    test('混老頭・対々和・三暗刻: 6翻で跳満', () {
      // 999s はロンで完成したので明刻（暗刻は 111m・999p・111s の3つ）
      final r = calc('111m999p111s99s11z', '9s');
      expect(r.isValid, isTrue, reason: r.error);
      expect(names(r), containsAll(['混老頭', '対々和', '三暗刻']));
      expect(r.han, 6);
      expect(r.limitName, '跳満');
      expect(r.totalScore, 12000);
    });

    test('混全帯么九: 2翻40符 2600点（辺張 2符・場風の雀頭 2符）', () {
      final r = calc('123m789p789s12s11z', '3s');
      expect(r.isValid, isTrue, reason: r.error);
      expect(names(r), ['混全帯么九']);
      expect(r.fu, 40);
      expect(r.totalScore, 2600);
    });
  });

  group('役満', () {
    test('大四喜はダブル役満', () {
      final r = calc('222z333z444z5m', '5m', melds: [pon('111z')]);
      expect(r.isValid, isTrue, reason: r.error);
      expect(names(r), ['大四喜']);
      expect(r.yakumanCount, 2);
      expect(r.totalScore, 64000);
    });

    test('小四喜', () {
      final r = calc('222z333z44z56m', '7m', melds: [pon('111z')]);
      expect(r.isValid, isTrue, reason: r.error);
      expect(names(r), ['小四喜']);
      expect(r.totalScore, 32000);
    });

    test('緑一色', () {
      final r = calc('234s234s666s888s6z', '6z');
      expect(r.isValid, isTrue, reason: r.error);
      expect(names(r), ['緑一色']);
      expect(r.totalScore, 32000);
    });

    test('清老頭', () {
      final r = calc('999m111p999p1s', '1s', melds: [pon('111m')]);
      expect(r.isValid, isTrue, reason: r.error);
      expect(names(r), ['清老頭']);
      expect(r.totalScore, 32000);
    });

    test('四槓子', () {
      final r = calc('9p', '9p',
          melds: [minkan('2222m'), minkan('3333p'), ankan('4444s'), minkan('6666s')]);
      expect(r.isValid, isTrue, reason: r.error);
      expect(names(r), ['四槓子']);
      expect(r.totalScore, 32000);
    });

    test('地和（子のツモ）は 8000-16000', () {
      final r = calc('23m456m789p234s55s', '1m', type: 'tsumo', chiho: true);
      expect(names(r), contains('地和'));
      expect(tsumoScore(r), '8000-16000');
    });

    test('地和は親には付かない', () {
      final r = calc('23m456m789p234s55s', '1m', type: 'tsumo', chiho: true, seat: '1z');
      expect(names(r), isNot(contains('地和')));
      expect(r.isYakuman, isFalse);
    });
  });

  group('状況役', () {
    test('嶺上開花: 門前ツモとあわせて2翻40符 700-1300', () {
      // 暗槓（中張）16符・ツモ 2符・単騎 2符
      final r = calc('123m456m789s5p', '5p', type: 'tsumo', rinshan: true, melds: [ankan('7777p')]);
      expect(r.isValid, isTrue, reason: r.error);
      expect(names(r), containsAll(['門前清自摸和', '嶺上開花']));
      expect(r.han, 2);
      expect(r.fu, 40);
      expect(tsumoScore(r), '700-1300');
    });

    test('槍槓: 平和とあわせて2翻30符 2000点', () {
      final r = calc('23m456m789p234s55s', '4m', chankan: true);
      expect(names(r), containsAll(['槍槓', '平和']));
      expect(r.totalScore, 2000);
    });

    test('槍槓はツモには付かない', () {
      final r = calc('23m456m789p234s55s', '4m', type: 'tsumo', chankan: true);
      expect(names(r), isNot(contains('槍槓')));
    });

    test('海底摸月: 門前ツモとあわせて2翻30符 500-1000', () {
      final r = calc('13m456m789p234s55s', '2m', type: 'tsumo', haitei: true);
      expect(names(r), containsAll(['門前清自摸和', '海底摸月']));
      expect(r.fu, 30);
      expect(tsumoScore(r), '500-1000');
    });

    test('嶺上開花のときは海底摸月を付けない', () {
      final r = calc('123m456m789s5p', '5p', type: 'tsumo', rinshan: true, haitei: true, melds: [ankan('7777p')]);
      expect(names(r), isNot(contains('海底摸月')));
    });

    test('河底撈魚: 1翻40符 1300点', () {
      final r = calc('13m456m789p234s55s', '2m', houtei: true);
      expect(names(r), ['河底撈魚']);
      expect(r.fu, 40);
      expect(r.totalScore, 1300);
    });

    test('ダブル立直は2翻で、立直は重ねて付けない', () {
      final r = calc('13m456m789p234s55s', '2m', doubleRiichi: true);
      expect(names(r), ['ダブル立直']);
      expect(r.han, 2);
      expect(r.totalScore, 2600);
    });
  });

  group('符の境目', () {
    test('鳴いた平和形のロンは20符ではなく30符', () {
      final r = calc('456m678p23s55s', '4s', melds: [chi('234m')]);
      expect(r.isValid, isTrue, reason: r.error);
      expect(names(r), ['断么九']);
      expect(r.fu, 30);
      expect(r.totalScore, 1000);
    });

    test('喰いタンなしのルールでは鳴いた断么九は役にならない', () {
      final r = ScoreCalculator.calculate(
        WinInput(
          handTiles: t('456m678p23s55s'),
          winningTile: '4s',
          melds: [chi('234m')],
          winType: 'ron',
          isRiichi: false,
          isIppatsu: false,
          isDoubleRiichi: false,
          doraTiles: const [],
          uraDoraTiles: const [],
          roundWind: '1z',
          playerWind: '2z',
        ),
        rules: const ScoreRules(kuitan: false),
      );
      expect(r.isValid, isFalse);
    });

    test('符は10符単位に切り上げる（32符 → 40符）', () {
      // 門前ロン 30符 + 嵌張 2符 = 32符
      final r = calc('13m456m789p234s55s', '2m', riichi: true);
      expect(r.fu, 40);
    });

    test('符が110符でも、4翻なら満貫', () {
      expect(ScoreCalculator.basePoints(4, 110, const ScoreRules()).limitName, '満貫');
      expect(ScoreCalculator.basePoints(3, 70, const ScoreRules()).limitName, '満貫');
      expect(ScoreCalculator.basePoints(3, 60, const ScoreRules()).limitName, isNull);
      expect(ScoreCalculator.basePoints(3, 60, const ScoreRules()).base, 1920);
    });
  });
}
