import 'dart:convert';

import '../session/data/session_repository.dart';
import '../session/domain/models.dart';

/// バックアップを読み込めなかったときのエラー（[message] は利用者向けの説明）
class BackupFormatException implements Exception {
  final String message;
  const BackupFormatException(this.message);

  @override
  String toString() => message;
}

/// 読み込んだバックアップの中身
class BackupData {
  /// バックアップを作った日時
  final DateTime? exportedAt;
  final List<GameSession> sessions;

  /// 壊れていて読み込めなかった対局の数
  final int skipped;

  /// ルール設定画面の内容（ルール設定を入れる前のバックアップ・壊れている場合は null）
  final GameSettings? defaultSettings;

  const BackupData({
    required this.exportedAt,
    required this.sessions,
    this.skipped = 0,
    this.defaultSettings,
  });
}

/// 今のデータに「追加」で読み込んだときの見込み
class MergePlan {
  /// 新しく追加される対局
  final List<GameSession> added;

  /// すでにある対局（同じ対局。今のデータを残し、バックアップ側は読み込まない）
  final int duplicates;

  const MergePlan({required this.added, required this.duplicates});
}

/// バックアップの形式（JSON）への変換と読み込み
class BackupCodec {
  BackupCodec._();

  /// このアプリのバックアップであることの目印
  static const appId = 'mahjong_score_app';
  static const kind = 'backup';

  /// 全対局（とルール設定画面の内容）をバックアップ用の文字列にする
  static String encode(List<GameSession> sessions,
          {GameSettings? defaultSettings, DateTime? now}) =>
      jsonEncode({
        'app': appId,
        'kind': kind,
        'version': SharedPrefsSessionRepository.formatVersion,
        'exportedAt': (now ?? DateTime.now()).toIso8601String(),
        if (defaultSettings != null) 'defaultSettings': defaultSettings.toJson(),
        'sessions': [for (final s in sessions) s.toJson()],
      });

  /// バックアップの文字列を読み込む
  static BackupData decode(String text) {
    final Object? data;
    try {
      data = jsonDecode(text.trim());
    } on FormatException {
      throw const BackupFormatException(
          'バックアップの形式になっていません。このアプリで書き出したファイル（またはテキスト）を選んでください。');
    }
    if (data is! Map<String, dynamic> || data['app'] != appId || data['kind'] != kind) {
      throw const BackupFormatException('このアプリのバックアップではありません。');
    }
    final version = data['version'];
    if (version is! int) {
      throw const BackupFormatException('バックアップのバージョンが分かりません。');
    }
    if (version > SharedPrefsSessionRepository.formatVersion) {
      throw const BackupFormatException(
          '新しいバージョンのアプリで作られたバックアップです。アプリを最新版に更新してから読み込んでください。');
    }
    final list = data['sessions'];
    if (list is! List) {
      throw const BackupFormatException('バックアップに対局のデータがありません。');
    }
    final sessions = <GameSession>[];
    final ids = <String>{};
    var skipped = 0;
    for (final e in list) {
      try {
        final s = GameSession.fromJson(e as Map<String, dynamic>);
        if (ids.add(s.id)) sessions.add(s);
      } catch (_) {
        skipped++;
      }
    }
    final exportedAt = DateTime.tryParse(data['exportedAt'] as String? ?? '');
    GameSettings? defaultSettings;
    final ds = data['defaultSettings'];
    if (ds is Map<String, dynamic>) {
      try {
        defaultSettings = GameSettings.fromJson(ds);
      } catch (_) {
        // ルール設定だけ壊れている場合は、対局だけ読み込む（今のルール設定は変えない）
      }
    }
    return BackupData(
      exportedAt: exportedAt,
      sessions: sessions,
      skipped: skipped,
      defaultSettings: defaultSettings,
    );
  }

  /// 今のデータに追加したときの見込み（同じ対局は今のデータを残す）
  static MergePlan planMerge(List<GameSession> current, List<GameSession> incoming) {
    final existing = {for (final s in current) s.id};
    final added = [for (final s in incoming) if (!existing.contains(s.id)) s];
    return MergePlan(added: added, duplicates: incoming.length - added.length);
  }

  /// ファイル名（例: mahjong_backup_20261104_1530.json）
  static String fileName(DateTime now) {
    String two(int v) => v.toString().padLeft(2, '0');
    return 'mahjong_backup_${now.year}${two(now.month)}${two(now.day)}'
        '_${two(now.hour)}${two(now.minute)}.json';
  }
}
