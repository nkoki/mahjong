import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../domain/models.dart';
import '../session_providers.dart';

/// 卓の上での位置（手前・右・向かい・左）
enum TableSide { bottom, right, top, left }

/// 手前に [bottomPlayer] がいるとき、[player] が座っている位置。
/// 風の順（東→南→西→北）に反時計回りに座るので、下家は右・対面は向かい・上家は左。
/// 3人打ちでは北の席が空く。
TableSide tableSideOf(GameSession s, int player, int bottomPlayer) {
  final offset = (s.seatWindIndexOf(player) - s.seatWindIndexOf(bottomPlayer) + 4) % 4;
  return TableSide.values[offset];
}

/// 卓の真ん中に置いて、全員が自分の向きで点数を読める表示
class TableViewScreen extends ConsumerStatefulWidget {
  final String sessionId;
  const TableViewScreen({super.key, required this.sessionId});

  @override
  ConsumerState<TableViewScreen> createState() => _TableViewScreenState();
}

class _TableViewScreenState extends ConsumerState<TableViewScreen> {
  /// 手前（画面の下）に座っている人
  int _bottom = 0;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider(widget.sessionId));
    if (s == null) return const Scaffold();
    final theme = Theme.of(context);
    final top = s.scores.reduce((a, b) => a > b ? a : b);

    Widget panel(int p) {
      final side = tableSideOf(s, p, _bottom);
      final turns = switch (side) {
        TableSide.bottom => 0,
        TableSide.right => 3,
        TableSide.top => 2,
        TableSide.left => 1,
      };
      final diff = s.scores[p] - top;
      return RotatedBox(
        key: ValueKey('table-player-$p'),
        quarterTurns: turns,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${GameSession.windNames[s.seatWindIndexOf(p)]} ${s.playerNames[p]}',
                  style: theme.textTheme.titleMedium, overflow: TextOverflow.ellipsis),
              Text(formatPoints(s.scores[p]),
                  style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
              Text(
                s.riichi[p] ? '立直' : (diff == 0 ? 'トップ' : 'トップとの差 ${formatPoints(-diff)}'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: s.riichi[p] ? theme.colorScheme.error : null,
                  fontWeight: s.riichi[p] ? FontWeight.bold : null,
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget at(TableSide side) {
      for (var p = 0; p < s.playerCount; p++) {
        if (tableSideOf(s, p, _bottom) == side) return panel(p);
      }
      return const SizedBox.shrink(); // 3人打ちの空いた席
    }

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      body: SafeArea(
        child: Stack(
          children: [
            Align(alignment: Alignment.bottomCenter, child: Padding(padding: const EdgeInsets.only(bottom: 56), child: at(TableSide.bottom))),
            Align(alignment: Alignment.topCenter, child: at(TableSide.top)),
            Align(alignment: Alignment.centerLeft, child: at(TableSide.left)),
            Align(alignment: Alignment.centerRight, child: at(TableSide.right)),
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(s.finished ? '終局' : s.roundName, style: theme.textTheme.titleLarge),
                    Text('${s.honba}本場  供託${s.riichiSticks}本', style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.rotate_right),
                      label: const Text('回す'),
                      onPressed: () => setState(() => _bottom = (_bottom + 1) % s.playerCount),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.close),
                      label: const Text('閉じる'),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
