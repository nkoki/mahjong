import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/l10n.dart';
import 'core/theme.dart';
import 'features/about/data_sources.dart';
import 'features/session/data/session_repository.dart';
import 'features/session/screens/home_screen.dart';
import 'features/session/session_providers.dart';
import 'features/settings/display_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 横向きにすると画面の並びが崩れるので、縦向きに固定する（Web はブラウザが向きを決めるので、横向きのときはお知らせを出す）
  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }
  // 牌の認識モデルの学習データ（CC BY など）の出典をライセンス画面に載せる
  registerDataSourceLicenses();
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
    final textScale = ref.watch(textScaleProvider);
    // 言語を切り替えたら、アプリ全体を作り直す（文字は tr() でその場で選ぶため）
    final lang = ref.watch(languageProvider);
    L10n.isEnglish = lang == AppLanguage.en;
    return MaterialApp(
      key: ValueKey(lang),
      scaffoldMessengerKey: _messengerKey,
      title: tr('麻雀点数計算', 'Mahjong Score'),
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      builder: (context, child) => PortraitOnly(child: applyTextScale(context, child, textScale)),
      debugShowCheckedModeBanner: false,
      home: const HomeScreen(),
    );
  }
}

/// 縦向きで使う画面。
///
/// アプリ版は縦向きに固定しているが、Web 版（特に iPhone の Safari）は向きを固定できないので、
/// スマホを横向きにしたとき（横長で、高さが足りないとき）は、崩れた画面の代わりに「縦向きにしてください」と出す。
/// パソコンのブラウザやタブレットのように高さが十分あれば、そのまま表示する。
class PortraitOnly extends StatelessWidget {
  final Widget child;

  /// 横向きのお知らせを出すかどうかを、向きだけで決める（テスト用。null なら Web のときだけ）
  final bool? enabled;

  const PortraitOnly({super.key, required this.child, this.enabled});

  /// この大きさのときにお知らせを出すか
  static bool isPhoneLandscape(Size size) => size.width > size.height && size.height < 500;

  @override
  Widget build(BuildContext context) {
    final on = enabled ?? kIsWeb;
    final show = on && isPhoneLandscape(MediaQuery.of(context).size);
    // 画面（と入力中の内容）は残したまま、上にお知らせを重ねる
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        if (show) _notice(context),
      ],
    );
  }

  Widget _notice(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: AppTheme.tableGreen,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.screen_rotation, size: 48, color: Color(0xFFF7F3EA)),
                const SizedBox(height: 12),
                Text(
                  tr('縦向きにしてください', 'Please rotate to portrait'),
                  key: const ValueKey('portrait-only'),
                  style: theme.textTheme.titleLarge?.copyWith(color: const Color(0xFFF7F3EA)),
                ),
                const SizedBox(height: 6),
                Text(
                  tr('このアプリは縦向きの画面で使います。入力中の内容は消えていません。',
                      'This app is used in portrait. Nothing you entered has been lost.'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: const Color(0xCCF7F3EA)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
