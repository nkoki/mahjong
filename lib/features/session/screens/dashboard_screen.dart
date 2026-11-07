import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n.dart';
import '../../../core/theme.dart';
import '../../draw/draw_input_screen.dart';
import '../../history/history_detail_screen.dart';
import '../../history/result_image.dart';
import '../../history/result_text.dart';
import '../../win/win_input_screen.dart';
import '../domain/models.dart';
import '../domain/session_logic.dart';
import '../screen_awake.dart';
import '../session_providers.dart';
import 'all_last_conditions_sheet.dart';
import 'table_view_screen.dart';
import '../domain/all_last_conditions.dart';

/// 対局ダッシュボード（現在の局・点数・立直・和了/流局の入力）
class DashboardScreen extends ConsumerWidget {
  final String sessionId;
  const DashboardScreen({super.key, required this.sessionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider(sessionId));
    if (s == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(tr('対局が見つかりません', 'Game not found'))),
      );
    }
    final notifier = ref.read(sessionsProvider.notifier);
    final awake = keepScreenOn(ref);

    // 対局中は画面を自動で消さない（メニューで切り替えられる）
    return KeepScreenOn(
      active: !s.finished,
      child: Scaffold(
      appBar: AppBar(
        title: Text(s.finished ? tr('終局', 'Game over') : displayRoundLabel(s.roundLabel)),
        actions: [
          IconButton(
            tooltip: tr('1つ前に戻す', 'Undo'),
            icon: const Icon(Icons.undo),
            onPressed: s.previous == null
                ? null
                : () async {
                    final ok = await _confirm(context, tr('直前の局の入力を取り消しますか？', 'Undo the last round entry?'));
                    if (ok) notifier.undo(sessionId);
                  },
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'history') {
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => HistoryDetailScreen(sessionId: sessionId)));
              } else if (v == 'table') {
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => TableViewScreen(sessionId: sessionId)));
              } else if (v == 'chombo') {
                final p = await _chooseChombo(context, s);
                if (p != null) notifier.applyChombo(sessionId, p);
              } else if (v == 'progress') {
                final r = await showDialog<(int, int, int)>(context: context, builder: (_) => _ProgressDialog(session: s));
                if (r != null) {
                  notifier.adjustProgress(sessionId, roundIndex: r.$1, honba: r.$2, riichiSticks: r.$3);
                }
              } else if (v == 'substitute') {
                final names = SessionLogic.recentPlayerNames(ref.read(sessionsProvider));
                final r = await showDialog<(int, String)>(
                    context: context, builder: (_) => _SubstituteDialog(session: s, suggestions: names));
                if (r != null) {
                  notifier.substitute(sessionId, r.$1, r.$2);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(SnackBar(content: Text(tr('「${r.$2}」に交代しました（元に戻すで取り消せます）', 'Substituted "${r.$2}" (undo to revert)'))));
                  }
                }
              } else if (v == 'awake') {
                ref.read(preferenceProvider(PreferenceKeys.keepScreenOn).notifier).set(awake ? '0' : '1');
              } else if (v == 'finish') {
                final ok = await _confirm(context, tr('対局を終了しますか？（供託はトップが獲得）', 'End the game? (Riichi sticks go to the top player)'));
                if (ok) notifier.finish(sessionId);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'history', child: Text(tr('局の履歴', 'Round history'))),
              PopupMenuItem(value: 'table', child: Text(tr('卓に置いて表示（全員の向きで点数を表示）', 'Table view (scores facing each player)'))),
              if (!s.finished) PopupMenuItem(value: 'chombo', child: Text(tr('チョンボ（錯和）を入力', 'Enter chombo'))),
              if (!s.finished) PopupMenuItem(value: 'progress', child: Text(tr('局・本場・供託を直す', 'Fix round / honba / riichi sticks'))),
              if (!s.finished) PopupMenuItem(value: 'substitute', child: Text(tr('プレイヤーを交代', 'Substitute player'))),
              CheckedPopupMenuItem(value: 'awake', checked: awake, child: Text(tr('対局中は画面を消さない', 'Keep screen on during game'))),
              if (!s.finished)
                PopupMenuItem(value: 'finish', child: Text(tr('対局を終了', 'End game'))),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _InfoBar(session: s),
            if (AllLastConditions.applies(s)) AllLastConditionsBar(session: s),
            Expanded(
              child: s.finished
                  ? _FinishedView(session: s)
                  : _PlayerGrid(
                      session: s,
                      onRiichi: (p) => notifier.toggleRiichi(sessionId, p),
                    ),
            ),
            if (!s.finished)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.emoji_events),
                        label: Text(tr('和了', 'Win')),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) =>
                                  WinInputScreen(sessionId: sessionId)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 52)),
                        icon: const Icon(Icons.water_drop_outlined),
                        label: Text(tr('流局', 'Draw')),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) =>
                                  DrawInputScreen(sessionId: sessionId)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      ),
    );
  }
}

