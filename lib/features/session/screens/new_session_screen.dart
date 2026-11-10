import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n.dart';
import '../../../core/routes.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets/player_name_field.dart';
import '../../../shared/widgets/rule_inputs.dart';
import '../domain/models.dart';
import '../domain/session_logic.dart';
import '../../settings/rule_presets.dart';
import '../../settings/rule_settings_screen.dart';
import '../session_providers.dart';

/// 新規対局の作成画面
class NewSessionScreen extends ConsumerStatefulWidget {
  const NewSessionScreen({super.key});

  @override
  ConsumerState<NewSessionScreen> createState() => _NewSessionScreenState();
}

class _NewSessionScreenState extends ConsumerState<NewSessionScreen> {
  /// 名前の入力欄（空のまま始めると「プレイヤー1」などになる）
  final _controllers = List.generate(4, (i) => TextEditingController());
  /// 人数（4人打ち: 4 / 3人打ち: 3）
  int _playerCount = 4;

  /// 人数を切り替えたときに、持ち点などの入力欄を作り直すためのキー
  int _formKey = 0;

  /// ルール設定画面で決めたルール（詳細ルールはこれをそのまま使う）
  late GameSettings _defaults;
  late GameLength _length;
  late bool _tobi;
  int? _starting;
  int? _return;
  late List<int?> _uma;

  @override
  void initState() {
    super.initState();
    _loadDefaults();
  }

  /// 人数に合ったルール設定を読み込み、持ち点などを初期値に戻す
  void _loadDefaults() {
    _preset = null;
    _defaults = ref.read(defaultSettingsProviderFor(_playerCount));
    _length = _defaults.length;
    _tobi = _defaults.tobi;
    _starting = _defaults.startingPoints;
    _return = _defaults.returnPoints;
    _uma = List.of(_defaults.uma);
    _formKey++;
  }

  /// 選んだルールのセットの名前（選んでいなければ null）
  String? _preset;

  void _applyPreset(RulePreset p) {
    _defaults = p.settings;
    _length = p.settings.length;
    _tobi = p.settings.tobi;
    _starting = p.settings.startingPoints;
    _return = p.settings.returnPoints;
    _uma = List.of(p.settings.uma);
    _preset = p.name;
    _formKey++;
  }

