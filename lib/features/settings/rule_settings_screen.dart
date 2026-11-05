import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../shared/widgets/rule_inputs.dart';
import '../session/domain/models.dart';
import '../session/session_providers.dart';
import '../../core/l10n.dart';
import 'rule_presets.dart';

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
        ..showSnackBar(SnackBar(content: Text(tr('入力内容を直してから切り替えてください', 'Fix the errors before switching'))));
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
      ..showSnackBar(SnackBar(content: Text(tr('ルールを保存しました。これから始める対局に使われます', 'Rules saved. They will be used for new games'))));
    Navigator.of(context).pop();
  }

  Future<void> _savePreset() async {
    final name = await showDialog<String>(context: context, builder: (_) => const _PresetNameDialog());
    if (name == null || !mounted) return;
    final list = RulePresets.save(ref.read(rulePresetsProvider), name, _edited);
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    if (list == null) {
      messenger.showSnackBar(SnackBar(content: Text(tr('ルールのセットは${RulePresets.max}個までです。使わないセットを削除してください', 'Up to ${RulePresets.max} rule sets. Delete ones you do not use'))));
      return;
    }
    saveRulePresets(ref, list);
    messenger.showSnackBar(SnackBar(content: Text(tr('「${name.trim()}」として保存しました', 'Saved as "${name.trim()}"'))));
  }

  Future<void> _deletePreset(RulePreset p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(tr('ルールのセット「${p.name}」を削除しますか？（始めた対局のルールは変わりません）', 'Delete the rule set "${p.name}"? (Rules of games already started will not change)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('キャンセル', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('削除', 'Delete'))),
        ],
      ),
    );
    if (ok == true) saveRulePresets(ref, RulePresets.remove(ref.read(rulePresetsProvider), p));
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
        title: Text(tr('ルール設定', 'Rules')),
        actions: [
          TextButton(
            onPressed: _reset,
            style: TextButton.styleFrom(foregroundColor: theme.colorScheme.onPrimary),
            child: Text(tr('初期値に戻す', 'Reset')),
          ),
        ],
      ),
      body: ListView(
        key: ValueKey(_formKey),
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<int>(
            segments: [
              ButtonSegment(value: 4, label: Text(tr('4人打ちのルール', '4-player rules'))),
              ButtonSegment(value: 3, label: Text(tr('3人打ちのルール', '3-player rules'))),
            ],
            selected: {_playerCount},
            onSelectionChanged: (v) => _switchPlayerCount(v.first),
          ),
          section(tr('ルールのセット', 'Rule sets')),
          Text(
            tr(
                'よく使うルールに名前を付けて保存しておくと、ここや新規対局の画面で選ぶだけで切り替えられます'
                    '（${_playerCount == 3 ? "3人打ち" : "4人打ち"}のセット。全部で${RulePresets.max}個まで）。',
                'Save rules you use often under a name, then switch to them with one tap here or on the new game screen'
                    ' (${_playerCount == 3 ? "3-player" : "4-player"} sets; up to ${RulePresets.max} in total).'),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final p in ref.watch(rulePresetsProvider).where((p) => p.playerCount == _playerCount))
                InputChip(
                  key: ValueKey('preset-${p.name}'),
                  label: Text(p.name),
                  onPressed: () => setState(() {
                    _load(p.settings);
                    _formKey++;
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(SnackBar(content: Text(tr('「${p.name}」のルールを読み込みました。保存すると、これから始める対局に使われます', 'Loaded "${p.name}". Save to use it for new games'))));
                  }),
                  onDeleted: () => _deletePreset(p),
                  deleteButtonTooltipMessage: tr('「${p.name}」を削除', 'Delete "${p.name}"'),
                ),
              ActionChip(
                key: const ValueKey('preset-save'),
                avatar: const Icon(Icons.bookmark_add_outlined, size: 18),
                label: Text(tr('今のルールをセットとして保存', 'Save current rules as a set')),
                onPressed: _isValid ? _savePreset : null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            color: theme.colorScheme.tertiaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                tr(
                    'ここで決めたルールは、これから始める対局に使われます。'
                        '対局中・終わった対局のルールは変わりません。\n'
                        '持ち点・返し・ウマ・トビ・半荘／東風は、新規対局の画面でその対局だけ変えることもできます。\n'
                        '4人打ちと3人打ちのルールは別々に保存されます。',
                    'These rules are used for new games. '
                        'Games in progress or finished keep their rules.\n'
                        'Starting points, return points, uma, bust and hanchan/East-only can also be changed for a single game on the new game screen.\n'
                        '4-player and 3-player rules are saved separately.'),
                style: TextStyle(color: theme.colorScheme.onTertiaryContainer, fontSize: 13),
              ),
            ),
          ),
          section(tr('対局', 'Game')),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: false, label: Text(tr('半荘戦', 'Hanchan'))),
              ButtonSegment(value: true, label: Text(tr('東風戦', 'East-only'))),
            ],
            selected: {s.tonpuu},
            onSelectionChanged: (v) => update((c) => c.copyWith(tonpuu: v.first)),
          ),
          label(tr('持ち点（配給原点）', 'Starting points')),
          PointsInput(
            label: tr('持ち点', 'Starting points'),
            initialValue: s.startingPoints,
            presets: _playerCount == 3 ? const [35000, 40000] : const [25000, 30000],
            errorText: _startingError,
            onChanged: (v) => setState(() => _starting = v),
          ),
          label(tr('返し（オカの基準）', 'Return points (basis for oka)')),
          PointsInput(
            label: tr('返し', 'Return points'),
            initialValue: s.returnPoints,
            presets: _playerCount == 3 ? const [35000, 40000] : const [25000, 30000],
            errorText: _returnError,
            onChanged: (v) => setState(() => _return = v),
          ),
          label(tr('ウマ', 'Uma')),
          UmaInput(
            initialValue: s.uma,
            errorText: _umaError,
            onChanged: (v) => setState(() => _uma = v),
          ),
          sw(tr('トビあり', 'Bust'), tr('0点未満の人が出たら対局を終了します', 'End the game when someone goes below 0'), s.tobi, (v) => update((c) => c.copyWith(tobi: v))),
          section(tr('点数計算', 'Scoring')),
          sw(tr('喰いタン', 'Kuitan'), tr('なしにすると、鳴いた手では断么九が役になりません', 'If off, tanyao does not count for open hands'), s.kuitan,
              (v) => update((c) => c.copyWith(kuitan: v))),
          sw(tr('切り上げ満貫', 'Kiriage mangan'), tr('4翻30符・3翻60符を満貫として扱います（子 7700点 → 8000点）', 'Treat 4 han 30 fu and 3 han 60 fu as mangan (non-dealer 7700 → 8000 pts)'), s.kiriageMangan,
              (v) => update((c) => c.copyWith(kiriageMangan: v))),
          sw(tr('数え役満', 'Kazoe yakuman'), tr('役満以外で13翻以上を役満にします。なしの場合は三倍満止まり', '13+ han counts as yakuman. If off, capped at sanbaiman'), s.kazoeYakuman,
              (v) => update((c) => c.copyWith(kazoeYakuman: v))),
          sw(tr('ダブル役満・役満の複合', 'Double / stacked yakuman'), tr('四暗刻単騎・国士無双十三面待ちなどを2倍にし、役満どうしを足します。なしの場合は役満1倍止まり', 'Suuankou tanki, 13-wait kokushi etc. count double, and yakuman stack. If off, capped at single yakuman'),
              s.doubleYakuman, (v) => update((c) => c.copyWith(doubleYakuman: v))),
          label(tr('連風牌（場風かつ自風）の雀頭の符', 'Fu for a double-wind pair (round and seat wind)')),
          SegmentedButton<int>(
            segments: [
              ButtonSegment(value: 4, label: Text(tr('4符', '4 fu'))),
              ButtonSegment(value: 2, label: Text(tr('2符', '2 fu'))),
            ],
            selected: {s.renpuuPairFu},
            onSelectionChanged: (v) => update((c) => c.copyWith(renpuuPairFu: v.first)),
          ),
          section(tr('進行', 'Progression')),
          sw(tr('ダブロン', 'Double ron'), tr('なしにすると頭ハネ（放銃者から見て打つ順番が近い1人だけが和了）になります', 'If off, head bump applies (only the player closest in turn order after the discarder wins)'), s.doubleRon,
              (v) => update((c) => c.copyWith(doubleRon: v))),
          sw(tr('和了止め', 'Agari-yame'), tr('オーラスで親が和了してトップのとき、連荘せずに対局を終了します', 'In the last round, if the dealer wins and is in first place, the game ends without renchan'), s.agariYame,
              (v) => update((c) => c.copyWith(agariYame: v))),
          sw(
              tr('西入（東風戦は南入）', 'West round extension (South for East-only)'),
              tr(
                  '最終局が終わって誰も返し点に届いていなければ、次の場（半荘戦は西場・東風戦は南場）に入ります。'
                      '延長中は誰かが返し点に届いた局で終了し、届かなくても延長の4局目で終了します。'
                      'ありのときの和了止めは、親が返し点に届いている場合だけです',
                  'If nobody has reached the return points after the last round, play continues into the next round (West for hanchan, South for East-only). '
                      'The extension ends when someone reaches the return points, or after its 4th hand at the latest. '
                      'With this on, agari-yame applies only if the dealer has reached the return points'),
              s.westRound,
              (v) => update((c) => c.copyWith(westRound: v))),
          sw(
              tr('包（責任払い）', 'Pao (liability)'),
              tr(
                  '大三元・大四喜を確定させる牌を鳴かせた人が払います。ツモは包の人が全額、'
                      'ほかの人からのロンは包の人と放銃者で半分ずつ。和了の結果画面で包の人を選びます',
                  'The player who fed the tile that confirmed daisangen/daisuushii pays. On tsumo they pay everything; '
                      'on ron from someone else, they and the discarder split it. Choose the pao player on the win result screen'),
              s.pao,
              (v) => update((c) => c.copyWith(pao: v))),
          section(tr('流局', 'Draws')),
          sw(tr('流し満貫', 'Nagashi mangan'), tr('流局の種類に「流し満貫」を表示します', 'Show "Nagashi mangan" as a draw type'), s.nagashiMangan,
              (v) => update((c) => c.copyWith(nagashiMangan: v))),
          sw(
              tr('途中流局', 'Abortive draws'),
              _playerCount == 3
                  ? tr('流局の種類に九種九牌・四開槓を表示します（3人打ちに四風連打・四家立直・三家和はありません）',
                      'Show nine terminals and four kans as draw types (3-player has no four winds, four riichi or triple ron)')
                  : tr('流局の種類に九種九牌・四風連打・四家立直・四開槓・三家和を表示します',
                      'Show nine terminals, four winds, four riichi, four kans and triple ron as draw types'),
              s.abortiveDraws,
              (v) => update((c) => c.copyWith(abortiveDraws: v))),
          if (_playerCount == 3) ...[
            section(tr('3人打ち', '3-player')),
            sw(tr('北抜き（抜きドラ）', 'North as nuki dora'), tr('北を抜いてドラにします（1枚につきドラ1）。なしの場合、北は普通の字牌です', 'Set aside North tiles as dora (1 dora each). If off, North is a normal honor tile'),
                s.nukiDora, (v) => update((c) => c.copyWith(nukiDora: v))),
            label(tr('ツモの支払い', 'Tsumo payment')),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, label: Text(tr('ツモ損', 'Tsumo loss'))),
                ButtonSegment(value: true, label: Text(tr('折半', 'Split'))),
              ],
              selected: {s.sanmaTsumoSplit},
              onSelectionChanged: (v) => update((c) => c.copyWith(sanmaTsumoSplit: v.first)),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                tr(
                    'ツモ損: いない北家の分はもらえません（子の満貫ツモは 親4000・子2000 の6000点）。\n'
                        '折半: 北家の分を2人で分けて払います（子の満貫ツモは 親5000・子3000 の8000点）。',
                    'Tsumo loss: the missing North seat\'s share is not paid (non-dealer mangan tsumo: dealer 4000, non-dealer 2000 = 6000 pts).\n'
                        'Split: the North share is split between the two payers (non-dealer mangan tsumo: dealer 5000, non-dealer 3000 = 8000 pts).'),
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
          section(tr('牌', 'Tiles')),
          sw(tr('赤ドラ', 'Red fives'),
              _playerCount == 3
                  ? tr('和了入力で赤5（5筒・5索）を選べるようにします（3人打ちに5萬はありません）',
                      'Allow red fives (5p, 5s) in win input (3-player has no 5m)')
                  : tr('和了入力で赤5（5萬・5筒・5索）を選べるようにします', 'Allow red fives (5m, 5p, 5s) in win input'),
              s.redDora,
              (v) => update((c) => c.copyWith(redDora: v))),
          section(tr('祝儀', 'Chips')),
          sw(tr('祝儀（チップ）を記録する', 'Record chips'),
              tr(
                  '和了ごとに祝儀の枚数を入れます（赤ドラ・裏ドラ・一発の数を目安に表示）。'
                      'ロンは放銃者が、ツモはほかの全員が払います。戦績・個人成績に合計を表示します',
                  'Enter the number of chips for each win (red fives, ura dora and ippatsu are shown as a guide). '
                      'On ron the discarder pays; on tsumo everyone else pays. Totals appear in the records and player stats'),
              s.chips,
              (v) => update((c) => c.copyWith(chips: v))),
          section(tr('ローカルルール（精算ポイント）', 'Local rules (settlement points)')),
          label(tr('焼き鳥（1回も和了しなかった人が払う）', 'Yakitori (paid by players who never won)')),
          _PointChoice(
            keyPrefix: 'yakitori',
            value: s.yakitori,
            onChanged: (v) => update((c) => c.copyWith(yakitori: v)),
          ),
          label(tr('トビ賞（飛んだ人が飛ばした人に払う）', 'Bust bonus (paid by the busted player to the one who busted them)')),
          _PointChoice(
            keyPrefix: 'tobiBonus',
            value: s.tobiBonus,
            onChanged: (v) => update((c) => c.copyWith(tobiBonus: v)),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              tr(
                  '終局したときの最終ポイント（ウマ・オカ込み）に足し引きします。'
                      '焼き鳥は和了した人で等分し、全員が和了したとき・誰も和了しなかったときは動きません。'
                      'トビ賞は「トビあり」のときだけで、最後の局の和了者（ダブロンなら等分）がもらいます。'
                      '流局のテンパイ料やチョンボで飛んだときは動きません。'
                      '和了者を記録していない古い局（以前の版で入力した局）がある対局では焼き鳥を数えません。',
                  'Added to or subtracted from the final points (including uma and oka) at game end. '
                      'Yakitori is shared equally among those who won; nothing moves if everyone or nobody won. '
                      'The bust bonus applies only with "Bust" on, and goes to the winner of the last hand (split on double ron). '
                      'It does not apply when the bust came from noten payments or a chombo. '
                      'Yakitori is not counted in games with old hands that have no recorded winner (entered in an earlier version).'),
              style: theme.textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _isValid ? _save : null, child: Text(tr('保存', 'Save'))),
          if (!_isValid)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(tr('入力内容を確認してください', 'Please check your input'),
                  textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.error)),
            ),
          const SizedBox(height: 8),
          Text(
              '${tr('オカ（トップが受け取る分）: ', 'Oka (goes to 1st place): ')}'
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
            label: Text(c == 0 ? tr('なし', 'None') : '${c}P'),
            selected: value == c,
            onSelected: (_) => onChanged(c),
          ),
      ],
    );
  }
}

/// ルールのセットの名前を入れるダイアログ
class _PresetNameDialog extends StatefulWidget {
  const _PresetNameDialog();

  @override
  State<_PresetNameDialog> createState() => _PresetNameDialogState();
}

class _PresetNameDialogState extends State<_PresetNameDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = RulePresets.validateName(_c.text);
    return AlertDialog(
      title: Text(tr('ルールのセットの名前', 'Rule set name')),
      content: TextField(
        key: const ValueKey('preset-name'),
        controller: _c,
        autofocus: true,
        decoration: InputDecoration(
          hintText: tr('例: いつもの面子、雀荘ルール', 'e.g. Usual group, Parlor rules'),
          helperText: tr('同じ名前のセットがあれば上書きします', 'Overwrites a set with the same name'),
          errorText: _c.text.isEmpty ? null : error,
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('キャンセル', 'Cancel'))),
        FilledButton(
          onPressed: error == null ? () => Navigator.pop(context, _c.text.trim()) : null,
          child: Text(tr('保存', 'Save')),
        ),
      ],
    );
  }
}
