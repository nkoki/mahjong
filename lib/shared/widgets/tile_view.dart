import 'package:flutter/material.dart';
import 'package:mahjong_score_engine/mahjong_score_engine.dart';

import 'tile_painter.dart';

/// 牌の表示ウィジェット（本物の牌に近い見た目を図形と文字で描く。[TilePainter]）
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

  @override
  Widget build(BuildContext context) {
    final height = width * 1.35;
    final fontStyle = DefaultTextStyle.of(context).style;
    Widget face = Semantics(
      label: tileSpokenName(tile),
      selected: selected,
      button: onTap != null,
      child: CustomPaint(
        size: Size(width, height),
        painter: TilePainter(
          tile,
          selected: selected,
          textStyle: TextStyle(fontFamily: fontStyle.fontFamily, fontFamilyFallback: fontStyle.fontFamilyFallback),
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
