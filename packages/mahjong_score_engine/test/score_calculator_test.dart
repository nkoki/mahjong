import 'package:mahjong_score_engine/mahjong_score_engine.dart';
import 'package:test/test.dart';

/// "123m456p" のような表記を牌リストに展開する（赤5は 0 で表す）
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

ScoreResult calc(
  String hand,
  String win, {
  String type = 'ron',
  List<Meld> melds = const [],
  bool riichi = false,
  bool ippatsu = false,
  bool doubleRiichi = false,
  String dora = '',
  String ura = '',
  String round = '1z',
  String seat = '2z',
  int honba = 0,
  int sticks = 0,
  bool tenho = false,
  bool haitei = false,
  bool rinshan = false,
}) {
  return ScoreCalculator.calculate(
    WinInput(
      handTiles: t(hand),
      winningTile: t(win).single,
      melds: melds,
      winType: type,
      isRiichi: riichi,
      isIppatsu: ippatsu,
      isDoubleRiichi: doubleRiichi,
      doraTiles: t(dora),
      uraDoraTiles: t(ura),
      roundWind: round,
      playerWind: seat,
      isTenho: tenho,
      isHaitei: haitei,
      isRinshan: rinshan,
    ),
    honba: honba,
    riichiSticks: sticks,
  );
}

List<String> names(ScoreResult r) => r.yakuList.map((y) => y.name).toList();

