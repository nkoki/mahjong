import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../session/domain/models.dart';
import '../session/domain/session_logic.dart';
import '../session/session_providers.dart';
import '../storage/storage_info_screen.dart';
import '../stats/stats_screen.dart';
import 'history_detail_screen.dart';

/// 戦績の絞り込み条件（UI に依存しない）
class HistoryFilter {
  /// 名前（一部でよい。大文字・小文字は区別しない）。空なら絞り込まない
  final String name;
  final StatsPeriod period;

  /// 人数（4 か 3）。null ならすべて
  final int? playerCount;
  final bool favoritesOnly;

  const HistoryFilter({
    this.name = '',
    this.period = StatsPeriod.all,
    this.playerCount,
    this.favoritesOnly = false,
  });

  /// 何か絞り込んでいるか
  bool get isActive => name.trim().isNotEmpty || period != StatsPeriod.all || playerCount != null || favoritesOnly;

  HistoryFilter copyWith({String? name, StatsPeriod? period, int? playerCount, bool clearPlayerCount = false, bool? favoritesOnly}) =>
      HistoryFilter(
        name: name ?? this.name,
        period: period ?? this.period,
        playerCount: clearPlayerCount ? null : (playerCount ?? this.playerCount),
        favoritesOnly: favoritesOnly ?? this.favoritesOnly,
      );

  bool matches(GameSession s, DateTime now) {
    if (favoritesOnly && !s.favorite) return false;
    if (playerCount != null && s.playerCount != playerCount) return false;
    final since = period.since(now);
    if (since != null && s.createdAt.isBefore(since)) return false;
    final q = name.trim().toLowerCase();
    if (q.isNotEmpty && !s.playerNames.any((n) => n.toLowerCase().contains(q))) return false;
    return true;
  }

  List<GameSession> apply(List<GameSession> sessions, DateTime now) =>
      [for (final s in sessions) if (matches(s, now)) s];
}

/// 戦績一覧
class HistoryListScreen extends ConsumerStatefulWidget {
  /// 絞り込みの基準の日時（テスト用。null なら今）
  final DateTime? now;

  const HistoryListScreen({super.key, this.now});

  @override
  ConsumerState<HistoryListScreen> createState() => _HistoryListScreenState();
}

class _HistoryListScreenState extends ConsumerState<HistoryListScreen> {
  HistoryFilter _filter = const HistoryFilter();
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String _date(DateTime d) =>
      '${d.year}/${d.month}/${d.day} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(sessionsProvider);
    final notifier = ref.read(sessionsProvider.notifier);
    final theme = Theme.of(context);
    final favCount = all.where((s) => s.favorite).length;
    final sessions = _filter.apply(all, widget.now ?? DateTime.now());
    final f = _filter;
    // 次に新しい対局を始めたときに削除される対局
    final nextRemoved = {for (final s in notifier.sessionsRemovedByNextCreate()) s.id};
    const max = SessionLogic.maxSavedSessions;

    return Scaffold(
      appBar: AppBar(
        title: const Text('戦績'),
        actions: [
          IconButton(
            tooltip: '個人成績',
            icon: const Icon(Icons.leaderboard_outlined),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const StatsScreen())),
          ),
          IconButton(
            tooltip: 'データの保存について',
            icon: const Icon(Icons.info_outline),
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const StorageInfoScreen())),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(8),
        children: [
          Card(
            color: theme.colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('保存中: ${all.length} / $max件（★お気に入り $favCount件）',
                      style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    '保存されるのは最新$max対局までです。それより多くなると、'
                    '新しい対局を始めたときに、お気に入り（★）にしていない一番古い対局から'
                    '自動で削除されます。対局中の対局は削除されません。',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (all.length > max)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'お気に入り・対局中の対局が多いため、$max件を超えて保存しています。',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.error),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: TextField(
              key: const ValueKey('history-name'),
              controller: _nameController,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                hintText: 'プレイヤーの名前で絞り込む',
                border: const OutlineInputBorder(),
                suffixIcon: f.name.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '名前の絞り込みを消す',
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() {
                          _nameController.clear();
                          _filter = f.copyWith(name: '');
                        }),
                      ),
              ),
              onChanged: (v) => setState(() => _filter = f.copyWith(name: v)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                FilterChip(
                  avatar: f.favoritesOnly ? null : const Icon(Icons.star, size: 18),
                  label: Text('お気に入り（$favCount）'),
                  selected: f.favoritesOnly,
                  onSelected: (v) => setState(() => _filter = f.copyWith(favoritesOnly: v)),
                ),
                for (final n in [4, 3])
                  FilterChip(
                    label: Text('$n人打ち'),
                    selected: f.playerCount == n,
                    onSelected: (v) => setState(
                        () => _filter = v ? f.copyWith(playerCount: n) : f.copyWith(clearPlayerCount: true)),
                  ),
                for (final p in StatsPeriod.values.where((p) => p != StatsPeriod.all))
                  FilterChip(
                    label: Text(p.label),
                    selected: f.period == p,
                    onSelected: (v) => setState(() => _filter = f.copyWith(period: v ? p : StatsPeriod.all)),
                  ),
              ],
            ),
          ),
          if (f.isActive)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text('${all.length}件中 ${sessions.length}件を表示', style: theme.textTheme.bodySmall),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _nameController.clear();
                      _filter = const HistoryFilter();
                    }),
                    child: const Text('絞り込みを解除'),
                  ),
                ],
              ),
            ),
          if (sessions.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                all.isEmpty
                    ? 'まだ対局がありません'
                    : f.favoritesOnly && favCount == 0
                        ? 'お気に入りの対局はありません。\n★ を押すとお気に入りにできます。'
                        : 'この条件に合う対局はありません',
                textAlign: TextAlign.center,
              ),
            ),
          for (final s in sessions)
            _SessionTile(
              session: s,
              dateText: _date(s.createdAt),
              willBeRemoved: nextRemoved.contains(s.id),
              onFavorite: () => notifier.toggleFavorite(s.id),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => HistoryDetailScreen(sessionId: s.id))),
            ),
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  final GameSession session;
  final String dateText;
  final bool willBeRemoved;
  final VoidCallback onFavorite;
  final VoidCallback onTap;

  const _SessionTile({
    required this.session,
    required this.dateText,
    required this.willBeRemoved,
    required this.onFavorite,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final s = session;
    final theme = Theme.of(context);
    final top = s.ranking.first;
    return Card(
      child: ListTile(
        leading: Icon(
          s.finished ? Icons.emoji_events : Icons.timelapse,
          color: s.finished ? Colors.amber.shade700 : null,
        ),
        title: Text(s.playerNames.join(' / ')),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$dateText  ${s.settings.isSanma ? "3人打ち " : ""}${s.settings.tonpuu ? "東風" : "半荘"}\n'
              '${s.finished ? "終局" : "対局中 ${s.roundLabel}"}  '
              'トップ: ${s.playerNames[top]} ${formatPoints(s.scores[top])}',
            ),
            if (willBeRemoved)
              Text('次に新しい対局を始めると削除されます',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error)),
          ],
        ),
        isThreeLine: true,
        trailing: IconButton(
          tooltip: s.favorite ? 'お気に入りを解除' : 'お気に入りにする',
          icon: Icon(
            s.favorite ? Icons.star : Icons.star_border,
            color: s.favorite ? Colors.amber.shade700 : null,
          ),
          onPressed: onFavorite,
        ),
        onTap: onTap,
      ),
    );
  }
}
