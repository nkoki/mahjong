import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_app/features/history/history_detail_screen.dart';
import 'package:mahjong_app/features/session/data/session_repository.dart';
import 'package:mahjong_app/features/session/domain/models.dart';
import 'package:mahjong_app/features/session/screens/new_session_screen.dart';
import 'package:mahjong_app/features/session/session_providers.dart';

void main() {
  group('ウマの表記', () {
    test('よくある形は「小-大」', () {
      expect(formatUma([20, 10, -10, -20]), '10-20');
      expect(formatUma([15, 5, -5, -15]), '5-15');
      expect(formatUma([0, 0, 0, 0]), 'なし');
    });
    test('それ以外は4つ並べる', () {
      expect(formatUma([30, 0, -10, -20]), '+30 / 0 / -10 / -20');
    });
  });

  group('入力チェック', () {
    test('持ち点', () {
      expect(validatePoints(27000), isNull);
      expect(validatePoints(null), isNotNull);
      expect(validatePoints(27050), contains('100点単位'));
      expect(validatePoints(500), contains('範囲'));
    });
    test('返しは持ち点以上', () {
      expect(validateReturnPoints(30000, 27000), isNull);
      expect(validateReturnPoints(25000, 27000), contains('持ち点以上'));
    });
    test('ウマは合計0', () {
      expect(validateUma([15, 5, -5, -15]), isNull);
      expect(validateUma([15, 5, -5, null]), contains('すべて'));
      expect(validateUma([20, 10, -10, -10]), contains('合計'));
    });
  });

  test('ウマを変えると最終ポイントが変わり、元に戻してもウマはそのまま', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(sessionsProvider.notifier);
    final id = n.create(['A', 'B', 'C', 'D'],
        const GameSettings(startingPoints: 25000, returnPoints: 25000, uma: [20, 10, -10, -20]));
    n.applyDraw(id, type: DrawType.exhaustive, tenpai: [true, false, false, false]);
    n.finish(id);
    // A: 28000点 1位
    expect(c.read(sessionProvider(id))!.finalResults.first.point, closeTo(3 + 20, 0.001));

    n.updateUma(id, [30, 10, -10, -30]);
    final s = c.read(sessionProvider(id))!;
    expect(s.settings.umaLabel, '10-30');
    expect(s.finalResults.first.point, closeTo(3 + 30, 0.001));
    expect(s.finalResults.fold<double>(0, (a, r) => a + r.point), closeTo(0, 0.001));

    n.undo(id); // 終局前に戻る
    expect(c.read(sessionProvider(id))!.settings.uma, [30, 10, -10, -30]);
  });

  group('画面', () {
    Future<ProviderContainer> pump(WidgetTester tester, Widget home,
        [List<GameSession> sessions = const []]) async {
      await tester.binding.setSurfaceSize(const Size(420, 1400));
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sessionRepositoryProvider.overrideWithValue(InMemorySessionRepository(sessions)),
        ],
        child: MaterialApp(home: home),
      ));
      return ProviderScope.containerOf(tester.element(find.byType(home.runtimeType)));
    }

    testWidgets('新規対局で持ち点・返し・ウマを自由な値にできる', (tester) async {
      final c = await pump(tester, const NewSessionScreen());
      await tester.enterText(find.widgetWithText(TextField, '持ち点'), '27000');
      await tester.enterText(find.widgetWithText(TextField, '返し'), '32000');
      for (final (i, v) in [(0, '15'), (1, '5'), (2, '-5'), (3, '-15')]) {
        await tester.enterText(find.byKey(ValueKey('uma-$i')), v);
      }
      await tester.pump();
      expect(find.textContaining('オカ（トップが受け取る分）: +20.0'), findsOneWidget);

      await tester.tap(find.text('対局開始'));
      await tester.pumpAndSettle();
      final s = c.read(sessionsProvider).single;
      expect(s.settings.startingPoints, 27000);
      expect(s.settings.returnPoints, 32000);
      expect(s.settings.uma, [15, 5, -5, -15]);
      expect(s.scores, [27000, 27000, 27000, 27000]);
    });

    testWidgets('入力に誤りがあると開始できない', (tester) async {
      final c = await pump(tester, const NewSessionScreen());
      await tester.enterText(find.byKey(const ValueKey('uma-3')), '-10');
      await tester.pump();
      expect(find.textContaining('合計が0になるように'), findsOneWidget);
      final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, '対局開始'));
      expect(button.onPressed, isNull);

      await tester.enterText(find.widgetWithText(TextField, '持ち点'), '25050');
      await tester.pump();
      expect(find.text('100点単位で入力してください'), findsOneWidget);
      expect(c.read(sessionsProvider), isEmpty);
    });

    testWidgets('よく使う値のボタンを押すと入力欄に入る', (tester) async {
      await pump(tester, const NewSessionScreen());
      await tester.tap(find.widgetWithText(ChoiceChip, '10-30'));
      await tester.pump();
      expect(tester.widget<TextField>(find.byKey(const ValueKey('uma-0'))).controller!.text, '30');
      expect(tester.widget<TextField>(find.byKey(const ValueKey('uma-3'))).controller!.text, '-30');
    });

    testWidgets('戦績詳細でウマを変更できる', (tester) async {
      final session = GameSession.start(
              id: 'x',
              playerNames: ['A', 'B', 'C', 'D'],
              settings: const GameSettings(returnPoints: 25000))
          .copyWith(scores: [40000, 30000, 20000, 10000], finished: true);
      final c = await pump(tester, const HistoryDetailScreen(sessionId: 'x'), [session]);
      expect(find.text('ウマ: 10-20'), findsOneWidget);
      expect(find.text('+35.0'), findsOneWidget); // 1位: +15 + 20

      await tester.tap(find.widgetWithText(OutlinedButton, '変更'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.widgetWithText(ChoiceChip, '10-30')));
      await tester.pump();
      await tester.tap(find.text('変更する'));
      await tester.pumpAndSettle();

      expect(find.text('ウマ: 10-30'), findsOneWidget);
      expect(find.text('+45.0'), findsOneWidget); // 1位: +15 + 30
      expect(c.read(sessionProvider('x'))!.settings.uma, [30, 10, -10, -30]);
    });
  });
}
