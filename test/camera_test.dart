import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mahjong_app/features/backup/backup_codec.dart';
import 'package:mahjong_app/features/camera/camera_providers.dart';
import 'package:mahjong_app/features/camera/camera_settings_screen.dart';
import 'package:mahjong_app/features/camera/tile_recognizer.dart';
import 'package:mahjong_app/features/session/data/session_repository.dart';
import 'package:mahjong_app/features/session/domain/models.dart';
import 'package:mahjong_app/features/session/session_providers.dart';
import 'package:mahjong_app/features/win/win_input_screen.dart';
import 'package:mahjong_score_engine/mahjong_score_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

const settings = CameraSettings(apiKey: 'sk-test');
final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);
final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 1, 2, 3]);

http.Response reply(String content, {int status = 200}) => http.Response.bytes(
      utf8.encode(jsonEncode({
        'choices': [
          {
            'message': {'role': 'assistant', 'content': content}
          }
        ]
      })),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

http.Response error(int status, String message) => http.Response.bytes(
      utf8.encode(jsonEncode({'error': {'message': message}})),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  group('Qwen API との通信', () {
    test('画像と指示文を送り、答えから牌を読み取る', () async {
      late http.Request sent;
      final client = MockClient((req) async {
        sent = req;
        return reply('2m 3m 4m 5mr 6m 7p 8p 9p 2s 3s 4s 5s 5s 1m');
      });
      final tiles = await QwenTileRecognizer(settings, client: client).recognize(png);
      expect(tiles, ['2m', '3m', '4m', '5mr', '6m', '7p', '8p', '9p', '2s', '3s', '4s', '5s', '5s', '1m']);

      expect(sent.url.toString(), CameraSettings.intlEndpoint);
      expect(sent.headers['Authorization'], 'Bearer sk-test');
      final body = jsonDecode(sent.body) as Map<String, dynamic>;
      expect(body['model'], 'qwen-vl-max');
      final content = (body['messages'] as List).single['content'] as List;
      expect(content[0]['image_url']['url'], startsWith('data:image/png;base64,'));
      expect(content[1]['text'], contains('1m〜9m'));
    });

    test('JPEG は image/jpeg として送る', () {
      final body = QwenTileRecognizer(settings).buildRequest(jpeg);
      final content = (body['messages'] as List).single['content'] as List;
      expect(content[0]['image_url']['url'], startsWith('data:image/jpeg;base64,'));
    });

    Future<String> failure(MockClient client, {CameraSettings s = settings}) async {
      try {
        await QwenTileRecognizer(s, client: client).recognize(png);
      } on RecognitionException catch (e) {
        return e.message;
      }
      fail('RecognitionException になるはず');
    }

    test('失敗したときは理由を分かる言葉で返す', () async {
      expect(await failure(MockClient((_) async => error(401, 'Invalid API-key'))),
          allOf(contains('API キーが正しくない'), contains('Invalid API-key')));
      expect(await failure(MockClient((_) async => error(429, 'Throttling'))), contains('上限'));
      expect(await failure(MockClient((_) async => error(404, 'model not found'))), contains('モデル名'));
      expect(await failure(MockClient((_) async => reply('NONE'))), contains('読み取れませんでした'));
      expect(await failure(MockClient((_) async => http.Response('<html>broken</html>', 200))), contains('応答を読み取れません'));
      expect(await failure(MockClient((_) async => throw http.ClientException('Failed to fetch'))),
          contains('接続できませんでした'));
      expect(await failure(MockClient((_) async => reply('1m')), s: const CameraSettings()),
          contains('API キーが設定されていません'));
    });

    test('答えに説明文が混ざっていても、牌の表記だけを取り出す', () {
      expect(QwenTileRecognizer.parseResponse('牌は 1m 9m 1z です。5zr や 0m は無効'), ['1m', '9m', '1z']);
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

  group('設定の保存', () {
    test('API キーは端末に保存され、バックアップには入らない', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = SharedPrefsSessionRepository(prefs);
      await repo.saveCameraSettings(
          const CameraSettings(apiKey: 'sk-secret', endpoint: CameraSettings.chinaEndpoint));
      final loaded = SharedPrefsSessionRepository(prefs).loadCameraSettings();
      expect(loaded.apiKey, 'sk-secret');
      expect(loaded.endpoint, CameraSettings.chinaEndpoint);

      final backup = BackupCodec.encode([], defaultSettings: const GameSettings());
      expect(backup, isNot(contains('sk-secret')));
    });
  });

  group('画面', () {
    late _FakePicker picker;
    late _FakeRecognizer recognizer;

    Future<void> pump(WidgetTester tester, {CameraSettings camera = settings}) async {
      await tester.binding.setSurfaceSize(const Size(420, 2600));
      final repo = InMemorySessionRepository([
        GameSession.start(id: 'x', playerNames: ['A', 'B', 'C', 'D'], settings: const GameSettings()),
      ])
        ..cameraSettings = camera;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sessionRepositoryProvider.overrideWithValue(repo),
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

    testWidgets('API キーがなければ設定を案内する', (tester) async {
      await pump(tester, camera: const CameraSettings());
      await tester.tap(find.byTooltip('カメラで手牌を読み取る'));
      await tester.pumpAndSettle();
      expect(find.text('カメラ認識の設定が必要です'), findsOneWidget);
      await tester.tap(find.text('設定を開く'));
      await tester.pumpAndSettle();
      expect(find.byType(CameraSettingsScreen), findsOneWidget);
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
      recognizer.error = const RecognitionException('API キーが正しくないか、このモデルを使う権限がありません。');
      await pump(tester);
      await tester.tap(find.byTooltip('カメラで手牌を読み取る'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('写真から選ぶ'));
      await tester.pumpAndSettle();
      expect(picker.fromCamera, isFalse);
      expect(find.text('読み取れませんでした'), findsOneWidget);
      expect(find.textContaining('API キーが正しくない'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('手牌（0/13枚・タップで削除）'), findsOneWidget);
    });

    testWidgets('設定画面で API キー・地域を保存できる', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 2000));
      final repo = InMemorySessionRepository();
      await tester.pumpWidget(ProviderScope(
        overrides: [sessionRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: CameraSettingsScreen()),
      ));
      await tester.enterText(find.widgetWithText(TextField, 'API キー'), ' sk-abc ');
      await tester.tap(find.text('中国本土版'));
      await tester.tap(find.text('qwen-vl-plus'));
      await tester.pump();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(repo.cameraSettings.apiKey, 'sk-abc');
      expect(repo.cameraSettings.endpoint, CameraSettings.chinaEndpoint);
      expect(repo.cameraSettings.model, 'qwen-vl-plus');
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
