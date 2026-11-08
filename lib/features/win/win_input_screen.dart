import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mahjong_score_engine/mahjong_score_engine.dart';

import '../../core/l10n.dart';
import '../../shared/widgets/tile_palette.dart';
import '../../shared/widgets/tile_view.dart';
import '../camera/camera_providers.dart';
import '../camera/tile_recognizer.dart';
import '../session/domain/models.dart';
import '../session/domain/session_logic.dart';
import '../session/session_providers.dart';
import 'hanfu_shortcuts.dart';
import 'meld_dialog.dart';
import 'win_result_screen.dart';

/// 牌の入力先
enum _Target { hand, win, dora, ura }

/// 和了入力画面（和了者・手牌・鳴き・ドラ・オプション）
///
/// 「翻・符で入力」に切り替えると、手牌を入れずに翻・符（または役満）を選ぶだけで計算できる。
///
/// ダブロンの2人目を入力するときは、1人目の入力内容を [previousWins] に、
/// 放銃者を [fixedLoser] に渡す（ロンのみ・放銃者・和了牌・ドラ表示牌は1人目と同じ）。
class WinInputScreen extends ConsumerStatefulWidget {
  final String sessionId;
  final List<WinEntry> previousWins;
  final int? fixedLoser;

  /// 最初から選んでおく和了者（卓ビューの席の「和了」から開いたとき）
  final int? initialWinner;

