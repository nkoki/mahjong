import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'session_providers.dart';

/// 画面を自動で消さない（スリープしない）ようにする（テストでは差し替える）
abstract class ScreenAwake {
  Future<void> setAwake(bool awake);
}

/// wakelock_plus を使った実装（Android・iOS・Web）
class WakelockScreenAwake implements ScreenAwake {
  const WakelockScreenAwake();

  @override
  Future<void> setAwake(bool awake) async {
    try {
      await WakelockPlus.toggle(enable: awake);
    } catch (e) {
      // 対応していない環境では何もしない（画面が消えるだけ）
      debugPrint('画面を消さない設定を変えられませんでした: $e');
    }
  }
}

final screenAwakeProvider = Provider<ScreenAwake>((ref) => const WakelockScreenAwake());

/// 対局中は画面を消さないか（表示などの設定。初期値はオン）
bool keepScreenOn(WidgetRef ref) => ref.watch(preferenceProvider(PreferenceKeys.keepScreenOn)) != '0';

/// [active] の間（かつ設定がオンのとき）、画面を自動で消さないようにする
class KeepScreenOn extends ConsumerStatefulWidget {
  final bool active;
  final Widget child;
  const KeepScreenOn({super.key, required this.active, required this.child});

  @override
  ConsumerState<KeepScreenOn> createState() => _KeepScreenOnState();
}

class _KeepScreenOnState extends ConsumerState<KeepScreenOn> {
  bool? _applied;
  late final ScreenAwake _service = ref.read(screenAwakeProvider);

  void _apply(bool awake) {
    if (_applied == awake) return;
    _applied = awake;
    _service.setAwake(awake);
  }

  @override
  Widget build(BuildContext context) {
    _apply(widget.active && keepScreenOn(ref));
    return widget.child;
  }

  @override
  void dispose() {
    if (_applied == true) _service.setAwake(false);
    super.dispose();
  }
}
