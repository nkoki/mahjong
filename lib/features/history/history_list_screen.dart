import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../session/domain/models.dart';
import '../session/domain/session_logic.dart';
import '../session/session_providers.dart';
import '../storage/storage_info_screen.dart';
import 'history_detail_screen.dart';

/// 戦績一覧
class HistoryListScreen extends ConsumerStatefulWidget {
  const HistoryListScreen({super.key});

  @override
  ConsumerState<HistoryListScreen> createState() => _HistoryListScreenState();
}

class _HistoryListScreenState extends ConsumerState<HistoryListScreen> {
  bool _favoritesOnly = false;

  String _date(DateTime d) =>
      '${d.year}/${d.month}/${d.day} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(sessionsProvider);
    final notifier = ref.read(sessionsProvider.notifier);
    final theme = Theme.of(context);
    final favCount = all.where((s) => s.favorite).length;
    final sessions = _favoritesOnly ? all.where((s) => s.favorite).toList() : all;
    // 次に新しい対局を始めたときに削除される対局
    final nextRemoved = {for (final s in notifier.sessionsRemovedByNextCreate()) s.id};
    const max = SessionLogic.maxSavedSessions;

    return Scaffold(
      appBar: AppBar(
        title: const Text('戦績'),
        actions: [
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
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: Text('すべて（${all.length}）'),
                  selected: !_favoritesOnly,
                  onSelected: (_) => setState(() => _favoritesOnly = false),
                ),
                ChoiceChip(
                  avatar: const Icon(Icons.star, size: 18),
                  label: Text('お気に入り（$favCount）'),
                  selected: _favoritesOnly,
                  onSelected: (_) => setState(() => _favoritesOnly = true),
                ),
              ],
            ),
          ),
          if (sessions.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                _favoritesOnly ? 'お気に入りの対局はありません。\n★ を押すとお気に入りにできます。' : 'まだ対局がありません',
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
