import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_app/features/about/data_sources.dart';
import 'package:mahjong_app/features/about/license_screen.dart';
import 'package:mahjong_app/features/camera/camera_providers.dart';
import 'package:mahjong_app/features/camera/tile_detection.dart';
import 'package:mahjong_app/features/camera/tile_recognizer.dart';
import 'package:mahjong_app/features/session/data/session_repository.dart';
import 'package:mahjong_app/features/session/domain/models.dart';
import 'package:mahjong_app/features/session/screens/home_screen.dart';
import 'package:mahjong_app/features/session/session_providers.dart';
import 'package:mahjong_app/features/win/win_input_screen.dart';
import 'package:mahjong_score_engine/mahjong_score_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 牌1枚（x は左端、y は上端。幅 0.05・高さ 0.07）
TileDetection det(Tile t, double x, double y, {double score = 0.9, double w = 0.05, double h = 0.07}) =>
    TileDetection(t, score, x, y, x + w, y + h);

void main() {
  group('検出結果の整理', () {
    test('重なった検出は確信度の高いほうだけ残す（種類が違っても）', () {
      final r = nonMaxSuppression([
        det('1m', 0.10, 0.5, score: 0.6),
        det('7m', 0.105, 0.5, score: 0.8),
        det('2m', 0.20, 0.5, score: 0.7),
      ]);
      expect(r.map((d) => d.tile), ['7m', '2m']);
    });

    test('左から順に並べる', () {
      final r = arrangeTiles([det('3p', 0.3, 0.5), det('1p', 0.1, 0.5), det('2p', 0.2, 0.5)]);
      expect(r.tiles, ['1p', '2p', '3p']);
      expect(r.ignored, 0);
    });

    test('写真が傾いていても、列に沿って左から並べる', () {
      // 右に行くほど上がっている（約20度）
      final tiles = ['1s', '2s', '3s', '4s', '5s', '6s', '7s'];
      final r = arrangeTiles([
        for (var i = tiles.length - 1; i >= 0; i--) det(tiles[i], 0.1 + i * 0.06, 0.6 - i * 0.022),
      ]);
      expect(r.tiles, tiles);
    });

    test('離れた列（鳴いた牌・ドラ表示牌）は除き、一番多い列を手牌にする', () {
      final r = arrangeTiles([
        for (var i = 0; i < 10; i++) det('${i % 9 + 1}m', 0.1 + i * 0.055, 0.6),
        det('1z', 0.2, 0.2),
        det('2z', 0.26, 0.2),
      ]);
      expect(r.tiles, hasLength(10));
      expect(r.tiles.first, '1m');
      expect(r.ignored, 2);
    });

    test('牌が写っている範囲が狭ければ、切り抜く範囲を返す', () {
      final small = [det('1m', 0.40, 0.45), det('2m', 0.46, 0.45)];
      final region = cropRegion(small)!;
      expect(region.left, lessThan(0.40));
      expect(region.left + region.width, greaterThan(0.51));
      expect(cropRegion([det('1m', 0.0, 0.0, w: 0.9, h: 0.9)]), isNull);
    });

    test('切り抜いた画像の座標を元の画像の座標に戻す', () {
      final d = det('1m', 0.5, 0.5, w: 0.1, h: 0.1).mapFromCrop(0.2, 0.4, 0.5, 0.5);
      expect(d.left, closeTo(0.45, 1e-9));
      expect(d.top, closeTo(0.65, 1e-9));
      expect(d.right, closeTo(0.50, 1e-9));
    });
  });

  group('モデルの出力の変換', () {
    // アンカー2つ（y中心, x中心, 高さ, 幅）
    final anchors = [0.5, 0.25, 0.2, 0.1, 0.5, 0.75, 0.2, 0.1];
    const labels = ['1m', '2m'];

    test('アンカーとずれから箱を求め、確信度が低いものは除く', () {
      final r = decodeDetections(
        rawBoxes: [0.5, 0.0, 0.0, 0.0, 0, 0, 0, 0],
        // background, 1m, 2m
        rawScores: [0.0, 0.1, 0.9, 0.0, 0.2, 0.1],
        anchors: anchors,
        labels: labels,
      );
      expect(r, hasLength(1));
      final d = r.single;
      expect(d.tile, '2m');
      expect(d.score, 0.9);
      expect(d.centerY, closeTo(0.6, 1e-6)); // 0.5 + 0.5 × 0.2
      expect(d.centerX, closeTo(0.25, 1e-6));
      expect(d.height, closeTo(0.2, 1e-6)); // exp(0) × 0.2
      expect(d.width, closeTo(0.1, 1e-6));
    });

    test('大きさは exp で求める', () {
      final r = decodeDetections(
        rawBoxes: [0, 0, 0.6931472, 0.6931472, 0, 0, 0, 0],
        rawScores: [0, 0.9, 0, 0, 0, 0],
        anchors: anchors,
        labels: labels,
      );
      expect(r.single.height, closeTo(0.4, 1e-5));
      expect(r.single.width, closeTo(0.2, 1e-5));
    });

    test('出力の大きさが合わなければエラー', () {
      expect(
          () => decodeDetections(rawBoxes: [0, 0, 0, 0], rawScores: [0, 0, 0], anchors: anchors, labels: labels),
          throwsArgumentError);
    });

    test('正方形に縮めたときの余白の分を戻す', () {
      // 横長（800×400）を 384 に縮めると 384×192。下半分は余白
      const box = Letterbox(800, 400, 384);
      expect(box.resizedWidth, 384);
      expect(box.resizedHeight, 192);
      final d = box.toImage(const TileDetection('1m', 0.9, 0.1, 0.25, 0.2, 0.45));
      expect(d.left, closeTo(0.1, 1e-9));
      expect(d.top, closeTo(0.5, 1e-9));
      expect(d.bottom, closeTo(0.9, 1e-9));
    });
  });

  group('読み取った牌を手牌に入れる', () {
    final fourteen = ['9p', '2m', '3m', '4m', '5m', '6m', '7p', '8p', '2s', '3s', '4s', '5s', '5s', '1m'];

    test('14枚なら13枚を手牌（並べ替え）に、最後の1枚を和了牌にする', () {
      final r = applyRecognition(fourteen, needHand: 13);
      expect(r.hand, sortTiles(fourteen.take(13).toList()));
      expect(r.winningTile, '1m');
      expect(r.notes, isEmpty);
    });

    test('13枚なら和了牌は手で選ぶ。足りなければ知らせる', () {
      expect(applyRecognition(fourteen.take(13).toList(), needHand: 13).notes, contains('和了牌は手で選んでください'));
      expect(applyRecognition(fourteen.take(10).toList(), needHand: 13).notes.single, contains('3枚足りません'));
    });

    test('鳴きがあるときは手牌の枚数を減らし、多すぎる分は使わない', () {
      final r = applyRecognition(fourteen, needHand: 10);
      expect(r.hand, hasLength(10));
      expect(r.winningTile, fourteen[10]);
      expect(r.notes.single, contains('後ろの3枚'));
    });

    test('3人打ちでは二萬〜八萬を除き、赤ドラなしなら赤5は普通の5にする', () {
      final r = applyRecognition(['1m', '2m', '9m', '5pr'], needHand: 13, sanma: true, redDora: false);
      expect(r.hand, ['1m', '9m', '5p']);
      expect(r.notes, contains('3人打ちでは使わない二萬〜八萬を1枚除きました'));
      expect(r.notes, contains('赤5を1枚、普通の5として入れました'));
    });

    test('同じ牌が5枚以上なら5枚目から除く', () {
      final r = applyRecognition(['1z', '1z', '1z', '1z', '1z'], needHand: 13);
      expect(r.hand, hasLength(4));
      expect(r.notes, contains('同じ牌が5枚以上あったので、1枚除きました'));
    });
  });

  group('以前の設定', () {
    test('以前の Qwen の API キーは読み込み時に消す', () async {
      SharedPreferences.setMockInitialValues({
        SharedPrefsSessionRepository.legacyCameraSettingsKey: '{"apiKey":"sk-secret"}',
      });
      final prefs = await SharedPreferences.getInstance();
      SharedPrefsSessionRepository(prefs).loadAll();
      expect(prefs.containsKey(SharedPrefsSessionRepository.legacyCameraSettingsKey), isFalse);
    });
  });

  group('ライセンス画面', () {
    testWidgets('ホーム画面から開け、学習データと道具の出典を表示する', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 3000));
      await tester.pumpWidget(ProviderScope(
        overrides: [sessionRepositoryProvider.overrideWithValue(InMemorySessionRepository())],
        child: const MaterialApp(home: HomeScreen()),
      ));
      await tester.tap(find.text('ライセンス・データの出典'));
      await tester.pumpAndSettle();
      expect(find.byType(LicenseScreen), findsOneWidget);
      expect(find.text('Riichi Mahjong（バージョン 8）'), findsOneWidget);
      expect(find.text('Riichi Mahjong Detection（バージョン 3）'), findsOneWidget);
      expect(find.text('ライセンス: CC BY 4.0'), findsNWidgets(2));
      expect(find.text('出典: https://universe.roboflow.com/hust-xq5rx/riichi-mahjong'), findsOneWidget);
      expect(find.text('riichi-mahjong-tiles'), findsOneWidget);
      expect(find.text('ライセンス: CC0 1.0（パブリックドメイン）'), findsOneWidget);
      expect(find.text('MediaPipe Model Maker'), findsOneWidget);
      expect(find.text('TensorFlow / Keras（MobileNetV3-Small の学習済みモデル）'), findsOneWidget);
    });

    test('標準のライセンス画面用の文にも出典が入る', () {
      for (final s in trainingDataSources.where((s) => s.license == 'CC BY 4.0')) {
        // CC BY の表記: 作品名・作成者・出典・ライセンスとそのリンク・変更内容
        final text = s.licenseText;
        expect(text, contains(s.title));
        expect(text, contains('作成者: '));
        expect(text, contains('出典: https://universe.roboflow.com/'));
        expect(text, contains('ライセンス: CC BY 4.0（https://creativecommons.org/licenses/by/4.0/）'));
        expect(text, contains('変更: '));
      }
      expect(trainingDataSources.where((s) => s.license == 'CC BY 4.0'), hasLength(2));
    });
  });

  group('画面', () {
    late _FakePicker picker;
    late _FakeRecognizer recognizer;

    Future<void> pump(WidgetTester tester, {bool supported = true}) async {
      await tester.binding.setSurfaceSize(const Size(420, 2600));
      final repo = InMemorySessionRepository([
        GameSession.start(id: 'x', playerNames: ['A', 'B', 'C', 'D'], settings: const GameSettings()),
      ]);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sessionRepositoryProvider.overrideWithValue(repo),
          cameraSupportedProvider.overrideWithValue(supported),
          photoPickerProvider.overrideWithValue(picker),
          tileRecognizerProvider.overrideWithValue(recognizer),
        ],
        child: const MaterialApp(home: WinInputScreen(sessionId: 'x')),
      ));
    }

    setUp(() {
      picker = _FakePicker();
      recognizer = _FakeRecognizer();
    });

    testWidgets('Web 版（使えない端末）ではカメラボタンを出さず、アプリ版で使えると表示する', (tester) async {
      await pump(tester, supported: false);
      expect(find.byTooltip('カメラで手牌を読み取る'), findsNothing);
      expect(find.textContaining('スマホのアプリ版（Android・iOS）で使えます'), findsOneWidget);
    });

    testWidgets('撮影して読み取った牌を手牌と和了牌に入れる', (tester) async {
      recognizer.result = ['2m', '3m', '4m', '5m', '6m', '7p', '8p', '9p', '2s', '3s', '4s', '5s', '5s', '1m'];
      await pump(tester);
      await tester.tap(find.byTooltip('カメラで手牌を読み取る'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('撮影する'));
      await tester.pumpAndSettle();
      expect(picker.fromCamera, isTrue);
      expect(find.text('読み取り結果'), findsOneWidget);
      expect(find.text('読み取った牌（14枚）'), findsOneWidget);
      await tester.tap(find.text('手牌に入れる'));
      await tester.pumpAndSettle();
      expect(find.text('手牌（13/13枚・タップで削除）'), findsOneWidget);
      expect(find.text('ロン'), findsWidgets); // 和了牌の欄に「ロン」と並んで表示される
    });

    testWidgets('読み取りに失敗したら理由を表示し、手牌は変えない', (tester) async {
      recognizer.error = const RecognitionException('麻雀牌を見つけられませんでした。');
      await pump(tester);
      await tester.tap(find.byTooltip('カメラで手牌を読み取る'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('写真から選ぶ'));
      await tester.pumpAndSettle();
      expect(picker.fromCamera, isFalse);
      expect(find.text('読み取れませんでした'), findsOneWidget);
      expect(find.textContaining('麻雀牌を見つけられませんでした'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('手牌（0/13枚・タップで削除）'), findsOneWidget);
    });
  });
}

class _FakePicker implements PhotoPicker {
  bool? fromCamera;

  @override
  Future<Uint8List?> pick({required bool fromCamera}) async {
    this.fromCamera = fromCamera;
    return Uint8List.fromList([0xFF, 0xD8, 0xFF]);
  }
}

class _FakeRecognizer implements TileRecognizer {
  List<Tile> result = const [];
  RecognitionException? error;

  @override
  Future<List<Tile>> recognize(Uint8List imageBytes) async {
    if (error != null) throw error!;
    return result;
  }
}
