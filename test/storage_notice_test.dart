import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_app/features/session/data/session_repository.dart';
import 'package:mahjong_app/features/session/domain/models.dart';
import 'package:mahjong_app/features/session/session_providers.dart';
import 'package:mahjong_app/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 保存に必ず失敗する保存先（容量オーバーなどを想定）
class FailingRepository extends InMemorySessionRepository {
  @override
  Future<void> saveAll(List<GameSession> sessions) async =>
      throw Exception('QuotaExceededError');
}

/// 読み込み時に問題があった保存先
class WarningRepository extends InMemorySessionRepository {
  @override
  List<String> get loadWarnings => ['保存データが壊れていて読み込めない対局が1件ありました。'];
}

Future<void> pumpApp(WidgetTester tester, SessionRepository repo) async {
  await tester.binding.setSurfaceSize(const Size(400, 900));
  await tester.pumpWidget(ProviderScope(
    overrides: [sessionRepositoryProvider.overrideWithValue(repo)],
    child: const MahjongApp(),
  ));
}

void main() {
  testWidgets('ホーム画面に保存の注意と保存状況が表示される', (tester) async {
    await pumpApp(tester, InMemorySessionRepository());
    expect(find.text('データの保存について'), findsOneWidget);
    expect(find.textContaining('アプリを削除したり'), findsOneWidget);
    expect(find.textContaining('保存中の対局: 0 / 100件'), findsOneWidget);

    await tester.tap(find.text('データの保存について'));
    await tester.pumpAndSettle();
    expect(find.text('この端末だけに保存されます'), findsOneWidget);
    expect(find.text('削除した対局は元に戻せません'), findsOneWidget);
    expect(find.textContaining('直近10回'), findsWidgets);
    expect(find.text('保存されるのは最新100対局まで'), findsOneWidget);
  });

  testWidgets('保存に失敗するとお知らせが出る', (tester) async {
    await pumpApp(tester, FailingRepository());
    await tester.tap(find.text('新規対局'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('対局開始'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('対局開始'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1)); // 画面の切り替えが終わるまで
    // どの画面にいてもスナックバーでお知らせ
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.descendant(
            of: find.byType(SnackBar),
            matching: find.textContaining('対局データを保存できませんでした')),
        findsOneWidget);

    // スナックバーが消えたあとも、ホーム画面には残る
    await tester.pumpAndSettle(const Duration(seconds: 10));
    expect(find.byType(SnackBar), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.textContaining('対局データを保存できませんでした'), findsOneWidget);
  });

  testWidgets('読み込みの問題がお知らせされ、閉じると消える', (tester) async {
    await pumpApp(tester, WarningRepository());
    expect(find.textContaining('読み込めない対局が1件'), findsOneWidget);
    await tester.tap(find.byTooltip('閉じる'));
    await tester.pump();
    expect(find.textContaining('読み込めない対局が1件'), findsNothing);
  });

  test('保存容量の使用量を計算できる', () async {
    SharedPreferences.setMockInitialValues({'other_app_key': 'x' * 1000});
    final prefs = await SharedPreferences.getInstance();
    final repo = SharedPrefsSessionRepository(prefs);
    expect(repo.usage().bytes, 0); // このアプリ以外のデータは数えない
    await repo.saveAll([
      GameSession.start(id: 'a', playerNames: ['A', 'B', 'C', 'D'], settings: const GameSettings()),
    ]);
    expect(repo.usage().bytes, greaterThan(300));
  });

  test('上限の50%以上で「上限に近い」と判定する', () {
    expect(const StorageUsage(bytes: 2400000, limitBytes: 5000000).isNearLimit, isFalse);
    expect(const StorageUsage(bytes: 2500000, limitBytes: 5000000).isNearLimit, isTrue);
    expect(const StorageUsage(bytes: 99999999).isNearLimit, isFalse); // 上限なし（スマホ）
  });
}
