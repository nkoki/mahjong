import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mahjong_score_engine/mahjong_score_engine.dart';

import '../../shared/widgets/tile_palette.dart';
import '../../shared/widgets/tile_view.dart';
import '../camera/camera_providers.dart';
import '../camera/tile_recognizer.dart';
import '../session/domain/models.dart';
import '../session/domain/session_logic.dart';
import '../session/session_providers.dart';
import 'meld_dialog.dart';
import 'win_result_screen.dart';

/// 牌の入力先
enum _Target { hand, win, dora, ura }

/// 和了入力画面（和了者・手牌・鳴き・ドラ・オプション）
///
/// ダブロンの2人目を入力するときは、1人目の入力内容を [previousWins] に、
/// 放銃者を [fixedLoser] に渡す（ロンのみ・放銃者・和了牌・ドラ表示牌は1人目と同じ）。
class WinInputScreen extends ConsumerStatefulWidget {
  final String sessionId;
  final List<WinEntry> previousWins;
  final int? fixedLoser;

  const WinInputScreen({
    super.key,
    required this.sessionId,
    this.previousWins = const [],
    this.fixedLoser,
  });

  /// ダブロンの2人目の入力かどうか
  bool get isAdditionalRon => previousWins.isNotEmpty;

  @override
  ConsumerState<WinInputScreen> createState() => _WinInputScreenState();
}

class _WinInputScreenState extends ConsumerState<WinInputScreen> {
  int? _winner;
  bool _tsumo = false;
  int? _loser;

  final List<Tile> _hand = [];
  Tile? _winTile;
  final List<Meld> _melds = [];
  final List<Tile> _dora = [];
  final List<Tile> _ura = [];
  _Target _target = _Target.hand;

  @override
  void initState() {
    super.initState();
    if (widget.isAdditionalRon) {
      // 同じ捨て牌へのロンなので、放銃者・和了牌・ドラ表示牌は1人目と同じ
      final first = widget.previousWins.first.input;
      _tsumo = false;
      _loser = widget.fixedLoser;
      _winTile = first.winningTile;
      _dora.addAll(first.doraTiles);
      _ura.addAll(first.uraDoraTiles);
    }
  }

  bool _riichi = false;
  bool _doubleRiichi = false;
  bool _ippatsu = false;
  bool _rinshan = false;
  bool _chankan = false;
  bool _haitei = false;
  bool _houtei = false;
  bool _tenho = false;

  int get _needHand => 13 - 3 * _melds.length;
  bool get _menzen => _melds.every((m) => !m.isOpen);

  /// 牌の残り枚数（赤5は1枚まで）
  /// 3人打ちで抜いた北の枚数
  int _nuki = 0;

  int _remaining(Tile tile) {
    final all = [
      ..._hand,
      if (_winTile != null) _winTile!,
      for (final m in _melds) ...m.tiles,
      ..._dora,
      ..._ura,
      for (var i = 0; i < _nuki; i++) '4z',
    ];
    final norm = normalizeTile(tile);
    final used = all.where((t) => normalizeTile(t) == norm).length;
    if (isRedDora(tile)) {
      if (all.contains(tile)) return 0;
    }
    return 4 - used;
  }

  void _selectWinner(GameSession s, int p) {
    setState(() {
      _winner = p;
      if (_loser == p) _loser = null;
      _riichi = s.riichi[p];
      if (!_riichi) {
        _doubleRiichi = false;
        _ippatsu = false;
      }
    });
  }

  void _onTile(Tile t) {
    if (_remaining(t) <= 0) return;
    setState(() {
      switch (_target) {
        case _Target.hand:
          if (_hand.length < _needHand) {
            _hand.add(t);
            _hand.replaceRange(0, _hand.length, sortTiles(_hand));
            if (_hand.length == _needHand && _winTile == null) {
              _target = _Target.win;
            }
          }
          break;
        case _Target.win:
          _winTile = t;
          _target = _Target.dora;
          break;
        case _Target.dora:
          if (_dora.length < 5) _dora.add(t);
          break;
        case _Target.ura:
          if (_ura.length < 5) _ura.add(t);
          break;
      }
    });
  }

  Future<void> _addMeld() async {
    if (_melds.length >= 4) return;
    final s = ref.read(sessionProvider(widget.sessionId));
    final m = await MeldDialog.show(context, _remaining,
        redDora: s?.settings.redDora ?? true, sanma: s?.settings.isSanma ?? false);
    if (m == null) return;
    setState(() {
      _melds.add(m);
      if (m.isOpen) {
        _riichi = false;
        _doubleRiichi = false;
        _ippatsu = false;
        _tenho = false;
      }
      while (_hand.length > _needHand) {
        _hand.removeLast();
      }
    });
  }

