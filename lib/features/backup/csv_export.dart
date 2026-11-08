import '../../core/l10n.dart';
import '../session/domain/models.dart';

/// 戦績を表計算ソフト（Excel・Google スプレッドシートなど）で開ける CSV に書き出す。
///
/// - 文字コードは UTF-8。Excel で文字化けしないように先頭に BOM を付ける
/// - 3人打ちの対局は、4人目の列を空にする
class CsvExport {
  CsvExport._();

  static const bom = '﻿';

  /// CSV の1つの値（カンマ・ダブルクォート・改行を含むときは "" で囲む）
  static String escape(String v) {
    if (v.contains(RegExp('[",\r\n]'))) return '"${v.replaceAll('"', '""')}"';
    return v;
  }

  static String _rows(List<List<String>> rows) =>
      '$bom${rows.map((r) => r.map(escape).join(',')).join('\r\n')}\r\n';

  static String _date(DateTime d) =>
      '${d.year}/${_pad2(d.month)}/${_pad2(d.day)} ${_pad2(d.hour)}:${_pad2(d.minute)}';
  static String _pad2(int v) => v.toString().padLeft(2, '0');
  static String _point(double v) => v.toStringAsFixed(1);

  static List<GameSession> _oldestFirst(List<GameSession> sessions) =>
      [...sessions]..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  /// 対局一覧（1行に1対局。古い順）
  static String games(List<GameSession> sessions) {
    final header = [
      tr('日時', 'Date'), tr('人数', 'Players'), tr('種類', 'Type'), tr('状態', 'Status'),
      tr('お気に入り', 'Favorite'), tr('持ち点', 'Starting points'), tr('返し', 'Return points'),
      tr('ウマ', 'Uma'), tr('局数', 'Rounds'),
      for (var i = 1; i <= 4; i++)
        ...[tr('名前$i', 'Name $i'), tr('点数$i', 'Points $i'), tr('順位$i', 'Rank $i'), tr('ポイント$i', 'Score $i')],
      for (var i = 1; i <= 4; i++) tr('祝儀$i', 'Chips $i'),
    ];
    final rows = <List<String>>[header];
    for (final s in _oldestFirst(sessions)) {
      final results = {for (final r in s.finalResults) r.player: r};
      rows.add([
        _date(s.createdAt),
        tr('${s.playerCount}人', '${s.playerCount} players'),
        s.settings.length.label,
        s.finished ? tr('終局', 'Finished') : tr('対局中', 'In progress'),
        s.favorite ? '★' : '',
        '${s.settings.startingPoints}',
        '${s.settings.returnPoints}',
        s.settings.umaLabel,
        '${s.records.length}',
        for (var p = 0; p < 4; p++)
          if (p < s.playerCount) ...[
            s.playerNames[p],
            '${s.scores[p]}',
            '${results[p]!.rank}',
            s.finished ? _point(results[p]!.point) : '',
          ] else
            ...['', '', '', ''],
        for (var p = 0; p < 4; p++) p < s.playerCount && s.settings.chips ? '${s.chipTotals[p]}' : '',
      ]);
    }
    return _rows(rows);
  }

  /// 局ごとの記録（1行に1局。古い対局から順に）
  static String rounds(List<GameSession> sessions) {
    final header = [
      tr('対局の日時', 'Game date'), tr('人数', 'Players'), tr('局', 'Round'), tr('種類', 'Type'),
      tr('内容', 'Details'), tr('修正済み', 'Edited'),
      for (var i = 1; i <= 4; i++) ...[tr('名前$i', 'Name $i'), tr('増減$i', 'Change $i'), tr('点数$i', 'Points $i')],
    ];
    final rows = <List<String>>[header];
    for (final s in _oldestFirst(sessions)) {
      for (final r in s.records) {
        rows.add([
          _date(s.createdAt),
          tr('${s.playerCount}人', '${s.playerCount} players'),
          displayRoundLabel(r.roundLabel),
          switch (r.kind) {
            'win' => tr('和了', 'Win'),
            'chombo' => tr('チョンボ', 'Chombo'),
            _ => tr('流局', 'Draw'),
          },
          r.description,
          r.edited ? tr('修正済み', 'Edited') : '',
          for (var p = 0; p < 4; p++)
            if (p < s.playerCount)
              ...[s.playerNames[p], '${r.deltas[p]}', '${r.scoresAfter[p]}']
            else
              ...['', '', ''],
        ]);
      }
    }
    return _rows(rows);
  }

  /// ファイル名（例: mahjong_games_20261104_0905.csv）
  static String fileName(String kind, DateTime now) =>
      'mahjong_${kind}_${now.year}${_pad2(now.month)}${_pad2(now.day)}_${_pad2(now.hour)}${_pad2(now.minute)}.csv';
}
