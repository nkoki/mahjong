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

class MahjongApp extends StatelessWidget {
  const MahjongApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '麻雀点数計算',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      debugShowCheckedModeBanner: false,
      home: const HomeScreen(),
    );
  }
}
