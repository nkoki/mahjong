import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_app/features/camera/guided_camera_screen.dart';
import 'package:mahjong_app/features/camera/guided_recognition.dart';
import 'package:mahjong_app/features/camera/tile_detection.dart';
import 'package:mahjong_score_engine/mahjong_score_engine.dart';

import 'camera_test.dart' show rowOf;

/// 枠つきの撮影（手牌・和了牌・鳴いた牌を枠ごとに読み取る）
void main() {
  group('枠', () {
    test('3つの枠は映像の中に収まり、重ならない', () {
      const frames = GuideFrames.all;
      for (final f in frames) {
        expect(f.left, greaterThanOrEqualTo(0));
        expect(f.top, greaterThanOrEqualTo(0));
        expect(f.right, lessThanOrEqualTo(1));
        expect(f.bottom, lessThanOrEqualTo(1));
      }
      bool overlap(PhotoRegion a, PhotoRegion b) =>
          a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom;
      for (var i = 0; i < frames.length; i++) {
        for (var j = i + 1; j < frames.length; j++) {
          expect(overlap(frames[i], frames[j]), isFalse);
        }
      }
      // 手牌の右どなりに和了牌、上に鳴いた牌
      expect(GuideFrames.win.left, greaterThan(GuideFrames.hand.right));
      expect(GuideFrames.melds.bottom, lessThan(GuideFrames.hand.top));
    });

    test('映像と写真の縦横比が同じなら、枠の位置はそのまま', () {
      final r = mapViewRegionToPhoto(GuideFrames.hand, 9 / 16, 1080, 1920);
      expect(r.left, closeTo(GuideFrames.hand.left, 1e-9));
      expect(r.top, closeTo(GuideFrames.hand.top, 1e-9));
      expect(r.width, closeTo(GuideFrames.hand.width, 1e-9));
    });

    test('写真のほうが横に広ければ（映像 9:16・写真 3:4）、映像は写真の真ん中', () {
      // 映像の幅は写真の幅の 0.75 倍。左右に 0.125 ずつ余る
      final r = mapViewRegionToPhoto(const PhotoRegion(0, 0.5, 1, 0.2), 9 / 16, 1500, 2000);
      expect(r.left, closeTo(0.125, 1e-9));
      expect(r.width, closeTo(0.75, 1e-9));
      expect(r.top, closeTo(0.5, 1e-9));
      expect(r.height, closeTo(0.2, 1e-9));
    });

    test('写真のほうが縦に長ければ、上下の余りの分を足す。はみ出す分は切り捨てる', () {
      final r = mapViewRegionToPhoto(const PhotoRegion(0.1, 0, 0.8, 1), 3 / 4, 1080, 1920);
      expect(r.top, closeTo(0.125, 1e-9));
      expect(r.height, closeTo(0.75, 1e-9));
      expect(r.left, closeTo(0.1, 1e-9));
      final px = regionPixels(const PhotoRegion(0.9, 0.9, 0.5, 0.5), 100, 200);
      expect(px.x + px.width, lessThanOrEqualTo(100));
      expect(px.y + px.height, lessThanOrEqualTo(200));
    });
  });

  group('鳴きの組分け', () {
    test('すき間で区切り、ポン・チー・槓を見分ける', () {
      final r = groupMelds(rowOf(['7z', '7z', '7z', '4p', '2p', '3p', '1s', '1s', '1s', '1s'], gaps: {3, 6}));
      expect(r.leftover, 0);
      expect(r.melds.map((m) => m.type), [MeldType.pon, MeldType.chi, MeldType.minkan]);
      expect(r.melds[1].tiles, ['2p', '3p', '4p'], reason: 'チーは小さい順に並べる');
      expect(r.melds[2].tiles, hasLength(4));
    });

    test('すき間を空けずに並べても、3枚ずつなら分けられる', () {
      final r = groupMelds(rowOf(['5m', '5mr', '5m', '6s', '7s', '8s']));
      expect(r.melds.map((m) => m.type), [MeldType.pon, MeldType.chi]);
      expect(r.melds.first.tiles, ['5m', '5mr', '5m'], reason: '赤5は普通の5と同じ牌として組にする');
    });

    test('組にできない牌は数える（字牌の続き・色の違う続き・枚数の余り）', () {
      expect(groupMelds(rowOf(['1z', '2z', '3z'])).leftover, 3);
      expect(groupMelds(rowOf(['1m', '2p', '3s'])).leftover, 3);
      final r = groupMelds(rowOf(['9m', '9m', '9m', '2s'], gaps: {3}));
      expect(r.melds.single.type, MeldType.pon);
      expect(r.leftover, 1);
    });

    test('2段に並べたときは、段ごとに読む', () {
      final top = rowOf(['6z', '6z', '6z']).detections;
      final bottom = [
        for (final d in rowOf(['3m', '4m', '5m']).detections)
          TileDetection(d.tile, d.score, d.left, d.top + 0.5, d.right, d.bottom + 0.5)
      ];
      final r = groupMelds(RegionTiles(1000, 400, [...bottom, ...top]));
      expect(r.melds.map((m) => m.type), [MeldType.pon, MeldType.chi]);
    });

    test('空なら鳴きなし', () {
      expect(groupMelds(RegionTiles.empty).melds, isEmpty);
    });
  });

  group('読み取った内容を手牌・和了牌・鳴きに分ける', () {
    test('鳴き1組: 手牌は10枚、和了牌は和了牌の枠から', () {
      final r = interpretGuided(
        hand: rowOf(['9p', '2m', '3m', '4m', '7p', '8p', '5s', '5s', '6s', '7s']),
        win: rowOf(['8s']),
        melds: rowOf(['1z', '1z', '1z']),
      );
      expect(r.melds.single.type, MeldType.pon);
      expect(r.needHand, 10);
      expect(r.hand, sortTiles(['9p', '2m', '3m', '4m', '7p', '8p', '5s', '5s', '6s', '7s']));
      expect(r.winningTile, '8s');
      expect(r.notes, isEmpty);
    });

    test('鳴きなし: 和了牌の枠が空で手牌が14枚なら、右端を和了牌にする', () {
      final tiles = ['1m', '2m', '3m', '4m', '5m', '6m', '7p', '8p', '9p', '2s', '3s', '4s', '5s', '5z'];
      final r = interpretGuided(hand: rowOf(tiles), win: RegionTiles.empty, melds: RegionTiles.empty);
      expect(r.melds, isEmpty);
      expect(r.hand, hasLength(13));
      expect(r.winningTile, '5z');
      expect(r.notes.single, contains('右端の牌を和了牌にしました'));
    });

    test('槓は明槓として入れ、暗槓のときの操作を知らせる。組にできない牌も知らせる', () {
      final r = interpretGuided(
        hand: rowOf(['2m', '3m', '4m', '7p', '8p', '9p', '5s', '5s', '6s', '7s']),
        win: rowOf(['8s']),
        melds: rowOf(['3z', '3z', '3z', '3z', '9m'], gaps: {4}),
      );
      expect(r.melds.single.type, MeldType.minkan);
      expect(r.notes.join(), contains('暗槓のときは'));
      expect(r.notes.join(), contains('組にできない牌が1枚'));
    });

    test('3人打ち: チーは入れず、二萬〜八萬を除く。赤ドラなしなら赤5は普通の5', () {
      final r = interpretGuided(
        hand: rowOf(['1m', '5m', '9m', '5pr', '6p', '7p']),
        win: rowOf(['1z']),
        melds: rowOf(['2s', '3s', '4s', '7z', '7z', '7z'], gaps: {3}),
        sanma: true,
        redDora: false,
      );
      expect(r.melds.single.type, MeldType.pon);
      expect(r.hand, sortTiles(['1m', '9m', '5p', '6p', '7p']));
      expect(r.notes.join(), contains('チー1組は入れませんでした'));
      expect(r.notes.join(), contains('二萬〜八萬を1枚除きました'));
      expect(r.notes.join(), contains('赤5を1枚'));
      expect(r.notes.join(), contains('手牌が5枚足りません'));
    });

    test('同じ牌は、鳴きの牌も合わせて4枚まで', () {
      final r = interpretGuided(
        hand: rowOf(['7z', '7z', '2m', '3m', '4m', '7p', '8p', '9p', '5s', '6s']),
        win: rowOf(['7s']),
        melds: rowOf(['7z', '7z', '7z']),
      );
      expect(r.hand.where((t) => t == '7z'), hasLength(1));
      expect(r.notes.join(), contains('同じ牌が5枚以上'));
    });

    test('手牌の枠の牌が多すぎれば、右の牌は使わない。和了牌が無ければ知らせる', () {
      final r = interpretGuided(
        hand: rowOf(['1m', '2m', '3m', '4m', '5m', '6m', '7m', '8m', '9m', '1p', '2p', '3p', '4p', '5p', '6p', '7p']),
        win: RegionTiles.empty,
        melds: RegionTiles.empty,
      );
      expect(r.hand, hasLength(13));
      expect(r.winningTile, isNull);
      expect(r.notes.join(), contains('右の3枚は使いませんでした'));
      expect(r.notes.join(), contains('和了牌は手で選んでください'));
    });

    test('和了牌の枠にいくつか見つかったら、確信度の高いものを使う', () {
      const win = RegionTiles(100, 100, [
        TileDetection('3p', 0.4, 0.1, 0.1, 0.4, 0.9),
        TileDetection('8p', 0.95, 0.5, 0.1, 0.9, 0.9),
      ]);
      final r = interpretGuided(hand: RegionTiles.empty, win: win, melds: RegionTiles.empty);
      expect(r.winningTile, '8p');
    });
  });

  group('撮影画面の枠', () {
    testWidgets('3つの枠の名前を出し、枠は GuideFrames の位置に置く', (tester) async {
      await tester.pumpWidget(const MaterialApp(
          home: Center(child: SizedBox(width: 360, height: 480, child: GuideOverlay()))));
      expect(find.text('手牌'), findsOneWidget);
      expect(find.text('和了牌'), findsOneWidget);
      expect(find.textContaining('鳴いた牌'), findsOneWidget);
      final origin = tester.getTopLeft(find.byType(GuideOverlay));
      final boxes = tester.widgetList<Positioned>(
          find.descendant(of: find.byType(GuideOverlay), matching: find.byType(Positioned)));
      final hand = boxes.firstWhere((p) => p.width != null && (p.width! - GuideFrames.hand.width * 360).abs() < 0.01);
      expect(hand.left, closeTo(GuideFrames.hand.left * 360, 0.01));
      expect(hand.top, closeTo(GuideFrames.hand.top * 480, 0.01));
      expect(origin, isNotNull);
      expect(tester.takeException(), isNull);
    });
  });

  group('権限', () {
    test('Android: カメラだけを使い、マイクと保存の権限は外す。カメラの無い端末にも入れられる', () {
      final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest, contains('android.permission.CAMERA'));
      expect(manifest, matches(RegExp(r'android\.permission\.RECORD_AUDIO"\s+tools:node="remove"')));
      expect(manifest, matches(RegExp(r'android\.permission\.WRITE_EXTERNAL_STORAGE"\s+tools:node="remove"')));
      expect(manifest, matches(RegExp(r'android\.hardware\.camera\.any"\s+android:required="false"')));
    });

    test('iOS: カメラを使う理由を書いてあり、マイクの理由は書かない（音は使わない）', () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      expect(plist, contains('NSCameraUsageDescription'));
      expect(plist, isNot(contains('NSMicrophoneUsageDescription')));
      final screen = File('lib/features/camera/guided_camera_screen.dart').readAsStringSync();
      expect(screen, contains('enableAudio: false'));
    });
  });
}