void main() {
  group('基本', () {
    test('立直・平和・ツモ（子）: 3翻20符 700-1300', () {
      final r = calc('23m456m789p234s55s', '1m', type: 'tsumo', riichi: true);
      expect(r.isValid, isTrue, reason: r.error);
      expect(names(r), containsAll(['立直', '門前清自摸和', '平和']));
      expect(r.han, 3);
      expect(r.fu, 20);
      expect(ScoreCalculator.formatScore(r, isDealer: false, isTsumo: true),
          '700-1300');
      expect(r.totalScore, 2700);
    });

    test('平和ロン（子）: 1翻30符 1000点', () {
      final r = calc('23m456m789p234s55s', '4m');
      expect(names(r), ['平和']);
      expect(r.fu, 30);
      expect(r.totalScore, 1000);
    });

    test('立直・嵌張ロン: 1翻40符 1300点', () {
      final r = calc('13m456m789p234s55s', '2m', riichi: true);
      expect(names(r), ['立直']);
      expect(r.fu, 40);
      expect(r.totalScore, 1300);
    });

    test('本場と供託', () {
      final r = calc('13m456m789p234s55s', '2m',
          riichi: true, honba: 2, sticks: 1);
      expect(r.paymentDetails.loserPayment, 1900);
      expect(r.paymentDetails.winnerGain, 2900);
    });

    test('親のツモは オール', () {
      final r = calc('23m456m789p234s55s', '1m',
          type: 'tsumo', riichi: true, seat: '1z', honba: 1);
      // 3翻20符 親 1300オール + 1本場
      expect(ScoreCalculator.formatScore(r, isDealer: true, isTsumo: true),
          '1300オール');
      expect(r.paymentDetails.playerPayments!.map((p) => p.amount),
          [1400, 1400, 1400]);
    });

    test('役なしはエラー', () {
      final r = calc('13m456m789p234s', '2m',
          melds: [const Meld(type: MeldType.pon, tiles: ['9s', '9s', '9s'])],
          dora: '8s');
      expect(r.isValid, isFalse);
    });

    test('鳴いて立直はエラー', () {
      final r = calc('23m456m789p55s', '1m',
          riichi: true,
          melds: [const Meld(type: MeldType.chi, tiles: ['2s', '3s', '4s'])]);
      expect(r.isValid, isFalse);
    });

    test('枚数不正はエラー', () {
      expect(calc('23m456m789p234s5s', '1m').isValid, isFalse);
    });
  });

  group('ドラ', () {
    test('ドラ・赤ドラ・裏ドラ', () {
      // 立直 断么九 ドラ2(表示牌4m→5m) 赤1 裏1(表示牌1s→2s)
      final r = calc('234m067m456p22s68s', '7s',
          riichi: true, dora: '4m', ura: '1s');
      expect(r.isValid, isTrue, reason: r.error);
      final m = {for (final y in r.yakuList) y.name: y.han};
      expect(m['ドラ'], 1);
      expect(m['赤ドラ'], 1);
      expect(m['裏ドラ'], 2);
    });

    test('字牌のドラ表示牌（北→東、中→白）', () {
      expect(getNextDora('4z'), '1z');
      expect(getNextDora('7z'), '5z');
      expect(getNextDora('9m'), '1m');
    });
  });

  group('役', () {
    test('七対子 25符2翻 1600点', () {
      final r = calc('1122m3344p5566s7z', '7z');
      expect(names(r), ['七対子']);
      expect(r.fu, 25);
      expect(r.totalScore, 1600);
    });

    test('二盃口は七対子より優先（高い方）', () {
      final r = calc('112233m445566p7s', '7s', riichi: true);
      expect(names(r), contains('二盃口'));
    });

    test('清一色（門前）は跳満 12000', () {
      final r = calc('1112345678m999m', '9m');
      // 九蓮宝燈は 9m 待ちを含むので役満になる → 別の形で確認
      expect(r.isYakuman, isTrue);
      final r2 = calc('1122334567899m', '9m');
      expect(names(r2), contains('清一色'));
      expect(r2.limitName, isNotNull);
    });

    test('混一色・役牌・対々和（鳴き）', () {
      final r = calc('111m999m22m55z', '5z', melds: [
        const Meld(type: MeldType.pon, tiles: ['7z', '7z', '7z']),
      ]);
      expect(r.isValid, isTrue, reason: r.error);
      expect(names(r), containsAll(['混一色', '役牌 中', '役牌 白', '対々和']));
    });

    test('一気通貫（門前2翻・鳴き1翻）', () {
      final r = calc('123456789m23p55s', '1p');
      expect(names(r), contains('一気通貫'));
      expect(r.yakuList.firstWhere((y) => y.name == '一気通貫').han, 2);
      final r2 = calc('456789m23p55s', '4p', melds: [
        const Meld(type: MeldType.chi, tiles: ['1m', '2m', '3m']),
      ]);
      expect(r2.yakuList.firstWhere((y) => y.name == '一気通貫').han, 1);
    });

    test('三色同順', () {
      final r = calc('123m123p123s789s5z', '5z', riichi: true);
      expect(names(r), contains('三色同順'));
    });

    test('純全帯么九', () {
      final r = calc('123m789m123p999s1s', '1s', riichi: true);
      expect(names(r), contains('純全帯么九'));
    });

    test('ダブ東', () {
      final r = calc('111z234m456p789s5s', '5s', seat: '1z');
      expect(names(r), containsAll(['役牌 場風東', '役牌 自風東']));
    });

    test('三暗刻 ロンのシャンポンは明刻扱い', () {
      // 111m 222p 333s 55z + 66z で 6z ロン → 6z は明刻なので三暗刻
      final r = calc('111m222p333s55z66z', '6z');
      expect(r.isValid, isTrue, reason: r.error);
      expect(names(r), contains('三暗刻'));
      expect(names(r), isNot(contains('四暗刻')));
    });

    test('高点法: 123123123m は三暗刻ではなく一盃口などの高い方', () {
      final r = calc('111222333m45p99s', '6p', type: 'tsumo');
      expect(r.isValid, isTrue);
      expect(names(r), contains('三暗刻'));
    });
  });

  group('役満', () {
    test('国士無双 32000', () {
      final r = calc('19m19p19s1234566z', '7z');
      expect(names(r), ['国士無双']);
      expect(r.totalScore, 32000);
    });

    test('国士無双十三面 64000', () {
      final r = calc('119m19p19s123456z', '7z');
      expect(names(r), ['国士無双']);
      final r2 = calc('19m19p19s1234567z', '1z');
      expect(names(r2), ['国士無双十三面待ち']);
      expect(r2.totalScore, 64000);
    });

    test('四暗刻（親ツモ）16000オール', () {
      final r = calc('111m222p333s55z66z', '6z', type: 'tsumo', seat: '1z');
      expect(names(r), ['四暗刻']);
      expect(ScoreCalculator.formatScore(r, isDealer: true, isTsumo: true),
          '16000オール');
    });

    test('四暗刻単騎はダブル役満', () {
      final r = calc('111m222p333s666z5z', '5z');
      expect(names(r), ['四暗刻単騎']);
      expect(r.totalScore, 64000);
    });

    test('大三元', () {
      final r = calc('555z666z777z12m99p', '3m');
      expect(names(r), contains('大三元'));
    });

    test('純正九蓮宝燈', () {
      final r = calc('1112345678999m', '5m');
      expect(names(r), ['純正九蓮宝燈']);
      expect(r.yakumanCount, 2);
    });

    test('天和', () {
      final r = calc('23m456m789p234s55s', '1m',
          type: 'tsumo', seat: '1z', tenho: true);
      expect(names(r), contains('天和'));
    });

    test('数え役満', () {
      // 立直 一発 ツモ 清一色 一気通貫 ... ドラ多数
      // 立直1 ツモ1 清一色6 一盃口1 一気通貫2 ドラ3(表示牌8m→9m) = 14翻
      final r = calc('1122334567899m', '9m',
          type: 'tsumo', riichi: true, dora: '8m');
      expect(r.limitName, '数え役満');
      expect(r.totalScore, 32000);
    });
  });

  group('符', () {
    test('暗刻・么九・単騎', () {
      // 門前ロン: 20+10 / 1z暗刻8 / 9p暗刻8 / 単騎2 = 48 → 50符
      final r = calc('111z999p234s567s5m', '5m', round: '2z', seat: '3z',
          riichi: true);
      expect(r.fu, 50);
    });

    test('明槓（么九）16符', () {
      final r = calc('234m567p789s1s', '1s', melds: [
        const Meld(type: MeldType.minkan, tiles: ['7z', '7z', '7z', '7z']),
      ]);
      // 20 + 明槓么九16 + 単騎2 = 38 → 40
      expect(r.fu, 40);
    });
  });
}