/// チョンボをした人を選ぶ（キャンセルなら null）
Future<int?> _chooseChombo(BuildContext context, GameSession s) async {
  int? selected;
  return showDialog<int>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          title: Text(tr('チョンボ（錯和）', 'Chombo')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(
                    '誤ロン・誤ツモ・ノーテン立直の流局などの罰符を入力します。満貫払いです'
                        '（子は親に4,000点・子に2,000点ずつ、親は全員に4,000点ずつ）。'
                        'この局は同じ本場でやり直し、この局で出した立直棒は本人に戻します。',
                    'Penalty for a false ron/tsumo, riichi while noten at a draw, etc. Paid as mangan '
                        '(non-dealer pays 4,000 to the dealer and 2,000 to each non-dealer; dealer pays 4,000 to everyone). '
                        'The round is replayed with the same honba, and riichi sticks put out this round are returned.')),
                const SizedBox(height: 12),
                for (var p = 0; p < s.playerCount; p++)
                  // RadioListTile は Flutter の版によって書き方が違うので、選んだ印を付けた行にする
                  ListTile(
                    key: ValueKey('chombo-$p'),
                    contentPadding: EdgeInsets.zero,
                    selected: selected == p,
                    leading: Icon(selected == p ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                    onTap: () => setState(() => selected = p),
                    title: Text('${windName(s.seatWindIndexOf(p))} ${s.playerNames[p]}'),
                    subtitle: Text(
                        tr('${formatPoints(SessionLogic.chomboDeltas(s, p)[p].abs())}点を払う',
                            'Pays ${formatPoints(SessionLogic.chomboDeltas(s, p)[p].abs())} pts'),
                        style: theme.textTheme.bodySmall),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('キャンセル', 'Cancel'))),
            FilledButton(
              onPressed: selected == null ? null : () => Navigator.pop(ctx, selected),
              child: Text(tr('罰符を払って局をやり直す', 'Pay penalty and replay round')),
            ),
          ],
        );
      },
    ),
  );
}

/// プレイヤーを交代するダイアログ（席と入る人の名前を返す）
class _SubstituteDialog extends StatefulWidget {
  final GameSession session;
  final List<String> suggestions;
  const _SubstituteDialog({required this.session, required this.suggestions});

  @override
  State<_SubstituteDialog> createState() => _SubstituteDialogState();
}

class _SubstituteDialogState extends State<_SubstituteDialog> {
  int? _seat;
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final theme = Theme.of(context);
    final error = _seat == null ? tr('交代する人を選んでください', 'Choose who leaves') : SessionLogic.validateSubstitute(s, _seat!, _name.text);
    final suggestions = widget.suggestions.where((n) => !s.playerNames.contains(n)).take(8).toList();
    return AlertDialog(
      title: Text(tr('プレイヤーを交代', 'Substitute player')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(
                  '抜ける人の点数と席（風）を、入る人がそのまま引き継ぎます。'
                      '個人成績では、交代する前の局は抜けた人、これからの局は入った人の成績として数え、'
                      '最終結果（順位・ポイント）は終局したときに打っている人の成績になります。',
                  'The new player takes over the score and seat (wind) of the leaving player. '
                      'In player stats, earlier rounds count for the leaving player and later rounds for the new one; '
                      'the final result (rank, points) goes to whoever is playing at the end.'),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(tr('抜ける人', 'Leaving'), style: theme.textTheme.titleSmall),
            Wrap(
              spacing: 6,
              children: [
                for (var p = 0; p < s.playerCount; p++)
                  ChoiceChip(
                    key: ValueKey('sub-seat-$p'),
                    label: Text('${windName(s.seatWindIndexOf(p))} ${s.playerNames[p]}'),
                    selected: _seat == p,
                    onSelected: (_) => setState(() => _seat = p),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('sub-name'),
              controller: _name,
              decoration: InputDecoration(labelText: tr('入る人の名前', 'New player name'), border: const OutlineInputBorder()),
              onChanged: (_) => setState(() {}),
            ),
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final n in suggestions)
                    ActionChip(label: Text(n), onPressed: () => setState(() => _name.text = n)),
                ],
              ),
            ],
            if (_seat != null && error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(error, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('キャンセル', 'Cancel'))),
        FilledButton(
          onPressed: error == null ? () => Navigator.pop(context, (_seat!, _name.text.trim())) : null,
          child: Text(tr('交代', 'Substitute')),
        ),
      ],
    );
  }
}

