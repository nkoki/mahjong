import '../session/domain/session_logic.dart' show HanFuEntry;

/// 翻・符で入力するときのショートカット（最近の入力・よく出る点数）。UI に依存しない
class HanFuShortcuts {
  HanFuShortcuts._();

  /// 覚えておく最近の入力の数
  static const maxRecent = 4;

  /// よく出る手（ロン・ツモどちらでも使えるもの）
  static const common = [
    HanFuEntry(han: 1, fu: 30),
    HanFuEntry(han: 2, fu: 30),
    HanFuEntry(han: 3, fu: 30),
    HanFuEntry(han: 1, fu: 40),
    HanFuEntry(han: 2, fu: 40),
    HanFuEntry(han: 3, fu: 40),
    HanFuEntry(han: 5),
    HanFuEntry(han: 6),
    HanFuEntry(han: 8),
  ];

  static bool same(HanFuEntry a, HanFuEntry b) => a.han == b.han && a.fu == b.fu && a.yakuman == b.yakuman;

  /// 保存した文字列（例: "3,30,0;5,0,0"）から読む。読めない部分は飛ばす
  static List<HanFuEntry> decode(String? text) {
    if (text == null || text.isEmpty) return const [];
    final out = <HanFuEntry>[];
    for (final part in text.split(';')) {
      final v = part.split(',').map(int.tryParse).toList();
      if (v.length != 3 || v.any((x) => x == null || x < 0)) continue;
      out.add(HanFuEntry(han: v[0]!, fu: v[1]!, yakuman: v[2]!));
    }
    return out.take(maxRecent).toList();
  }

  static String encode(List<HanFuEntry> list) => [for (final e in list) '${e.han},${e.fu},${e.yakuman}'].join(';');

  /// [e] を最近の入力の先頭に入れる（同じものは前から消す）。5翻以上は符を数えない
  static List<HanFuEntry> remember(List<HanFuEntry> recent, HanFuEntry e) {
    final n = e.yakuman > 0
        ? HanFuEntry(yakuman: e.yakuman)
        : e.han >= 5
            ? HanFuEntry(han: e.han)
            : e;
    return [n, ...recent.where((r) => !same(r, n))].take(maxRecent).toList();
  }

  /// チップの表示（例: 3翻30符、満貫(5翻)、役満）
  static String label(HanFuEntry e) {
    if (e.yakuman > 0) return e.yakuman == 1 ? '役満' : '${e.yakuman}倍役満';
    if (e.han >= 5) {
      final name = e.han >= 13
          ? '数え役満'
          : e.han >= 11
              ? '三倍満'
              : e.han >= 8
                  ? '倍満'
                  : e.han >= 6
                      ? '跳満'
                      : '満貫';
      return '$name(${e.han}翻)';
    }
    return '${e.han}翻${e.fu}符';
  }
}
