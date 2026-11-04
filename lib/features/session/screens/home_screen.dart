import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/routes.dart';
import '../../../core/theme.dart';
import '../../history/history_list_screen.dart';
import '../session_providers.dart';
import 'new_session_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ongoing =
        ref.watch(sessionsProvider).where((s) => !s.finished).toList();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('麻雀点数計算')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 16),
          Icon(Icons.grid_view_rounded, size: 72, color: theme.colorScheme.primary),
          const SizedBox(height: 8),
          Text('4人打ち 点数計算・対局管理',
              textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
          const SizedBox(height: 32),
          FilledButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: const Text('新規対局'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NewSessionScreen()),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
            icon: const Icon(Icons.history),
            label: const Text('戦績'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HistoryListScreen()),
            ),
          ),
          if (ongoing.isNotEmpty) ...[
            const SizedBox(height: 32),
            Text('対局中（続きから）', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final s in ongoing)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.casino_outlined),
                  title: Text(s.playerNames.join(' / ')),
                  subtitle: Text(
                      '${s.roundLabel}  供託${s.riichiSticks}本\n'
                      '${[for (var i = 0; i < 4; i++) formatPoints(s.scores[i])].join(' / ')}'),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(dashboardRoute(s.id)),
                ),
              ),
          ],
          const SizedBox(height: 24),
          Text(
            '※ 対局データはこの端末に自動で保存されます',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
