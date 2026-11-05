import 'package:flutter/material.dart';

import '../../../core/l10n.dart';
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
                child: Text(
                    tr('${session.isExtraRound ? "延長戦" : "オーラス"}の条件（トップになるには）を見る',
                        'What it takes to finish 1st (${session.isExtraRound ? "extension" : "last round"})'),
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
  String name(int p) => '${windName(s.seatWindIndexOf(p))} ${s.playerNames[p]}';
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
              Text(tr('トップになるのに必要な和了', 'Wins needed to take 1st'), style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                  tr('いまのトップ: ${name(top)}（${formatPoints(s.scores[top])}点）',
                      'Current leader: ${name(top)} (${formatPoints(s.scores[top])} pts)'),
                  style: theme.textTheme.bodyMedium),
              const SizedBox(height: 4),
              Text(
                tr(
                    'いちばん安い和了を表示します。本場（${s.honba}本場）と供託（${s.riichiSticks}本）を含めて計算し、'
                        '同点のときは起家に近い人を上位とします。流局のテンパイ料での逆転や、これから出す立直棒は含みません。',
                    'Shows the cheapest win. Includes honba (${s.honba}) and riichi sticks (${s.riichiSticks}); '
                        'ties go to the player closest to the first dealer. Excludes comebacks via noten payments and future riichi sticks.'),
                style: theme.textTheme.bodySmall,
              ),
              for (final c in conditions) ...[
                const Divider(height: 24),
                Text(
                    tr(
                        '${name(c.player)}（${formatPoints(s.scores[c.player])}点・'
                            'トップと${formatPoints(s.scores[top] - s.scores[c.player])}点差）',
                        '${name(c.player)} (${formatPoints(s.scores[c.player])} pts, '
                            '${formatPoints(s.scores[top] - s.scores[c.player])} behind)'),
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                _row(theme, c.ron, label: tr('ロン（トップ以外から）', 'Ron (not from leader)')),
                _row(theme, c.direct, label: tr('直撃（${s.playerNames[top]}から）', 'Direct hit (from ${s.playerNames[top]})')),
                _row(theme, c.tsumo, label: tr('ツモ', 'Tsumo')),
              ],
            ],
          ),
        ),
      );
    },
  );
}

Widget _row(ThemeData theme, WinCondition? c, {required String label}) {
  String score(WinCondition w) => w.score.replaceAll('オール', tr('オール', ' all'));
  var text = c != null
      ? tr('${c.handLabel}（${score(c)}）', '${c.handLabel} (${score(c)})')
      : tr('役満でも届かない', 'Not even with yakuman');
  final alt = c?.highFu;
  if (alt != null) {
    text += tr('\n符が高ければ ${alt.handLabel}（${score(alt)}）でも届く',
        '\nWith higher fu, ${alt.handLabel} (${score(alt)}) also works');
  }
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
