import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models.dart';

/// 対局データの保存先
abstract class SessionRepository {
  /// 保存済みの全対局を読み込む（起動時に1回）
  List<GameSession> loadAll();

  /// 全対局を保存する
  Future<void> saveAll(List<GameSession> sessions);
}

/// 端末内に保存する実装（shared_preferences）
///
/// - Android: SharedPreferences / iOS: NSUserDefaults / Web: localStorage
/// - 全対局を1つの JSON 文字列として保存する
class SharedPrefsSessionRepository implements SessionRepository {
  final SharedPreferences prefs;

  SharedPrefsSessionRepository(this.prefs);

  /// 保存キー
  static const storageKey = 'mahjong_sessions';

  /// 読み込めなかったデータの退避先（消さずに残しておく）
  static const corruptKey = 'mahjong_sessions_corrupt';

  /// データ形式のバージョン（将来、形式を変えたときの移行用）
  static const formatVersion = 1;

  @override
  List<GameSession> loadAll() {
    final raw = prefs.getString(storageKey);
    if (raw == null) return const [];
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final version = data['version'] as int? ?? 0;
      if (version > formatVersion) {
        // 新しいバージョンのアプリで保存されたデータは上書きしない
        throw FormatException('未対応のデータ形式です（version $version）');
      }
      return List<GameSession>.unmodifiable((data['sessions'] as List)
          .map((e) => GameSession.fromJson(e as Map<String, dynamic>)));
    } catch (e, st) {
      debugPrint('対局データの読み込みに失敗しました: $e\n$st');
      // 壊れたデータは別のキーに退避して、空の状態で起動する
      prefs.setString(corruptKey, raw);
      prefs.remove(storageKey);
      return const [];
    }
  }

  @override
  Future<void> saveAll(List<GameSession> sessions) async {
    final raw = jsonEncode({
      'version': formatVersion,
      'sessions': [for (final s in sessions) s.toJson()],
    });
    await prefs.setString(storageKey, raw);
  }
}

/// メモリ上だけに保存する実装（テスト用）
class InMemorySessionRepository implements SessionRepository {
  List<GameSession> saved;
  int saveCount = 0;

  InMemorySessionRepository([this.saved = const []]);

  @override
  List<GameSession> loadAll() => saved;

  @override
  Future<void> saveAll(List<GameSession> sessions) async {
    saved = sessions;
    saveCount++;
  }
}
