import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../session/domain/models.dart';

/// 対局の結果を、LINE などに貼り付けられるテキストにする（UI に依存しない）
class ResultText {
  ResultText._();

  static String build(GameSession s) {
    final d = s.createdAt;
    final rules = s.settings;
    final b = StringBuffer()
      ..writeln('【麻雀 ${s.finished ? "対局結果" : "対局中（${s.roundLabel}）の順位"}】')
      ..writeln('${d.year}/${d.month}/${d.day}  ${rules.isSanma ? "3人打ち " : ""}${rules.tonpuu ? "東風戦" : "半荘戦"}');
    final chips = s.chipTotals;
    for (final r in s.finalResults) {
      b.write('${r.rank}位 ${s.playerNames[r.player]}  ${formatPoints(r.score)}点');
      if (s.finished) b.write('  ${formatPoint(r.point)}');
      final extra = [
        if (rules.chips) '祝儀 ${chips[r.player] > 0 ? "+" : ""}${chips[r.player]}枚',
        if (r.adjustment != 0) '焼き鳥・トビ賞 ${formatPoint(r.adjustment)}',
      ];
      if (extra.isNotEmpty) b.write('（${extra.join("・")}）');
      b.writeln();
    }
    b.write('ウマ ${rules.umaLabel}・返し ${formatPoints(rules.returnPoints)}点・${s.records.length}局');
    return b.toString();
  }

  /// クリップボードにコピーして、知らせる
  static Future<void> copy(BuildContext context, GameSession s) async {
    await Clipboard.setData(ClipboardData(text: build(s)));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('結果をコピーしました。LINE などに貼り付けて送れます')));
  }
}
