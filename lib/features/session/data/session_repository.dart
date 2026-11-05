import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models.dart';

/// 保存容量の使用状況
class StorageUsage {
  /// 保存データの合計サイズ（バイト）
  final int bytes;

  /// 保存容量の上限の目安（バイト）。上限がない・分からない場合は null
  final int? limitBytes;

  const StorageUsage({required this.bytes, this.limitBytes});

  /// 上限に対する使用率（0.0〜1.0）。上限がなければ null
  double? get ratio => limitBytes == null ? null : (bytes / limitBytes!).clamp(0.0, 1.0);

  /// 上限に近づいているか（目安の50%以上）
  bool get isNearLimit => ratio != null && ratio! >= 0.5;
}

/// 対局データの保存先
abstract class SessionRepository {
  /// 保存済みの全対局を読み込む（起動時に1回）
  List<GameSession> loadAll();

  /// 全対局を保存する
  Future<void> saveAll(List<GameSession> sessions);

  /// 読み込み時に起きた問題（利用者に知らせる内容）
  List<String> get loadWarnings;

  /// 保存容量の使用状況
  StorageUsage usage();

  /// 最後にバックアップを書き出した日時（一度もなければ null）
  DateTime? get lastBackupAt;

  /// バックアップを書き出した日時を記録する
  Future<void> setLastBackupAt(DateTime at);

  /// ルール設定画面で決めた、新しい対局に使うルール（未設定なら null）。
  /// 4人打ちと3人打ちで別々に保存する
  GameSettings? loadDefaultSettings({int playerCount = 4});

  /// 新しい対局に使うルールを保存する（人数は [GameSettings.playerCount] で判断）
  Future<void> saveDefaultSettings(GameSettings settings);

  /// 表示などの設定（入力方法・画面の明るさ・文字の大きさなど）。無ければ null
  String? loadPreference(String key);

  /// 表示などの設定を保存する
  Future<void> savePreference(String key, String value);
}

/// ブラウザ（Web 版）の保存容量の上限の目安。多くのブラウザで 1サイトあたり約5MB
const webStorageLimitBytes = 5 * 1000 * 1000;

/// 端末内に保存する実装（shared_preferences）
///
/// - Android: SharedPreferences / iOS: NSUserDefaults / Web: localStorage
/// - 対局ごとに別のキーへ保存し、並び順は目次（[indexKey]）に保存する
/// - 保存時は前回保存したときから変わった対局だけを書き込む。対局データは
///   変更のたびに新しいオブジェクトに置き換わるので、同じオブジェクトか
///   どうか（identical）で変更の有無が分かる
class SharedPrefsSessionRepository implements SessionRepository {
  final SharedPreferences prefs;

  SharedPrefsSessionRepository(this.prefs);

  /// 目次（対局IDの並び）のキー
  static const indexKey = 'mahjong_session_index';

  /// 対局1つ分のキーの先頭部分（後ろに対局IDが付く）
  static const sessionKeyPrefix = 'mahjong_session_';

  /// 読み込めなかったデータの退避先の先頭部分（消さずに残しておく）
  static const corruptKeyPrefix = 'mahjong_corrupt_';

  /// 以前（version 1・2）の、全対局を1つにまとめて保存していたキー
  static const legacyKey = 'mahjong_sessions';

  /// データ形式のバージョン（将来、形式を変えたときの移行用）
  /// - 1: 全対局を1つのキーに保存。元に戻す履歴に局の記録を丸ごと保存
  /// - 2: 全対局を1つのキーに保存。元に戻す履歴は局の記録の件数だけ保存
  /// - 3: 対局ごとに別のキーに保存（version 1・2 のデータは起動時に自動で移行）
  /// - 4: 局の記録に和了者・放銃者・立直した人・和了点を追加（個人成績の集計用）。
  ///      version 3 のデータはそのまま読める（その局は個人成績の和了率などに含めない）
  /// - 5: ルールに祝儀（チップ）を記録するか、局の記録に祝儀の増減を追加。
  ///      version 4 以前のデータはそのまま読める（祝儀なしとして扱う）
  /// - 6: ルールに焼き鳥・トビ賞（精算ポイント）を追加。
  ///      version 5 以前のデータはそのまま読める（どちらもなしとして扱う）
  /// - 7: 対局の途中のプレイヤーの交代を追加（元に戻す用の前の状態には、交代する前の名前も保存）。
  ///      version 6 以前のデータはそのまま読める（交代なしとして扱う）
  static const formatVersion = 7;

  static String sessionKey(String id) => '$sessionKeyPrefix$id';

  /// 最後にバックアップを書き出した日時のキー
  static const lastBackupKey = 'mahjong_last_backup_at';

  /// 表示などの設定のキーの先頭部分（後ろに設定の名前が付く）
  static const preferenceKeyPrefix = 'mahjong_pref_';

