import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../session/domain/models.dart';
import 'result_text.dart';
import 'score_chart.dart';

/// 画像を OS の共有画面で送る（テストでは差し替える）
abstract class ImageSharer {
  Future<void> share(Uint8List png, {required String fileName, required String title});
}

class SharePlusImageSharer implements ImageSharer {
  const SharePlusImageSharer();

  @override
  Future<void> share(Uint8List png, {required String fileName, required String title}) async {
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(png, mimeType: 'image/png', name: fileName)],
      fileNameOverrides: [fileName],
      title: title,
      // Web で共有の機能が無いブラウザは、画像をダウンロードする
      downloadFallbackEnabled: true,
    ));
  }
}

final imageSharerProvider = Provider<ImageSharer>((ref) => const SharePlusImageSharer());

/// 共有する画像のファイル名（例: mahjong_20260601_1230.png）
String resultImageFileName(GameSession s) {
  final d = s.createdAt;
  String two(int v) => v.toString().padLeft(2, '0');
  return 'mahjong_${d.year}${two(d.month)}${two(d.day)}_${two(d.hour)}${two(d.minute)}.png';
}

/// 結果を画像にする前の確認（プレビューと共有ボタン）
Future<void> showResultImage(BuildContext context, GameSession s) => showDialog<void>(
      context: context,
      builder: (_) => _ResultImageDialog(session: s),
    );

class _ResultImageDialog extends ConsumerStatefulWidget {
  final GameSession session;
  const _ResultImageDialog({required this.session});

  @override
  ConsumerState<_ResultImageDialog> createState() => _ResultImageDialogState();
}

class _ResultImageDialogState extends ConsumerState<_ResultImageDialog> {
  final _key = GlobalKey();
  bool _busy = false;

  Future<Uint8List> _capture() async {
    final boundary = _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  Future<void> _share() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final png = await _capture();
      await ref.read(imageSharerProvider).share(png,
          fileName: resultImageFileName(widget.session), title: tr('麻雀の対局結果', 'Mahjong game result'));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text(tr('画像を共有できませんでした（$e）。「結果をコピー」でテキストを送れます',
              'Could not share the image ($e). You can send text with "Copy result"'))));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('結果を画像で共有', 'Share result as image')),
      contentPadding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              child: RepaintBoundary(key: _key, child: ResultCard(session: widget.session)),
            ),
            const SizedBox(height: 8),
            Text(
                tr('この画像を、LINE などのアプリを選んで送れます（送り先は自分で選びます）。',
                    'You can send this image via an app such as LINE (you choose the recipient).'),
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('閉じる', 'Close'))),
        FilledButton.icon(
          key: const ValueKey('share-image'),
          icon: const Icon(Icons.share),
          label: Text(tr('共有', 'Share')),
          onPressed: _busy ? null : _share,
        ),
      ],
    );
  }
}

/// 画像にする結果のカード（端末の明るさの設定に関係なく、いつも明るい表示）
class ResultCard extends StatelessWidget {
  final GameSession session;
  const ResultCard({super.key, required this.session});

  static const width = 360.0;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final d = s.createdAt;
    return Theme(
      data: AppTheme.light(),
      child: Builder(builder: (context) {
        final theme = Theme.of(context);
        final chips = s.chipTotals;
        return Material(
          color: theme.colorScheme.surface,
          child: SizedBox(
            width: width,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  color: AppTheme.tableGreen,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          s.finished
                              ? tr('対局結果', 'Game result')
                              : tr('対局中（${s.roundLabel}）の順位', 'Standings (${displayRoundLabel(s.roundLabel)})'),
                          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                      Text(
                        tr(
                            '${d.year}/${d.month}/${d.day}  ${s.settings.isSanma ? "3人打ち " : ""}'
                                '${s.settings.length.label}・${s.records.length}局',
                            '${d.year}/${d.month}/${d.day}  ${s.settings.isSanma ? "3-player " : ""}'
                                '${s.settings.length.label} · ${s.records.length} rounds'),
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                for (final r in s.finalResults)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant)),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: r.rank == 1 ? AppTheme.vermilion : theme.colorScheme.secondaryContainer,
                          foregroundColor: r.rank == 1 ? Colors.white : null,
                          child: Text('${r.rank}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.playerNames[r.player],
                                  overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
                              Text(
                                tr(
                                    '${formatPoints(r.score)}点'
                                        '${s.settings.chips ? '  祝儀 ${chips[r.player] > 0 ? "+" : ""}${chips[r.player]}枚' : ''}'
                                        '${r.adjustment != 0 ? '  焼き鳥・トビ賞 ${formatPoint(r.adjustment)}' : ''}',
                                    '${formatPoints(r.score)} pts'
                                        '${s.settings.chips ? '  Chips ${chips[r.player] > 0 ? "+" : ""}${chips[r.player]}' : ''}'
                                        '${r.adjustment != 0 ? '  Yakitori/bust bonus ${formatPoint(r.adjustment)}' : ''}'),
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        if (s.finished)
                          Text(formatPoint(r.point),
                              style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold, color: deltaColor(context, r.point))),
                      ],
                    ),
                  ),
                if (s.records.isNotEmpty)
                  Padding(padding: const EdgeInsets.fromLTRB(8, 12, 12, 4), child: ScoreChart(session: s)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                  child: Text(
                    tr('ウマ ${s.settings.umaLabel}・返し ${formatPoints(s.settings.returnPoints)}点',
                        'Uma ${s.settings.umaLabel} · Return ${formatPoints(s.settings.returnPoints)} pts'),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

/// テキストのコピーと画像の共有を選ぶメニュー
Future<void> showShareMenu(BuildContext context, GameSession s) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: Text(tr('画像で共有', 'Share as image')),
              subtitle: Text(tr('順位・点数・点数の推移のグラフを画像にして送る', 'Send ranks, scores and the score chart as an image')),
              onTap: () {
                Navigator.pop(ctx);
                showResultImage(context, s);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_all_outlined),
              title: Text(tr('テキストでコピー', 'Copy as text')),
              subtitle: Text(tr('LINE などに貼り付けて送る', 'Paste into LINE or other chat apps')),
              onTap: () {
                Navigator.pop(ctx);
                ResultText.copy(context, s);
              },
            ),
          ],
        ),
      ),
    );
