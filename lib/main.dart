import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/theme.dart';
import 'features/session/data/session_repository.dart';
import 'features/session/screens/home_screen.dart';
import 'features/session/session_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 端末に保存した対局データを読み込めるように準備
  final prefs = await SharedPreferences.getInstance();
  runApp(ProviderScope(
    overrides: [
      sessionRepositoryProvider
          .overrideWithValue(SharedPrefsSessionRepository(prefs)),
    ],
    child: const MahjongApp(),
  ));
}

class MahjongApp extends ConsumerStatefulWidget {
  const MahjongApp({super.key});

  @override
  ConsumerState<MahjongApp> createState() => _MahjongAppState();
}

class _MahjongAppState extends ConsumerState<MahjongApp> {
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  Widget build(BuildContext context) {
    // 保存に失敗したら、どの画面にいてもお知らせする
    ref.listen<String?>(saveErrorProvider, (prev, next) {
      if (next != null && prev == null) {
        _messengerKey.currentState?.showSnackBar(SnackBar(
          content: Text(next),
          duration: const Duration(seconds: 8),
          showCloseIcon: true,
        ));
      }
    });
    return MaterialApp(
      scaffoldMessengerKey: _messengerKey,
      title: '麻雀点数計算',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      debugShowCheckedModeBanner: false,
      home: const HomeScreen(),
    );
  }
}
