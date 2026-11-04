import 'package:flutter/material.dart';
import 'package:mahjong_score_engine/mahjong_score_engine.dart';

import 'tile_view.dart';

/// 全ての牌を並べた入力用パレット
///
/// [remaining] で牌ごとの残り枚数を返すと、0枚の牌は押せなくなる。
class TilePalette extends StatelessWidget {
  final void Function(Tile tile) onSelected;
  final int Function(Tile tile)? remaining;

  /// 赤5を表示するか
  final bool showRed;

  const TilePalette({
    super.key,
    required this.onSelected,
    this.remaining,
    this.showRed = true,
  });

  static List<List<Tile>> rows({bool showRed = true}) => [
        for (final s in ['m', 'p', 's'])
          [
            for (var n = 1; n <= 9; n++) '$n$s',
            if (showRed) '5${s}r',
          ],
        [for (var n = 1; n <= 7; n++) '${n}z'],
      ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      // 1行10枚が収まる幅にする
      final w = ((constraints.maxWidth - 10 * 3) / 10).floorToDouble().clamp(14.0, 40.0);
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final row in rows(showRed: showRed))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final t in row)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: TileView(
                        t,
                        key: ValueKey('palette-$t'),
                        width: w,
                        dimmed: remaining != null && remaining!(t) <= 0,
                        onTap: () => onSelected(t),
                      ),
                    ),
                ],
              ),
            ),
        ],
      );
    });
  }
}
