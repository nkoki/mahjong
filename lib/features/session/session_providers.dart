import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mahjong_score_engine/mahjong_score_engine.dart';

import 'data/session_repository.dart';
import 'domain/models.dart';
import 'domain/session_logic.dart';

/// 対局データの保存先。main() で端末保存の実装に差し替える。
final sessionRepositoryProvider = Provider<SessionRepository>(
  (ref) => InMemorySessionRepository(),
);

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
      ref.read(saveErrorProvider.notifier).state =
          '対局データを保存できませんでした。端末（ブラウザ）の保存容量がいっぱいの可能性があります。'
          '不要な対局を削除してください。';
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
          {required List<int> deltas, String? description}) =>
      _update(
          id,
          (s) => SessionLogic.editRound(s, index,
              deltas: deltas, description: description));

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
  }) =>
      _update(
        id,
        (s) => SessionLogic.applyWins(s,
            wins: wins, loser: loser, description: description),
      );

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

  void delete(String id) => state = state.where((s) => s.id != id).toList();
}
