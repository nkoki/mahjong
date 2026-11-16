import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import 'guided_recognition.dart';

/// 枠つきの撮影で撮った写真
class GuidedPhoto {
  final Uint8List bytes;

  /// 撮影画面に出していたカメラの映像の縦横比（幅 ÷ 高さ）。枠の位置を写真の中の位置に直すのに使う
  final double viewAspect;

  /// 写真が鏡のように左右反転しているか。
  /// Web 版は、外側（背面）でないカメラ（スマホの内側のカメラ・パソコンのカメラ）の映像と写真を左右反転する
  final bool mirrored;

  const GuidedPhoto(this.bytes, this.viewAspect, {this.mirrored = false});
}

/// 枠つきの撮影（テストでは差し替える）
abstract class GuidedCapture {
  /// 撮影画面を開いて写真を撮る。やめたら null
  Future<GuidedPhoto?> capture(BuildContext context);
}

/// カメラの映像に枠を重ねた撮影画面を開く
class CameraGuidedCapture implements GuidedCapture {
  const CameraGuidedCapture();

  @override
  Future<GuidedPhoto?> capture(BuildContext context) => Navigator.of(context)
      .push<GuidedPhoto>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const GuidedCameraScreen()));
}

/// カメラの映像の上に、手牌・和了牌・鳴いた牌を置く場所の枠を重ねた撮影画面。
///
/// 撮った写真は、枠の位置で切り分けて読み取る（guided_recognition.dart）。
/// 写真はこの端末の中だけで使い、保存も送信もしない
class GuidedCameraScreen extends StatefulWidget {
  const GuidedCameraScreen({super.key});

  @override
  State<GuidedCameraScreen> createState() => _GuidedCameraScreenState();
}

