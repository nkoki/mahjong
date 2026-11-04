import 'package:flutter/material.dart';
import 'package:mahjong_score_engine/mahjong_score_engine.dart';

import '../../shared/widgets/tile_palette.dart';
import '../../shared/widgets/tile_view.dart';

/// 鳴き（チー・ポン・カン）を1つ入力するダイアログ
class MeldDialog extends StatefulWidget {
  /// 牌ごとの残り枚数
  final int Function(Tile tile) remaining;

  const MeldDialog({super.key, required this.remaining});

  static Future<Meld?> show(
      BuildContext context, int Function(Tile tile) remaining) {
    return showDialog<Meld>(
      context: context,
      builder: (_) => MeldDialog(remaining: remaining),
    );
  }

  @override
  State<MeldDialog> createState() => _MeldDialogState();
}

class _MeldDialogState extends State<MeldDialog> {
  MeldType _type = MeldType.pon;
  Tile? _base;
  bool _red = false;

  static const _labels = {
    MeldType.chi: 'チー',
    MeldType.pon: 'ポン',
    MeldType.minkan: '明槓',
    MeldType.kakan: '加槓',
    MeldType.ankan: '暗槓',
  };

  List<Tile> _tilesFor(Tile base) {
    final n = tileNumber(base);
    final s = tileSuit(base);
    switch (_type) {
      case MeldType.chi:
        return ['$n$s', '${n + 1}$s', '${n + 2}$s'];
      case MeldType.pon:
        return List.filled(3, base);
      default:
        return List.filled(4, base);
    }
  }

  /// 選択中の形で使える牌か
  bool _canUse(Tile base) {
    if (_type == MeldType.chi) {
      if (isHonorTile(base) || tileNumber(base) > 7) return false;
    }
    final tiles = _tilesFor(base);
    final need = countTiles(tiles);
    return need.entries.every((e) => widget.remaining(e.key) >= e.value);
  }

  List<Tile> get _result {
    final tiles = _tilesFor(_base!);
    if (_red) {
      final i = tiles.indexWhere((t) => isNumberTile(t) && tileNumber(t) == 5);
      if (i >= 0) tiles[i] = '${tiles[i]}r';
    }
    return tiles;
  }

  bool get _hasFive =>
      _base != null &&
      _tilesFor(_base!).any((t) => isNumberTile(t) && tileNumber(t) == 5) &&
      widget.remaining('5${tileSuit(_base!)}r') > 0;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('鳴きを追加'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                children: [
                  for (final t in _labels.keys)
                    ChoiceChip(
                      label: Text(_labels[t]!),
                      selected: _type == t,
                      onSelected: (_) => setState(() {
                        _type = t;
                        if (_base != null && !_canUse(_base!)) _base = null;
                        _red = false;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(_type == MeldType.chi ? '順子の一番小さい牌を選択' : '牌を選択',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              TilePalette(
                showRed: false,
                remaining: (t) => _canUse(t) ? 1 : 0,
                onSelected: (t) {
                  if (_canUse(t)) {
                    setState(() {
                      _base = t;
                      _red = false;
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              if (_base != null) ...[
                Row(
                  children: [
                    Text('${_labels[_type]}：'),
                    for (final t in _result)
                      Padding(
                        padding: const EdgeInsets.only(right: 2),
                        child: TileView(t, width: 28),
                      ),
                  ],
                ),
                if (_hasFive)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('赤5を含む'),
                    value: _red,
                    onChanged: (v) => setState(() => _red = v ?? false),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
        FilledButton(
          onPressed: _base == null
              ? null
              : () => Navigator.pop(
                  context, Meld(type: _type, tiles: _result, calledTile: null)),
          child: const Text('追加'),
        ),
      ],
    );
  }
}
