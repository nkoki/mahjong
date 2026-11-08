import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mahjong_score_engine/mahjong_score_engine.dart';

import '../../core/l10n.dart';
import 'data/session_repository.dart';
import 'domain/models.dart';
import 'domain/session_logic.dart';

/// 対局データの保存先。main() で端末保存の実装に差し替える。
final sessionRepositoryProvider = Provider<SessionRepository>(
  (ref) => InMemorySessionRepository(),
);

/// 表示などの設定（1つの値）。端末に保存し、次に起動したときも同じにする
class PreferenceNotifier extends FamilyNotifier<String?, String> {
  @override
  String? build(String key) => ref.read(sessionRepositoryProvider).loadPreference(key);

  void set(String value) {
    if (state == value) return;
    state = value;
    ref.read(sessionRepositoryProvider).savePreference(arg, value).catchError((Object e) {
      debugPrint('設定（$arg）を保存できませんでした: $e');
    });
  }
}

/// 表示などの設定。キーは [PreferenceKeys] を使う
final preferenceProvider =
    NotifierProvider.family<PreferenceNotifier, String?, String>(PreferenceNotifier.new);

/// 表示などの設定の名前
class PreferenceKeys {
  PreferenceKeys._();

  /// 和了入力の入力方法（'hand' | 'hanfu'）
  static const winInputMode = 'win_input_mode';

  /// 対局中は画面を消さないか（'1' | '0'。無ければオン）
  static const keepScreenOn = 'keep_screen_on';

  /// 画面の明るさ（'system' | 'light' | 'dark'。無ければ端末の設定に合わせる）
  static const themeMode = 'theme_mode';

  /// 文字の大きさの倍率（'1.0' | '1.15' | '1.3'。無ければ標準）
  static const textScale = 'text_scale';

  /// 翻・符で入力した最近の手（例: "3,30,0;5,0,0"。新しい順）
  static const recentHanFu = 'recent_hanfu';

  /// 名前を付けて保存したルールのセット（JSON）
  static const rulePresets = 'rule_presets';

  /// 表示の言語（'ja' | 'en'。無ければ日本語）
  static const language = 'language';

  /// 対局画面のレイアウト（'simple' | 'table'。無ければシンプル）
  static const dashboardLayout = 'dashboard_layout';
}

/// 全対局の一覧（変更のたびに端末へ自動保存）
final sessionsProvider =
    NotifierProvider<SessionsNotifier, List<GameSession>>(SessionsNotifier.new);

/// 直近の保存に失敗したときのメッセージ（成功すると null に戻る）
final saveErrorProvider = StateProvider<String?>((ref) => null);

/// 起動時の読み込みで起きた問題のうち、まだ閉じていないもの
final loadWarningsProvider = StateProvider<List<String>>((ref) {
  // 読み込みが終わってから取り出す（watch にすると対局が変わるたびに作り直されて、
  // 閉じた警告がまた表示されてしまうので read にする）
  ref.read(sessionsProvider);
  return ref.read(sessionRepositoryProvider).loadWarnings;
});

/// 新しい対局に使うルール（4人打ち。ルール設定画面で変更・保存する）
final defaultSettingsProvider = NotifierProvider<DefaultSettingsNotifier, GameSettings>(
    () => DefaultSettingsNotifier(4));

/// 新しい対局に使うルール（3人打ち）
final defaultSanmaSettingsProvider = NotifierProvider<DefaultSettingsNotifier, GameSettings>(
    () => DefaultSettingsNotifier(3));

/// 人数に合ったルール設定の provider
NotifierProvider<DefaultSettingsNotifier, GameSettings> defaultSettingsProviderFor(
        int playerCount) =>
    playerCount == 3 ? defaultSanmaSettingsProvider : defaultSettingsProvider;

class DefaultSettingsNotifier extends Notifier<GameSettings> {
  DefaultSettingsNotifier(this.playerCount);

  final int playerCount;

  @override
  GameSettings build() =>
      ref.read(sessionRepositoryProvider).loadDefaultSettings(playerCount: playerCount) ??
      (playerCount == 3 ? const GameSettings.sanma() : const GameSettings());

  /// 保存する
  Future<void> save(GameSettings settings) async {
    state = settings;
    await ref.read(sessionRepositoryProvider).saveDefaultSettings(settings);
  }
}

/// 最後にバックアップを書き出した日時
final lastBackupProvider = StateProvider<DateTime?>(
    (ref) => ref.read(sessionRepositoryProvider).lastBackupAt);

/// IDから対局を取得
final sessionProvider = Provider.family<GameSession?, String>((ref, id) {
  final sessions = ref.watch(sessionsProvider);
  for (final s in sessions) {
    if (s.id == id) return s;
  }
  return null;
});

class SessionsNotifier extends Notifier<List<GameSession>> {
  var _counter = 0;

  @override
  List<GameSession> build() => ref.read(sessionRepositoryProvider).loadAll();

  /// 状態を更新して保存する
  @override
  set state(List<GameSession> value) {
    super.state = value;
    _save(value);
  }

