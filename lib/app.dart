import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'providers/theme_mode_provider.dart';

/// 应用根（M1）：AppTheme 亮/暗 + go_router。
///
/// themeMode 来自 [themeModeProvider]（M8 T8.3）：设置页切换后立即生效，
/// 值持久化在 prefs 的 `theme_mode`，重启保持。
class ControlHubApp extends ConsumerWidget {
  const ControlHubApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'ControlHub',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: appRouter,
    );
  }
}
