import 'package:go_router/go_router.dart';

import '../../core/router/transitions.dart';
import 'my_info_page.dart';
import 'settings_page.dart';
import 'split_tunnel_page.dart';

/// M8 路由（T8.1–T8.5）。
///
/// 边界铁律：本模块只导出 `List<GoRoute>`，**绝不改** `lib/core/router/app_router.dart`
/// —— 并行期间其他 agent 也在改它，汇总方把 [settingsRoutes] 拼进总表即可。
///
/// 路径与 `app_router.dart` 现有占位页一致，汇总时直接替换：
/// - `/settings`    设置（Tab 分支）
/// - `/split-tunnel` 分应用代理（二级页）
/// - `/my-info`     我的信息（二级页）
/// - `/tutorials`   教程（M7 的页面，这里只借路径做跳转，不注册）
abstract class SettingsRoutes {
  static const settings = '/settings';
  static const splitTunnel = '/split-tunnel';
  static const myInfo = '/my-info';
  static const tutorials = '/tutorials';

  /// 退出登录后跳转目标（app_router 已有 /login）。
  static const login = '/login';
}

/// M8 的所有路由，交给汇总方拼进 `app_router.dart`。
final List<GoRoute> settingsRoutes = [
  GoRoute(
    path: SettingsRoutes.settings,
    pageBuilder: (context, state) =>
        AppTransitions.fadeLift(state: state, child: const SettingsPage()),
  ),
  GoRoute(
    path: SettingsRoutes.splitTunnel,
    pageBuilder: (context, state) => AppTransitions.slideFromRight(
      state: state,
      child: const SplitTunnelPage(),
    ),
  ),
  GoRoute(
    path: SettingsRoutes.myInfo,
    pageBuilder: (context, state) =>
        AppTransitions.slideFromRight(state: state, child: const MyInfoPage()),
  ),
];
