import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mahjong_score_engine/mahjong_score_engine.dart';

import 'domain/models.dart';
import 'domain/session_logic.dart';

/// 全対局の一覧（インメモリ保存。アプリ終了で消える）
final sessionsProvider =
    NotifierProvider<SessionsNotifier, List<GameSession>>(SessionsNotifier.new);

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
  List<GameSession> build() => const [];

  /// 新規対局を作成してIDを返す
  String create(List<String> names, GameSettings settings) {
    final id = '${DateTime.now().millisecondsSinceEpoch}-${_counter++}';
    final session =
        GameSession.start(id: id, playerNames: names, settings: settings);
    state = [session, ...state];
    return id;
  }

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

  void delete(String id) => state = state.where((s) => s.id != id).toList();
}