  Future<void> _openRuleSettings() async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => RuleSettingsScreen(initialPlayerCount: _playerCount)));
    // 詳細ルールだけ反映する（持ち点などはこの画面で入力した値をそのまま使う）
    if (mounted) {
      setState(() => _defaults = ref.read(defaultSettingsProviderFor(_playerCount)));
    }
  }

  /// 持ち点・返しのよく使う値
  List<int> get _pointPresets =>
      _playerCount == 3 ? const [35000, 40000] : const [25000, 30000];

  String? get _startingError => validatePoints(_starting);
  String? get _returnError => validateReturnPoints(_return, _starting);
  String? get _umaError => validateUma(_uma, playerCount: _playerCount);
  String? get _nameError =>
      SessionLogic.validatePlayerNames([for (var i = 0; i < _playerCount; i++) _controllers[i].text]);
  bool get _isValid =>
      _startingError == null && _returnError == null && _umaError == null && _nameError == null;

  /// 前回のメンバーを座順のまま入れる
  void _fillMembers(List<String> names) {
    setState(() {
      for (var i = 0; i < _playerCount; i++) {
        final n = names[i];
        _controllers[i].text = SessionLogic.isDefaultPlayerName(n) ? '' : n;
      }
    });
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _start() async {
    final names = [
      for (var i = 0; i < _playerCount; i++)
        _controllers[i].text.trim().isEmpty
            ? SessionLogic.defaultPlayerName(i)
            : _controllers[i].text.trim()
    ];
    if (!_isValid) return;
    final settings = _defaults.copyWith(
      startingPoints: _starting!,
      returnPoints: _return!,
      uma: List.unmodifiable(_uma.map((v) => v!)),
      length: _length,
      tobi: _tobi,
    );
    final notifier = ref.read(sessionsProvider.notifier);
    final removed = notifier.sessionsRemovedByNextCreate();
    if (removed.isNotEmpty) {
      final ok = await _confirmRemoval(removed);
      if (!ok || !mounted) return;
    }
    final id = notifier.create(names, settings);
    Navigator.of(context).pushReplacement(dashboardRoute(id));
  }

  /// 上限を超えて古い対局が削除されることの確認
  Future<bool> _confirmRemoval(List<GameSession> removed) async {
    String date(DateTime d) => '${d.year}/${d.month}/${d.day}';
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('古い対局が削除されます', 'Old games will be deleted')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr(
                '保存できる対局は${SessionLogic.maxSavedSessions}件までです。'
                    '新しい対局を始めると、お気に入り（★）にしていない一番古い対局'
                    '${removed.length > 1 ? "から${removed.length}件" : ""}が削除されます。'
                    '削除すると元に戻せません。',
                'Up to ${SessionLogic.maxSavedSessions} games can be saved. '
                    'Starting a new game deletes the oldest ${removed.length > 1 ? "${removed.length} games" : "game"} not marked as favorite (★). '
                    'This cannot be undone.')),
            const SizedBox(height: 12),
            for (final s in removed.take(3))
              Text('${tr('・', '• ')}${date(s.createdAt)}  ${s.playerNames.join(" / ")}',
                  style: Theme.of(ctx).textTheme.bodySmall),
            if (removed.length > 3)
              Text(tr('・ほか${removed.length - 3}件', '• ${removed.length - 3} more'), style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 12),
            Text(tr('残したい対局は、戦績画面で ★ を押してお気に入りにしてください。', 'To keep a game, tap ★ on the records screen to mark it as favorite.'),
                style: Theme.of(ctx).textTheme.bodySmall),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: Text(tr('キャンセル', 'Cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: Text(tr('削除して開始', 'Delete and start'))),
        ],
      ),
    );
    return r ?? false;
  }

  /// 前回のメンバー（ボタンを押すと座順のまま入れる）
  Widget? _lastMembers() {
    final last = SessionLogic.lastMembers(ref.watch(sessionsProvider), _playerCount);
    if (last == null) return null;
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        icon: const Icon(Icons.history),
        label: Text(tr('前回のメンバー（${last.join("・")}）', 'Last members (${last.join(", ")})'),
            overflow: TextOverflow.ellipsis),
        onPressed: () => _fillMembers(last),
      ),
    );
  }

  Widget _label(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
      );

  @override
  Widget build(BuildContext context) {
    final winds = [
      tr('東家（起家）', 'East (first dealer)'),
      tr('南家', 'South'),
      tr('西家', 'West'),
      tr('北家', 'North'),
    ];
    // 過去に入力したことのあるプレイヤーの名前（新しく使った順）
    final knownNames = SessionLogic.recentPlayerNames(ref.watch(sessionsProvider), limit: null);
    return Scaffold(
      appBar: AppBar(title: Text(tr('新規対局', 'New game'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<int>(
            segments: [
              ButtonSegment(value: 4, label: Text(tr('4人打ち', '4-player'))),
              ButtonSegment(value: 3, label: Text(tr('3人打ち', '3-player'))),
            ],
            selected: {_playerCount},
            onSelectionChanged: (v) => setState(() {
              _playerCount = v.first;
              _loadDefaults();
            }),
          ),
          if (_playerCount == 3)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                tr(
                    '3人打ち: 二萬〜八萬を使わない・チーなし・'
                        '${_defaults.nukiDora ? "北抜きあり" : "北抜きなし"}・'
                        '${_defaults.sanmaTsumoSplit ? "ツモ折半" : "ツモ損"}',
                    '3-player: no 2m-8m, no chi, '
                        '${_defaults.nukiDora ? "North as nuki dora" : "no nuki dora"}, '
                        '${_defaults.sanmaTsumoSplit ? "tsumo split" : "tsumo loss"}'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 16),
          Text(tr('プレイヤー', 'Players'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          // 名前の欄を押すと、過去のプレイヤーの一覧が開く（文字を入れると部分一致で絞り込む）
          for (var i = 0; i < _playerCount; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: PlayerNameField(
                fieldKey: ValueKey('player-name-$i'),
                controller: _controllers[i],
                candidates: knownNames,
                exclude: {
                  for (var j = 0; j < _playerCount; j++)
                    if (j != i && _controllers[j].text.trim().isNotEmpty) _controllers[j].text.trim()
                },
                labelText: winds[i],
                hintText: SessionLogic.defaultPlayerName(i),
                onChanged: (_) => setState(() {}),
              ),
            ),
          if (_nameError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_nameError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          if (_lastMembers() case final w?) w,
          const SizedBox(height: 16),
          Text(tr('ルール', 'Rules'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (ref.watch(rulePresetsProvider).where((p) => p.playerCount == _playerCount).toList()
              case final presets when presets.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final p in presets)
                  ChoiceChip(
                    key: ValueKey('new-preset-${p.name}'),
                    avatar: const Icon(Icons.bookmark_outline, size: 18),
                    label: Text(p.name),
                    selected: _preset == p.name,
                    onSelected: (_) => setState(() => _applyPreset(p)),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                  tr('保存したルールのセットを選ぶと、下の持ち点・ウマなどと詳細ルールが切り替わります。',
                      'Choosing a saved rule set switches the starting points, uma, etc. below and the detailed rules.'),
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
          SegmentedButton<GameLength>(
            key: const ValueKey('game-length'),
            showSelectedIcon: false,
            segments: [for (final l in GameLength.values) ButtonSegment(value: l, label: Text(l.shortLabel))],
            selected: {_length},
            onSelectionChanged: (v) => setState(() => _length = v.first),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              tr('${_length.label}（${_length.rounds(_playerCount)}局${_length == GameLength.single ? "で終局して精算" : ""}）',
                  '${_length.label} (${_length.rounds(_playerCount)} hand${_length == GameLength.single ? ", then settle" : "s"})'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 12),
          _label(context, tr('持ち点（配給原点）', 'Starting points')),
          PointsInput(
            label: tr('持ち点', 'Starting points'),
            key: ValueKey('starting-$_formKey'),
            initialValue: _defaults.startingPoints,
            presets: _pointPresets,
            errorText: _startingError,
            onChanged: (v) => setState(() => _starting = v),
          ),
          _label(context, tr('返し（オカの基準）', 'Return points (basis for oka)')),
          PointsInput(
            label: tr('返し', 'Return points'),
            key: ValueKey('return-$_formKey'),
            initialValue: _defaults.returnPoints,
            presets: _pointPresets,
            errorText: _returnError,
            onChanged: (v) => setState(() => _return = v),
          ),
          if (_startingError == null && _returnError == null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(
                '${tr('オカ（トップが受け取る分）: ', 'Oka (goes to 1st place): ')}'
                '${formatPoint((_return! - _starting!) * _playerCount / 1000)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          _label(context, tr('ウマ', 'Uma')),
          UmaInput(
            key: ValueKey('uma-input-$_formKey'),
            initialValue: _defaults.uma,
            errorText: _umaError,
            onChanged: (v) => setState(() => _uma = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('トビあり（0点未満で終了）', 'Bust (game ends below 0)')),
            value: _tobi,
            onChanged: (v) => setState(() => _tobi = v),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('詳細ルール', 'Detailed rules'), style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(_defaults.ruleSummary.join(tr('・', ', ')),
                      style: Theme.of(context).textTheme.bodySmall),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _openRuleSettings,
                      child: Text(tr('ルール設定を開く', 'Open rule settings')),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _isValid ? _start : null,
            child: Text(tr('対局開始', 'Start game')),
          ),
          if (!_isValid)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(tr('入力内容を確認してください', 'Please check your input'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ],
      ),
    );
  }
}
