import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../shared/widgets/rule_inputs.dart';
import '../session/domain/models.dart';
import '../session/session_providers.dart';

/// ルール設定画面（これから始める対局に使うルール）
///
/// 4人打ちと3人打ちのルールを別々に保存する。画面の上で、どちらを編集するか切り替える。
class RuleSettingsScreen extends ConsumerStatefulWidget {
  /// 最初に表示する人数（4 か 3）
  final int initialPlayerCount;

  const RuleSettingsScreen({super.key, this.initialPlayerCount = 4});

  @override
  ConsumerState<RuleSettingsScreen> createState() => _RuleSettingsScreenState();
}

class _RuleSettingsScreenState extends ConsumerState<RuleSettingsScreen> {
  /// 編集中の人数
  late int _playerCount = widget.initialPlayerCount;

  /// もう一方の人数で編集した内容（切り替えても消えないように取っておき、保存時にまとめて保存する）
  final Map<int, GameSettings> _stash = {};

  late GameSettings _settings;
  int? _starting;
  int? _return;
  late List<int?> _uma;

  /// 入力欄を作り直すためのキー（「初期値に戻す」で使う）
  int _formKey = 0;

  @override
  void initState() {
    super.initState();
    _load(ref.read(defaultSettingsProviderFor(_playerCount)));
  }

