import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../session/session_providers.dart';

/// 選べる文字の大きさ（表示名, 倍率）
List<(String, double)> get textScaleChoices =>
    [(tr('標準', 'Normal'), 1.0), (tr('大', 'Large'), 1.15), (tr('特大', 'Extra large'), 1.3)];

/// 画面の明るさ（端末の設定に合わせる・明るい・暗い）
ThemeMode themeModeOf(String? v) => switch (v) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

/// 文字の大きさの倍率（変な値なら標準）
double textScaleOf(String? v) {
  final d = double.tryParse(v ?? '');
  return textScaleChoices.any((c) => c.$2 == d) ? d! : 1.0;
}

/// 表示の言語
final languageProvider =
    Provider<AppLanguage>((ref) => AppLanguage.of(ref.watch(preferenceProvider(PreferenceKeys.language))));

final themeModeProvider =
    Provider<ThemeMode>((ref) => themeModeOf(ref.watch(preferenceProvider(PreferenceKeys.themeMode))));
final textScaleProvider =
    Provider<double>((ref) => textScaleOf(ref.watch(preferenceProvider(PreferenceKeys.textScale))));

/// アプリ全体の文字の大きさを [scale] 倍にする（端末の文字の大きさの設定にさらに掛ける）
Widget applyTextScale(BuildContext context, Widget? child, double scale) {
  final mq = MediaQuery.of(context);
  return MediaQuery(
    data: mq.copyWith(textScaler: TextScaler.linear(mq.textScaler.scale(1) * scale)),
    child: child ?? const SizedBox.shrink(),
  );
}

/// 表示の設定（明るさ・文字の大きさ）
class DisplaySettingsScreen extends ConsumerWidget {
  const DisplaySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final mode = ref.watch(themeModeProvider);
    final scale = ref.watch(textScaleProvider);
    return Scaffold(
      appBar: AppBar(title: Text(tr('表示の設定', 'Display'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('言語 / Language', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<AppLanguage>(
            key: const ValueKey('language'),
            segments: [for (final l in AppLanguage.values) ButtonSegment(value: l, label: Text(l.label))],
            selected: {ref.watch(languageProvider)},
            onSelectionChanged: (v) =>
                ref.read(preferenceProvider(PreferenceKeys.language).notifier).set(v.first.code),
          ),
          const SizedBox(height: 6),
          Text(
              tr('英語にすると、画面の表示が英語になります（保存した対局のメモなど、入力した文字はそのままです）。'
                      '切り替えるとホーム画面に戻ります。',
                  'Switches the app to English. Text you entered and notes saved earlier stay as they are. '
                  'Switching returns to the home screen.'),
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 24),
          Text(tr('画面の明るさ', 'Theme'), style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<ThemeMode>(
            segments: [
              ButtonSegment(value: ThemeMode.system, label: Text(tr('端末に合わせる', 'System'))),
              ButtonSegment(value: ThemeMode.light, label: Text(tr('明るい', 'Light'))),
              ButtonSegment(value: ThemeMode.dark, label: Text(tr('暗い', 'Dark'))),
            ],
            selected: {mode},
            onSelectionChanged: (v) => ref
                .read(preferenceProvider(PreferenceKeys.themeMode).notifier)
                .set(switch (v.first) { ThemeMode.light => 'light', ThemeMode.dark => 'dark', _ => 'system' }),
          ),
          const SizedBox(height: 6),
          Text(tr('「暗い」は夜や暗い場所で見やすく、画面のまぶしさを抑えます。', '"Dark" is easier on the eyes at night or in dim places.'), style: theme.textTheme.bodySmall),
          const SizedBox(height: 24),
          Text(tr('文字の大きさ', 'Text size'), style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<double>(
            segments: [for (final c in textScaleChoices) ButtonSegment(value: c.$2, label: Text(c.$1))],
            selected: {scale},
            onSelectionChanged: (v) =>
                ref.read(preferenceProvider(PreferenceKeys.textScale).notifier).set('${v.first}'),
          ),
          const SizedBox(height: 6),
          Text(
              tr('端末の文字の大きさの設定に、さらに掛け合わせます。大きくすると、画面によっては1行に入りきらず折り返します。',
                  'Multiplied by your device text size setting. Larger sizes may wrap onto more lines on some screens.'),
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('見本', 'Preview'), style: theme.textTheme.labelMedium),
                  Text(displayRoundLabel('東1局 0本場'), style: theme.textTheme.titleLarge),
                  Text('25,000', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                  Text(tr('この大きさで表示します。設定はこの端末に保存されます。', 'Text will appear at this size. The setting is saved on this device.')),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
