import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_config.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/splash/splash_screen.dart';
import 'providers/theme_mode_provider.dart';

/// 应用根（M1）：AppTheme 亮/暗 + go_router。
///
/// themeMode 来自 [themeModeProvider]（M8 T8.3）：设置页切换后立即生效，
/// 值持久化在 prefs 的 `theme_mode`，重启保持。
class ControlHubApp extends ConsumerStatefulWidget {
  const ControlHubApp({super.key});

  @override
  ConsumerState<ControlHubApp> createState() => _ControlHubAppState();
}

class _ControlHubAppState extends ConsumerState<ControlHubApp> {
  bool _showSplash = true;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      // 最近任务卡片（手机后台任务列表）显示的名字：白标品牌名 >
      // 编译默认名。真正的 App 内标题走站点配置，不走这里。
      title: AppConfig.appName.isEmpty ? 'ControlHub' : AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: appRouter,
      // builder 在 MaterialApp 内部（自带 Directionality + Theme），
      // 开屏动画叠在路由之上，淡出后移除露出首页/登录页。
      builder: (context, child) => Stack(
        children: [
          ?child,
          if (_showSplash)
            SplashScreen(
              onDone: () {
                if (mounted) setState(() => _showSplash = false);
              },
            ),
        ],
      ),
    );
  }
}
