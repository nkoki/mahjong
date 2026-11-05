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
      '日時', '人数', '種類', '状態', 'お気に入り', '持ち点', '返し', 'ウマ', '局数',
      for (var i = 1; i <= 4; i++) ...['名前$i', '点数$i', '順位$i', 'ポイント$i'],
    ];
    final rows = <List<String>>[header];
    for (final s in _oldestFirst(sessions)) {
      final results = {for (final r in s.finalResults) r.player: r};
      rows.add([
        _date(s.createdAt),
        '${s.playerCount}人',
        s.settings.tonpuu ? '東風戦' : '半荘戦',
        s.finished ? '終局' : '対局中',
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
      ]);
    }
    return _rows(rows);
  }

  /// 局ごとの記録（1行に1局。古い対局から順に）
  static String rounds(List<GameSession> sessions) {
    final header = [
      '対局の日時', '人数', '局', '種類', '内容', '修正済み',
      for (var i = 1; i <= 4; i++) ...['名前$i', '増減$i', '点数$i'],
    ];
    final rows = <List<String>>[header];
    for (final s in _oldestFirst(sessions)) {
      for (final r in s.records) {
        rows.add([
          _date(s.createdAt),
          '${s.playerCount}人',
          r.roundLabel,
          r.kind == 'win' ? '和了' : '流局',
          r.description,
          r.edited ? '修正済み' : '',
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
