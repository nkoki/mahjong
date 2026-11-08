import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/l10n.dart';
import '../../../core/theme.dart';
import '../domain/models.dart';

/// 対局画面の「卓ビュー」（グラフィカルなレイアウト）。
///
/// 卓を真上から見た形で、4人（3人）を実際の席の位置に置く。起家（最初の親）がいちばん下で、
/// 打つ順番（反時計回り）に右・上・左と並ぶ。3人打ちは北家の席（左）が空く。
/// 真ん中の表示窓に局・本場・供託を出し、立直した人の前には千点棒を置く。席を押すと立直・取り消し。
class MahjongTableView extends StatelessWidget {
  final GameSession session;
  final void Function(int player) onRiichi;

  const MahjongTableView({super.key, required this.session, required this.onRiichi});

  /// 席の位置（0=下, 1=右, 2=上, 3=左）。起家が下で、打つ順番に反時計回り
  static int positionOf(GameSession s, int player) => player % s.playerCount;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final rank = s.ranking;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth, h = c.maxHeight;
        // 真ん中の表示窓のまわりに、十字の形に席を寄せて置く（縦長の画面でも端に離れすぎないように）
        final centerSize = math.max(92.0, math.min(math.min(w * 0.27, h * 0.22), 170.0));
        final sideW = math.max(80.0, math.min((w - centerSize) / 2 - 8, 190.0));
        final vertW = math.min(w * 0.62, 280.0);
        final seatH = math.max(96.0, math.min((h - centerSize) / 2 - 22, 160.0));
        // 文字の大きさは4人とも同じにする（いちばん狭い左右の席に合わせて、1つの倍率を決める）
        final scale = math.min((sideW - 10) / 104, (seatH - 24) / 96).clamp(0.62, 1.5).toDouble();
        final cx = w / 2, cy = h / 2;
        final gap = math.min(16.0, (h - centerSize - seatH * 2) / 4).clamp(4.0, 16.0);
        Widget seat(int p) => _Seat(
              key: ValueKey('seat-$p'),
              scale: scale,
              name: s.playerNames[p],
              wind: windName(s.seatWindIndexOf(p)),
              isDealer: s.dealer == p,
              score: s.scores[p],
              rank: rank.indexOf(p) + 1,
              riichi: s.riichi[p],
              onTap: (s.riichi[p] || s.scores[p] >= 1000) ? () => onRiichi(p) : null,
            );
        final seats = <Widget>[];
        for (var p = 0; p < s.playerCount; p++) {
          final pos = positionOf(s, p);
          seats.add(switch (pos) {
            0 => Positioned(left: cx - vertW / 2, top: cy + centerSize / 2 + gap, width: vertW, height: seatH, child: seat(p)),
            1 => Positioned(left: cx + centerSize / 2 + 2, top: cy - seatH / 2, width: sideW, height: seatH, child: seat(p)),
            2 => Positioned(left: cx - vertW / 2, top: cy - centerSize / 2 - gap - seatH, width: vertW, height: seatH, child: seat(p)),
            _ => Positioned(left: cx - centerSize / 2 - 2 - sideW, top: cy - seatH / 2, width: sideW, height: seatH, child: seat(p)),
          });
        }
        // 席のまわりに余白があれば、卓の縁にその人の手牌（裏向き13枚）を並べる
        final hands = <(Rect, bool)>[];
        final tileLong = math.min(22.0, (w - 60) / 13 / 0.74);
        final tileShort = tileLong * 0.74;
        final rowLen = tileShort * 13;
        for (var p = 0; p < s.playerCount; p++) {
          final pos = positionOf(s, p);
          if (pos == 0) {
            final top = h - 18 - tileLong;
            if (top > cy + centerSize / 2 + gap + seatH + 6) {
              hands.add((Rect.fromLTWH(cx - rowLen / 2, top, rowLen, tileLong), true));
            }
          } else if (pos == 2) {
            const top = 18.0;
            if (top + tileLong + 6 < cy - centerSize / 2 - gap - seatH) {
              hands.add((Rect.fromLTWH(cx - rowLen / 2, top, rowLen, tileLong), true));
            }
          } else {
            final left = pos == 1 ? w - 18 - tileLong : 18.0;
            final seatLeft = pos == 1 ? cx + centerSize / 2 + 2 : cx - centerSize / 2 - 2 - sideW;
            final clear = pos == 1 ? left > seatLeft + sideW + 6 : left + tileLong + 6 < seatLeft;
            if (clear && rowLen < h - 40) {
              hands.add((Rect.fromLTWH(left, cy - rowLen / 2, tileLong, rowLen), false));
            }
          }
        }
        return CustomPaint(
          painter: _TablePainter(hands),
          child: Stack(
            children: [
              Positioned(
                left: cx - centerSize / 2,
                top: cy - centerSize / 2,
                width: centerSize,
                height: centerSize,
                child: _CenterPanel(session: s),
              ),
              ...seats,
            ],
          ),
        );
      }),
    );
  }
}

