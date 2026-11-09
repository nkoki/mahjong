import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n.dart';
import '../../draw/draw_input_screen.dart';
import '../../win/win_input_screen.dart';
import '../domain/models.dart';
import '../session_providers.dart';
import 'table_layout.dart';

/// 卓の上での位置（手前・右・向かい・左）
enum TableSide { bottom, right, top, left }

/// 手前に [bottomPlayer] がいるとき、[player] が座っている位置。
/// 風の順（東→南→西→北）に反時計回りに座るので、下家は右・対面は向かい・上家は左。
/// 3人打ちでは北の席が空く。
TableSide tableSideOf(GameSession s, int player, int bottomPlayer) {
  final offset = (s.seatWindIndexOf(player) - s.seatWindIndexOf(bottomPlayer) + 4) % 4;
  return TableSide.values[offset];
}

/// 卓の真ん中に置いて、全員が自分の向きで点数を読める表示（卓の形。席の立直・和了も押せる）
class TableViewScreen extends ConsumerStatefulWidget {
  final String sessionId;
  const TableViewScreen({super.key, required this.sessionId});

  @override
  ConsumerState<TableViewScreen> createState() => _TableViewScreenState();
}

class _TableViewScreenState extends ConsumerState<TableViewScreen> {
  /// 手前（画面の下）に座っている人
  int _bottom = 0;

  void _push(Widget screen) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  Future<void> _undo() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(tr('直前の局の入力を取り消しますか？', 'Undo the last round entry?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('キャンセル', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('取り消す', 'Undo'))),
        ],
      ),
    );
    if (ok == true) ref.read(sessionsProvider.notifier).undo(widget.sessionId);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider(widget.sessionId));
    if (s == null) return const Scaffold();
    final notifier = ref.read(sessionsProvider.notifier);
    const fg = Color(0xFFF7F3EA);
    final buttonStyle = TextButton.styleFrom(foregroundColor: fg, disabledForegroundColor: const Color(0x66F7F3EA));

    return Scaffold(
      backgroundColor: const Color(0xFF16382C),
      body: SafeArea(
        child: Column(
          children: [
            if (s.finished)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(tr('終局しました', 'Game over'),
                    style: const TextStyle(color: fg, fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            // 卓の形で表示。各席はその人の向きに回し、席の「立直」「和了」をそのまま押せる
            Expanded(
              child: MahjongTableView(
                session: s,
                faceEachPlayer: true,
                bottomPlayer: _bottom,
                onRiichi: (p) => notifier.toggleRiichi(widget.sessionId, p),
                onWin: (p) => _push(WinInputScreen(sessionId: widget.sessionId, initialWinner: p)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 4,
                children: [
                  if (!s.finished)
                    TextButton.icon(
                      key: const ValueKey('table-draw'),
                      style: buttonStyle,
                      icon: const Icon(Icons.water_drop_outlined),
                      label: Text(tr('流局', 'Draw')),
                      onPressed: () => _push(DrawInputScreen(sessionId: widget.sessionId)),
                    ),
                  TextButton.icon(
                    key: const ValueKey('table-undo'),
                    style: buttonStyle,
                    icon: const Icon(Icons.undo),
                    label: Text(tr('戻す', 'Undo')),
                    onPressed: s.previous == null ? null : _undo,
                  ),
                  TextButton.icon(
                    style: buttonStyle,
                    icon: const Icon(Icons.rotate_right),
                    label: Text(tr('回す', 'Rotate')),
                    onPressed: () => setState(() => _bottom = (_bottom + 1) % s.playerCount),
                  ),
                  TextButton.icon(
                    style: buttonStyle,
                    icon: const Icon(Icons.close),
                    label: Text(tr('閉じる', 'Close')),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
