import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../shared/widgets/rule_inputs.dart';
import '../session/domain/models.dart';
import '../session/session_providers.dart';

/// ルール設定画面（これから始める対局に使うルール）
class RuleSettingsScreen extends ConsumerStatefulWidget {
  const RuleSettingsScreen({super.key});

  @override
  ConsumerState<RuleSettingsScreen> createState() => _RuleSettingsScreenState();
}

class _RuleSettingsScreenState extends ConsumerState<RuleSettingsScreen> {
  late GameSettings _settings;
  int? _starting;
  int? _return;
  late List<int?> _uma;

  /// 入力欄を作り直すためのキー（「初期値に戻す」で使う）
  int _formKey = 0;

  @override
  void initState() {
    super.initState();
    _load(ref.read(defaultSettingsProvider));
  }

  void _load(GameSettings s) {
    _settings = s;
    _starting = s.startingPoints;
    _return = s.returnPoints;
    _uma = List.of(s.uma);
  }

  String? get _startingError => validatePoints(_starting);
  String? get _returnError => validateReturnPoints(_return, _starting);
  String? get _umaError => validateUma(_uma);
  bool get _isValid => _startingError == null && _returnError == null && _umaError == null;

  GameSettings get _edited => _settings.copyWith(
        startingPoints: _starting,
        returnPoints: _return,
        uma: _umaError == null ? List.unmodifiable(_uma.map((v) => v!)) : null,
      );

  Future<void> _save() async {
    if (!_isValid) return;
    await ref.read(defaultSettingsProvider.notifier).save(_edited);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('ルールを保存しました。これから始める対局に使われます')));
    Navigator.of(context).pop();
  }

  void _reset() {
    setState(() {
      _load(const GameSettings());
      _formKey++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = _settings;
    // 画面を描き直す前に続けて操作しても前の変更が消えないよう、常に最新の設定から作り直す
    void update(GameSettings Function(GameSettings current) f) =>
        setState(() => _settings = f(_settings));

    Widget section(String title) => Padding(
          padding: const EdgeInsets.only(top: 24, bottom: 4),
          child: Text(title, style: theme.textTheme.titleMedium),
        );
    Widget label(String text) => Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 6),
          child: Text(text, style: theme.textTheme.bodyMedium),
        );
    Widget sw(String title, String subtitle, bool value, ValueChanged<bool> onChanged) =>
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(title),
          subtitle: Text(subtitle, style: theme.textTheme.bodySmall),
          value: value,
          onChanged: onChanged,
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text('ルール設定'),
        actions: [
          TextButton(
            onPressed: _reset,
            style: TextButton.styleFrom(foregroundColor: theme.colorScheme.onPrimary),
            child: const Text('初期値に戻す'),
          ),
        ],
      ),
      body: ListView(
        key: ValueKey(_formKey),
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: theme.colorScheme.tertiaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'ここで決めたルールは、これから始める対局に使われます。'
                '対局中・終わった対局のルールは変わりません。\n'
                '持ち点・返し・ウマ・トビ・半荘／東風は、新規対局の画面でその対局だけ変えることもできます。',
                style: TextStyle(color: theme.colorScheme.onTertiaryContainer, fontSize: 13),
              ),
            ),
          ),
          section('対局'),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('半荘戦')),
              ButtonSegment(value: true, label: Text('東風戦')),
            ],
            selected: {s.tonpuu},
            onSelectionChanged: (v) => update((c) => c.copyWith(tonpuu: v.first)),
          ),
          label('持ち点（配給原点）'),
          PointsInput(
            label: '持ち点',
            initialValue: s.startingPoints,
            presets: const [25000, 30000],
            errorText: _startingError,
            onChanged: (v) => setState(() => _starting = v),
          ),
          label('返し（オカの基準）'),
          PointsInput(
            label: '返し',
            initialValue: s.returnPoints,
            presets: const [25000, 30000],
            errorText: _returnError,
            onChanged: (v) => setState(() => _return = v),
          ),
          label('ウマ'),
          UmaInput(
            initialValue: s.uma,
            errorText: _umaError,
            onChanged: (v) => setState(() => _uma = v),
          ),
          sw('トビあり', '0点未満の人が出たら対局を終了します', s.tobi, (v) => update((c) => c.copyWith(tobi: v))),
          section('点数計算'),
          sw('喰いタン', 'なしにすると、鳴いた手では断么九が役になりません', s.kuitan,
              (v) => update((c) => c.copyWith(kuitan: v))),
          sw('切り上げ満貫', '4翻30符・3翻60符を満貫として扱います（子 7700点 → 8000点）', s.kiriageMangan,
              (v) => update((c) => c.copyWith(kiriageMangan: v))),
          sw('数え役満', '役満以外で13翻以上を役満にします。なしの場合は三倍満止まり', s.kazoeYakuman,
              (v) => update((c) => c.copyWith(kazoeYakuman: v))),
          sw('ダブル役満・役満の複合', '四暗刻単騎・国士無双十三面待ちなどを2倍にし、役満どうしを足します。なしの場合は役満1倍止まり',
              s.doubleYakuman, (v) => update((c) => c.copyWith(doubleYakuman: v))),
          label('連風牌（場風かつ自風）の雀頭の符'),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 4, label: Text('4符')),
              ButtonSegment(value: 2, label: Text('2符')),
            ],
            selected: {s.renpuuPairFu},
            onSelectionChanged: (v) => update((c) => c.copyWith(renpuuPairFu: v.first)),
          ),
          section('進行'),
          sw('ダブロン', 'なしにすると頭ハネ（放銃者から見て打つ順番が近い1人だけが和了）になります', s.doubleRon,
              (v) => update((c) => c.copyWith(doubleRon: v))),
          sw('和了止め', 'オーラスで親が和了してトップのとき、連荘せずに対局を終了します', s.agariYame,
              (v) => update((c) => c.copyWith(agariYame: v))),
          section('流局'),
          sw('流し満貫', '流局の種類に「流し満貫」を表示します', s.nagashiMangan,
              (v) => update((c) => c.copyWith(nagashiMangan: v))),
          sw('途中流局', '流局の種類に九種九牌・四風連打・四家立直・四開槓・三家和を表示します', s.abortiveDraws,
              (v) => update((c) => c.copyWith(abortiveDraws: v))),
          section('牌'),
          sw('赤ドラ', '和了入力で赤5（5萬・5筒・5索）を選べるようにします', s.redDora,
              (v) => update((c) => c.copyWith(redDora: v))),
          const SizedBox(height: 24),
          FilledButton(onPressed: _isValid ? _save : null, child: const Text('保存')),
          if (!_isValid)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('入力内容を確認してください',
                  textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.error)),
            ),
          const SizedBox(height: 8),
          Text('オカ（トップが受け取る分）: '
              '${_startingError == null && _returnError == null ? formatPoint((_return! - _starting!) * 4 / 1000) : "-"}',
              textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
