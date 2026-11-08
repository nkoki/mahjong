import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../session/domain/models.dart';

/// 対局の結果を、LINE などに貼り付けられるテキストにする（UI に依存しない）
class ResultText {
  ResultText._();

  static String build(GameSession s) {
    final d = s.createdAt;
    final rules = s.settings;
    final b = StringBuffer()
      ..writeln(tr('【麻雀 ${s.finished ? "対局結果" : "対局中（${s.roundLabel}）の順位"}】',
          '[Mahjong ${s.finished ? "result" : "standings (${displayRoundLabel(s.roundLabel)})"}]'))
      ..writeln(tr('${d.year}/${d.month}/${d.day}  ${rules.isSanma ? "3人打ち " : ""}${rules.length.label}',
          '${d.year}/${d.month}/${d.day}  ${rules.isSanma ? "3-player " : ""}${rules.length.label}'));
    final chips = s.chipTotals;
    for (final r in s.finalResults) {
      b.write(tr('${r.rank}位 ${s.playerNames[r.player]}  ${formatPoints(r.score)}点',
          '#${r.rank} ${s.playerNames[r.player]}  ${formatPoints(r.score)} pts'));
      if (s.finished) b.write('  ${formatPoint(r.point)}');
      final extra = [
        if (rules.chips)
          tr('祝儀 ${chips[r.player] > 0 ? "+" : ""}${chips[r.player]}枚',
              'Chips ${chips[r.player] > 0 ? "+" : ""}${chips[r.player]}'),
        if (r.adjustment != 0)
          tr('焼き鳥・トビ賞 ${formatPoint(r.adjustment)}', 'Yakitori/bust bonus ${formatPoint(r.adjustment)}'),
      ];
      if (extra.isNotEmpty) b.write(tr('（${extra.join("・")}）', ' (${extra.join(", ")})'));
      b.writeln();
    }
    b.write(tr('ウマ ${rules.umaLabel}・返し ${formatPoints(rules.returnPoints)}点・${s.records.length}局',
        'Uma ${rules.umaLabel} · Return ${formatPoints(rules.returnPoints)} pts · ${s.records.length} rounds'));
    return b.toString();
  }

  /// クリップボードにコピーして、知らせる
  static Future<void> copy(BuildContext context, GameSession s) async {
    await Clipboard.setData(ClipboardData(text: build(s)));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(tr('結果をコピーしました。LINE などに貼り付けて送れます', 'Result copied. Paste it into LINE or other chat apps'))));
  }
}
