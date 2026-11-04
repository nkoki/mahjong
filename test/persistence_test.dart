import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_app/features/session/data/session_repository.dart';
import 'package:mahjong_app/features/session/domain/models.dart';
import 'package:mahjong_app/features/session/session_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 立直・流局・和了相当の進行をした対局を作る
GameSession playedSession(ProviderContainer c) {
  final n = c.read(sessionsProvider.notifier);
  final id = n.create(['A', 'B', 'C', 'D'],
      const GameSettings(tonpuu: true, uma: [30, 10, -10, -30]));
  n.toggleRiichi(id, 1);
  n.applyDraw(id, type: DrawType.exhaustive, tenpai: [false, true, false, false]);
  n.toggleRiichi(id, 2);
  return c.read(sessionProvider(id))!;
}

void expectSameSession(GameSession a, GameSession b) {
  expect(jsonEncode(b.toJson()), jsonEncode(a.toJson()));
  expect(b.createdAt, a.createdAt);
  expect(b.scores, a.scores);
  expect(b.riichi, a.riichi);
  expect(b.riichiSticks, a.riichiSticks);
  expect(b.roundLabel, a.roundLabel);
  expect(b.records.length, a.records.length);
  expect(b.settings.uma, a.settings.uma);
  expect(b.settings.tonpuu, a.settings.tonpuu);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('JSON に変換して戻しても同じ内容になる（元に戻す履歴も含む）', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final s = playedSession(c);
    final restored = GameSession.fromJson(
        jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
    expectSameSession(s, restored);
    expect(restored.previous, isNotNull);
    expect(restored.previous!.roundLabel, '東1局 0本場');
  });

  test('元に戻す履歴は直近の指定段数までだけ保存する', () {
    var s = GameSession.start(
        id: 'x', playerNames: ['A', 'B', 'C', 'D'], settings: const GameSettings());
    for (var i = 0; i < 5; i++) {
      s = s.copyWith(honba: i + 1, previous: s);
    }
    var j = s.toJson(undoDepth: 2);
    var depth = 0;
    while (j['previous'] != null) {
      j = j['previous'] as Map<String, dynamic>;
      depth++;
    }
    expect(depth, 2);
  });

  test('アプリを再起動しても対局が残っている', () async {
    final prefs = await SharedPreferences.getInstance();
    final c1 = ProviderContainer(overrides: [
      sessionRepositoryProvider.overrideWithValue(SharedPrefsSessionRepository(prefs)),
    ]);
    final s = playedSession(c1);
    await Future<void>.delayed(Duration.zero); // 非同期の保存を待つ
    c1.dispose();

    // 「再起動」: 新しいコンテナで端末から読み直す
    final c2 = ProviderContainer(overrides: [
      sessionRepositoryProvider.overrideWithValue(SharedPrefsSessionRepository(prefs)),
    ]);
    addTearDown(c2.dispose);
    final loaded = c2.read(sessionsProvider);
    expect(loaded, hasLength(1));
    expectSameSession(s, loaded.single);

    // 読み込み後も続きから操作でき、元に戻すも使える
    c2.read(sessionsProvider.notifier).undo(s.id);
    expect(c2.read(sessionProvider(s.id))!.roundLabel, '東1局 0本場');
  });

  test('削除も保存される', () async {
    final repo = InMemorySessionRepository();
    final c = ProviderContainer(
        overrides: [sessionRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(c.dispose);
    final s = playedSession(c);
    await Future<void>.delayed(Duration.zero);
    expect(repo.saved, hasLength(1));
    c.read(sessionsProvider.notifier).delete(s.id);
    await Future<void>.delayed(Duration.zero);
    expect(repo.saved, isEmpty);
  });

  test('壊れたデータがあっても起動でき、元のデータは退避される', () async {
    SharedPreferences.setMockInitialValues(
        {SharedPrefsSessionRepository.storageKey: '{壊れたJSON'});
    final prefs = await SharedPreferences.getInstance();
    final repo = SharedPrefsSessionRepository(prefs);
    expect(repo.loadAll(), isEmpty);
    expect(prefs.getString(SharedPrefsSessionRepository.corruptKey), '{壊れたJSON');
    expect(prefs.getString(SharedPrefsSessionRepository.storageKey), isNull);
  });
}