  @override
  String? loadPreference(String key) => prefs.getString('$preferenceKeyPrefix$key');

  @override
  Future<void> savePreference(String key, String value) =>
      prefs.setString('$preferenceKeyPrefix$key', value);

  @override
  DateTime? get lastBackupAt {
    final v = prefs.getString(lastBackupKey);
    return v == null ? null : DateTime.tryParse(v);
  }

  @override
  Future<void> setLastBackupAt(DateTime at) =>
      prefs.setString(lastBackupKey, at.toIso8601String());

  /// 新しい対局に使うルールのキー（4人打ち）
  static const defaultSettingsKey = 'mahjong_default_settings';

  /// 新しい対局に使うルールのキー（3人打ち）
  static const defaultSanmaSettingsKey = 'mahjong_default_settings_3';

  static String _defaultKey(int playerCount) =>
      playerCount == 3 ? defaultSanmaSettingsKey : defaultSettingsKey;

  @override
  GameSettings? loadDefaultSettings({int playerCount = 4}) {
    final raw = prefs.getString(_defaultKey(playerCount));
    if (raw == null) return null;
    try {
      return GameSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('ルール設定を読み込めませんでした（初期値を使います）: $e');
      return null;
    }
  }

  @override
  Future<void> saveDefaultSettings(GameSettings settings) =>
      prefs.setString(_defaultKey(settings.playerCount), jsonEncode(settings.toJson()));

  /// 以前のカメラ認識（Qwen API）の設定のキー。API キーが入っているので、読み込み時に消す
  static const legacyCameraSettingsKey = 'mahjong_camera_settings';

  final List<String> _warnings = [];

  @override
  List<String> get loadWarnings => List.unmodifiable(_warnings);

  /// このアプリが保存しているデータ（退避したデータも含む）の合計サイズ
  @override
  StorageUsage usage() {
    var bytes = 0;
    for (final k in prefs.getKeys()) {
      if (!k.startsWith('mahjong_')) continue;
      final v = prefs.get(k);
      if (v is String) bytes += utf8.encode(v).length + k.length;
    }
    return StorageUsage(bytes: bytes, limitBytes: kIsWeb ? webStorageLimitBytes : null);
  }

  /// 前回保存した状態（対局ID → 対局）。変更の有無の判定に使う
  final Map<String, GameSession> _saved = {};

  /// 前回保存した目次
  List<String> _savedOrder = const [];

  // ---------------------------------------------------------------------
  // 読み込み
  // ---------------------------------------------------------------------
  @override
  List<GameSession> loadAll() {
    // カメラ認識は端末の中で動くモデルになり、API キーは使わなくなったので消しておく
    if (prefs.containsKey(legacyCameraSettingsKey)) prefs.remove(legacyCameraSettingsKey);
    if (prefs.getString(indexKey) == null && prefs.getString(legacyKey) != null) {
      return _migrateLegacy();
    }

    final order = _readIndex();
    // 目次に載っていない対局データ（目次の保存前にアプリが終了した場合など）も拾う
    final known = order.toSet();
    final orphans = prefs
        .getKeys()
        .where((k) => k.startsWith(sessionKeyPrefix) && k != indexKey)
        .map((k) => k.substring(sessionKeyPrefix.length))
        .where((id) => !known.contains(id));

    final sessions = <GameSession>[];
    final orphanSessions = <GameSession>[];
    for (final id in [...order, ...orphans]) {
      final s = _readSession(id);
      if (s == null) continue;
      (known.contains(id) ? sessions : orphanSessions).add(s);
    }
    orphanSessions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final all = [...sessions, ...orphanSessions];

    for (final s in all) {
      _saved[s.id] = s;
    }
    _savedOrder = [for (final s in all) s.id];
    if (orphanSessions.isNotEmpty || all.length != order.length) {
      _writeIndex(_savedOrder);
    }
    return List.unmodifiable(all);
  }

