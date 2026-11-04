import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../session/session_providers.dart';
import 'history_detail_screen.dart';

/// 戦績一覧
class HistoryListScreen extends ConsumerWidget {
  const HistoryListScreen({super.key});

  String _date(DateTime d) =>
      '${d.year}/${d.month}/${d.day} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sessionsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('戦績')),
      body: sessions.isEmpty
          ? const Center(child: Text('まだ対局がありません'))
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: sessions.length,
              itemBuilder: (context, i) {
                final s = sessions[i];
                final top = s.ranking.first;
                return Card(
                  child: ListTile(
                    leading: Icon(
                      s.finished ? Icons.emoji_events : Icons.timelapse,
                      color: s.finished ? Colors.amber.shade700 : null,
                    ),
                    title: Text(s.playerNames.join(' / ')),
                    subtitle: Text(
                      '${_date(s.createdAt)}  ${s.settings.tonpuu ? "東風" : "半荘"}\n'
                      '${s.finished ? "終局" : "対局中 ${s.roundLabel}"}  '
                      'トップ: ${s.playerNames[top]} ${formatPoints(s.scores[top])}',
                    ),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => HistoryDetailScreen(sessionId: s.id))),
                  ),
                );
              },
            ),
    );
  }
}
