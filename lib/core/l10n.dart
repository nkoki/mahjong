/// 表示の言語（日本語・英語）。
///
/// 文字は `tr('日本語', 'English')` のように、その場所に両方の言語で書く。
/// 言語を切り替えるとアプリ全体を作り直すので、[L10n.isEnglish] はアプリの一番外側（main.dart）で決める。
///
/// 注意: 保存するデータ（局の名前「東1局 0本場」・局の種類など）は日本語のまま保存し、
/// 表示するときに [displayRoundLabel] などで英語にする。
library;

/// 選べる言語
enum AppLanguage {
  ja('ja', '日本語'),
  en('en', 'English');

  /// 保存する値
  final String code;

  /// 選ぶところの表示（どちらの言語でも、その言語の名前で表示する）
  final String label;
  const AppLanguage(this.code, this.label);

  static AppLanguage of(String? code) => code == 'en' ? AppLanguage.en : AppLanguage.ja;
}

class L10n {
  L10n._();

  /// 英語で表示するか（初期値は日本語）
  static bool isEnglish = false;
}

/// 今の言語の文字を返す
String tr(String ja, String en) => L10n.isEnglish ? en : ja;

const _windsEn = ['East', 'South', 'West', 'North'];
const _windsJa = ['東', '南', '西', '北'];

/// 風の名前（0=東）
String windName(int i) => tr(_windsJa[i % 4], _windsEn[i % 4]);

/// 保存した局の名前（例: "東1局 2本場"）を今の言語で表示する（英語: "East 1, 2 honba"）。
/// 読めない形（後から追加した局の名前など）はそのまま返す
String displayRoundLabel(String label) {
  if (!L10n.isEnglish) return label;
  final m = RegExp(r'^([東南西北])(\d)局(?:\s*(\d+)本場)?(.*)$').firstMatch(label);
  if (m == null) return label;
  final wind = _windsEn[_windsJa.indexOf(m.group(1)!)];
  final honba = m.group(3);
  final rest = m.group(4) ?? '';
  return '$wind ${m.group(2)}${honba != null ? ', $honba honba' : ''}$rest';
}

/// 役の名前（点数計算エンジンが返す日本語の名前）を今の言語で表示する
String yakuName(String ja) {
  if (!L10n.isEnglish) return ja;
  final yakuhai = RegExp(r'^役牌 (場風|自風)?(.)$').firstMatch(ja);
  if (yakuhai != null) {
    const honors = {'東': 'East', '南': 'South', '西': 'West', '北': 'North', '白': 'White', '發': 'Green', '中': 'Red'};
    final kind = switch (yakuhai.group(1)) { '場風' => 'Round wind ', '自風' => 'Seat wind ', _ => '' };
    return 'Yakuhai ($kind${honors[yakuhai.group(2)] ?? yakuhai.group(2)})';
  }
  return _yakuEn[ja] ?? ja;
}

const _yakuEn = {
  '立直': 'Riichi',
  'ダブル立直': 'Double riichi',
  '一発': 'Ippatsu',
  '門前清自摸和': 'Menzen tsumo',
  '平和': 'Pinfu',
  '断么九': 'Tanyao',
  '一盃口': 'Iipeikou',
  '二盃口': 'Ryanpeikou',
  '一気通貫': 'Ittsu',
  '三色同順': 'Sanshoku doujun',
  '三色同刻': 'Sanshoku doukou',
  '七対子': 'Chiitoitsu',
  '対々和': 'Toitoi',
  '三暗刻': 'Sanankou',
  '三槓子': 'Sankantsu',
  '小三元': 'Shousangen',
  '混老頭': 'Honroutou',
  '混全帯么九': 'Chanta',
  '純全帯么九': 'Junchan',
  '混一色': 'Honitsu',
  '清一色': 'Chinitsu',
  '嶺上開花': 'Rinshan kaihou',
  '槍槓': 'Chankan',
  '海底摸月': 'Haitei',
  '河底撈魚': 'Houtei',
  '流し満貫': 'Nagashi mangan',
  '天和': 'Tenhou',
  '地和': 'Chiihou',
  '国士無双': 'Kokushi musou',
  '国士無双十三面待ち': 'Kokushi musou (13-wait)',
  '四暗刻': 'Suuankou',
  '四暗刻単騎': 'Suuankou tanki',
  '大三元': 'Daisangen',
  '小四喜': 'Shousuushii',
  '大四喜': 'Daisuushii',
  '字一色': 'Tsuuiisou',
  '緑一色': 'Ryuuiisou',
  '清老頭': 'Chinroutou',
  '九蓮宝燈': 'Chuuren poutou',
  '純正九蓮宝燈': 'Junsei chuuren poutou',
  '四槓子': 'Suukantsu',
  'ドラ': 'Dora',
  '赤ドラ': 'Red dora',
  '裏ドラ': 'Ura dora',
  '抜きドラ': 'Nuki dora',
  '翻・符で入力': 'Entered as han/fu',
  '数え役満': 'Kazoe yakuman',
};

