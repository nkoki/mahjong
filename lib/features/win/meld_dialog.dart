import 'package:flutter/material.dart';
import 'package:mahjong_score_engine/mahjong_score_engine.dart';

import '../../core/l10n.dart';
import '../../shared/widgets/tile_palette.dart';
import '../../shared/widgets/tile_view.dart';

/// 鳴き（チー・ポン・カン）を1つ入力するダイアログ
class MeldDialog extends StatefulWidget {
  /// 牌ごとの残り枚数
  final int Function(Tile tile) remaining;

  /// 赤ドラありのルールか（なしなら「赤5を含む」を表示しない）
  final bool redDora;

  /// 3人打ち（チーなし・二萬〜八萬なし）
  final bool sanma;

  const MeldDialog(
      {super.key, required this.remaining, this.redDora = true, this.sanma = false});

  static Future<Meld?> show(BuildContext context, int Function(Tile tile) remaining,
      {bool redDora = true, bool sanma = false}) {
    return showDialog<Meld>(
      context: context,
      builder: (_) => MeldDialog(remaining: remaining, redDora: redDora, sanma: sanma),
    );
  }

  @override
  State<MeldDialog> createState() => _MeldDialogState();
}

class _MeldDialogState extends State<MeldDialog> {
  MeldType _type = MeldType.pon;
  Tile? _base;
  bool _red = false;

  static Map<MeldType, String> get _labels => {
        MeldType.chi: tr('チー', 'Chi'),
        MeldType.pon: tr('ポン', 'Pon'),
        MeldType.minkan: tr('明槓', 'Open kan'),
        MeldType.kakan: tr('加槓', 'Added kan'),
        MeldType.ankan: tr('暗槓', 'Closed kan'),
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
      widget.redDora &&
      _base != null &&
      _tilesFor(_base!).any((t) => isNumberTile(t) && tileNumber(t) == 5) &&
      widget.remaining('5${tileSuit(_base!)}r') > 0;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('鳴きを追加', 'Add call')),
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
                    if (!(widget.sanma && t == MeldType.chi))
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
              Text(_type == MeldType.chi ? tr('順子の一番小さい牌を選択', 'Select the lowest tile of the run') : tr('牌を選択', 'Select a tile'),
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              TilePalette(
                showRed: false,
                sanma: widget.sanma,
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
                    Text(tr('${_labels[_type]}：', '${_labels[_type]}: ')),
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
                    title: Text(tr('赤5を含む', 'Includes red five')),
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
            onPressed: () => Navigator.pop(context), child: Text(tr('キャンセル', 'Cancel'))),
        FilledButton(
          onPressed: _base == null
              ? null
              : () => Navigator.pop(
                  context, Meld(type: _type, tiles: _result, calledTile: null)),
          child: Text(tr('追加', 'Add')),
        ),
      ],
    );
  }
}
