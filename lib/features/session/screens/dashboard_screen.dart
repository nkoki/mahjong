import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../draw/draw_input_screen.dart';
import '../../history/history_detail_screen.dart';
import '../../win/win_input_screen.dart';
import '../domain/models.dart';
import '../screen_awake.dart';
import '../session_providers.dart';
import 'table_view_screen.dart';

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
        body: const Center(child: Text('対局が見つかりません')),
      );
    }
    final notifier = ref.read(sessionsProvider.notifier);
    final awake = keepScreenOn(ref);

    // 対局中は画面を自動で消さない（メニューで切り替えられる）
    return KeepScreenOn(
      active: !s.finished,
      child: Scaffold(
      appBar: AppBar(
        title: Text(s.finished ? '終局' : s.roundLabel),
        actions: [
          IconButton(
            tooltip: '1つ前に戻す',
            icon: const Icon(Icons.undo),
            onPressed: s.previous == null
                ? null
                : () async {
                    final ok = await _confirm(context, '直前の局の入力を取り消しますか？');
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
              } else if (v == 'awake') {
                ref.read(preferenceProvider(PreferenceKeys.keepScreenOn).notifier).set(awake ? '0' : '1');
              } else if (v == 'finish') {
                final ok = await _confirm(context, '対局を終了しますか？（供託はトップが獲得）');
                if (ok) notifier.finish(sessionId);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'history', child: Text('局の履歴')),
              const PopupMenuItem(value: 'table', child: Text('卓に置いて表示（全員の向きで点数を表示）')),
              CheckedPopupMenuItem(value: 'awake', checked: awake, child: const Text('対局中は画面を消さない')),
              if (!s.finished)
                const PopupMenuItem(value: 'finish', child: Text('対局を終了')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _InfoBar(session: s),
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
                        label: const Text('和了'),
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
                        label: const Text('流局'),
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

Future<bool> _confirm(BuildContext context, String message) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
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
          Text('${rules.isSanma ? "3人打ち " : ""}${rules.tonpuu ? "東風戦" : "半荘戦"}  '
              '${session.records.length}局消化'),
          Text('本場 ${session.honba}  /  供託 ${session.riichiSticks}本'),
        ],
      ),
    );
    if (session.finished || !session.isExtraRound) return bar;
    // 西入（南入）の延長戦中は、終わる条件を表示する
    final lastName = '${GameSession.windNames[(rules.totalRounds ~/ rules.playerCount) % 4]}'
        '${rules.playerCount}局';
    return Column(
      children: [
        bar,
        Container(
          width: double.infinity,
          color: theme.colorScheme.tertiaryContainer,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            '${rules.extensionName}（延長戦）中: 返し点 ${formatPoints(rules.returnPoints)}点に'
            '届いた人が出た局で終了します（最長 $lastName まで）',
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
              wind: GameSession.windNames[session.seatWindIndexOf(p)],
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
    return Card(
      elevation: isDealer ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDealer ? Colors.orange : Colors.transparent,
          width: 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor:
                      isDealer ? Colors.orange : theme.colorScheme.secondaryContainer,
                  child: Text(wind,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isDealer ? Colors.white : null)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(name,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall),
                ),
                Text('$rank位', style: theme.textTheme.labelMedium),
              ],
            ),
            const Spacer(),
            FittedBox(
              child: Text(formatPoints(score),
                  style: theme.textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ),
            Text(diffFromTop == 0 ? 'トップ' : 'トップまで ${formatPoints(diffFromTop)}',
                style: theme.textTheme.bodySmall),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: riichi
                  ? FilledButton(
                      style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 36),
                          backgroundColor: Theme.of(context).colorScheme.error,
                          foregroundColor: Theme.of(context).colorScheme.onError),
                      onPressed: onRiichi,
                      child: const Text('立直中（取消）'),
                    )
                  : OutlinedButton(
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36)),
                      onPressed: onRiichi,
                      child: const Text('立直'),
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
        Text('最終結果', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        for (final r in session.finalResults)
          Card(
            child: ListTile(
              leading: CircleAvatar(child: Text('${r.rank}')),
              title: Text(session.playerNames[r.player]),
              subtitle: Text('${formatPoints(r.score)}点'),
              trailing: Text(formatPoint(r.point),
                  style: theme.textTheme.titleLarge?.copyWith(
                      color: deltaColor(context, r.point) ?? deltaColor(context, 1))),
            ),
          ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          icon: const Icon(Icons.list_alt),
          label: const Text('局の履歴を見る'),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => HistoryDetailScreen(sessionId: session.id))),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
          child: const Text('ホームへ戻る'),
        ),
      ],
    );
  }
}
