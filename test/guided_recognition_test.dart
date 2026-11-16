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
    test('4つのエリアは映像の中に収まり、重ならない', () {
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
      expect(GuideFrames.dora.bottom, lessThan(GuideFrames.melds.top), reason: 'ドラ表示牌はいちばん上');
      // 手牌のエリアがいちばん大きい
      double areaOf(PhotoRegion r) => r.width * r.height;
      for (final other in [GuideFrames.win, GuideFrames.melds, GuideFrames.dora]) {
        expect(areaOf(GuideFrames.hand), greaterThan(areaOf(other)));
        expect(GuideFrames.hand.height, greaterThanOrEqualTo(other.height));
      }
      expect(GuideFrames.all, [GuideFrames.hand, GuideFrames.win, GuideFrames.melds, GuideFrames.dora]);
    });

    test('撮影画面の上下（ボタンを重ねる所）を除いた範囲に、エリアを置く', () {
      final regions = guideRegionsInView(400, 800, 50, 150);
      expect(regions, hasLength(GuideFrames.all.length));
      final hand = regions[0], dora = regions[3];
      // エリアを置く範囲は、上から 50〜650（高さ 600）
      expect(dora.top, closeTo((50 + GuideFrames.dora.top * 600) / 800, 1e-9));
      expect(hand.bottom, closeTo((50 + GuideFrames.hand.bottom * 600) / 800, 1e-9));
      expect(hand.bottom, lessThanOrEqualTo(650 / 800));
      expect(hand.left, GuideFrames.hand.left);
      expect(hand.width, GuideFrames.hand.width);
    });

    test('映像を画面いっぱいに広げたとき、画面からはみ出した左右の分を足して写真の位置にする', () {
      // 画面 400×800（縦横比 0.5）に、写真 1080×1920（0.5625）を高さいっぱいで出す → 左右が切れる
      final r = mapViewRegionToPhoto(const PhotoRegion(0, 0.25, 1, 0.5), 0.5, 1080, 1920);
      const visible = 0.5 / 0.5625; // 写真の幅のうち、画面に見えている割合
      expect(r.left, closeTo((1 - visible) / 2, 1e-9));
      expect(r.width, closeTo(visible, 1e-9));
      expect(r.top, closeTo(0.25, 1e-9));
      expect(r.height, closeTo(0.5, 1e-9));
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

    test('離さずに並べたとき、余りがいちばん少ない分け方を選ぶ（槓に見える4枚を、ポンとチーに分ける）', () {
      final r = groupMelds(rowOf(['3s', '3s', '3s', '3s', '4s', '5s']));
      expect(r.leftover, 0);
      expect(r.melds.map((m) => m.type), [MeldType.pon, MeldType.chi]);
      expect(r.melds[1].tiles, ['3s', '4s', '5s']);
      // 続きが重なる並び: 2筒3筒4筒 4筒4筒4筒 5筒6筒7筒
      final r2 = groupMelds(rowOf(['2p', '3p', '4p', '4p', '4p', '4p', '5p', '6p', '7p']));
      expect(r2.leftover, 0);
      expect(r2.melds.map((m) => m.type), [MeldType.chi, MeldType.pon, MeldType.chi]);
      // 4枚だけなら槓
      expect(groupMelds(rowOf(['3s', '3s', '3s', '3s'])).melds.single.type, MeldType.minkan);
      // 離さずに4組
      final r3 = groupMelds(rowOf(['1z', '1z', '1z', '7m', '8m', '9m', '5z', '5z', '5z', '5z', '1p', '2p', '3p']));
      expect(r3.melds.map((m) => m.type), [MeldType.pon, MeldType.chi, MeldType.minkan, MeldType.chi]);
      expect(r3.leftover, 0);
    });

    test('離さずに並べると分けられないときは、すき間で区切った分け方を使う', () {
      // 9萬 | 9萬 9萬 9萬 の順に読めても、すき間があれば 余り1枚＋ポン。すき間がなくても同じ結果になる
      // 1索2索 | 3索 3索 3索: 離さないと 1-2-3 のチー＋余り2枚、すき間で区切ると 余り2枚＋ポン（余りが同じなら離さない分け方）
      final r = groupMelds(rowOf(['4m', '5m', '6m', '6m', '7m', '8m', '8m'], gaps: {3}));
      expect(r.melds.map((m) => m.tiles.join()), ['4m5m6m', '6m7m8m']);
      expect(r.leftover, 1);
      // すき間で区切ったほうが余りが少ない例: 2筒3筒 | 4筒4筒4筒 … 離さないと 2-3-4＋余り2、区切ると 余り2＋ポン → 同じなので離さない分け方
      final r2 = groupMelds(rowOf(['7z', '1s', '2s', '3s', '4s', '5s', '6s'], gaps: {1}));
      expect(r2.leftover, 1);
      expect(r2.melds, hasLength(2));
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

    test('ドラ表示牌は左から順に入れる。5枚まで。同じ牌の枚数にも数える', () {
      final r = interpretGuided(
        hand: rowOf(['2m', '3m', '4m', '7p', '8p', '9p', '5s', '5s', '6s', '7s', '1z', '1z', '1z']),
        win: rowOf(['8s']),
        melds: RegionTiles.empty,
        dora: rowOf(['9s', '3z', '1z', '1z']),
      );
      expect(r.dora, ['9s', '3z', '1z'], reason: '東は手牌に3枚あるので、ドラ表示牌に入れられるのは1枚');
      expect(r.notes.join(), contains('同じ牌が5枚以上'));
      final many = interpretGuided(
        hand: RegionTiles.empty,
        win: RegionTiles.empty,
        melds: RegionTiles.empty,
        dora: rowOf(['1m', '2m', '3m', '4m', '5m', '6m', '7m']),
      );
      expect(many.dora, ['1m', '2m', '3m', '4m', '5m']);
      expect(many.notes.join(), contains('ドラ表示牌が多すぎた'));
      // 渡さなければ空
      expect(interpretGuided(hand: RegionTiles.empty, win: RegionTiles.empty, melds: RegionTiles.empty).dora, isEmpty);
    });

    test('ドラ表示牌のエリアの上の段はドラ表示牌、下の段は裏ドラ表示牌', () {
      RegionTiles twoRows(List<Tile> top, List<Tile> bottom) => RegionTiles(1000, 400, [
            // 下の段を先に渡しても、上の段がドラ表示牌になる
            for (final d in rowOf(bottom).detections)
              TileDetection(d.tile, d.score, d.left, d.top * 0.45 + 0.5, d.right, d.bottom * 0.45 + 0.5),
            for (final d in rowOf(top).detections)
              TileDetection(d.tile, d.score, d.left, d.top * 0.45, d.right, d.bottom * 0.45),
          ]);
      final r = interpretGuided(
        hand: RegionTiles.empty,
        win: RegionTiles.empty,
        melds: RegionTiles.empty,
        dora: twoRows(['9s', '3z'], ['1p', '7z']),
      );
      expect(r.dora, ['9s', '3z']);
      expect(r.ura, ['1p', '7z']);
      // 1段だけならドラ表示牌だけ
      final one = interpretGuided(
          hand: RegionTiles.empty, win: RegionTiles.empty, melds: RegionTiles.empty, dora: rowOf(['2m']));
      expect(one.dora, ['2m']);
      expect(one.ura, isEmpty);
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

  group('撮影画面のエリア', () {
    testWidgets('4つのエリアを薄い色で塗って名前を出し、GuideFrames の位置に置く', (tester) async {
      await tester.pumpWidget(const MaterialApp(
          home: Center(child: SizedBox(width: 360, height: 480, child: GuideOverlay()))));
      expect(find.text('手牌'), findsOneWidget);
      expect(find.text('和了牌'), findsOneWidget);
      expect(find.text('鳴いた牌'), findsOneWidget);
      expect(find.text('ドラ表示牌（下の段に裏ドラ）'), findsOneWidget);
      for (final (key, frame) in [
        ('area-hand', GuideFrames.hand),
        ('area-win', GuideFrames.win),
        ('area-melds', GuideFrames.melds),
        ('area-dora', GuideFrames.dora),
      ]) {
        final p = tester.widget<Positioned>(find.byKey(ValueKey(key)));
        expect(p.left, closeTo(frame.left * 360, 0.01));
        expect(p.top, closeTo(frame.top * 480, 0.01));
        expect(p.width, closeTo(frame.width * 360, 0.01));
        expect(p.height, closeTo(frame.height * 480, 0.01));
        // 線の枠ではなく、薄い色（下の牌が見える）で塗る
        final box = tester.widget<DecoratedBox>(
            find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(DecoratedBox)));
        final deco = box.decoration as BoxDecoration;
        expect(deco.border, isNull);
        expect(deco.color!.a, inInclusiveRange(0.1, 0.35));
      }
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
