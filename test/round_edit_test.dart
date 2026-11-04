import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_app/features/history/history_detail_screen.dart';
import 'package:mahjong_app/features/session/data/session_repository.dart';
import 'package:mahjong_app/features/session/domain/models.dart';
import 'package:mahjong_app/features/session/domain/session_logic.dart';
import 'package:mahjong_app/features/session/session_providers.dart';

/// 3局進めた対局（東1: B テンパイ / 東2: 全員ノーテン / 東3: C テンパイ）
GameSession threeRounds() {
  var s = GameSession.start(
      id: 'x', playerNames: ['A', 'B', 'C', 'D'], settings: const GameSettings());
  s = SessionLogic.applyDraw(s, type: DrawType.exhaustive, tenpai: [false, true, false, false]);
  s = SessionLogic.applyDraw(s, type: DrawType.exhaustive, tenpai: [false, false, false, false]);
  s = SessionLogic.applyDraw(s, type: DrawType.exhaustive, tenpai: [false, false, true, false]);
  return s;
}

void main() {
  group('局の修正', () {
    test('差分がその局以降の点数と今の点数に反映され、局の進行は変わらない', () {
      final s = threeRounds();
      expect(s.records[0].deltas, [-1000, 3000, -1000, -1000]);
      // 東1局は本当は A のテンパイだった
      final e = SessionLogic.editRound(s, 0,
          deltas: [3000, -1000, -1000, -1000], description: 'A テンパイ');
      expect(e.records[0].deltas, [3000, -1000, -1000, -1000]);
      expect(e.records[0].edited, isTrue);
      expect(e.records[0].description, 'A テンパイ');
      expect(e.records[0].scoresAfter, [28000, 24000, 24000, 24000]);
      // 後の局は増減はそのまま、点数だけずれる
      expect(e.records[2].deltas, s.records[2].deltas);
      expect(e.records[2].scoresAfter,
          [for (var i = 0; i < 4; i++) s.records[2].scoresAfter[i] + [4000, -4000, 0, 0][i]]);
      expect(e.scores, e.records.last.scoresAfter);
      expect(e.roundStartScores, e.scores);
      expect(e.roundLabel, s.roundLabel);
      expect(e.dealer, s.dealer);
      expect(e.records[1].edited, isFalse);
    });

    test('入力チェック', () {
      final s = threeRounds();
      expect(SessionLogic.validateRoundEdit(s, 0, [3000, -1000, -1000, -1000]), isNull);
      expect(SessionLogic.validateRoundEdit(s, 0, [3000, -1000, -1000, null]), contains('すべて'));
      expect(SessionLogic.validateRoundEdit(s, 0, [3050, -1050, -1000, -1000]), contains('100点単位'));
      expect(SessionLogic.validateRoundEdit(s, 0, [3000, 0, -1000, -1000]), contains('合計を0'));
      expect(() => SessionLogic.editRound(s, 0, deltas: [1, 2, 3, 4]), throwsArgumentError);
    });

    test('立直棒を出した局は、合計が -1000 のまま修正する', () {
      var s = GameSession.start(
          id: 'x', playerNames: ['A', 'B', 'C', 'D'], settings: const GameSettings());
      s = SessionLogic.toggleRiichi(s, 0);
      s = SessionLogic.applyDraw(s, type: DrawType.exhaustive, tenpai: [true, false, false, false]);
      expect(s.records[0].deltas, [2000, -1000, -1000, -1000]);
      expect(SessionLogic.validateRoundEdit(s, 0, [3000, -1000, -1000, -1000]), contains('合計を-1000'));
      expect(SessionLogic.validateRoundEdit(s, 0, [-1000, 2000, -1000, -1000]), isNull);
    });

    test('終局時の供託は修正後のトップに付け替える', () {
      var s = GameSession.start(
          id: 'x', playerNames: ['A', 'B', 'C', 'D'], settings: const GameSettings());
      s = SessionLogic.applyDraw(s, type: DrawType.exhaustive, tenpai: [false, true, false, false]);
      s = SessionLogic.toggleRiichi(s, 3);
      s = SessionLogic.finishManually(s);
      // B がトップで供託1本を受け取っている
      expect(s.settledSticks, 1);
      expect(s.scores, [24000, 29000, 24000, 24000 - 1000]);

      // 東1局は本当は C のテンパイだった → トップは C になり、供託も C へ
      final e = SessionLogic.editRound(s, 0, deltas: [-1000, -1000, 3000, -1000]);
      expect(e.scores, [24000, 24000, 29000, 23000]);
      expect(e.ranking.first, 2);
      expect(e.scores.fold<int>(0, (a, v) => a + v), 100000);
    });

    test('元に戻すと修正前に戻る', () {
      final s = threeRounds();
      final e = SessionLogic.editRound(s, 1, deltas: [3000, -1000, -1000, -1000]);
      final u = SessionLogic.undo(e);
      expect(u.records[1].deltas, s.records[1].deltas);
      expect(u.scores, s.scores);
    });

    test('修正済みの印・供託の付け替え情報は保存して読み込んでも残る', () {
      var s = threeRounds();
      s = SessionLogic.editRound(s, 0, deltas: [3000, -1000, -1000, -1000]);
      s = SessionLogic.finishManually(s.copyWith(riichiSticks: 2));
      final restored = GameSession.fromJson(
          jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
      expect(restored.records[0].edited, isTrue);
      expect(restored.records[1].edited, isFalse);
      expect(restored.settledSticks, 2);
      // 修正前の状態（元に戻す用）も正しく読み込める
      var a = s, b = restored;
      while (a.previous != null && b.previous != null) {
        a = a.previous!;
        b = b.previous!;
        expect(b.records.map((r) => r.deltas), a.records.map((r) => r.deltas));
        expect(b.scores, a.scores);
      }
    });
  });

  testWidgets('戦績詳細から局を修正し、元に戻せる', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sessionRepositoryProvider.overrideWithValue(InMemorySessionRepository([threeRounds()])),
      ],
      child: const MaterialApp(home: HistoryDetailScreen(sessionId: 'x')),
    ));

    // 一覧は新しい順なので、最後のボタンが東1局
    await tester.tap(find.byTooltip('この局を修正').last);
    await tester.pumpAndSettle();
    expect(find.text('局の修正  東1局 0本場'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('delta-0')), '3000');
    await tester.pump();
    expect(find.textContaining('合計を0にしてください'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('delta-1')), '-1000');
    await tester.pump();
    expect(find.text('修正後の今の点数'), findsOneWidget);

    await tester.tap(find.text('修正を保存'));
    await tester.pumpAndSettle();
    expect(find.text('東1局 0本場（修正済み）'), findsOneWidget);
    expect(find.text('局を修正しました'), findsOneWidget);

    await tester.tap(find.text('元に戻す'));
    await tester.pumpAndSettle();
    expect(find.text('東1局 0本場（修正済み）'), findsNothing);
  });
}