/// 卓（木の縁と、細かい目の緑の布）
class _TablePainter extends CustomPainter {
  /// 手牌を並べる場所（横に並べるなら true）
  final List<(Rect, bool)> hands;
  const _TablePainter(this.hands);

  @override
  void paint(Canvas canvas, Size size) {
    final outer = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16));
    canvas.drawRRect(
      outer,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6E4B2A), Color(0xFF4A3019)],
        ).createShader(Offset.zero & size),
    );
    final inner = outer.deflate(8);
    canvas.drawRRect(inner, Paint()..color = AppTheme.tableGreen);
    // 布の目（毎回同じになるよう乱数の種は固定）
    canvas.save();
    canvas.clipRRect(inner);
    final rnd = math.Random(3);
    final light = Paint()..color = const Color(0x0DFFFFFF);
    final dark = Paint()..color = const Color(0x12000000);
    final n = (size.width * size.height / 90).clamp(500, 6000).toInt();
    for (var i = 0; i < n; i++) {
      final o = Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height);
      canvas.drawCircle(o, 0.8, i.isEven ? light : dark);
    }
    // 内側の影（縁の段差）
    canvas.drawRRect(
      inner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = const Color(0x33000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    // 手牌（裏向き）: 緑の背に、象牙色の面の縁が少し見える
    for (final (rect, horizontal) in hands) {
      const n = 13;
      for (var i = 0; i < n; i++) {
        final r = horizontal
            ? Rect.fromLTWH(rect.left + rect.width / n * i, rect.top, rect.width / n - 1, rect.height)
            : Rect.fromLTWH(rect.left, rect.top + rect.height / n * i, rect.width, rect.height / n - 1);
        final rr = RRect.fromRectAndRadius(r, const Radius.circular(2));
        canvas.drawRRect(rr.shift(const Offset(0, 1.5)), Paint()..color = const Color(0x55000000));
        canvas.drawRRect(rr, Paint()..color = const Color(0xFFF3EDDD));
        final back = horizontal
            ? Rect.fromLTRB(r.left, r.top, r.right, r.bottom - r.height * 0.28)
            : Rect.fromLTRB(r.left, r.top, r.right - r.width * 0.28, r.bottom);
        canvas.drawRRect(RRect.fromRectAndRadius(back, const Radius.circular(2)), Paint()..color = const Color(0xFF1E7A57));
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TablePainter old) => old.hands.length != hands.length ||
      Iterable<int>.generate(hands.length).any((i) => old.hands[i] != hands[i]);
}

/// 真ん中の表示窓（自動卓の真ん中の窓のように、局・本場・供託を出す）
class _CenterPanel extends StatelessWidget {
  final GameSession session;
  const _CenterPanel({required this.session});

  @override
  Widget build(BuildContext context) {
    final s = session;
    final rules = s.settings;
    const fg = Color(0xFFE7F2EA);
    return Semantics(
      label: tr('${s.roundName} ${s.honba}本場 供託${s.riichiSticks}本',
          '${displayRoundLabel(s.roundName)}, ${s.honba} honba, ${s.riichiSticks} riichi sticks'),
      container: true,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0F1F19),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF2F5545), width: 2),
          boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 6, offset: Offset(0, 2))],
        ),
        padding: const EdgeInsets.all(8),
        child: ExcludeSemantics(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(displayRoundLabel(s.roundName),
                    style: const TextStyle(color: fg, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 1, height: 1.1)),
                const SizedBox(height: 4),
                Text(tr('${s.honba}本場', '${s.honba} honba'),
                    style: const TextStyle(color: Color(0xFFFFD27A), fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                // 供託の点棒（多いときは5本まで描いて、数を添える）
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (s.riichiSticks == 0)
                          const PointStick(width: 52, kind: PointStickKind.thousand, faded: true)
                        else
                          for (var i = 0; i < math.min(s.riichiSticks, 5); i++)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 1),
                              child: PointStick(width: 52, kind: PointStickKind.thousand),
                            ),
                      ],
                    ),
                    const SizedBox(width: 6),
                    Text(tr('供託 ${s.riichiSticks}', 'Sticks ${s.riichiSticks}'),
                        style: const TextStyle(color: fg, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  tr('${rules.isSanma ? "3人 " : ""}${rules.tonpuu ? "東風" : "半荘"}・${s.records.length}局消化',
                      '${rules.isSanma ? "3P " : ""}${rules.tonpuu ? "East" : "Hanchan"} · ${s.records.length} played'),
                  style: const TextStyle(color: Color(0xB3E7F2EA), fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 卓の上の1人分の席。文字の大きさは [scale] で決め、4人とも同じにする
class _Seat extends StatelessWidget {
  final double scale;
  final String name;
  final String wind;
  final bool isDealer;
  final int score;
  final int rank;
  final bool riichi;
  final VoidCallback? onTap;

  const _Seat({
    super.key,
    required this.scale,
    required this.name,
    required this.wind,
    required this.isDealer,
    required this.score,
    required this.rank,
    required this.riichi,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const fg = Color(0xFFF7F3EA);
    final k = scale;
    // 卓ビューの札は短く（立直中の札をもう一度押すと取り消す。読み上げでは取り消せることも伝える）
    final action = riichi ? tr('立直中', 'In riichi') : tr('立直', 'Riichi');
    // 端末の文字の大きさの設定は、倍率に含めて計算済みなので重ねて掛けない
    return MediaQuery.withNoTextScaling(
      child: Semantics(
        button: true,
        enabled: onTap != null,
        label: tr('$wind $name ${formatPoints(score)}点 $rank位${riichi ? ' 立直中（押すと取消）' : ''}',
            '$wind $name ${formatPoints(score)} pts, rank $rank${riichi ? ', in riichi (tap to cancel)' : ''}'),
        child: Material(
          color: riichi ? const Color(0x24FFFFFF) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 22 * k,
                        height: 22 * k,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isDealer ? AppTheme.vermilionDark : const Color(0x26FFFFFF),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(wind.characters.first,
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13 * k, height: 1)),
                      ),
                      SizedBox(width: 5 * k),
                      Flexible(
                        child: Text(name,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: TextStyle(color: fg, fontSize: 13 * k, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  SizedBox(height: 2 * k),
                  // 点数（10万点を超えるような長い数字だけ、はみ出さないよう縮める）
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      formatPoints(score),
                      style: TextStyle(
                        color: fg,
                        fontSize: 26 * k,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                        height: 1.15,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  if (riichi) ...[
                    SizedBox(height: 3 * k),
                    PointStick(width: 60 * k, kind: PointStickKind.thousand),
                  ],
                  SizedBox(height: 5 * k),
                  // 順位と、立直の札（押せることが分かるように、ほかの文字より大きめのボタンの形）
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(tr('$rank位', '#$rank'),
                          style: TextStyle(color: const Color(0xCCF7F3EA), fontSize: 12 * k, fontWeight: FontWeight.w700)),
                      SizedBox(width: 6 * k),
                      Container(
                      constraints: BoxConstraints(minWidth: 72 * k),
                      padding: EdgeInsets.symmetric(horizontal: 14 * k, vertical: 6 * k),
                      decoration: BoxDecoration(
                        color: riichi ? AppTheme.vermilionDark : const Color(0x14FFFFFF),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: riichi ? AppTheme.vermilionDark : const Color(0x99F7F3EA), width: 1.5),
                      ),
                      child: Text(action,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: onTap == null ? const Color(0x66F7F3EA) : fg,
                              fontSize: 16 * k,
                              fontWeight: FontWeight.w800,
                              height: 1.2)),
                      ),
                    ]),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum PointStickKind { thousand, hundred }

/// 点棒（千点棒は真ん中に赤い点が1つ、百点棒は黒い点が並ぶ）
class PointStick extends StatelessWidget {
  final double width;
  final PointStickKind kind;

  /// 薄く描く（供託が無いとき）
  final bool faded;

  const PointStick({super.key, required this.width, required this.kind, this.faded = false});

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: faded ? 0.25 : 1,
        child: CustomPaint(size: Size(width, width * 0.11), painter: _PointStickPainter(kind)),
      );
}

class _PointStickPainter extends CustomPainter {
  final PointStickKind kind;
  const _PointStickPainter(this.kind);

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.height / 2));
    canvas.drawRRect(r.shift(const Offset(0, 1)), Paint()..color = const Color(0x55000000));
    canvas.drawRRect(r, Paint()..color = const Color(0xFFFFFCF4));
    final dot = size.height * 0.3;
    final c = size.center(Offset.zero);
    if (kind == PointStickKind.thousand) {
      canvas.drawCircle(c, dot * 1.1, Paint()..color = AppTheme.vermilion);
    } else {
      final p = Paint()..color = const Color(0xFF222222);
      for (var i = -3; i <= 3; i++) {
        canvas.drawCircle(c + Offset(i * size.width * 0.09, 0), dot * 0.6, p);
      }
    }
  }

  @override
  bool shouldRepaint(_PointStickPainter old) => old.kind != kind;
}
