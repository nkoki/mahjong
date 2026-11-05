import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/routes.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets/rule_inputs.dart';
import '../domain/models.dart';
import '../domain/session_logic.dart';
import '../../settings/rule_settings_screen.dart';
import '../session_providers.dart';

/// 新規対局の作成画面
class NewSessionScreen extends ConsumerStatefulWidget {
  const NewSessionScreen({super.key});

  @override
  ConsumerState<NewSessionScreen> createState() => _NewSessionScreenState();
}

class _NewSessionScreenState extends ConsumerState<NewSessionScreen> {
  final _controllers = List.generate(
      4, (i) => TextEditingController(text: 'プレイヤー${i + 1}'));
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
    _defaults = ref.read(defaultSettingsProvider);
    _tonpuu = _defaults.tonpuu;
    _tobi = _defaults.tobi;
    _starting = _defaults.startingPoints;
    _return = _defaults.returnPoints;
    _uma = List.of(_defaults.uma);
  }

  Future<void> _openRuleSettings() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const RuleSettingsScreen()));
    // 詳細ルールだけ反映する（持ち点などはこの画面で入力した値をそのまま使う）
    if (mounted) setState(() => _defaults = ref.read(defaultSettingsProvider));
  }

  String? get _startingError => validatePoints(_starting);
  String? get _returnError => validateReturnPoints(_return, _starting);
  String? get _umaError => validateUma(_uma);
  bool get _isValid =>
      _startingError == null && _returnError == null && _umaError == null;

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _start() async {
    final names = [
      for (var i = 0; i < 4; i++)
        _controllers[i].text.trim().isEmpty
            ? 'プレイヤー${i + 1}'
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
          Text('プレイヤー', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (var i = 0; i < 4; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                controller: _controllers[i],
                decoration: InputDecoration(
                  labelText: winds[i],
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text('ルール', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
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
            initialValue: _defaults.startingPoints,
            presets: const [25000, 30000],
            errorText: _startingError,
            onChanged: (v) => setState(() => _starting = v),
          ),
          _label(context, '返し（オカの基準）'),
          PointsInput(
            label: '返し',
            initialValue: _defaults.returnPoints,
            presets: const [25000, 30000],
            errorText: _returnError,
            onChanged: (v) => setState(() => _return = v),
          ),
          if (_startingError == null && _returnError == null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(
                'オカ（トップが受け取る分）: '
                '${formatPoint((_return! - _starting!) * 4 / 1000)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          _label(context, 'ウマ'),
          UmaInput(
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
