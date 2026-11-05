import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';

/// バックアップファイルの保存・選択（テストでは差し替える）
abstract class BackupFileService {
  /// ファイルに保存する。保存できたら true、利用者がキャンセルしたら false。
  /// [dialogTitle] が空なら「バックアップの保存先」
  Future<bool> save(String fileName, String content, {String dialogTitle = ''});

  /// ファイルを選んで中身を読み込む。キャンセルしたら null
  Future<String?> pick();
}

/// file_picker を使った実装
/// - Android / iOS: 保存先を選ぶ画面が開く（「ファイル」アプリ・Google ドライブなど）
/// - Web: ダウンロードとして保存される
class FilePickerBackupFileService implements BackupFileService {
  const FilePickerBackupFileService();

  @override
  Future<bool> save(String fileName, String content, {String dialogTitle = ''}) async {
    final path = await FilePicker.saveFile(
      dialogTitle: dialogTitle.isEmpty ? tr('バックアップの保存先', 'Save backup to') : dialogTitle,
      fileName: fileName,
      bytes: Uint8List.fromList(utf8.encode(content)),
    );
    // Web はダウンロードを始めるだけで、常に null が返る
    return kIsWeb || path != null;
  }

  @override
  Future<String?> pick() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: tr('バックアップファイルを選択', 'Select a backup file'),
      withData: true,
    );
    final bytes = result?.files.single.bytes;
    if (bytes == null) return null;
    return utf8.decode(bytes, allowMalformed: true);
  }
}

final backupFileServiceProvider =
    Provider<BackupFileService>((ref) => const FilePickerBackupFileService());
