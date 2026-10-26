import 'package:flutter/material.dart';

import 'app.dart';
import 'core/config/api_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 隐藏入口存的地址覆盖（通常为空 → 用编译常量），必须在 runApp 前完成，
  // 保证首个请求就拿到的 base 是最终值。
  try {
    await ApiConfig.loadOverride();
  } catch (_) {
    // prefs 读失败不阻塞启动：退回内置地址。
  }
  runApp(const ControlHubApp());
}
