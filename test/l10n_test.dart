import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_app/core/l10n.dart';
import 'package:mahjong_app/features/session/data/session_repository.dart';
import 'package:mahjong_app/features/session/session_providers.dart';
import 'package:mahjong_app/main.dart';

/// 表示の言語（日本語・英語）
void main() {
  tearDown(() => L10n.isEnglish = false);

  test('tr と、保存データ（日本語）の表示の変換', () {
    expect(tr('和了', 'Win'), '和了');
    expect(displayRoundLabel('東1局 2本場'), '東1局 2本場');
    L10n.isEnglish = true;
    expect(tr('和了', 'Win'), 'Win');
    expect(displayRoundLabel('東1局 2本場'), 'East 1, 2 honba');
    expect(displayRoundLabel('南4局'), 'South 4');
    expect(displayRoundLabel('追加した局'), '追加した局');
    expect(windName(2), 'West');
    expect(yakuName('立直'), 'Riichi');
    expect(yakuName('役牌 場風東'), 'Yakuhai (Round wind East)');
    expect(yakuName('役牌 中'), 'Yakuhai (Red)');
    expect(yakuName('知らない役'), '知らない役');
    expect(limitName('跳満'), 'Haneman');
    expect(fuName('暗刻(么九牌)'), 'Closed triplet (terminal/honor)');
    expect(engineError('手牌の枚数が正しくありません（13枚必要、現在12枚）'), 'Wrong number of tiles in hand (need 13, have 12)');
    expect(AppLanguage.of('en'), AppLanguage.en);
    expect(AppLanguage.of(null), AppLanguage.ja);
  });

  testWidgets('保存した言語の設定でアプリ全体を表示する', (tester) async {
    final repo = InMemorySessionRepository([]);
    await repo.savePreference(PreferenceKeys.language, 'en');
    await tester.pumpWidget(ProviderScope(
      overrides: [sessionRepositoryProvider.overrideWithValue(repo)],
      child: const MahjongApp(),
    ));
    expect(L10n.isEnglish, isTrue);
  });
}