  /// 編集する人数を切り替える
  void _switchPlayerCount(int count) {
    if (count == _playerCount) return;
    if (!_isValid) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('入力内容を直してから切り替えてください')));
      return;
    }
    setState(() {
      _stash[_playerCount] = _edited;
      _playerCount = count;
      _load(_stash[count] ?? ref.read(defaultSettingsProviderFor(count)));
      _formKey++;
    });
  }

  void _load(GameSettings s) {
    _settings = s;
    _starting = s.startingPoints;
    _return = s.returnPoints;
    _uma = List.of(s.uma);
  }

  String? get _startingError => validatePoints(_starting);
  String? get _returnError => validateReturnPoints(_return, _starting);
  String? get _umaError => validateUma(_uma, playerCount: _playerCount);
  bool get _isValid => _startingError == null && _returnError == null && _umaError == null;

  GameSettings get _edited => _settings.copyWith(
        startingPoints: _starting,
        returnPoints: _return,
        uma: _umaError == null ? List.unmodifiable(_uma.map((v) => v!)) : null,
      );

  Future<void> _save() async {
    if (!_isValid) return;
    _stash[_playerCount] = _edited;
    for (final e in _stash.entries) {
      final provider = defaultSettingsProviderFor(e.key);
      // 変えていない人数のルールは保存しない
      if (jsonEncode(ref.read(provider).toJson()) == jsonEncode(e.value.toJson())) continue;
      await ref.read(provider.notifier).save(e.value);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('ルールを保存しました。これから始める対局に使われます')));
    Navigator.of(context).pop();
  }

  void _reset() {
    setState(() {
      _load(_playerCount == 3 ? const GameSettings.sanma() : const GameSettings());
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
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 4, label: Text('4人打ちのルール')),
              ButtonSegment(value: 3, label: Text('3人打ちのルール')),
            ],
            selected: {_playerCount},
            onSelectionChanged: (v) => _switchPlayerCount(v.first),
          ),
          const SizedBox(height: 12),
          Card(
            color: theme.colorScheme.tertiaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'ここで決めたルールは、これから始める対局に使われます。'
                '対局中・終わった対局のルールは変わりません。\n'
                '持ち点・返し・ウマ・トビ・半荘／東風は、新規対局の画面でその対局だけ変えることもできます。\n'
                '4人打ちと3人打ちのルールは別々に保存されます。',
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
            presets: _playerCount == 3 ? const [35000, 40000] : const [25000, 30000],
            errorText: _startingError,
            onChanged: (v) => setState(() => _starting = v),
          ),
          label('返し（オカの基準）'),
          PointsInput(
            label: '返し',
            initialValue: s.returnPoints,
            presets: _playerCount == 3 ? const [35000, 40000] : const [25000, 30000],
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
          sw(
              '西入（東風戦は南入）',
              '最終局が終わって誰も返し点に届いていなければ、次の場（半荘戦は西場・東風戦は南場）に入ります。'
                  '延長中は誰かが返し点に届いた局で終了し、届かなくても延長の4局目で終了します。'
                  'ありのときの和了止めは、親が返し点に届いている場合だけです',
              s.westRound,
              (v) => update((c) => c.copyWith(westRound: v))),
          sw(
              '包（責任払い）',
              '大三元・大四喜を確定させる牌を鳴かせた人が払います。ツモは包の人が全額、'
                  'ほかの人からのロンは包の人と放銃者で半分ずつ。和了の結果画面で包の人を選びます',
              s.pao,
              (v) => update((c) => c.copyWith(pao: v))),
          section('流局'),
          sw('流し満貫', '流局の種類に「流し満貫」を表示します', s.nagashiMangan,
              (v) => update((c) => c.copyWith(nagashiMangan: v))),
          sw(
              '途中流局',
              _playerCount == 3
                  ? '流局の種類に九種九牌・四開槓を表示します（3人打ちに四風連打・四家立直・三家和はありません）'
                  : '流局の種類に九種九牌・四風連打・四家立直・四開槓・三家和を表示します',
              s.abortiveDraws,
              (v) => update((c) => c.copyWith(abortiveDraws: v))),
          if (_playerCount == 3) ...[
            section('3人打ち'),
            sw('北抜き（抜きドラ）', '北を抜いてドラにします（1枚につきドラ1）。なしの場合、北は普通の字牌です',
                s.nukiDora, (v) => update((c) => c.copyWith(nukiDora: v))),
            label('ツモの支払い'),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('ツモ損')),
                ButtonSegment(value: true, label: Text('折半')),
              ],
              selected: {s.sanmaTsumoSplit},
              onSelectionChanged: (v) => update((c) => c.copyWith(sanmaTsumoSplit: v.first)),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'ツモ損: いない北家の分はもらえません（子の満貫ツモは 親4000・子2000 の6000点）。\n'
                '折半: 北家の分を2人で分けて払います（子の満貫ツモは 親5000・子3000 の8000点）。',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
          section('牌'),
          sw('赤ドラ',
              _playerCount == 3
                  ? '和了入力で赤5（5筒・5索）を選べるようにします（3人打ちに5萬はありません）'
                  : '和了入力で赤5（5萬・5筒・5索）を選べるようにします',
              s.redDora,
              (v) => update((c) => c.copyWith(redDora: v))),
          section('祝儀'),
          sw('祝儀（チップ）を記録する',
              '和了ごとに祝儀の枚数を入れます（赤ドラ・裏ドラ・一発の数を目安に表示）。'
                  'ロンは放銃者が、ツモはほかの全員が払います。戦績・個人成績に合計を表示します',
              s.chips,
              (v) => update((c) => c.copyWith(chips: v))),
          section('ローカルルール（精算ポイント）'),
          label('焼き鳥（1回も和了しなかった人が払う）'),
          _PointChoice(
            keyPrefix: 'yakitori',
            value: s.yakitori,
            onChanged: (v) => update((c) => c.copyWith(yakitori: v)),
          ),
          label('トビ賞（飛んだ人が飛ばした人に払う）'),
          _PointChoice(
            keyPrefix: 'tobiBonus',
            value: s.tobiBonus,
            onChanged: (v) => update((c) => c.copyWith(tobiBonus: v)),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '終局したときの最終ポイント（ウマ・オカ込み）に足し引きします。'
              '焼き鳥は和了した人で等分し、全員が和了したとき・誰も和了しなかったときは動きません。'
              'トビ賞は「トビあり」のときだけで、最後の局の和了者（ダブロンなら等分）がもらいます。'
              '流局のテンパイ料やチョンボで飛んだときは動きません。'
              '和了者を記録していない古い局（以前の版で入力した局）がある対局では焼き鳥を数えません。',
              style: theme.textTheme.bodySmall,
            ),
          ),
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
              '${_startingError == null && _returnError == null ? formatPoint((_return! - _starting!) * _playerCount / 1000) : "-"}',
              textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// 精算ポイントを選ぶ（なし・5P・10P・20P）
class _PointChoice extends StatelessWidget {
  final String keyPrefix;
  final int value;
  final ValueChanged<int> onChanged;
  const _PointChoice({required this.keyPrefix, required this.value, required this.onChanged});

  static const choices = [0, 5, 10, 20];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        for (final c in {...choices, value})
          ChoiceChip(
            key: ValueKey('$keyPrefix-$c'),
            label: Text(c == 0 ? 'なし' : '${c}P'),
            selected: value == c,
            onSelected: (_) => onChanged(c),
          ),
      ],
    );
  }
}
