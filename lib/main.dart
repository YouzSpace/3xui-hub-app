import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/api_config.dart';
import 'providers/auth_providers.dart';
import 'vpn/bypass_china.dart';
import 'vpn/vpn_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 隐藏入口存的地址覆盖（通常为空 → 用编译常量），必须在 runApp 前完成，
  // 保证首个请求就拿到的最终值。
  // 启动读操作并行：地址覆盖（prefs）+ assets 地址 + token 回填（secure storage）
  // 互不依赖，串行会白白多等存储 I/O。任一失败都不阻塞启动。
  try {
    await Future.wait([
      ApiConfig.loadOverride(),
      ApiConfig.loadAssetsBase(),
      initTokenState(),
    ]);
  } catch (_) {
    // 读失败退回内置地址 / 视为未登录。
  }
  // M4：VPN 引擎初始化（幂等）放后台，不阻塞 runApp 造成启动白屏；
  // 首次连接前 controller 还会再调一次 initialize（幂等，重复调用无害）。
  unawaited(() async {
    try {
      await providerContainer.read(vpnEngineProvider).initialize();
    } catch (_) {}
  }());
  // 「绕开国内」开关回填，不阻塞启动。
  unawaited(providerContainer.read(bypassChinaProvider.notifier).restore());
  runApp(UncontrolledProviderScope(
    container: providerContainer,
    child: const ControlHubApp(),
  ));
}