  const WinInputScreen({
    super.key,
    required this.sessionId,
    this.previousWins = const [],
    this.fixedLoser,
    this.initialWinner,
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
    // 前回選んだ入力方法（手牌／翻・符）にする
    _quick = ref.read(preferenceProvider(PreferenceKeys.winInputMode)) == 'hanfu';
    if (widget.isAdditionalRon) {
      // 同じ捨て牌へのロンなので、放銃者・和了牌・ドラ表示牌は1人目と同じ
      // （1人目を翻・符で入力したときは和了牌・ドラ表示牌が無いので、放銃者だけ同じ）
      final firstEntry = widget.previousWins.first;
      final first = firstEntry.input;
      _tsumo = false;
      _loser = widget.fixedLoser;
      if (firstEntry.hanFu == null) {
        _winTile = first.winningTile;
        _dora.addAll(first.doraTiles);
        _ura.addAll(first.uraDoraTiles);
      }
      _quick = firstEntry.hanFu != null;
    } else if (widget.initialWinner != null) {
      // 和了者を選んだ状態で始める（立直していれば立直も付ける）
      final s = ref.read(sessionProvider(widget.sessionId));
      final p = widget.initialWinner!;
      if (s != null && p >= 0 && p < s.playerCount) {
        _winner = p;
        _riichi = s.riichi[p];
      }
    }
  }

  /// 翻・符で入力する（手牌を入れない）
  bool _quick = false;
  int? _quickHan;
  int? _quickFu;

  /// 役満の倍数（1以上なら役満。翻・符は使わない）
  int _quickYakuman = 0;

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

  HanFuEntry get _hanFu => HanFuEntry(han: _quickHan ?? 0, fu: _quickFu ?? 0, yakuman: _quickYakuman);

  /// 翻・符で入力した内容の点数（本場・供託を含まない。見込みの表示用）
  ScoreResult _quickResult(GameSession s, int? winner) => ScoreCalculator.calculateFromHanFu(
        han: _hanFu.han,
        fu: _hanFu.fu,
        yakuman: _hanFu.yakuman,
        isTsumo: _tsumo,
        playerWind: winner == null ? '2z' : s.seatWindTileOf(winner),
        rules: s.settings.scoreRules,
      );

  void _calculateQuick(GameSession s) {
    String? err;
    if (_winner == null) {
      err = tr('和了者を選択してください', 'Select the winner');
    } else if (!_tsumo && _loser == null) {
      err = tr('放銃者を選択してください', 'Select the discarder');
    } else if (_quickYakuman == 0 && _quickHan == null) {
      err = tr('翻数を選んでください', 'Choose the han');
    } else if (_quickYakuman == 0 && _quickHan! < 5 && _quickFu == null) {
      err = tr('符を選んでください', 'Choose the fu');
    }
    err ??= switch (_quickResult(s, _winner).error) { final e? => engineError(e), null => null };
    if (err != null) {
      _snack(err);
      return;
    }
    final entry = WinEntry.hanFu(session: s, winner: _winner!, isTsumo: _tsumo, hanFu: _hanFu);
    // 次の入力のために覚えておく（最近の入力のチップに出す）
    final recent = HanFuShortcuts.decode(ref.read(preferenceProvider(PreferenceKeys.recentHanFu)));
    ref
        .read(preferenceProvider(PreferenceKeys.recentHanFu).notifier)
        .set(HanFuShortcuts.encode(HanFuShortcuts.remember(recent, _hanFu)));
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => WinResultScreen(
        sessionId: widget.sessionId,
        entries: [...widget.previousWins, entry],
        loser: _tsumo ? null : _loser,
      ),
    ));
  }

  void _calculate(GameSession s) {
    if (_quick) {
      _calculateQuick(s);
      return;
    }
    String? err;
    if (_winner == null) {
      err = tr('和了者を選択してください', 'Select the winner');
    } else if (!_tsumo && _loser == null) {
      err = tr('放銃者を選択してください', 'Select the discarder');
    } else if (_hand.length != _needHand) {
      err = tr('手牌をあと${_needHand - _hand.length}枚入力してください', 'Enter ${_needHand - _hand.length} more tiles in hand');
    } else if (_winTile == null) {
      err = tr('和了牌を入力してください', 'Enter the winning tile');
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
      _snack(result.error != null ? engineError(result.error!) : tr('計算できませんでした', 'Could not calculate'));
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
            ListTile(
              title: Text(tr('手牌の写真', 'Photo of hand')),
              subtitle: Text(tr(
                  '牌を横一列に並べ、全部の牌が大きくはっきり写るように撮ってください。'
                      '和了牌は一番右に置くと、和了牌として入ります。'
                      '読み取りはこの端末の中で行い、写真はどこにも送りません。',
                  'Line the tiles up in one row and make every tile large and clear. '
                      'Put the winning tile at the far right to enter it as the winning tile. '
                      'Recognition runs on this device; the photo is not sent anywhere.')),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: Text(tr('撮影する', 'Take photo')),
              onTap: () => Navigator.pop(ctx, true),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(tr('写真から選ぶ', 'Choose from photos')),
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
      _snack(tr('写真を取得できませんでした: $e', 'Could not get the photo: $e'));
      return;
    }
    if (bytes == null || !mounted) return;

    // 読み取り中の表示
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Expanded(child: Text(tr('牌を読み取っています…', 'Reading tiles…'))),
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
      error = tr('読み取りに失敗しました: $e', 'Recognition failed: $e');
    }
    if (!mounted) return;
    Navigator.of(context).pop(); // 読み取り中の表示を閉じる

    if (error != null) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('読み取れませんでした', 'Could not read tiles')),
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
          title: Text(tr('読み取り結果', 'Recognition result')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('読み取った牌（${tiles!.length}枚）', 'Tiles read (${tiles.length})'), style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                TileRow(tiles, tileWidth: 22),
                const SizedBox(height: 12),
                Text(tr('手牌（${r.hand.length}/$_needHand枚）', 'Hand (${r.hand.length}/$_needHand)'), style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                TileRow(r.hand, tileWidth: 22),
                if (r.winningTile != null && !fixedWin) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    Text(tr('和了牌: ', 'Winning tile: '), style: theme.textTheme.titleSmall),
                    TileView(r.winningTile!, width: 22),
                  ]),
                ],
                for (final n in [
                  ...r.notes,
                  if (fixedWin && r.winningTile != null) tr('和了牌は1人目と同じなので、読み取った和了牌は使いません',
                        'The winning tile is the same as the 1st winner, so the read winning tile is not used'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('・$n', style: theme.textTheme.bodySmall),
                  ),
                const SizedBox(height: 10),
                Text(
                    tr(
                        '読み取りは間違えることがあります（牌を見落としたり、牌でないものを牌と読んだりすることがあります）。'
                            '入れたあとに、手牌をよく確認してください。',
                        'Recognition can be wrong (it may miss tiles or read non-tiles as tiles). '
                            'Check the hand carefully after entering it.'),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('キャンセル', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('手牌に入れる', 'Use as hand'))),
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
    _snack(tr('読み取った牌を入れました。間違いがないか確認してください', 'Tiles entered. Please check they are correct'));
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
        title: Text(widget.isAdditionalRon
            ? tr('2人目の和了入力', '2nd winner')
            : tr('和了入力  ${s.roundLabel}', 'Win  ${displayRoundLabel(s.roundLabel)}')),
        actions: [
          // カメラ認識は Android・iOS のアプリ版だけ（Web 版ではボタンを出さない）
          if (ref.watch(cameraSupportedProvider))
            IconButton(
              tooltip: tr('カメラで手牌を読み取る', 'Read hand with camera'),
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
                          tr(
                              'ダブロンの2人目の和了を入力します。'
                                  '${widget.previousWins.first.hanFu == null ? '放銃者・和了牌・ドラ表示牌' : '放銃者'}は1人目（'
                                  '${widget.previousWins.map((e) => s.playerNames[e.winner]).join("・")}）と同じです。',
                              'Enter the 2nd winner of a double ron. '
                                  '${widget.previousWins.first.hanFu == null ? 'Discarder, winning tile and dora indicators are' : 'Discarder is'} the same as the 1st winner ('
                                  '${widget.previousWins.map((e) => s.playerNames[e.winner]).join(", ")}).'),
                          style: TextStyle(color: theme.colorScheme.onTertiaryContainer),
                        ),
                      ),
                    ),
                  _section(theme, tr('和了者', 'Winner')),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (var p = 0; p < s.playerCount; p++)
                        if (!widget.previousWins.any((e) => e.winner == p) &&
                            p != widget.fixedLoser)
                        ChoiceChip(
                          label: Text(
                              '${windName(s.seatWindIndexOf(p))} ${s.playerNames[p]}'),
                          selected: _winner == p,
                          onSelected: (_) => _selectWinner(s, p),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (!widget.isAdditionalRon)
                    SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(value: false, label: Text(tr('ロン', 'Ron'))),
                        ButtonSegment(value: true, label: Text(tr('ツモ', 'Tsumo'))),
                      ],
                      selected: {_tsumo},
                      onSelectionChanged: (v) => setState(() => _tsumo = v.first),
                    ),
                  if (widget.isAdditionalRon) ...[
                    _section(theme, tr('放銃者', 'Discarder')),
                    Text(tr('${s.playerNames[widget.fixedLoser!]}（1人目と同じ）', '${s.playerNames[widget.fixedLoser!]} (same as 1st winner)')),
                  ] else if (!_tsumo) ...[
                    _section(theme, tr('放銃者', 'Discarder')),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (var p = 0; p < s.playerCount; p++)
                          if (p != _winner)
                            ChoiceChip(
                              label: Text(
                                  '${windName(s.seatWindIndexOf(p))} ${s.playerNames[p]}'),
                              selected: _loser == p,
                              onSelected: (_) => setState(() => _loser = p),
                            ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(value: false, label: Text(tr('手牌で入力', 'By hand')), icon: const Icon(Icons.grid_view)),
                      ButtonSegment(
                          value: true, label: Text(tr('翻・符で入力', 'By han/fu')), icon: const Icon(Icons.calculate_outlined)),
                    ],
                    selected: {_quick},
                    onSelectionChanged: (v) {
                      setState(() => _quick = v.first);
                      ref
                          .read(preferenceProvider(PreferenceKeys.winInputMode).notifier)
                          .set(v.first ? 'hanfu' : 'hand');
                    },
                  ),
                  if (_quick) ..._quickSection(theme, s) else ...[
                  _section(theme, tr('手牌（${_hand.length}/$_needHand枚・タップで削除）', 'Hand (${_hand.length}/$_needHand, tap to remove)')),
                  _targetBox(
                    target: _Target.hand,
                    child: _hand.isEmpty
                        ? Text(tr('下の牌をタップして入力', 'Tap tiles below to enter'))
                        : TileRow(_hand,
                            onTap: (i) => setState(() => _hand.removeAt(i))),
                  ),
                  if (!ref.watch(cameraSupportedProvider))
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(tr('カメラで手牌を読み取る機能は、スマホのアプリ版（Android・iOS）で使えます', 'Reading the hand with the camera is available in the phone app (Android/iOS)'),
                          style: theme.textTheme.bodySmall),
                    ),
                  _section(theme, tr('和了牌', 'Winning tile')),
                  _targetBox(
                    target: _Target.win,
                    child: _winTile == null
                        ? Text(tr('和了牌を選択', 'Select the winning tile'))
                        : Row(children: [
                            TileView(_winTile!, width: 30,
                                onTap: () => setState(() => _winTile = null)),
                            const SizedBox(width: 8),
                            Text(_tsumo ? tr('ツモ', 'Tsumo') : tr('ロン', 'Ron')),
                          ]),
                  ),
                  _section(theme, tr('鳴き（${_melds.length}）', 'Calls (${_melds.length})')),
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
                          label: Text(tr('鳴きを追加', 'Add call')),
                          onPressed: _addMeld,
                        ),
                    ],
                  ),
                  _section(theme, tr('ドラ表示牌（タップで削除）', 'Dora indicators (tap to remove)')),
                  _targetBox(
                    target: _Target.dora,
                    child: _dora.isEmpty
                        ? Text(tr('ドラ表示牌を選択（なしでも可）', 'Select dora indicators (optional)'))
                        : TileRow(_dora,
                            onTap: (i) => setState(() => _dora.removeAt(i))),
                  ),
                  if (_riichi || _doubleRiichi) ...[
                    _section(theme, tr('裏ドラ表示牌', 'Ura dora indicators')),
                    _targetBox(
                      target: _Target.ura,
                      child: _ura.isEmpty
                          ? Text(tr('裏ドラ表示牌を選択', 'Select ura dora indicators'))
                          : TileRow(_ura,
                              onTap: (i) => setState(() => _ura.removeAt(i))),
                    ),
                  ],
                  if (s.settings.isSanma && s.settings.nukiDora) ...[
                    _section(theme, tr('抜きドラ（抜いた北の枚数）', 'Nuki dora (North tiles set aside)')),
                    Row(
                      children: [
                        IconButton.outlined(
                          tooltip: tr('減らす', 'Decrease'),
                          onPressed: _nuki > 0 ? () => setState(() => _nuki--) : null,
                          icon: const Icon(Icons.remove),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(tr('北 × $_nuki', 'North × $_nuki'), style: theme.textTheme.titleMedium),
                        ),
                        IconButton.outlined(
                          tooltip: tr('増やす', 'Increase'),
                          onPressed: _nuki < 4 && _remaining('4z') > 0
                              ? () => setState(() => _nuki++)
                              : null,
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                  ],
                  _section(theme, tr('オプション', 'Options')),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _flag(tr('立直', 'Riichi'), _riichi, _menzen, (v) {
                        _riichi = v;
                        if (!v) {
                          _doubleRiichi = false;
                          _ippatsu = false;
                        }
                      }),
                      _flag(tr('ダブル立直', 'Double riichi'), _doubleRiichi, _menzen, (v) {
                        _doubleRiichi = v;
                        if (v) _riichi = true;
                      }),
                      _flag(tr('一発', 'Ippatsu'), _ippatsu, _riichi || _doubleRiichi,
                          (v) => _ippatsu = v),
                      if (_tsumo) ...[
                        _flag(tr('嶺上開花', 'Rinshan kaihou'), _rinshan, true, (v) => _rinshan = v),
                        _flag(tr('海底摸月', 'Haitei'), _haitei, true, (v) => _haitei = v),
                        _flag(_winner == s.dealer ? tr('天和', 'Tenhou') : tr('地和', 'Chiihou'), _tenho,
                            _melds.isEmpty, (v) => _tenho = v),
                      ] else ...[
                        _flag(tr('槍槓', 'Chankan'), _chankan, true, (v) => _chankan = v),
                        _flag(tr('河底撈魚', 'Houtei'), _houtei, true, (v) => _houtei = v),
                      ],
                    ],
                  ),
                  ],
                  const SizedBox(height: 12),
                ],
              ),
            ),
            if (_quick) _quickBottom(theme, s) else _paletteArea(theme, s),
          ],
        ),
      ),
    );
  }

  /// 翻・符で入力するときの、翻・符（役満）を選ぶ欄
  List<Widget> _quickSection(ThemeData theme, GameSession s) {
    final rules = s.settings.scoreRules;
    final needFu = _quickYakuman == 0 && (_quickHan == null || _quickHan! < 5);
    bool fuEnabled(int fu) {
      final han = _quickHan ?? 1;
      if (fu == 20) return _tsumo && han >= 2;
      if (fu == 25) return han >= 2;
      return true;
    }

    final recent = HanFuShortcuts.decode(ref.watch(preferenceProvider(PreferenceKeys.recentHanFu)));
    final shortcuts = [
      ...recent,
      ...HanFuShortcuts.common.where((c) => !recent.any((r) => HanFuShortcuts.same(r, c))),
    ];
    final isDealer = _winner != null && _winner == s.dealer;
    String? scoreOf(HanFuEntry e) {
      final r = ScoreCalculator.calculateFromHanFu(
          han: e.han,
          fu: e.fu,
          yakuman: e.yakuman,
          isTsumo: _tsumo,
          playerWind: isDealer ? '1z' : '2z',
          rules: rules);
      if (!r.isValid) return null;
      return _tsumo
          ? ScoreCalculator.formatScore(r, isDealer: isDealer, isTsumo: true).replaceAll('オール', tr('オール', ' all'))
          : '${r.totalScore}';
    }

    bool selected(HanFuEntry e) =>
        e.yakuman > 0 ? _quickYakuman == e.yakuman : _quickYakuman == 0 && _quickHan == e.han && (e.han >= 5 || _quickFu == e.fu);

    return [
      _section(
          theme,
          tr('よく使う（${_winner == null ? "子" : isDealer ? "親" : "子"}の${_tsumo ? "ツモ" : "ロン"}）',
              'Common (${_winner == null ? "non-dealer" : isDealer ? "dealer" : "non-dealer"} ${_tsumo ? "tsumo" : "ron"})')),
      Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (var i = 0; i < shortcuts.length; i++)
            if (scoreOf(shortcuts[i]) case final score?)
              ChoiceChip(
                key: ValueKey('shortcut-${HanFuShortcuts.label(shortcuts[i])}'),
                avatar: i < recent.length ? const Icon(Icons.history, size: 16) : null,
                label: Text('${HanFuShortcuts.label(shortcuts[i])} $score'),
                selected: selected(shortcuts[i]),
                onSelected: (_) => setState(() {
                  final e = shortcuts[i];
                  _quickYakuman = e.yakuman;
                  _quickHan = e.yakuman > 0 ? _quickHan : e.han;
                  _quickFu = e.yakuman > 0 || e.han >= 5 ? _quickFu : e.fu;
                }),
              ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
            tr('時計の印が付いたものは最近入力した手です（新しい順）。下で翻数・符を選んでも入力できます。',
                'Clock icons mark recent entries (newest first). You can also choose han and fu below.'),
            style: theme.textTheme.bodySmall),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          tr(
              'ドラ・赤ドラ・裏ドラ${s.settings.isSanma && s.settings.nukiDora ? '・抜きドラ' : ''}も含めた翻数を選んでください。'
                  '本場・供託は自動で加えます。包（責任払い）は手牌で入力したときだけ選べます。',
              'Choose han including dora, red fives, ura dora${s.settings.isSanma && s.settings.nukiDora ? ', nuki dora' : ''}. '
                  'Honba and riichi sticks are added automatically. Pao can only be chosen when entering the hand.'),
          style: theme.textTheme.bodySmall,
        ),
      ),
      _section(theme, tr('翻数', 'Han')),
      Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (var h = 1; h <= 13; h++)
            ChoiceChip(
              label: Text(h == 13 ? tr('13翻以上', '13+ han') : tr('$h翻', '$h han')),
              selected: _quickYakuman == 0 && _quickHan == h,
              onSelected: (_) => setState(() {
                _quickHan = h;
                _quickYakuman = 0;
                if (_quickFu != null && !fuEnabled(_quickFu!)) _quickFu = null;
              }),
            ),
          for (var y = 1; y <= (rules.doubleYakuman ? 3 : 1); y++)
            ChoiceChip(
              label: Text(y == 1
                  ? tr('役満', 'Yakuman')
                  : y == 2
                      ? tr('二倍役満', 'Double yakuman')
                      : tr('三倍役満', 'Triple yakuman')),
              selected: _quickYakuman == y,
              onSelected: (_) => setState(() => _quickYakuman = y),
            ),
        ],
      ),
      if (needFu) ...[
        _section(theme, tr('符', 'Fu')),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final f in ScoreCalculator.hanFuChoices)
              ChoiceChip(
                label: Text(tr('$f符', '$f fu')),
                selected: _quickFu == f,
                onSelected: fuEnabled(f) ? (_) => setState(() => _quickFu = f) : null,
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
              tr('20符は平和ツモ、25符は七対子（どちらも2翻以上）。5翻以上は符に関係なく満貫以上です。',
                  '20 fu is pinfu tsumo, 25 fu is chiitoitsu (both 2+ han). 5+ han is mangan or more regardless of fu.'),
              style: theme.textTheme.bodySmall),
        ),
      ],
    ];
  }

  /// 翻・符で入力するときの下の欄（点数の見込みと計算ボタン）
  Widget _quickBottom(ThemeData theme, GameSession s) {
    final ready = _quickYakuman > 0 || (_quickHan != null && (_quickHan! >= 5 || _quickFu != null));
    var preview = tr('翻数と符を選んでください', 'Choose han and fu');
    if (ready) {
      final r = _quickResult(s, _winner);
      if (!r.isValid) {
        preview = engineError(r.error ?? '');
      } else {
        final isDealer = _winner != null && _winner == s.dealer;
        final who = _winner == null ? '' : (isDealer ? tr('親の', 'Dealer ') : tr('子の', 'Non-dealer '));
        final score = _tsumo
            ? ScoreCalculator.formatScore(r, isDealer: isDealer, isTsumo: true).replaceAll('オール', tr('オール', ' all'))
            : tr('${r.totalScore}点', '${r.totalScore} pts');
        preview = tr(
            '$who${_tsumo ? 'ツモ' : 'ロン'} $score'
                '${r.limitName != null ? '（${r.limitName}）' : ''}'
                '${_winner == null ? '（和了者を選ぶと親・子が決まります）' : ''}',
            '$who${_tsumo ? 'tsumo' : 'ron'} $score'
                '${r.limitName != null ? ' (${limitName(r.limitName!)})' : ''}'
                '${_winner == null ? ' (select the winner to set dealer/non-dealer)' : ''}');
      }
    }
    return Material(
      elevation: 8,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            Expanded(child: Text(preview, style: theme.textTheme.titleSmall)),
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(80, 40)),
              onPressed: () => _calculate(s),
              child: Text(tr('計算', 'Calculate')),
            ),
          ],
        ),
      ),
    );
  }


  Widget _paletteArea(ThemeData theme, GameSession s) {
    final labels = {
      _Target.hand: tr('手牌', 'Hand'),
      _Target.win: tr('和了牌', 'Win tile'),
      _Target.dora: tr('ドラ表示', 'Dora'),
      _Target.ura: tr('裏ドラ', 'Ura dora'),
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
                  child: Text(tr('計算', 'Calculate')),
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
        MeldType.chi => tr('チー', 'Chi'),
        MeldType.pon => tr('ポン', 'Pon'),
        MeldType.minkan => tr('明槓', 'Open kan'),
        MeldType.kakan => tr('加槓', 'Added kan'),
        MeldType.ankan => tr('暗槓', 'Closed kan'),
      };
}
