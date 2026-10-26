import 'package:flutter/material.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

/// 应用根（M1）：AppTheme 亮/暗 + go_router。
///
/// themeMode 固定 system，M8 设置页接 themeModeProvider 后改为可切。
class ControlHubApp extends StatelessWidget {
  const ControlHubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'ControlHub',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: appRouter,
    );
  }
}