/// 今の局・本場・供託を直すダイアログ（局の通し番号・本場・供託を返す）
class _ProgressDialog extends StatefulWidget {
  final GameSession session;
  const _ProgressDialog({required this.session});

  @override
  State<_ProgressDialog> createState() => _ProgressDialogState();
}

class _ProgressDialogState extends State<_ProgressDialog> {
  late int _round = widget.session.roundIndex;
  late int _honba = widget.session.honba;
  late int _sticks = widget.session.riichiSticks;

  Widget _counter(String label, int value, ValueChanged<int> onChanged, String key) => Row(
        children: [
          Expanded(child: Text(label)),
          IconButton(
            key: ValueKey('$key-minus'),
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: value > 0 ? () => onChanged(value - 1) : null,
          ),
          SizedBox(width: 32, child: Text('$value', textAlign: TextAlign.center, key: ValueKey('$key-value'))),
          IconButton(
            key: ValueKey('$key-plus'),
            icon: const Icon(Icons.add_circle_outline),
            onPressed: value < 99 ? () => onChanged(value + 1) : null,
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final max = SessionLogic.maxRoundIndex(s.settings);
    return AlertDialog(
      title: Text(tr('局・本場・供託を直す', 'Fix round / honba / sticks')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                tr(
                    '数え間違いや、局の削除・追加でずれたときに直します。点数は変わりません。'
                        '供託を増やすと、その分の点数は場に出たまま（誰からも引かれない）になります。',
                    'Fix miscounts or shifts caused by deleting/adding rounds. Scores do not change. '
                        'Added riichi sticks stay on the table (not taken from anyone).'),
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text(tr('局', 'Round'))),
                DropdownButton<int>(
                  key: const ValueKey('progress-round'),
                  value: _round,
                  items: [
                    for (var i = 0; i <= max; i++)
                      DropdownMenuItem(
                        value: i,
                        child: Text(tr(
                            '${s.copyWith(roundIndex: i).roundName}'
                                '（親: ${s.playerNames[i % s.playerCount]}）',
                            '${displayRoundLabel(s.copyWith(roundIndex: i).roundName)}'
                                ' (dealer: ${s.playerNames[i % s.playerCount]})')),
                      ),
                  ],
                  onChanged: (v) => setState(() => _round = v!),
                ),
              ],
            ),
            _counter(tr('本場', 'Honba'), _honba, (v) => setState(() => _honba = v), 'progress-honba'),
            _counter(tr('供託（立直棒）', 'Riichi sticks'), _sticks, (v) => setState(() => _sticks = v), 'progress-sticks'),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('キャンセル', 'Cancel'))),
        FilledButton(
          onPressed: _round == s.roundIndex && _honba == s.honba && _sticks == s.riichiSticks
              ? null
              : () => Navigator.pop(context, (_round, _honba, _sticks)),
          child: Text(tr('直す', 'Fix')),
        ),
      ],
    );
  }
}

Future<bool> _confirm(BuildContext context, String message) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false), child: Text(tr('キャンセル', 'Cancel'))),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
      ],
    ),
  );
  return r ?? false;
}

