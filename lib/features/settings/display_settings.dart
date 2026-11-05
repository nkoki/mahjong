import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../session/session_providers.dart';

/// 選べる文字の大きさ（表示名, 倍率）
const textScaleChoices = [('標準', 1.0), ('大', 1.15), ('特大', 1.3)];

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
      appBar: AppBar(title: const Text('表示の設定')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('画面の明るさ', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('端末に合わせる')),
              ButtonSegment(value: ThemeMode.light, label: Text('明るい')),
              ButtonSegment(value: ThemeMode.dark, label: Text('暗い')),
            ],
            selected: {mode},
            onSelectionChanged: (v) => ref
                .read(preferenceProvider(PreferenceKeys.themeMode).notifier)
                .set(switch (v.first) { ThemeMode.light => 'light', ThemeMode.dark => 'dark', _ => 'system' }),
          ),
          const SizedBox(height: 6),
          Text('「暗い」は夜や暗い場所で見やすく、画面のまぶしさを抑えます。', style: theme.textTheme.bodySmall),
          const SizedBox(height: 24),
          Text('文字の大きさ', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<double>(
            segments: [for (final c in textScaleChoices) ButtonSegment(value: c.$2, label: Text(c.$1))],
            selected: {scale},
            onSelectionChanged: (v) =>
                ref.read(preferenceProvider(PreferenceKeys.textScale).notifier).set('${v.first}'),
          ),
          const SizedBox(height: 6),
          Text('端末の文字の大きさの設定に、さらに掛け合わせます。大きくすると、画面によっては1行に入りきらず折り返します。',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('見本', style: theme.textTheme.labelMedium),
                  Text('東1局 0本場', style: theme.textTheme.titleLarge),
                  Text('25,000', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const Text('この大きさで表示します。設定はこの端末に保存されます。'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