class _GuidedCameraScreenState extends State<GuidedCameraScreen> {
  CameraController? _controller;
  String? _error;
  bool _taking = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException('noCamera', tr('カメラが見つかりません', 'No camera found'));
      }
      // 外側（背面）のカメラを使う。無ければ最初のカメラ
      final camera = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => cameras.first);
      // 音は使わない（マイクの許可を求めない）
      final controller = CameraController(camera, ResolutionPreset.veryHigh, enableAudio: false);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (e) {
      if (!mounted) return;
      final denied = e is CameraException && e.code.toLowerCase().contains('denied') ||
          e.toString().contains('NotAllowedError');
      setState(() => _error = denied
          ? tr('カメラを使う許可がありません。端末（ブラウザ）の設定でカメラを許可するか、前の画面の「写真から選ぶ」を使ってください。',
              'Camera permission was denied. Allow the camera in the device (browser) settings, or use "Choose from photos" on the previous screen.')
          : tr('カメラを使えませんでした（$e）。前の画面の「撮影する（エリアなし）」か「写真から選ぶ」を使ってください。',
              'Could not use the camera ($e). Use "Take photo (no areas)" or "Choose from photos" on the previous screen.'));
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  /// 画面に出しているカメラの映像の縦横比（幅 ÷ 高さ）。
  /// アプリ版は縦向きに固定していて、映像の大きさは横向きで届くので入れ替える。Web 版は見たままの大きさで届く
  double _viewAspect(CameraController c) {
    final size = c.value.previewSize;
    if (size == null || size.width <= 0 || size.height <= 0) return 9 / 16;
    return kIsWeb ? size.width / size.height : size.height / size.width;
  }

  /// 映像と写真が鏡のように左右反転しているか（Web 版で、外側（背面）でないカメラを使っているとき）
  bool _mirrored(CameraController? c) =>
      kIsWeb && c != null && c.description.lensDirection != CameraLensDirection.back;

  Future<void> _shoot() async {
    final c = _controller;
    if (c == null || _taking) return;
    setState(() => _taking = true);
    try {
      final file = await c.takePicture();
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      Navigator.of(context).pop(GuidedPhoto(bytes, _viewAspect(c), mirrored: _mirrored(c)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _taking = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('撮影できませんでした: $e', 'Could not take the photo: $e'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    const fg = Color(0xFFF7F3EA);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: fg,
        title: Text(tr('エリアに合わせて撮影', 'Fit tiles to the areas')),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: _error != null
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!, key: const ValueKey('guided-error'), style: const TextStyle(color: fg)),
                      )
                    : c == null
                        ? const CircularProgressIndicator()
                        : AspectRatio(
                            aspectRatio: _viewAspect(c),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                // アプリ版は CameraPreview が向きを合わせる。Web 版は映像をそのまま置く
                                // （CameraPreview は Web 版で縦横比を取り違えることがあり、枠と写真がずれる）
                                if (kIsWeb) c.buildPreview() else CameraPreview(c),
                                const GuideOverlay(),
                              ],
                            ),
                          ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                tr(
                    '牌が色の付いたエリアの中に大きく写るように合わせます。牌同士は離さなくてかまいません。'
                        '使わないエリア（鳴きがないときなど）は空けておきます。'
                        '裏ドラ表示牌は、ドラ表示牌のエリアの下の段に、上の段から少し離して置きます（上下にくっつけると、2枚を1枚と読み間違えることがあります）。'
                        '裏返した牌（暗槓）は読み取れません。写真はどこにも送りません。'
                        '${_mirrored(c) ? '\nこのカメラの映像は、鏡のように左右が反転して見えます（読み取るときに元に戻します）。' : ''}',
                    'Fit the tiles inside the colored areas. Tiles may touch each other. '
                        'Leave unused areas empty. '
                        'Put ura dora indicators in a row below the dora indicators, slightly apart (rows that touch may be misread as one tile). '
                        'Face-down tiles (closed kan) are not read. The photo is not sent anywhere.'
                        '${_mirrored(c) ? '\nThis camera is shown mirrored (it is flipped back when reading).' : ''}'),
                style: const TextStyle(color: Color(0xCCF7F3EA), fontSize: 12),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12, top: 4),
              child: FilledButton.icon(
                key: const ValueKey('guided-shutter'),
                style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.vermilion, foregroundColor: Colors.white, minimumSize: const Size(180, 56)),
                icon: const Icon(Icons.photo_camera),
                label: Text(tr('撮影', 'Shoot')),
                onPressed: c == null || _taking ? null : _shoot,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// カメラの映像の上に重ねるエリア（[GuideFrames] の4つ）と、その名前。
/// 牌が見えるように、薄い色で塗って場所を示す（線の枠ではなく、色の付いた区画）
class GuideOverlay extends StatelessWidget {
  const GuideOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth, h = box.maxHeight;
      // 名前は、牌に重ならないように置く: 牌は左から並べるので右上の角に。和了牌は幅が狭いので、エリアの下に出す
      Widget area(PhotoRegion r, String label, Color color, Key key, {bool labelBelow = false}) {
        final text = Text(label,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                height: 1.2,
                shadows: const [Shadow(color: Colors.black, blurRadius: 3)]));
        return Positioned(
          key: key,
          left: r.left * w,
          top: r.top * h,
          width: r.width * w,
          height: r.height * h,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color.withAlpha(56),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              if (labelBelow)
                Positioned(right: 0, bottom: -18, child: text)
              else
                Positioned(right: 6, top: 2, child: text),
            ],
          ),
        );
      }

      return IgnorePointer(
        child: MediaQuery.withNoTextScaling(
          child: Stack(
            children: [
              area(GuideFrames.dora, tr('ドラ表示牌（下の段に裏ドラ）', 'Dora (ura dora in the row below)'), const Color(0xFFB9F6A5), const ValueKey('area-dora')),
              area(GuideFrames.melds, tr('鳴いた牌', 'Calls'), const Color(0xFF8FD3FF), const ValueKey('area-melds')),
              area(GuideFrames.hand, tr('手牌', 'Hand'), const Color(0xFFFFE08A), const ValueKey('area-hand')),
              area(GuideFrames.win, tr('和了牌', 'Win'), const Color(0xFFFF9C8F), const ValueKey('area-win')),
            ],
          ),
        ),
      );
    });
  }
}