  void _calculate(GameSession s) {
    String? err;
    if (_winner == null) {
      err = '和了者を選択してください';
    } else if (!_tsumo && _loser == null) {
      err = '放銃者を選択してください';
    } else if (_hand.length != _needHand) {
      err = '手牌をあと${_needHand - _hand.length}枚入力してください';
    } else if (_winTile == null) {
      err = '和了牌を入力してください';
    }
    if (err != null) {
      _snack(err);
      return;
    }
    final winner = _winner!;
    final riichiNow = _riichi || _doubleRiichi;
    final input = WinInput(
      handTiles: List.of(_hand),
      winningTile: _winTile!,
      melds: List.of(_melds),
      winType: _tsumo ? 'tsumo' : 'ron',
      isRiichi: _riichi || _doubleRiichi,
      isIppatsu: riichiNow && _ippatsu,
      isDoubleRiichi: _doubleRiichi,
      doraTiles: List.of(_dora),
      uraDoraTiles: riichiNow ? List.of(_ura) : const [],
      roundWind: s.roundWindTile,
      playerWind: s.seatWindTileOf(winner),
      isRinshan: _tsumo && _rinshan,
      isChankan: !_tsumo && _chankan,
      isHaitei: _tsumo && _haitei,
      isHoutei: !_tsumo && _houtei,
      isTenho: _tsumo && _tenho && s.dealer == winner,
      isChiho: _tsumo && _tenho && s.dealer != winner,
      nukiDora: s.settings.isSanma && s.settings.nukiDora ? _nuki : 0,
    );
    // ここでは手が和了形になっているか・役があるかだけを確かめる。
    // 本場・供託をだれが受け取るかはダブロンかどうかで変わるので、結果画面で計算する。
    // （ダッシュボードで立直宣言していなくても、和了者自身の立直棒は自分に戻るだけなので収支は同じ）
    final result = ScoreCalculator.calculate(input, rules: s.settings.scoreRules);
    if (!result.isValid) {
      _snack(result.error ?? '計算できませんでした');
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => WinResultScreen(
        sessionId: widget.sessionId,
        entries: [...widget.previousWins, WinEntry(winner: winner, input: input)],
        loser: _tsumo ? null : _loser,
      ),
    ));
  }

  /// カメラ（写真）から手牌を読み取る
  Future<void> _readFromCamera(GameSession s) async {
    final fromCamera = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('手牌の写真'),
              subtitle: Text('牌を横一列に並べ、全部の牌が大きくはっきり写るように撮ってください。'
                  '和了牌は一番右に置くと、和了牌として入ります。'
                  '読み取りはこの端末の中で行い、写真はどこにも送りません。'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('撮影する'),
              onTap: () => Navigator.pop(ctx, true),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('写真から選ぶ'),
              onTap: () => Navigator.pop(ctx, false),
            ),
          ],
        ),
      ),
    );
    if (fromCamera == null || !mounted) return;

    final Uint8List? bytes;
    try {
      bytes = await ref.read(photoPickerProvider).pick(fromCamera: fromCamera);
    } catch (e) {
      _snack('写真を取得できませんでした: $e');
      return;
    }
    if (bytes == null || !mounted) return;

    // 読み取り中の表示
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(child: Text('牌を読み取っています…')),
          ],
        ),
      ),
    );
    List<Tile>? tiles;
    String? error;
    try {
      tiles = await ref.read(tileRecognizerProvider).recognize(bytes);
    } on RecognitionException catch (e) {
      error = e.message;
    } catch (e) {
      error = '読み取りに失敗しました: $e';
    }
    if (!mounted) return;
    Navigator.of(context).pop(); // 読み取り中の表示を閉じる

    if (error != null) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('読み取れませんでした'),
          content: Text(error!),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
      return;
    }

    final r = applyRecognition(tiles!,
        needHand: _needHand, sanma: s.settings.isSanma, redDora: s.settings.redDora);
    final fixedWin = widget.isAdditionalRon;
    final apply = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          title: const Text('読み取り結果'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('読み取った牌（${tiles!.length}枚）', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                TileRow(tiles, tileWidth: 22),
                const SizedBox(height: 12),
                Text('手牌（${r.hand.length}/$_needHand枚）', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                TileRow(r.hand, tileWidth: 22),
                if (r.winningTile != null && !fixedWin) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    Text('和了牌: ', style: theme.textTheme.titleSmall),
                    TileView(r.winningTile!, width: 22),
                  ]),
                ],
                for (final n in [
                  ...r.notes,
                  if (fixedWin && r.winningTile != null) '和了牌は1人目と同じなので、読み取った和了牌は使いません',
                ])
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('・$n', style: theme.textTheme.bodySmall),
                  ),
                const SizedBox(height: 10),
                Text('読み取りは間違えることがあります。入れたあとに、手牌をよく確認してください。',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('手牌に入れる')),
          ],
        );
      },
    );
    if (apply != true || !mounted) return;
    setState(() {
      _hand
        ..clear()
        ..addAll(r.hand);
      if (r.winningTile != null && !fixedWin) _winTile = r.winningTile;
      _target = _hand.length < _needHand
          ? _Target.hand
          : (_winTile == null ? _Target.win : _Target.dora);
    });
    _snack('読み取った牌を入れました。間違いがないか確認してください');
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider(widget.sessionId));
    if (s == null) return const Scaffold();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isAdditionalRon ? '2人目の和了入力' : '和了入力  ${s.roundLabel}'),
        actions: [
          // カメラ認識は Android・iOS のアプリ版だけ（Web 版ではボタンを出さない）
          if (ref.watch(cameraSupportedProvider))
            IconButton(
              tooltip: 'カメラで手牌を読み取る',
              icon: const Icon(Icons.photo_camera_outlined),
              onPressed: () => _readFromCamera(s),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  if (widget.isAdditionalRon)
                    Card(
                      color: theme.colorScheme.tertiaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          'ダブロンの2人目の和了を入力します。'
                          '放銃者・和了牌・ドラ表示牌は1人目（'
                          '${widget.previousWins.map((e) => s.playerNames[e.winner]).join("・")}）と同じです。',
                          style: TextStyle(color: theme.colorScheme.onTertiaryContainer),
                        ),
                      ),
                    ),
                  _section(theme, '和了者'),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (var p = 0; p < s.playerCount; p++)
                        if (!widget.previousWins.any((e) => e.winner == p) &&
                            p != widget.fixedLoser)
                        ChoiceChip(
                          label: Text(
                              '${GameSession.windNames[s.seatWindIndexOf(p)]} ${s.playerNames[p]}'),
                          selected: _winner == p,
                          onSelected: (_) => _selectWinner(s, p),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (!widget.isAdditionalRon)
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('ロン')),
                        ButtonSegment(value: true, label: Text('ツモ')),
                      ],
                      selected: {_tsumo},
                      onSelectionChanged: (v) => setState(() => _tsumo = v.first),
                    ),
                  if (widget.isAdditionalRon) ...[
                    _section(theme, '放銃者'),
                    Text('${s.playerNames[widget.fixedLoser!]}（1人目と同じ）'),
                  ] else if (!_tsumo) ...[
                    _section(theme, '放銃者'),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (var p = 0; p < s.playerCount; p++)
                          if (p != _winner)
                            ChoiceChip(
                              label: Text(s.playerNames[p]),
                              selected: _loser == p,
                              onSelected: (_) => setState(() => _loser = p),
                            ),
                      ],
                    ),
                  ],
                  _section(theme, '手牌（${_hand.length}/$_needHand枚・タップで削除）'),
                  _targetBox(
                    target: _Target.hand,
                    child: _hand.isEmpty
                        ? const Text('下の牌をタップして入力')
                        : TileRow(_hand,
                            onTap: (i) => setState(() => _hand.removeAt(i))),
                  ),
                  if (!ref.watch(cameraSupportedProvider))
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('カメラで手牌を読み取る機能は、スマホのアプリ版（Android・iOS）で使えます',
                          style: theme.textTheme.bodySmall),
                    ),
                  _section(theme, '和了牌'),
                  _targetBox(
                    target: _Target.win,
                    child: _winTile == null
                        ? const Text('和了牌を選択')
                        : Row(children: [
                            TileView(_winTile!, width: 30,
                                onTap: () => setState(() => _winTile = null)),
                            const SizedBox(width: 8),
                            Text(_tsumo ? 'ツモ' : 'ロン'),
                          ]),
                  ),
                  _section(theme, '鳴き（${_melds.length}）'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (var i = 0; i < _melds.length; i++)
                        InputChip(
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('${_meldLabel(_melds[i].type)} '),
                              for (final t in _melds[i].tiles)
                                TileView(t, width: 20),
                            ],
                          ),
                          onDeleted: () => setState(() => _melds.removeAt(i)),
                        ),
                      if (_melds.length < 4)
                        ActionChip(
                          avatar: const Icon(Icons.add),
                          label: const Text('鳴きを追加'),
                          onPressed: _addMeld,
                        ),
                    ],
                  ),
                  _section(theme, 'ドラ表示牌（タップで削除）'),
                  _targetBox(
                    target: _Target.dora,
                    child: _dora.isEmpty
                        ? const Text('ドラ表示牌を選択（なしでも可）')
                        : TileRow(_dora,
                            onTap: (i) => setState(() => _dora.removeAt(i))),
                  ),
                  if (_riichi || _doubleRiichi) ...[
                    _section(theme, '裏ドラ表示牌'),
                    _targetBox(
                      target: _Target.ura,
                      child: _ura.isEmpty
                          ? const Text('裏ドラ表示牌を選択')
                          : TileRow(_ura,
                              onTap: (i) => setState(() => _ura.removeAt(i))),
                    ),
                  ],
                  if (s.settings.isSanma && s.settings.nukiDora) ...[
                    _section(theme, '抜きドラ（抜いた北の枚数）'),
                    Row(
                      children: [
                        IconButton.outlined(
                          tooltip: '減らす',
                          onPressed: _nuki > 0 ? () => setState(() => _nuki--) : null,
                          icon: const Icon(Icons.remove),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text('北 × $_nuki', style: theme.textTheme.titleMedium),
                        ),
                        IconButton.outlined(
                          tooltip: '増やす',
                          onPressed: _nuki < 4 && _remaining('4z') > 0
                              ? () => setState(() => _nuki++)
                              : null,
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                  ],
                  _section(theme, 'オプション'),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _flag('立直', _riichi, _menzen, (v) {
                        _riichi = v;
                        if (!v) {
                          _doubleRiichi = false;
                          _ippatsu = false;
                        }
                      }),
                      _flag('ダブル立直', _doubleRiichi, _menzen, (v) {
                        _doubleRiichi = v;
                        if (v) _riichi = true;
                      }),
                      _flag('一発', _ippatsu, _riichi || _doubleRiichi,
                          (v) => _ippatsu = v),
                      if (_tsumo) ...[
                        _flag('嶺上開花', _rinshan, true, (v) => _rinshan = v),
                        _flag('海底摸月', _haitei, true, (v) => _haitei = v),
                        _flag(_winner == s.dealer ? '天和' : '地和', _tenho,
                            _melds.isEmpty, (v) => _tenho = v),
                      ] else ...[
                        _flag('槍槓', _chankan, true, (v) => _chankan = v),
                        _flag('河底撈魚', _houtei, true, (v) => _houtei = v),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
            _paletteArea(theme, s),
          ],
        ),
      ),
    );
  }

  Widget _paletteArea(ThemeData theme, GameSession s) {
    const labels = {
      _Target.hand: '手牌',
      _Target.win: '和了牌',
      _Target.dora: 'ドラ表示',
      _Target.ura: '裏ドラ',
    };
    return Material(
      elevation: 8,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final t in labels.keys)
                          if (t != _Target.ura || _riichi || _doubleRiichi)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: ChoiceChip(
                                visualDensity: VisualDensity.compact,
                                label: Text(labels[t]!),
                                selected: _target == t,
                                onSelected: (_) => setState(() => _target = t),
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(80, 40)),
                  onPressed: () => _calculate(s),
                  child: const Text('計算'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            TilePalette(
              onSelected: _onTile,
              remaining: _remaining,
              showRed: s.settings.redDora,
              sanma: s.settings.isSanma,
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(ThemeData theme, String title) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text(title, style: theme.textTheme.titleSmall),
      );

  Widget _targetBox({required _Target target, required Widget child}) {
    final selected = _target == target;
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => setState(() => _target = target),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? theme.colorScheme.primary : theme.dividerColor,
            width: selected ? 2 : 1,
          ),
        ),
        alignment: Alignment.centerLeft,
        child: child,
      ),
    );
  }

  Widget _flag(String label, bool value, bool enabled, void Function(bool) set) {
    return FilterChip(
      label: Text(label),
      selected: value,
      onSelected: enabled ? (v) => setState(() => set(v)) : null,
    );
  }

  static String _meldLabel(MeldType t) => switch (t) {
        MeldType.chi => 'チー',
        MeldType.pon => 'ポン',
        MeldType.minkan => '明槓',
        MeldType.kakan => '加槓',
        MeldType.ankan => '暗槓',
      };
}
