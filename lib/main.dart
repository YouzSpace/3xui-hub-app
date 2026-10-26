import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/api_config.dart';
import 'providers/auth_providers.dart';
import 'vpn/blocked_apps.dart';
import 'vpn/vpn_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 隐藏入口存的地址覆盖（通常为空 → 用编译常量），必须在 runApp 前完成，
  // 保证首个请求就拿到的最终值。
  try {
    await ApiConfig.loadOverride();
  } catch (_) {
    // prefs 读失败不阻塞启动：退回内置地址。
  }
  // M2：先从 TokenStore 回填 token 状态，再 runApp ——
  // GoRouter 首次 redirect 就能拿到持久化登录态（T2.5 杀进程重开仍登录）。
  await initTokenState();
  // M4：VPN 引擎初始化（幂等）。失败不阻塞启动：
  // 首次连接前 controller 还会再调一次 initialize。
  try {
    await providerContainer.read(vpnEngineProvider).initialize();
  } catch (_) {}
  // 分应用代理勾选回填，不阻塞启动（restore 内部已兜底空列表）。
  unawaited(providerContainer.read(blockedAppsProvider.notifier).restore());
  runApp(UncontrolledProviderScope(
    container: providerContainer,
    child: const ControlHubApp(),
  ));
}
