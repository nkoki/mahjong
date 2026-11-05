import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mahjong_score_engine/mahjong_score_engine.dart';

import '../../core/l10n.dart';
import '../session/domain/session_logic.dart' show HanFuEntry;
import '../session/session_providers.dart';

/// 点数早見表の1マス
class ScoreTableCell {
  /// ロンの点数（例: 3900）。この組み合わせでロンできなければ null
  final String? ron;

  /// ツモの点数（例: 1000-2000、1300オール）。ツモできなければ null
  final String? tsumo;

  /// 満貫などの名前（満貫未満なら null）
  final String? limitName;

  const ScoreTableCell({this.ron, this.tsumo, this.limitName});
}

/// 点数早見表（UI に依存しない）
class ScoreTable {
  ScoreTable._();

  /// 表の行（符）と列（翻）
  static const fus = ScoreCalculator.hanFuChoices;
  static const hans = [1, 2, 3, 4];

  /// 満貫以上の行（名前, 翻の目安, 計算に使う手）
  static const limits = [
    ('満貫', '5翻', HanFuEntry(han: 5)),
    ('跳満', '6・7翻', HanFuEntry(han: 6)),
    ('倍満', '8〜10翻', HanFuEntry(han: 8)),
    ('三倍満', '11・12翻', HanFuEntry(han: 11)),
    ('役満', '', HanFuEntry(yakuman: 1)),
  ];

  static ScoreTableCell cell({
    required int han,
    required int fu,
    int yakuman = 0,
    required bool isDealer,
    required ScoreRules rules,
  }) {
    ScoreResult calc(bool tsumo) => ScoreCalculator.calculateFromHanFu(
        han: han, fu: fu, yakuman: yakuman, isTsumo: tsumo, playerWind: isDealer ? '1z' : '2z', rules: rules);
    final ron = calc(false), tsumo = calc(true);
    return ScoreTableCell(
      ron: ron.isValid ? ScoreCalculator.formatScore(ron, isDealer: isDealer, isTsumo: false) : null,
      tsumo: tsumo.isValid ? ScoreCalculator.formatScore(tsumo, isDealer: isDealer, isTsumo: true) : null,
      limitName: ron.isValid ? ron.limitName : (tsumo.isValid ? tsumo.limitName : null),
    );
  }
}

/// 点数早見表の画面
class ScoreTableScreen extends ConsumerStatefulWidget {
  const ScoreTableScreen({super.key});

  @override
  ConsumerState<ScoreTableScreen> createState() => _ScoreTableScreenState();
}

class _ScoreTableScreenState extends ConsumerState<ScoreTableScreen> {
  bool _dealer = false;
  int _players = 4;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(defaultSettingsProviderFor(_players));
    final rules = settings.scoreRules;
    final small = theme.textTheme.bodySmall;
    final border = BorderSide(color: theme.colorScheme.outlineVariant);

    Widget head(String text) => Padding(
          padding: const EdgeInsets.all(6),
          child: Text(text, textAlign: TextAlign.center, style: theme.textTheme.labelLarge),
        );

