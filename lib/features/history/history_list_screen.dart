import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
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

  HistoryFilter copyWith(
          {String? name, StatsPeriod? period, int? playerCount, bool clearPlayerCount = false, bool? favoritesOnly}) =>
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

  List<GameSession> apply(List<GameSession> sessions, DateTime now) => [
        for (final s in sessions)
          if (matches(s, now)) s
      ];
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

  /// 選択モード（削除する対局を選ぶ）。null なら通常の表示
  Set<String>? _selected;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String _date(DateTime d) => '${d.year}/${d.month}/${d.day} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';

  /// 選択モードで対局の選択を切り替える（続けてタップしても最新の選択から切り替える）
  void _toggleSelected(String id) {
    final cur = _selected;
    if (cur == null) return;
    _selected = cur.contains(id) ? ({...cur}..remove(id)) : {...cur, id};
  }

  /// 選択した対局を削除する（お気に入りを含むときは警告してから）
  Future<void> _deleteSelected(List<GameSession> visible) async {
    final targets = [
      for (final s in visible)
        if (_selected!.contains(s.id)) s
    ];
    if (targets.isEmpty) return;
    final favs = targets.where((s) => s.favorite).length;
    final playing = targets.where((s) => !s.finished).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: favs > 0 ? Icon(Icons.warning_amber_rounded, color: Theme.of(ctx).colorScheme.error) : null,
        title: Text(favs > 0
            ? tr('お気に入りが含まれています', 'Favorites are included')
            : tr('${targets.length}件の対局を削除', 'Delete ${targets.length} games')),
        content: Text([
          if (favs > 0)
            tr('選択した${targets.length}件のうち、お気に入り（★）の対局が$favs件含まれています。お気に入りも含めて削除しますか？',
                '$favs of the ${targets.length} selected games are favorites (★). Delete them including the favorites?')
          else
            tr('選択した${targets.length}件の対局を削除しますか？', 'Delete the ${targets.length} selected games?'),
          if (playing > 0) tr('対局中の対局（$playing件）も削除されます。', '$playing games in progress will also be deleted.'),
          tr('削除した対局は元に戻せません。個人成績からも消えます。', 'Deleted games cannot be restored and are removed from player stats.'),
        ].join('\n')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('キャンセル', 'Cancel'))),
          FilledButton(
            key: const ValueKey('confirm-delete-selected'),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(favs > 0 ? tr('お気に入りも含めて削除', 'Delete including favorites') : tr('削除', 'Delete')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final n = ref.read(sessionsProvider.notifier).deleteMany({for (final s in targets) s.id});
    setState(() => _selected = null);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('$n件の対局を削除しました', 'Deleted $n games'))));
  }

  /// お気に入り以外をすべて削除する
  Future<void> _deleteAllExceptFavorites(List<GameSession> all) async {
    final targets = all.where((s) => !s.favorite).toList();
    final messenger = ScaffoldMessenger.of(context);
    if (targets.isEmpty) {
      messenger
          .showSnackBar(SnackBar(content: Text(tr('お気に入り以外の対局はありません', 'There are no games other than favorites'))));
      return;
    }
    final favs = all.length - targets.length;
    final playing = targets.where((s) => !s.finished).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('お気に入り以外をすべて削除', 'Delete all except favorites')),
        content: Text([
          tr('お気に入り（★）以外の${targets.length}件の対局をすべて削除しますか？',
              'Delete all ${targets.length} games that are not favorites (★)?'),
          if (favs > 0) tr('お気に入りの$favs件は残ります。', 'The $favs favorite games are kept.'),
          if (playing > 0) tr('対局中の対局（$playing件）も削除されます。', '$playing games in progress will also be deleted.'),
          tr('削除した対局は元に戻せません。個人成績からも消えます。', 'Deleted games cannot be restored and are removed from player stats.'),
        ].join('\n')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('キャンセル', 'Cancel'))),
          FilledButton(
            key: const ValueKey('confirm-delete-all'),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('削除', 'Delete')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final n = ref.read(sessionsProvider.notifier).deleteAllExceptFavorites();
    setState(() => _selected = null);
    messenger.showSnackBar(SnackBar(content: Text(tr('$n件の対局を削除しました', 'Deleted $n games'))));
  }

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
    final selected = _selected;
    final selectedVisible = selected == null ? 0 : sessions.where((s) => selected.contains(s.id)).length;
    final allVisibleSelected = sessions.isNotEmpty && selectedVisible == sessions.length;

    return Scaffold(
      appBar: selected != null
          ? AppBar(
              leading: IconButton(
                key: const ValueKey('selection-close'),
                tooltip: tr('選択をやめる', 'Cancel selection'),
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _selected = null),
              ),
              title: Text(tr('$selectedVisible件を選択', '$selectedVisible selected')),
              actions: [
                IconButton(
                  key: const ValueKey('select-all'),
                  tooltip: allVisibleSelected ? tr('すべての選択を外す', 'Deselect all') : tr('表示中をすべて選択', 'Select all shown'),
                  icon: Icon(allVisibleSelected ? Icons.deselect : Icons.select_all),
                  onPressed: () => setState(() =>
                      _selected = allVisibleSelected ? <String>{} : {...selected, for (final s in sessions) s.id}),
                ),
                IconButton(
                  key: const ValueKey('delete-selected'),
                  tooltip: tr('選択した対局を削除', 'Delete selected games'),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: selectedVisible == 0 ? null : () => _deleteSelected(sessions),
                ),
              ],
            )
          : AppBar(
              title: Text(tr('戦績', 'History')),
              actions: [
                IconButton(
                  tooltip: tr('個人成績', 'Player stats'),
                  icon: const Icon(Icons.leaderboard_outlined),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StatsScreen())),
                ),
                IconButton(
                  tooltip: tr('データの保存について', 'About data storage'),
                  icon: const Icon(Icons.info_outline),
                  onPressed: () =>
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StorageInfoScreen())),
                ),
                PopupMenuButton<String>(
                  key: const ValueKey('history-menu'),
                  tooltip: tr('その他', 'More'),
                  onSelected: (v) {
                    if (v == 'select') setState(() => _selected = <String>{});
                    if (v == 'delete-all') _deleteAllExceptFavorites(all);
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'select',
                      enabled: all.isNotEmpty,
                      child: ListTile(
                        leading: const Icon(Icons.checklist),
                        title: Text(tr('選択して削除', 'Select and delete')),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete-all',
                      enabled: all.isNotEmpty,
                      child: ListTile(
                        leading: const Icon(Icons.delete_sweep_outlined),
                        title: Text(tr('お気に入り以外をすべて削除', 'Delete all except favorites')),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
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
                  Text(
                      tr('保存中: ${all.length} / $max件（★お気に入り $favCount件）',
                          'Saved: ${all.length} / $max (★ favorites: $favCount)'),
                      style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    tr(
                        '保存されるのは最新$max対局までです。それより多くなると、'
                            '新しい対局を始めたときに、お気に入り（★）にしていない一番古い対局から'
                            '自動で削除されます。対局中の対局は削除されません。',
                        'Only the latest $max games are kept. Beyond that, starting a new game '
                            'automatically deletes the oldest game that is not a favorite (★). '
                            'Games in progress are never deleted.'),
                    style: theme.textTheme.bodySmall,
                  ),
                  if (all.length > max)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        tr('お気に入り・対局中の対局が多いため、$max件を超えて保存しています。',
                            'More than $max games are saved because of many favorites / games in progress.'),
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
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
                hintText: tr('プレイヤーの名前で絞り込む', 'Filter by player name'),
                border: const OutlineInputBorder(),
                suffixIcon: f.name.isEmpty
                    ? null
                    : IconButton(
                        tooltip: tr('名前の絞り込みを消す', 'Clear name filter'),
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
                  label: Text(tr('お気に入り（$favCount）', 'Favorites ($favCount)')),
                  selected: f.favoritesOnly,
                  onSelected: (v) => setState(() => _filter = f.copyWith(favoritesOnly: v)),
                ),
                for (final n in [4, 3])
                  FilterChip(
                    label: Text(tr('$n人打ち', '$n-player')),
                    selected: f.playerCount == n,
                    onSelected: (v) =>
                        setState(() => _filter = v ? f.copyWith(playerCount: n) : f.copyWith(clearPlayerCount: true)),
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
                    child: Text(
                        tr('${all.length}件中 ${sessions.length}件を表示', 'Showing ${sessions.length} of ${all.length}'),
                        style: theme.textTheme.bodySmall),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _nameController.clear();
                      _filter = const HistoryFilter();
                    }),
                    child: Text(tr('絞り込みを解除', 'Clear filters')),
                  ),
                ],
              ),
            ),
          if (sessions.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                all.isEmpty
                    ? tr('まだ対局がありません', 'No games yet')
                    : f.favoritesOnly && favCount == 0
                        ? tr('お気に入りの対局はありません。\n★ を押すとお気に入りにできます。', 'No favorite games.\nTap ★ to add a favorite.')
                        : tr('この条件に合う対局はありません', 'No games match these filters'),
                textAlign: TextAlign.center,
              ),
            ),
          if (selected != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                  tr('削除する対局をタップして選びます。お気に入り（★）を選んだときは、削除の前に確認します。',
                      'Tap games to select them for deletion. You will be asked to confirm if favorites (★) are selected.'),
                  style: theme.textTheme.bodySmall),
            ),
          for (final s in sessions)
            _SessionTile(
              session: s,
              dateText: _date(s.createdAt),
              willBeRemoved: nextRemoved.contains(s.id),
              selected: selected?.contains(s.id),
              onFavorite: () => notifier.toggleFavorite(s.id),
              onTap: selected != null
                  ? () => setState(() => _toggleSelected(s.id))
                  : () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => HistoryDetailScreen(sessionId: s.id))),
              onLongPress: selected == null ? () => setState(() => _selected = {s.id}) : null,
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

  /// 選択モードのときの選択状態（null なら選択モードではない）
  final bool? selected;
  final VoidCallback onFavorite;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _SessionTile({
    required this.session,
    required this.dateText,
    required this.willBeRemoved,
    required this.selected,
    required this.onFavorite,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final s = session;
    final theme = Theme.of(context);
    final top = s.ranking.first;
    final sel = selected;
    return Card(
      child: ListTile(
        key: ValueKey('session-${s.id}'),
        selected: sel ?? false,
        leading: sel != null
            ? Checkbox(key: ValueKey('select-${s.id}'), value: sel, onChanged: (_) => onTap())
            : Icon(
                s.finished ? Icons.emoji_events : Icons.timelapse,
                color: s.finished ? const Color(0xFFB8860B) : null,
              ),
        title: Text(s.playerNames.join(' / ')),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(
                  '$dateText  ${s.settings.isSanma ? "3人打ち " : ""}${s.settings.length.shortLabel}\n'
                      '${s.finished ? "終局" : "対局中 ${s.roundLabel}"}  '
                      'トップ: ${s.playerNames[top]} ${formatPoints(s.scores[top])}',
                  '$dateText  ${s.settings.isSanma ? "3-player " : ""}${s.settings.length.label}\n'
                      '${s.finished ? "Finished" : "In progress ${displayRoundLabel(s.roundLabel)}"}  '
                      'Top: ${s.playerNames[top]} ${formatPoints(s.scores[top])}'),
            ),
            if (willBeRemoved)
              Text(tr('次に新しい対局を始めると削除されます', 'Will be deleted when the next game starts'),
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
          ],
        ),
        isThreeLine: true,
        trailing: sel != null
            ? (s.favorite ? const Icon(Icons.star, color: Color(0xFFB8860B)) : null)
            : IconButton(
                tooltip: s.favorite ? tr('お気に入りを解除', 'Remove from favorites') : tr('お気に入りにする', 'Add to favorites'),
                icon: Icon(
                  s.favorite ? Icons.star : Icons.star_border,
                  color: s.favorite ? const Color(0xFFB8860B) : null,
                ),
                onPressed: onFavorite,
              ),
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );
  }
}