  List<String> _readIndex() {
    final raw = prefs.getString(indexKey);
    if (raw == null) return const [];
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _checkVersion(data);
      return (data['ids'] as List).map((e) => e as String).toList();
    } catch (e) {
      debugPrint('目次の読み込みに失敗しました（対局データから作り直します）: $e');
      _warnings.add('対局の一覧（並び順）の保存データが壊れていたため、作り直しました。対局の並び順が変わっている場合があります。');
      _backup(indexKey, raw);
      return const [];
    }
  }

  GameSession? _readSession(String id) {
    final key = sessionKey(id);
    final raw = prefs.getString(key);
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _checkVersion(data);
      return GameSession.fromJson(data['session'] as Map<String, dynamic>);
    } catch (e) {
      debugPrint('対局データ($id)の読み込みに失敗しました: $e');
      _warnings.add(e is FormatException && e.message.startsWith('未対応')
          ? '新しいバージョンのアプリで保存された対局が1件あり、このバージョンでは読み込めませんでした。アプリを最新版に更新してください。'
          : '保存データが壊れていて読み込めない対局が1件ありました。この対局は表示されません。');
      // 壊れた対局だけを退避し、他の対局はそのまま使う
      _backup(key, raw);
      prefs.remove(key);
      return null;
    }
  }

  static void _checkVersion(Map<String, dynamic> data) {
    final version = data['version'] as int? ?? 0;
    if (version > formatVersion) {
      // 新しいバージョンのアプリで保存されたデータは読めないので、退避用のキーに残す
      throw FormatException('未対応のデータ形式です（version $version）');
    }
  }

  void _backup(String key, String raw) {
    prefs.setString('$corruptKeyPrefix$key', raw);
  }

  /// version 1・2（全対局を1つのキーに保存）からの移行
  List<GameSession> _migrateLegacy() {
    final raw = prefs.getString(legacyKey)!;
    List<GameSession> sessions;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final version = data['version'] as int? ?? 0;
      if (version > 2) throw FormatException('未対応のデータ形式です（version $version）');
      sessions = List<GameSession>.unmodifiable((data['sessions'] as List)
          .map((e) => GameSession.fromJson(e as Map<String, dynamic>)));
    } catch (e) {
      debugPrint('以前の形式の対局データを読み込めませんでした: $e');
      _warnings.add('以前のバージョンで保存した対局データが壊れていて、読み込めませんでした。');
      _backup(legacyKey, raw);
      prefs.remove(legacyKey);
      return const [];
    }
    // 新しい形式で書き込み、目次まで書けたら古いデータを消す。
    // 途中でアプリが終了しても、目次がなければ次の起動でもう一度移行する。
    () async {
      try {
        for (final s in sessions) {
          await prefs.setString(sessionKey(s.id), _encodeSession(s));
        }
        await _writeIndex([for (final s in sessions) s.id]);
        await prefs.remove(legacyKey);
      } catch (e) {
        debugPrint('対局データの移行に失敗しました: $e');
      }
    }();
    for (final s in sessions) {
      _saved[s.id] = s;
    }
    _savedOrder = [for (final s in sessions) s.id];
    return sessions;
  }

  // ---------------------------------------------------------------------
  // 保存
  // ---------------------------------------------------------------------
  static String _encodeSession(GameSession s) =>
      jsonEncode({'version': formatVersion, 'session': s.toJson()});

  Future<void> _writeIndex(List<String> ids) =>
      prefs.setString(indexKey, jsonEncode({'version': formatVersion, 'ids': ids}));

  /// 前回から変わった対局だけを書き込む
  @override
  Future<void> saveAll(List<GameSession> sessions) async {
    // 先に「保存済み」の記録を更新してから書き込む（連続で呼ばれても二重に書かない）
    final changed = <GameSession>[
      for (final s in sessions)
        if (!identical(_saved[s.id], s)) s
    ];
    final ids = [for (final s in sessions) s.id];
    final removed = _saved.keys.where((id) => !ids.contains(id)).toList();
    final orderChanged = !listEquals(ids, _savedOrder);
    for (final s in changed) {
      _saved[s.id] = s;
    }
    for (final id in removed) {
      _saved.remove(id);
    }
    _savedOrder = ids;

    for (final s in changed) {
      try {
        await prefs.setString(sessionKey(s.id), _encodeSession(s));
      } catch (e) {
        // 失敗した対局は次の保存のときに書き直す
        if (identical(_saved[s.id], s)) _saved.remove(s.id);
        rethrow;
      }
    }
    if (orderChanged) await _writeIndex(ids);
    for (final id in removed) {
      await prefs.remove(sessionKey(id));
    }
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

  @override
  List<String> loadWarnings = [];

  @override
  StorageUsage usage() => const StorageUsage(bytes: 0);

  @override
  DateTime? lastBackupAt;

  @override
  Future<void> setLastBackupAt(DateTime at) async => lastBackupAt = at;

  /// 4人打ちのルール設定
  GameSettings? defaultSettings;

  /// 3人打ちのルール設定
  GameSettings? defaultSanmaSettings;

  @override
  GameSettings? loadDefaultSettings({int playerCount = 4}) =>
      playerCount == 3 ? defaultSanmaSettings : defaultSettings;

  @override
  Future<void> saveDefaultSettings(GameSettings settings) async {
    if (settings.isSanma) {
      defaultSanmaSettings = settings;
    } else {
      defaultSettings = settings;
    }
  }

  /// 表示などの設定
  final Map<String, String> preferences = {};

  @override
  String? loadPreference(String key) => preferences[key];

  @override
  Future<void> savePreference(String key, String value) async => preferences[key] = value;
}
