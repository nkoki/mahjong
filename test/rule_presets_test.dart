import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_app/features/session/data/session_repository.dart';
import 'package:mahjong_app/features/session/domain/models.dart';
import 'package:mahjong_app/features/session/screens/new_session_screen.dart';
import 'package:mahjong_app/features/session/session_providers.dart';
import 'package:mahjong_app/features/settings/rule_presets.dart';
import 'package:mahjong_app/features/settings/rule_settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ルールのセット
void main() {
  test('保存・上書き・削除・上限。壊れた部分は飛ばして読む', () {
    var list = <RulePreset>[];
    list = RulePresets.save(list, ' 雀荘 ', const GameSettings(kiriageMangan: true))!;
    list = RulePresets.save(list, '雀荘', const GameSettings.sanma())!;
    expect(list.length, 2, reason: '人数が違えば別のセット');
    list = RulePresets.save(list, '雀荘', const GameSettings(uma: [30, 10, -10, -30]))!;
    expect(list.length, 2);
    final four = list.firstWhere((p) => p.playerCount == 4);
    expect(four.settings.uma, [30, 10, -10, -30]);
    final back = RulePresets.decode(RulePresets.encode(list));
    expect(back.map((p) => '${p.name}/${p.playerCount}'), ['雀荘/3', '雀荘/4']);
    expect(back.last.settings.uma, [30, 10, -10, -30]);
    expect(RulePresets.remove(back, back.first).single.playerCount, 4);
    expect(RulePresets.decode('[{"name":"x"}, 1, {"name":"ok","settings":${'{"startingPoints":25000,"returnPoints":30000,"uma":[0,0,0,0],"tonpuu":true,"tobi":false}'}}]')
        .single.settings.tonpuu, isTrue);
    expect(RulePresets.decode('こわれた'), isEmpty);
    var full = <RulePreset>[];
    for (var i = 0; i < RulePresets.max; i++) {
      full = RulePresets.save(full, 'r$i', const GameSettings())!;
    }
    expect(RulePresets.save(full, 'over', const GameSettings()), isNull);
    expect(RulePresets.save(full, 'r3', const GameSettings()), isNotNull, reason: '上書きはできる');
    expect(RulePresets.validateName(' '), isNotNull);
    expect(RulePresets.validateName('a' * 21), isNotNull);
  });

  testWidgets('ルール設定で保存し、新規対局の画面で選ぶと切り替わる', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(420, 4000));
    final repo = InMemorySessionRepository([]);
    await tester.pumpWidget(ProviderScope(
      overrides: [sessionRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: RuleSettingsScreen()),
    ));
    await tester.pumpAndSettle();
    final c = ProviderScope.containerOf(tester.element(find.byType(RuleSettingsScreen)));
    await tester.tap(find.text('東風'));
    await tester.tap(find.text('切り上げ満貫'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('preset-save')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('preset-name')), '雀荘ルール');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '保存').last);
    await tester.pumpAndSettle();
    final saved = c.read(rulePresetsProvider).single;
    expect(saved.name, '雀荘ルール');
    expect(saved.settings.tonpuu, isTrue);
    expect(saved.settings.kiriageMangan, isTrue);
    expect(c.read(defaultSettingsProvider).tonpuu, isFalse, reason: 'セットの保存では、いつものルールは変わらない');

    await tester.pumpWidget(ProviderScope(
      key: UniqueKey(),
      overrides: [sessionRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: NewSessionScreen()),
    ));
    await tester.pumpAndSettle();
    final c2 = ProviderScope.containerOf(tester.element(find.byType(NewSessionScreen)));
    expect(find.textContaining('切り上げ満貫なし'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('new-preset-雀荘ルール')));
    await tester.pump();
    expect(find.textContaining('切り上げ満貫あり'), findsOneWidget);
    await tester.ensureVisible(find.text('対局開始'));
    await tester.tap(find.text('対局開始'));
    await tester.pumpAndSettle();
    final s = c2.read(sessionsProvider).single;
    expect(s.settings.tonpuu, isTrue);
    expect(s.settings.kiriageMangan, isTrue);
  });
}
