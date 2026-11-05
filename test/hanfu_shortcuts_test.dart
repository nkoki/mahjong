import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_app/features/session/data/session_repository.dart';
import 'package:mahjong_app/features/session/domain/session_logic.dart';
import 'package:mahjong_app/features/session/session_providers.dart';
import 'package:mahjong_app/features/win/hanfu_shortcuts.dart';
import 'package:mahjong_app/features/win/win_input_screen.dart';
import 'package:mahjong_app/features/win/win_result_screen.dart';

import 'han_fu_input_test.dart' show newGame;

/// 翻・符で入力するときのショートカット
void main() {
  test('最近の入力は新しい順に4つまで。同じものは前に出し、満貫以上は符を数えない', () {
    var r = <HanFuEntry>[];
    r = HanFuShortcuts.remember(r, const HanFuEntry(han: 3, fu: 30));
    r = HanFuShortcuts.remember(r, const HanFuEntry(han: 5, fu: 40));
    r = HanFuShortcuts.remember(r, const HanFuEntry(han: 3, fu: 30));
    expect(r.map(HanFuShortcuts.label), ['3翻30符', '満貫(5翻)']);
    expect(r[1].fu, 0);
    for (var h = 1; h <= 4; h++) {
      r = HanFuShortcuts.remember(r, HanFuEntry(han: h, fu: 50));
    }
    expect(r.length, 4);
    expect(HanFuShortcuts.label(r.first), '4翻50符');
  });

  test('保存する文字列との変換。壊れた部分は飛ばす', () {
    final list = [const HanFuEntry(han: 2, fu: 40), const HanFuEntry(yakuman: 2)];
    final text = HanFuShortcuts.encode(list);
    expect(text, '2,40,0;0,0,2');
    final back = HanFuShortcuts.decode(text);
    expect(HanFuShortcuts.same(back[0], list[0]) && HanFuShortcuts.same(back[1], list[1]), isTrue);
    expect(HanFuShortcuts.decode('x;1,30;3,30,0').map(HanFuShortcuts.label), ['3翻30符']);
    expect(HanFuShortcuts.decode(null), isEmpty);
    expect(HanFuShortcuts.label(const HanFuEntry(yakuman: 2)), '2倍役満');
    expect(HanFuShortcuts.label(const HanFuEntry(han: 11)), '三倍満(11翻)');
  });

  testWidgets('よく使う点数を1回押すだけで翻・符が入り、次からは最近の入力に出る', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 2000));
    final repo = InMemorySessionRepository([newGame()]);
    await tester.pumpWidget(ProviderScope(
      overrides: [sessionRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: WinInputScreen(sessionId: 'x')),
    ));
    final c = ProviderScope.containerOf(tester.element(find.byType(WinInputScreen)));
    await tester.tap(find.text('南 B').first);
    await tester.pump();
    await tester.tap(find.widgetWithText(ChoiceChip, '西 C').last);
    await tester.pump();
    await tester.tap(find.text('翻・符で入力'));
    await tester.pump();
    expect(find.text('よく使う（子のロン）'), findsOneWidget);
    await tester.tap(find.text('3翻30符 3900'));
    await tester.pump();
    expect(find.text('子のロン 3900点'), findsOneWidget);
    // 親のツモに変えると、表示も親のツモの点数になる
    await tester.tap(find.text('東 A').first);
    await tester.pump();
    await tester.tap(find.text('ツモ'));
    await tester.pump();
    expect(find.text('3翻30符 2000オール'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, '跳満(6翻) 6000オール'));
    await tester.pump();
    await tester.tap(find.text('計算'));
    await tester.pumpAndSettle();
    expect(find.byType(WinResultScreen), findsOneWidget);
    expect(c.read(preferenceProvider(PreferenceKeys.recentHanFu)), '6,0,0');
    await tester.pageBack();
    await tester.pumpAndSettle();
    final chip = find.ancestor(of: find.text('跳満(6翻) 6000オール'), matching: find.byType(ChoiceChip));
    expect(tester.widget<ChoiceChip>(chip).avatar, isNotNull, reason: '最近の入力として先頭に出る');
  });
}
