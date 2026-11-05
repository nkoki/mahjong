import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_app/features/backup/backup_codec.dart';
import 'package:mahjong_app/features/backup/backup_file_service.dart';
import 'package:mahjong_app/features/backup/backup_screen.dart';
import 'package:mahjong_app/features/session/data/session_repository.dart';
import 'package:mahjong_app/features/session/domain/models.dart';
import 'package:mahjong_app/features/session/domain/session_logic.dart';
import 'package:mahjong_app/features/session/session_providers.dart';

GameSession game(String id, {int day = 1, bool favorite = false}) {
  var s = GameSession.start(
      id: id,
      playerNames: ['A$id', 'B', 'C', 'D'],
      settings: const GameSettings(uma: [30, 10, -10, -30]),
      now: DateTime(2026, 1, day));
  s = SessionLogic.toggleRiichi(s, 1);
  s = SessionLogic.applyDraw(s, type: DrawType.exhaustive, tenpai: [false, true, false, false]);
  s = SessionLogic.editRound(s, 0, deltas: [3000, -2000, -1000, -1000]);
  s = SessionLogic.finishManually(s.copyWith(riichiSticks: 1));
  return s.copyWith(favorite: favorite);
}

/// ファイルの保存・選択の代わり
class FakeFileService implements BackupFileService {
  String? saved;
  String? savedName;
  String? toPick;

  @override
  Future<bool> save(String fileName, String content) async {
    savedName = fileName;
    saved = content;
    return true;
  }

  @override
  Future<String?> pick() async => toPick;
}

