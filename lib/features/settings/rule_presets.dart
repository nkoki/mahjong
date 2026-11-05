import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../session/domain/models.dart';
import '../session/session_providers.dart';

/// 名前を付けて保存したルール（「いつもの面子」「雀荘ルール」など）
class RulePreset {
  final String name;
  final GameSettings settings;
  const RulePreset(this.name, this.settings);

  int get playerCount => settings.playerCount;

  Map<String, dynamic> toJson() => {'name': name, 'settings': settings.toJson()};
}

/// ルールのセットの保存・読み込み（UI に依存しない）
class RulePresets {
  RulePresets._();

  /// 保存できる数（4人打ち・3人打ちを合わせて）
  static const max = 20;

  /// 名前の長さの上限
  static const maxNameLength = 20;

  /// 保存した文字列から読む（壊れている部分は飛ばす）
  static List<RulePreset> decode(String? text) {
    if (text == null || text.isEmpty) return const [];
    try {
      final list = jsonDecode(text) as List;
      return [
        for (final e in list)
          if (e is Map<String, dynamic>)
            if (_tryParse(e) case final p?) p
      ];
    } catch (_) {
      return const [];
    }
  }

  static RulePreset? _tryParse(Map<String, dynamic> e) {
    try {
      return RulePreset(e['name'] as String, GameSettings.fromJson(e['settings'] as Map<String, dynamic>));
    } catch (_) {
      return null;
    }
  }

  static String encode(List<RulePreset> list) => jsonEncode([for (final p in list) p.toJson()]);

  /// 名前のチェック（問題なければ null）
  static String? validateName(String name) {
    final t = name.trim();
    if (t.isEmpty) return tr('名前を入力してください', 'Enter a name');
    if (t.length > maxNameLength) return tr('$maxNameLength文字までにしてください', 'Up to $maxNameLength characters');
    return null;
  }

  /// 同じ人数・同じ名前のセットがあれば上書きし、なければ先頭に足す。上限を超えたら null
  static List<RulePreset>? save(List<RulePreset> list, String name, GameSettings settings) {
    final t = name.trim();
    final i = list.indexWhere((p) => p.name == t && p.playerCount == settings.playerCount);
    if (i >= 0) {
      return [for (var j = 0; j < list.length; j++) j == i ? RulePreset(t, settings) : list[j]];
    }
    if (list.length >= max) return null;
    return [RulePreset(t, settings), ...list];
  }

  static List<RulePreset> remove(List<RulePreset> list, RulePreset p) =>
      [for (final e in list) if (!(e.name == p.name && e.playerCount == p.playerCount)) e];
}

/// 保存したルールのセット
final rulePresetsProvider = Provider<List<RulePreset>>(
    (ref) => RulePresets.decode(ref.watch(preferenceProvider(PreferenceKeys.rulePresets))));

/// ルールのセットを保存し直す
void saveRulePresets(WidgetRef ref, List<RulePreset> list) =>
    ref.read(preferenceProvider(PreferenceKeys.rulePresets).notifier).set(RulePresets.encode(list));
