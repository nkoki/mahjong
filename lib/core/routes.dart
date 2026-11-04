import 'package:flutter/material.dart';

import '../features/session/screens/dashboard_screen.dart';

/// ダッシュボードのルート名（和了・流局入力後にここまで戻る）
const dashboardRouteName = 'dashboard';

Route<void> dashboardRoute(String sessionId) => MaterialPageRoute(
      settings: const RouteSettings(name: dashboardRouteName),
      builder: (_) => DashboardScreen(sessionId: sessionId),
    );

/// ダッシュボードまで戻る
void popToDashboard(BuildContext context) {
  Navigator.of(context)
      .popUntil((r) => r.settings.name == dashboardRouteName || r.isFirst);
}
