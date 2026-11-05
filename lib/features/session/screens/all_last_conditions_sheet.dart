import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../domain/all_last_conditions.dart';
import '../domain/models.dart';

/// オーラス（延長戦）のときに対局画面に出す帯。押すと条件の一覧を開く
class AllLastConditionsBar extends StatelessWidget {
  final GameSession session;
  const AllLastConditionsBar({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.secondaryContainer,
      child: InkWell(
        key: const ValueKey('all-last-conditions'),
        onTap: () => showAllLastConditions(context, session),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.flag_outlined, size: 18, color: theme.colorScheme.onSecondaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${session.isExtraRound ? "延長戦" : "オーラス"}の条件（トップになるには）を見る',
                    style: TextStyle(color: theme.colorScheme.onSecondaryContainer, fontSize: 13)),
              ),
              Icon(Icons.chevron_right, size: 18, color: theme.colorScheme.onSecondaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}

/// 条件の一覧（ボトムシート）
Future<void> showAllLastConditions(BuildContext context, GameSession s) {
  final conditions = AllLastConditions.compute(s);
  final top = s.ranking.first;
  String name(int p) => '${GameSession.windNames[s.seatWindIndexOf(p)]} ${s.playerNames[p]}';
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Text('トップになるのに必要な和了', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text('いまのトップ: ${name(top)}（${formatPoints(s.scores[top])}点）', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 4),
              Text(
                'いちばん安い和了を表示します。本場（${s.honba}本場）と供託（${s.riichiSticks}本）を含めて計算し、'
                '同点のときは起家に近い人を上位とします。流局のテンパイ料での逆転や、これから出す立直棒は含みません。',
                style: theme.textTheme.bodySmall,
              ),
              for (final c in conditions) ...[
                const Divider(height: 24),
                Text('${name(c.player)}（${formatPoints(s.scores[c.player])}点・'
                    'トップと${formatPoints(s.scores[top] - s.scores[c.player])}点差）',
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                _row(theme, c.ron, label: 'ロン（トップ以外から）'),
                _row(theme, c.direct, label: '直撃（${s.playerNames[top]}から）'),
                _row(theme, c.tsumo, label: 'ツモ'),
              ],
            ],
          ),
        ),
      );
    },
  );
}

Widget _row(ThemeData theme, WinCondition? c, {required String label}) {
  var text = c != null ? '${c.handLabel}（${c.score}）' : '役満でも届かない';
  final alt = c?.highFu;
  if (alt != null) text += '\n符が高ければ ${alt.handLabel}（${alt.score}）でも届く';
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 150, child: Text(label, style: theme.textTheme.bodyMedium)),
        Expanded(
          child: Text(text,
              style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: c != null ? FontWeight.bold : null, color: c == null ? theme.colorScheme.outline : null)),
        ),
      ],
    ),
  );
}
