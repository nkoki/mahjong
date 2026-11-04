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

  /// 100局分の記録がある対局（元に戻す履歴つき）
  GameSession hundredRounds() {
    var s = GameSession.start(
        id: 'big',
        playerNames: ['プレイヤー1', 'プレイヤー2', 'プレイヤー3', 'プレイヤー4'],
        settings: const GameSettings(tobi: false));
    for (var i = 0; i < 100; i++) {
      final rec = RoundRecord(
        roundLabel: '南4局 12本場',
        kind: 'win',
        description: 'プレイヤー2 ロン ← プレイヤー3 3翻 40符 5200  [立直 断么九 赤ドラ]',
        deltas: const [0, 6200, -5200, -1000],
        scoresAfter: [25000 + i, 31200, 19800, 24000],
      );
      s = s.copyWith(records: [...s.records, rec], previous: s, honba: i + 1);
    }
    return s;
  }

  test('100局＋元に戻す10回分でも約25KB程度に収まる', () {
    final s = hundredRounds();
    final full = utf8.encode(jsonEncode(s.toJson())).length;
    final noUndo = utf8.encode(jsonEncode(s.toJson(undoDepth: 0))).length;
    // 元に戻す履歴1回分は数百バイト程度
    expect(full - noUndo, lessThan(10 * 400));
    expect(full, lessThan(30000));
  });

  test('元に戻す履歴の記録・点数が正しく復元される', () {
    final s = hundredRounds();
    final restored = GameSession.fromJson(
        jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
    var a = s, b = restored;
    for (var i = 0; i < 10; i++) {
      a = a.previous!;
      b = b.previous!;
      expect(b.records.length, a.records.length);
      expect(b.honba, a.honba);
      expect(b.playerNames, a.playerNames);
      expect(b.records.last.scoresAfter, a.records.last.scoresAfter);
    }
    expect(b.previous, isNull); // 11段目以降は保存しない
  });

  test('以前の形式（version 1）のデータも読み込める', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final s = playedSession(c);
    // version 1: 元に戻す履歴にも名前・ルール・記録を丸ごと保存していた
    Map<String, dynamic> v1(GameSession x) => {
          'id': x.id,
          'createdAt': x.createdAt.toIso8601String(),
          'playerNames': x.playerNames,
          'settings': x.settings.toJson(),
          'scores': x.scores,
          'roundIndex': x.roundIndex,
          'honba': x.honba,
          'riichiSticks': x.riichiSticks,
          'riichi': x.riichi,
          'roundStartScores': x.roundStartScores,
          'records': [for (final r in x.records) r.toJson()],
          'finished': x.finished,
          if (x.previous != null) 'previous': v1(x.previous!),
        };
    SharedPreferences.setMockInitialValues({
      SharedPrefsSessionRepository.storageKey: jsonEncode({
        'version': 1,
        'sessions': [v1(s)],
      }),
    });
    final prefs = await SharedPreferences.getInstance();
    final loaded = SharedPrefsSessionRepository(prefs).loadAll();
    expectSameSession(s, loaded.single);
    expect(loaded.single.previous!.records.length, s.previous!.records.length);
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