void main() {
  group('書き出しと読み込み', () {
    test('書き出して読み込むと同じ内容に戻る', () {
      final sessions = [game('1', favorite: true), game('2', day: 2)];
      final data = BackupCodec.decode(BackupCodec.encode(sessions, now: DateTime(2026, 3, 1, 12)));
      expect(data.exportedAt, DateTime(2026, 3, 1, 12));
      expect(data.skipped, 0);
      expect(data.sessions.map((s) => jsonEncode(s.toJson())),
          sessions.map((s) => jsonEncode(s.toJson())));
      final s = data.sessions.first;
      expect(s.favorite, isTrue);
      expect(s.settings.uma, [30, 10, -10, -30]);
      expect(s.records.first.edited, isTrue);
      expect(s.settledSticks, 1);
      expect(s.previous, isNotNull); // 元に戻すの履歴も入っている
    });

    test('ルール設定も書き出して読み込める。入っていない・壊れている場合は null', () {
      const rules = GameSettings(kuitan: false, doubleRon: false, startingPoints: 30000);
      final data = BackupCodec.decode(BackupCodec.encode([game('1')], defaultSettings: rules));
      expect(data.defaultSettings!.kuitan, isFalse);
      expect(data.defaultSettings!.doubleRon, isFalse);
      expect(data.defaultSettings!.startingPoints, 30000);

      expect(BackupCodec.decode(BackupCodec.encode([game('1')])).defaultSettings, isNull);

      final broken = jsonDecode(BackupCodec.encode([game('1')], defaultSettings: rules))
          as Map<String, dynamic>
        ..['defaultSettings'] = {'startingPoints': '壊れた値'};
      final b = BackupCodec.decode(jsonEncode(broken));
      expect(b.defaultSettings, isNull);
      expect(b.sessions, hasLength(1)); // 対局は読み込める
    });

    test('このアプリのバックアップでないものは読み込まない', () {
      expect(() => BackupCodec.decode('こんにちは'), throwsA(isA<BackupFormatException>()));
      expect(() => BackupCodec.decode('{"app":"other","kind":"backup","version":3,"sessions":[]}'),
          throwsA(isA<BackupFormatException>()));
      expect(() => BackupCodec.decode('{"app":"mahjong_score_app","kind":"backup","version":3}'),
          throwsA(isA<BackupFormatException>()));
    });

    test('新しいバージョンのバックアップは読み込まない', () {
      final text = jsonEncode({
        'app': BackupCodec.appId,
        'kind': BackupCodec.kind,
        'version': SharedPrefsSessionRepository.formatVersion + 1,
        'sessions': [],
      });
      expect(
          () => BackupCodec.decode(text),
          throwsA(isA<BackupFormatException>()
              .having((e) => e.message, 'message', contains('最新版'))));
    });

    test('壊れた対局は飛ばし、同じ対局が2つあれば1つにする', () {
      final ok = game('1').toJson();
      final text = jsonEncode({
        'app': BackupCodec.appId,
        'kind': BackupCodec.kind,
        'version': 3,
        'sessions': [ok, ok, {'id': '壊れた対局'}],
      });
      final data = BackupCodec.decode(text);
      expect(data.sessions, hasLength(1));
      expect(data.skipped, 1);
    });

    test('追加の見込み（すでにある対局は数えない）', () {
      final plan = BackupCodec.planMerge([game('1'), game('2')], [game('2'), game('3')]);
      expect(plan.added.map((s) => s.id), ['3']);
      expect(plan.duplicates, 1);
    });

    test('ファイル名', () {
      expect(BackupCodec.fileName(DateTime(2026, 11, 4, 9, 5)), 'mahjong_backup_20261104_0905.json');
    });

    test('バックアップを勧めるタイミング', () {
      final now = DateTime(2026, 11, 30);
      expect(shouldRecommendBackup(0, null, now: now), isFalse);
      expect(shouldRecommendBackup(1, null, now: now), isTrue);
      expect(shouldRecommendBackup(1, DateTime(2026, 11, 10), now: now), isFalse);
      expect(shouldRecommendBackup(1, DateTime(2026, 10, 31), now: now), isTrue);
    });
  });

  group('データへの反映', () {
    test('追加: すでにある対局は今のデータを残し、新しい順に並べる', () {
      final repo = InMemorySessionRepository([game('2', day: 2)]);
      final c = ProviderContainer(overrides: [sessionRepositoryProvider.overrideWithValue(repo)]);
      addTearDown(c.dispose);
      final n = c.read(sessionsProvider.notifier);
      n.toggleFavorite('2'); // 今のデータ側だけお気に入り
      final added = n.importSessions([game('1', day: 1), game('2', day: 2), game('3', day: 3)],
          replace: false);
      expect(added, 2);
      final list = c.read(sessionsProvider);
      expect(list.map((s) => s.id), ['3', '2', '1']);
      expect(list[1].favorite, isTrue);
    });

    test('置き換え: 今のデータはなくなる', () async {
      final repo = InMemorySessionRepository([game('9')]);
      final c = ProviderContainer(overrides: [sessionRepositoryProvider.overrideWithValue(repo)]);
      addTearDown(c.dispose);
      c.read(sessionsProvider.notifier).importSessions([game('1')], replace: true);
      expect(c.read(sessionsProvider).map((s) => s.id), ['1']);
      await Future<void>.delayed(Duration.zero);
      expect(repo.saved.map((s) => s.id), ['1']); // 保存もされる
    });
  });

  group('画面', () {
    late FakeFileService files;
    late InMemorySessionRepository repo;

    Future<ProviderContainer> pump(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1400));
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sessionRepositoryProvider.overrideWithValue(repo),
          backupFileServiceProvider.overrideWithValue(files),
        ],
        child: const MaterialApp(home: BackupScreen()),
      ));
      return ProviderScope.containerOf(tester.element(find.byType(BackupScreen)));
    }

    setUp(() {
      files = FakeFileService();
      repo = InMemorySessionRepository([game('1'), game('2', day: 2)]);
    });

    testWidgets('ファイルに保存すると、最後のバックアップ日時が記録される', (tester) async {
      await pump(tester);
      expect(find.text('まだバックアップしていません'), findsOneWidget);
      await tester.tap(find.text('ファイルに保存'));
      await tester.pumpAndSettle();
      expect(files.savedName, startsWith('mahjong_backup_'));
      expect(BackupCodec.decode(files.saved!).sessions, hasLength(2));
      expect(find.textContaining('最後のバックアップ:'), findsOneWidget);
      expect(repo.lastBackupAt, isNotNull);
    });

    testWidgets('ファイルから読み込んで追加できる', (tester) async {
      files.toPick = BackupCodec.encode([game('2', day: 2), game('3', day: 3)]);
      final c = await pump(tester);
      await tester.tap(find.text('ファイルから読み込む'));
      await tester.pumpAndSettle();
      expect(find.textContaining('新しく 1件を追加します'), findsOneWidget);
      expect(find.textContaining('すでにある 1件'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '追加'));
      await tester.pumpAndSettle();
      expect(c.read(sessionsProvider).map((s) => s.id), ['3', '2', '1']);
      expect(find.textContaining('1件の対局を追加しました'), findsOneWidget);
    });

    testWidgets('すべて置き換えは、もう一度確認してから行う', (tester) async {
      files.toPick = BackupCodec.encode([game('5')]);
      final c = await pump(tester);
      await tester.tap(find.text('ファイルから読み込む'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'すべて置き換え'));
      await tester.pumpAndSettle();
      expect(find.textContaining('今ある対局 2件はすべて削除され'), findsOneWidget);
      await tester.tap(find.text('置き換える'));
      await tester.pumpAndSettle();
      expect(c.read(sessionsProvider).map((s) => s.id), ['5']);
    });

    testWidgets('別のファイルを選ぶと理由を表示し、何も変えない', (tester) async {
      files.toPick = '{"hello": "world"}';
      final c = await pump(tester);
      await tester.tap(find.text('ファイルから読み込む'));
      await tester.pumpAndSettle();
      expect(find.text('読み込めませんでした'), findsOneWidget);
      expect(find.text('このアプリのバックアップではありません。'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(c.read(sessionsProvider), hasLength(2));
    });

    testWidgets('書き出したファイルにルール設定も入る', (tester) async {
      repo.defaultSettings = const GameSettings(kuitan: false);
      await pump(tester);
      await tester.tap(find.text('ファイルに保存'));
      await tester.pumpAndSettle();
      expect(BackupCodec.decode(files.saved!).defaultSettings!.kuitan, isFalse);
    });

    testWidgets('「ルール設定も読み込む」にチェックがあればルール設定も変わる', (tester) async {
      files.toPick = BackupCodec.encode([game('1')], // すでにある対局だけ
          defaultSettings: const GameSettings(kuitan: false, tonpuu: true));
      final c = await pump(tester);
      await tester.tap(find.text('ファイルから読み込む'));
      await tester.pumpAndSettle();
      expect(find.text('ルール設定も読み込む'), findsOneWidget);
      // 追加する対局がなくても、ルール設定だけ読み込める
      await tester.tap(find.widgetWithText(FilledButton, '追加'));
      await tester.pumpAndSettle();
      expect(c.read(defaultSettingsProvider).kuitan, isFalse);
      expect(c.read(defaultSettingsProvider).tonpuu, isTrue);
      expect(repo.defaultSettings!.kuitan, isFalse); // 端末にも保存される
      expect(find.textContaining('ルール設定も読み込みました'), findsOneWidget);
    });

    testWidgets('チェックを外すと今のルール設定のまま', (tester) async {
      files.toPick = BackupCodec.encode([game('3', day: 3)],
          defaultSettings: const GameSettings(kuitan: false));
      final c = await pump(tester);
      await tester.tap(find.text('ファイルから読み込む'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ルール設定も読み込む'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '追加'));
      await tester.pumpAndSettle();
      expect(c.read(sessionsProvider), hasLength(3));
      expect(c.read(defaultSettingsProvider).kuitan, isTrue);
    });

    testWidgets('ルール設定の入っていない以前のバックアップは、そのことを表示して対局だけ読み込む', (tester) async {
      files.toPick = BackupCodec.encode([game('3', day: 3)]);
      final c = await pump(tester);
      await tester.tap(find.text('ファイルから読み込む'));
      await tester.pumpAndSettle();
      expect(find.text('ルール設定も読み込む'), findsNothing);
      expect(find.textContaining('ルール設定が入っていない'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '追加'));
      await tester.pumpAndSettle();
      expect(c.read(sessionsProvider), hasLength(3));
    });

    testWidgets('テキストを貼り付けて読み込める', (tester) async {
      repo = InMemorySessionRepository();
      final c = await pump(tester);
      await tester.tap(find.text('テキストを貼り付けて読み込む'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), BackupCodec.encode([game('7')]));
      await tester.tap(find.text('読み込む'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '追加'));
      await tester.pumpAndSettle();
      expect(c.read(sessionsProvider).map((s) => s.id), ['7']);
    });
  });
}