class _InfoBar extends StatelessWidget {
  final GameSession session;
  const _InfoBar({required this.session});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rules = session.settings;
    final bar = Container(
      width: double.infinity,
      color: theme.colorScheme.primaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 16,
        children: [
          Text(tr(
              '${rules.isSanma ? "3人打ち " : ""}${rules.tonpuu ? "東風戦" : "半荘戦"}  '
                  '${session.records.length}局消化',
              '${rules.isSanma ? "3-player " : ""}${rules.tonpuu ? "East-only" : "Hanchan"}  '
                  '${session.records.length} rounds played')),
          Text(tr('本場 ${session.honba}  /  供託 ${session.riichiSticks}本',
              'Honba ${session.honba}  /  Riichi sticks ${session.riichiSticks}')),
        ],
      ),
    );
    if (session.finished || !session.isExtraRound) return bar;
    // 西入（南入）の延長戦中は、終わる条件を表示する
    final lastName = tr(
        '${GameSession.windNames[(rules.totalRounds ~/ rules.playerCount) % 4]}'
            '${rules.playerCount}局',
        '${windName(rules.totalRounds ~/ rules.playerCount)} ${rules.playerCount}');
    return Column(
      children: [
        bar,
        Container(
          width: double.infinity,
          color: theme.colorScheme.tertiaryContainer,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            tr(
                '${rules.extensionName}（延長戦）中: 返し点 ${formatPoints(rules.returnPoints)}点に'
                    '届いた人が出た局で終了します（最長 $lastName まで）',
                '${rules.extensionName} (extension): the game ends when someone reaches '
                    '${formatPoints(rules.returnPoints)} pts (until $lastName at most)'),
            style: TextStyle(color: theme.colorScheme.onTertiaryContainer, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

class _PlayerGrid extends StatelessWidget {
  final GameSession session;
  final void Function(int player) onRiichi;
  const _PlayerGrid({required this.session, required this.onRiichi});

  @override
  Widget build(BuildContext context) {
    final rank = session.ranking;
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth > 600;
      return GridView.count(
        padding: const EdgeInsets.all(12),
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: wide ? 2.2 : 1.05,
        children: [
          for (var p = 0; p < session.playerCount; p++)
            _PlayerCard(
              name: session.playerNames[p],
              wind: windName(session.seatWindIndexOf(p)),
              isDealer: session.dealer == p,
              score: session.scores[p],
              rank: rank.indexOf(p) + 1,
              riichi: session.riichi[p],
              diffFromTop: session.scores[rank.first] - session.scores[p],
              onRiichi: (session.riichi[p] || session.scores[p] >= 1000)
                  ? () => onRiichi(p)
                  : null,
            ),
        ],
      );
    });
  }
}

class _PlayerCard extends StatelessWidget {
  final String name;
  final String wind;
  final bool isDealer;
  final int score;
  final int rank;
  final bool riichi;
  final int diffFromTop;
  final VoidCallback? onRiichi;

  const _PlayerCard({
    required this.name,
    required this.wind,
    required this.isDealer,
    required this.score,
    required this.rank,
    required this.riichi,
    required this.diffFromTop,
    required this.onRiichi,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppTheme.accent(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(
          color: isDealer ? accent : theme.colorScheme.outlineVariant,
          width: isDealer ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // 風の札（親は朱色の札。起家マークのように四角く）
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isDealer ? accent : theme.colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(4),
                    border: isDealer ? null : Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Text(wind,
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: isDealer ? Colors.white : theme.colorScheme.onSurface)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(name,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall),
                ),
                Text(tr('$rank位', '#$rank'), style: theme.textTheme.labelMedium),
              ],
            ),
            const Spacer(),
            FittedBox(
              child: Text(formatPoints(score),
                  style: theme.textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ),
            Text(diffFromTop == 0 ? tr('トップ', 'Top') : tr('トップまで ${formatPoints(diffFromTop)}', '${formatPoints(diffFromTop)} behind top'),
                style: theme.textTheme.bodySmall),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: riichi
                  ? FilledButton(
                      style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 36),
                          backgroundColor: accent,
                          foregroundColor: Colors.white),
                      onPressed: onRiichi,
                      child: Text(tr('立直中（取消）', 'Riichi (cancel)')),
                    )
                  : OutlinedButton(
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36)),
                      onPressed: onRiichi,
                      child: Text(tr('立直', 'Riichi')),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FinishedView extends StatelessWidget {
  final GameSession session;
  const _FinishedView({required this.session});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(tr('最終結果', 'Final result'), style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        for (final r in session.finalResults)
          Card(
            child: ListTile(
              leading: CircleAvatar(child: Text('${r.rank}')),
              title: Text(session.playerNames[r.player]),
              subtitle: Text(tr(
                  '${formatPoints(r.score)}点'
                      '${r.adjustment != 0 ? '  焼き鳥・トビ賞 ${formatPoint(r.adjustment)}' : ''}',
                  '${formatPoints(r.score)} pts'
                      '${r.adjustment != 0 ? '  Yakitori/bust bonus ${formatPoint(r.adjustment)}' : ''}')),
              trailing: Text(formatPoint(r.point),
                  style: theme.textTheme.titleLarge?.copyWith(
                      color: deltaColor(context, r.point) ?? deltaColor(context, 1))),
            ),
          ),
        const SizedBox(height: 16),
        FilledButton.icon(
          icon: const Icon(Icons.image_outlined),
          label: Text(tr('結果を画像で共有', 'Share result as image')),
          onPressed: () => showResultImage(context, session),
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          icon: const Icon(Icons.copy_all_outlined),
          label: Text(tr('結果をコピー（LINE などに貼り付け）', 'Copy result (paste into chat apps)')),
          onPressed: () => ResultText.copy(context, session),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.list_alt),
          label: Text(tr('局の履歴を見る', 'View round history')),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => HistoryDetailScreen(sessionId: session.id))),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
          child: Text(tr('ホームへ戻る', 'Back to home')),
        ),
      ],
    );
  }
}