    Widget body(ScoreTableCell c) {
      if (c.ron == null && c.tsumo == null) {
        return Padding(
            padding: const EdgeInsets.all(6),
            child: Text('—', textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.outline)));
      }
      return Container(
        color: c.limitName != null ? theme.colorScheme.tertiaryContainer.withAlpha(120) : null,
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: Column(
          children: [
            Text(_score(c.ron), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
            Text(_score(c.tsumo), style: small),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(tr('点数早見表', 'Score table'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: false, label: Text(tr('子', 'Non-dealer'))),
                  ButtonSegment(value: true, label: Text(tr('親', 'Dealer'))),
                ],
                selected: {_dealer},
                onSelectionChanged: (v) => setState(() => _dealer = v.first),
              ),
              SegmentedButton<int>(
                segments: [
                  ButtonSegment(value: 4, label: Text(tr('4人打ち', '4-player'))),
                  ButtonSegment(value: 3, label: Text(tr('3人打ち', '3-player'))),
                ],
                selected: {_players},
                onSelectionChanged: (v) => setState(() => _players = v.first),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            tr(
              '上の数字がロン、下の数字がツモ（${_dealer ? "全員が払う額" : "子-親が払う額"}）です。本場・供託は含みません。'
                  '色の付いたマスは満貫です。ルール設定（${_players == 3 ? "3人打ち" : "4人打ち"}）の'
                  '「切り上げ満貫${settings.kiriageMangan ? "あり" : "なし"}」'
                  '${_players == 3 ? "・${settings.sanmaTsumoSplit ? "ツモ折半" : "ツモ損"}" : ""}で計算しています。'
                  '20符はツモ（平和ツモ）だけ、25符（七対子）は2翻からです。',
              'Top: ron. Bottom: tsumo (${_dealer ? "paid by each player" : "non-dealer-dealer payments"}). '
                  'Honba and riichi deposits are not included. Shaded cells are mangan. '
                  'Calculated with the rule settings (${_players == 3 ? "3-player" : "4-player"}): '
                  'rounded-up mangan ${settings.kiriageMangan ? "on" : "off"}'
                  '${_players == 3 ? ", ${settings.sanmaTsumoSplit ? "tsumo split" : "tsumo loss"}" : ""}. '
                  '20 fu is tsumo only (pinfu tsumo); 25 fu (chiitoitsu) starts at 2 han.',
            ),
            style: small,
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 32),
              child: Table(
                key: const ValueKey('score-table'),
                defaultColumnWidth: const IntrinsicColumnWidth(),
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                border: TableBorder(horizontalInside: border, verticalInside: border, top: border, bottom: border),
                children: [
                  TableRow(children: [head(tr('符＼翻', 'Fu / Han')), for (final h in ScoreTable.hans) head(tr('$h翻', '$h han'))]),
                  for (final fu in ScoreTable.fus)
                    TableRow(children: [
                      head(tr('$fu符', '$fu fu')),
                      for (final h in ScoreTable.hans)
                        body(ScoreTable.cell(han: h, fu: fu, isDealer: _dealer, rules: rules)),
                    ]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(tr('満貫以上', 'Mangan and above'), style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Table(
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            columnWidths: const {0: IntrinsicColumnWidth()},
            border: TableBorder(horizontalInside: border, top: border, bottom: border),
            children: [
              TableRow(children: [head(''), head(tr('ロン', 'Ron')), head(tr('ツモ', 'Tsumo'))]),
              for (final (name, hint, hand) in ScoreTable.limits)
                () {
                  final c = ScoreTable.cell(
                      han: hand.han, fu: 30, yakuman: hand.yakuman, isDealer: _dealer, rules: rules);
                  return TableRow(children: [
                    Padding(
                      padding: const EdgeInsets.all(6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(limitName(name), style: theme.textTheme.labelLarge),
                          if (hint.isNotEmpty) Text(_hint(hint), style: small),
                        ],
                      ),
                    ),
                    Text(_score(c.ron),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                    Text(_score(c.tsumo), textAlign: TextAlign.center),
                  ]);
                }(),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            tr('数え役満（13翻以上）は「数え役満${settings.kazoeYakuman ? "あり" : "なし（三倍満止まり）"}」の設定に従います。',
                'Kazoe yakuman (13+ han) follows the setting: ${settings.kazoeYakuman ? "on" : "off (capped at sanbaiman)"}.'),
            style: small,
          ),
        ],
      ),
    );
  }
}

/// 点数の表示（英語では「オール」を all にする）。無ければ —
String _score(String? s) => s == null ? '—' : tr(s, s.replaceAll('オール', ' all'));

/// 翻の目安の表示（例: 6・7翻 → 6/7 han）
String _hint(String s) => tr(s, s.replaceAll('翻', ' han').replaceAll('・', '/').replaceAll('〜', '-'));