/// 満貫などの名前を今の言語で表示する
String limitName(String ja) {
  if (!L10n.isEnglish) return ja;
  const m = {
    '満貫': 'Mangan',
    '跳満': 'Haneman',
    '倍満': 'Baiman',
    '三倍満': 'Sanbaiman',
    '役満': 'Yakuman',
    '数え役満': 'Kazoe yakuman',
    '二倍役満': 'Double yakuman',
    '三倍役満': 'Triple yakuman',
    '四倍役満': '4x yakuman',
    '五倍役満': '5x yakuman',
    '六倍役満': '6x yakuman',
  };
  return m[ja] ?? ja;
}

/// 符の内訳の名前を今の言語で表示する
String fuName(String ja) {
  if (!L10n.isEnglish) return ja;
  const m = {
    '副底': 'Base',
    'ツモ': 'Tsumo',
    '門前ロン': 'Closed ron',
    '七対子': 'Chiitoitsu',
    '平和ツモ': 'Pinfu tsumo',
    '喰い平和形': 'Open pinfu shape',
    '単騎待ち': 'Tanki wait',
    '嵌張待ち': 'Kanchan wait',
    '辺張待ち': 'Penchan wait',
    '雀頭(三元牌)': 'Pair (dragon)',
    '雀頭(場風)': 'Pair (round wind)',
    '雀頭(自風)': 'Pair (seat wind)',
    '雀頭(連風牌)': 'Pair (double wind)',
  };
  if (m[ja] case final en?) return en;
  // 例: 明刻(么九牌) → Open triplet (terminal/honor)
  final g = RegExp(r'^(.+)\((么九牌|中張牌)\)$').firstMatch(ja);
  if (g != null) {
    const kinds = {'明刻': 'Open triplet', '暗刻': 'Closed triplet', '明槓': 'Open kan', '暗槓': 'Closed kan'};
    return '${kinds[g.group(1)] ?? g.group(1)} (${g.group(2) == '么九牌' ? 'terminal/honor' : 'simple'})';
  }
  return ja;
}

/// 点数計算エンジンのエラーの文を今の言語で表示する（知らない文はそのまま）
String engineError(String ja) {
  if (!L10n.isEnglish) return ja;
  const m = {
    '和了形になっていません': 'This is not a winning hand',
    '役がありません（ドラのみでは和了できません）': 'No yaku (dora alone is not enough to win)',
    '符を選んでください': 'Choose the fu',
    '翻数を選んでください': 'Choose the han',
    '20符はツモ（平和ツモ）のときだけです。ロンなら30符です': '20 fu is only for tsumo (pinfu tsumo). Ron is 30 fu',
    '20符（平和ツモ）は2翻以上です': '20 fu (pinfu tsumo) needs at least 2 han',
    '25符（七対子）は2翻以上です': '25 fu (chiitoitsu) needs at least 2 han',
    '鳴きは4つまでです': 'Up to 4 calls',
    'チーは同じ種類の連続した3枚で指定してください': 'A chi must be 3 consecutive tiles of one suit',
    'ポンは同じ牌3枚で指定してください': 'A pon must be 3 identical tiles',
    '槓子は同じ牌4枚で指定してください': 'A kan must be 4 identical tiles',
    '3人打ちでは二萬〜八萬は使いません': '2m-8m are not used in 3-player',
    '3人打ちではチーはできません': 'No chi in 3-player',
  };
  if (m[ja] case final en?) return en;
  final count = RegExp(r'^手牌の枚数が正しくありません（(\d+)枚必要、現在(\d+)枚）$').firstMatch(ja);
  if (count != null) return 'Wrong number of tiles in hand (need ${count.group(1)}, have ${count.group(2)})';
  return ja;
}