  Future<void> _save(List<GameSession> value) async {
    try {
      await ref.read(sessionRepositoryProvider).saveAll(value);
      if (ref.read(saveErrorProvider) != null) {
        ref.read(saveErrorProvider.notifier).state = null;
      }
    } catch (e, st) {
      debugPrint('対局データの保存に失敗しました: $e\n$st');
      ref.read(saveErrorProvider.notifier).state = tr(
          '対局データを保存できませんでした。端末（ブラウザ）の保存容量がいっぱいの可能性があります。'
              '不要な対局を削除してください。',
          'Could not save game data. The storage of this device (browser) may be full. '
              'Please delete games you no longer need.');
    }
  }

  /// 新規対局を作成してIDを返す。
  /// 保存件数の上限を超える場合は、お気に入りでない一番古い終局済みの対局から削除する。
  String create(List<String> names, GameSettings settings) {
    final id = '${DateTime.now().millisecondsSinceEpoch}-${_counter++}';
    final session =
        GameSession.start(id: id, playerNames: names, settings: settings);
    final next = [session, ...state];
    final pruneIds =
        SessionLogic.sessionsToPrune(next).map((s) => s.id).toSet();
    state = [
      for (final s in next)
        if (!pruneIds.contains(s.id)) s
    ];
    return id;
  }

  /// 次に新規対局を作成したときに削除される対局（なければ空）
  List<GameSession> sessionsRemovedByNextCreate() {
    // 新しい対局は対局中なので削除対象にならない。1件増える分、上限を1つ減らして判定する
    return SessionLogic.sessionsToPrune(state,
        max: SessionLogic.maxSavedSessions - 1);
  }

  void toggleFavorite(String id) => _update(id, SessionLogic.toggleFavorite);

  void editRound(String id, int index,
          {required List<int> deltas, String? description, ({List<int> winners, int? loser})? who}) =>
      _update(
          id,
          (s) => SessionLogic.editRound(s, index,
              deltas: deltas, description: description, who: who));

  void substitute(String id, int seat, String name) => _update(id, (s) => SessionLogic.substitute(s, seat, name));

  void deleteRound(String id, int index) => _update(id, (s) => SessionLogic.deleteRound(s, index));

  void insertRound(String id, int index,
          {required String roundLabel, required List<int> deltas, List<int>? winners, int? loser, String description = ''}) =>
      _update(
          id,
          (s) => SessionLogic.insertRound(s, index,
              roundLabel: roundLabel, deltas: deltas, winners: winners, loser: loser, description: description));

  void adjustProgress(String id, {required int roundIndex, required int honba, required int riichiSticks}) => _update(
      id, (s) => SessionLogic.adjustProgress(s, roundIndex: roundIndex, honba: honba, riichiSticks: riichiSticks));

  void updateUma(String id, List<int> uma) =>
      _update(id, (s) => SessionLogic.updateUma(s, uma));

  GameSession? _get(String id) {
    for (final s in state) {
      if (s.id == id) return s;
    }
    return null;
  }

  void _update(String id, GameSession Function(GameSession) f) {
    state = [
      for (final s in state)
        if (s.id == id) f(s) else s
    ];
  }

  void toggleRiichi(String id, int player) =>
      _update(id, (s) => SessionLogic.toggleRiichi(s, player));

  void applyWin(
    String id, {
    required int winner,
    int? loser,
    required ScoreResult result,
    required String description,
  }) =>
      _update(
        id,
        (s) => SessionLogic.applyWin(s,
            winner: winner,
            loser: loser,
            result: result,
            description: description),
      );

  void applyWins(
    String id, {
    required List<ScoredWin> wins,
    int? loser,
    required String description,
    Map<int, int> chips = const {},
  }) =>
      _update(
        id,
        (s) => SessionLogic.applyWins(s,
            wins: wins, loser: loser, description: description, chips: chips),
      );

  void applyChombo(String id, int player) => _update(id, (s) => SessionLogic.applyChombo(s, player));

  void applyDraw(
    String id, {
    required DrawType type,
    required List<bool> tenpai,
    int? nagashiPlayer,
  }) =>
      _update(
        id,
        (s) => SessionLogic.applyDraw(s,
            type: type, tenpai: tenpai, nagashiPlayer: nagashiPlayer),
      );

  void finish(String id) => _update(id, SessionLogic.finishManually);

  bool canUndo(String id) => _get(id)?.previous != null;

  void undo(String id) => _update(id, SessionLogic.undo);

  /// バックアップから読み込む。
  /// [replace] が true なら今のデータを全部置き換え、false なら今のデータに追加する
  /// （同じ対局がすでにある場合は今のデータを残す）。返り値は追加した件数。
  int importSessions(List<GameSession> incoming, {required bool replace}) {
    final List<GameSession> next;
    int added;
    if (replace) {
      next = List.of(incoming);
      added = incoming.length;
    } else {
      final existing = {for (final s in state) s.id};
      final toAdd = [for (final s in incoming) if (!existing.contains(s.id)) s];
      next = [...state, ...toAdd];
      added = toAdd.length;
    }
    next.sort((a, b) => b.createdAt.compareTo(a.createdAt)); // 新しい順
    state = List.unmodifiable(next);
    return added;
  }

  /// すべての対局でプレイヤーの名前を変える（まとめる）。変えた対局数と、変えられなかった対局数を返す
  ({int renamed, int skipped}) renamePlayer(String from, String to) {
    final r = SessionLogic.renamePlayer(state, from, to);
    if (r.renamed > 0) state = r.sessions;
    return (renamed: r.renamed, skipped: r.skipped);
  }

  void delete(String id) => state = state.where((s) => s.id != id).toList();
}
