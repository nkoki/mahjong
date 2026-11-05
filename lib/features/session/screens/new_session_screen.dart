import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/routes.dart';
import '../../../core/theme.dart';
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
  late bool _tonpuu;
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
    _tonpuu = _defaults.tonpuu;
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
    _tonpuu = p.settings.tonpuu;
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

  /// 名前の候補を、空いている一番上の欄に入れる
  void _fillName(String name) {
    for (var i = 0; i < _playerCount; i++) {
      if (_controllers[i].text.trim().isEmpty) {
        setState(() => _controllers[i].text = name);
        return;
      }
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('空いている欄がありません。入れ替える欄の名前を消してから選んでください')));
  }

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
      tonpuu: _tonpuu,
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
        title: const Text('古い対局が削除されます'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('保存できる対局は${SessionLogic.maxSavedSessions}件までです。'
                '新しい対局を始めると、お気に入り（★）にしていない一番古い対局'
                '${removed.length > 1 ? "から${removed.length}件" : ""}が削除されます。'
                '削除すると元に戻せません。'),
            const SizedBox(height: 12),
            for (final s in removed.take(3))
              Text('・${date(s.createdAt)}  ${s.playerNames.join(" / ")}',
                  style: Theme.of(ctx).textTheme.bodySmall),
            if (removed.length > 3)
              Text('・ほか${removed.length - 3}件', style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 12),
            Text('残したい対局は、戦績画面で ★ を押してお気に入りにしてください。',
                style: Theme.of(ctx).textTheme.bodySmall),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: const Text('削除して開始')),
        ],
      ),
    );
    return r ?? false;
  }

  /// 過去の対局で使った名前の候補と、前回のメンバー
  List<Widget> _nameSuggestions(BuildContext context) {
    final sessions = ref.watch(sessionsProvider);
    final recent = SessionLogic.recentPlayerNames(sessions);
    final last = SessionLogic.lastMembers(sessions, _playerCount);
    if (recent.isEmpty && last == null) return const [];
    final entered = {for (var i = 0; i < _playerCount; i++) _controllers[i].text.trim()};
    final small = Theme.of(context).textTheme.bodySmall;
    return [
      if (last != null)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.history),
            label: Text('前回のメンバー（${last.join("・")}）', overflow: TextOverflow.ellipsis),
            onPressed: () => _fillMembers(last),
          ),
        ),
      if (recent.isNotEmpty) ...[
        Text('最近のプレイヤー（タップすると空いている欄に入ります）', style: small),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final n in recent)
              ActionChip(
                label: Text(n),
                onPressed: entered.contains(n) ? null : () => _fillName(n),
              ),
          ],
        ),
      ],
    ];
  }

  Widget _label(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
      );

  @override
  Widget build(BuildContext context) {
    const winds = ['東家（起家）', '南家', '西家', '北家'];
    return Scaffold(
      appBar: AppBar(title: const Text('新規対局')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 4, label: Text('4人打ち')),
              ButtonSegment(value: 3, label: Text('3人打ち')),
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
                '3人打ち: 二萬〜八萬を使わない・チーなし・'
                '${_defaults.nukiDora ? "北抜きあり" : "北抜きなし"}・'
                '${_defaults.sanmaTsumoSplit ? "ツモ折半" : "ツモ損"}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 16),
          Text('プレイヤー', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (var i = 0; i < _playerCount; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                key: ValueKey('player-name-$i'),
                controller: _controllers[i],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: winds[i],
                  hintText: SessionLogic.defaultPlayerName(i),
                  border: const OutlineInputBorder(),
                  suffixIcon: _controllers[i].text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '名前を消す',
                          icon: const Icon(Icons.clear),
                          onPressed: () => setState(() => _controllers[i].clear()),
                        ),
                ),
              ),
            ),
          if (_nameError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_nameError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          ..._nameSuggestions(context),
          const SizedBox(height: 16),
          Text('ルール', style: Theme.of(context).textTheme.titleMedium),
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
              child: Text('保存したルールのセットを選ぶと、下の持ち点・ウマなどと詳細ルールが切り替わります。',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('半荘戦')),
              ButtonSegment(value: true, label: Text('東風戦')),
            ],
            selected: {_tonpuu},
            onSelectionChanged: (v) => setState(() => _tonpuu = v.first),
          ),
          const SizedBox(height: 12),
          _label(context, '持ち点（配給原点）'),
          PointsInput(
            label: '持ち点',
            key: ValueKey('starting-$_formKey'),
            initialValue: _defaults.startingPoints,
            presets: _pointPresets,
            errorText: _startingError,
            onChanged: (v) => setState(() => _starting = v),
          ),
          _label(context, '返し（オカの基準）'),
          PointsInput(
            label: '返し',
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
                'オカ（トップが受け取る分）: '
                '${formatPoint((_return! - _starting!) * _playerCount / 1000)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          _label(context, 'ウマ'),
          UmaInput(
            key: ValueKey('uma-input-$_formKey'),
            initialValue: _defaults.uma,
            errorText: _umaError,
            onChanged: (v) => setState(() => _uma = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('トビあり（0点未満で終了）'),
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
                  Text('詳細ルール', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(_defaults.ruleSummary.join('・'),
                      style: Theme.of(context).textTheme.bodySmall),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _openRuleSettings,
                      child: const Text('ルール設定を開く'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _isValid ? _start : null,
            child: const Text('対局開始'),
          ),
          if (!_isValid)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('入力内容を確認してください',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ],
      ),
    );
  }
}
