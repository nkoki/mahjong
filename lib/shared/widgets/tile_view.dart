import 'package:flutter/material.dart';
import 'package:mahjong_score_engine/mahjong_score_engine.dart';

/// 牌の表示ウィジェット（画像を使わず文字で描画）
class TileView extends StatelessWidget {
  final Tile tile;
  final double width;
  final VoidCallback? onTap;
  final bool selected;
  final bool dimmed;

  /// 横向き（鳴いた牌の表示などに使用）
  final bool sideways;

  const TileView(
    this.tile, {
    super.key,
    this.width = 32,
    this.onTap,
    this.selected = false,
    this.dimmed = false,
    this.sideways = false,
  });

  static const _honors = ['東', '南', '西', '北', '白', '發', '中'];
  static const _manNums = ['一', '二', '三', '四', '伍', '六', '七', '八', '九'];

  @override
  Widget build(BuildContext context) {
    final suit = tileSuit(tile);
    final n = tileNumber(tile);
    final red = isRedDora(tile);
    final height = width * 1.35;

    Color color;
    String top;
    String? bottom;
    switch (suit) {
      case 'm':
        color = const Color(0xFFC62828);
        top = _manNums[n - 1];
        bottom = '萬';
        break;
      case 'p':
        color = const Color(0xFF1565C0);
        top = '$n';
        bottom = '筒';
        break;
      case 's':
        color = const Color(0xFF2E7D32);
        top = '$n';
        bottom = '索';
        break;
      default:
        top = _honors[n - 1];
        color = n == 6
            ? const Color(0xFF2E7D32)
            : n == 7
                ? const Color(0xFFC62828)
                : n == 5
                    ? const Color(0xFF90A4AE)
                    : const Color(0xFF212121);
    }
    if (red) color = const Color(0xFFD50000);

    Widget face = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: red ? const Color(0xFFFFEBEE) : const Color(0xFFFFFDF5),
        borderRadius: BorderRadius.circular(width * 0.14),
        border: Border.all(
          color: selected ? Colors.orange : const Color(0xFFBDBDBD),
          width: selected ? 2.5 : 1,
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x33000000), offset: Offset(0, 2), blurRadius: 1),
        ],
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                top,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: width * (bottom == null ? 0.7 : 0.55),
                  height: 1.0,
                ),
              ),
              if (bottom != null)
                Text(
                  bottom,
                  style: TextStyle(
                    color: color,
                    fontSize: width * 0.4,
                    height: 1.1,
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    if (sideways) face = RotatedBox(quarterTurns: 1, child: face);
    if (dimmed) face = Opacity(opacity: 0.3, child: face);
    if (onTap == null) return face;
    return GestureDetector(onTap: dimmed ? null : onTap, child: face);
  }
}

/// 牌を横に並べて表示
class TileRow extends StatelessWidget {
  final List<Tile> tiles;
  final double tileWidth;
  final void Function(int index)? onTap;

  const TileRow(this.tiles, {super.key, this.tileWidth = 28, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 2,
      runSpacing: 4,
      children: [
        for (var i = 0; i < tiles.length; i++)
          TileView(
            tiles[i],
            width: tileWidth,
            onTap: onTap == null ? null : () => onTap!(i),
          ),
      ],
    );
  }
}
