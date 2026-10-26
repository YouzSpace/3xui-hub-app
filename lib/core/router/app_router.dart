import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/announcements/announcements_page.dart';
import '../../features/auth/login_page.dart';
import '../../features/home/home_page.dart';
import '../../features/nodes/nodes_page.dart';
import '../../features/nodes/nodes_routes.dart';
import '../../features/payment/payment_webview_page.dart';
import '../../features/plans/order_history_page.dart';
import '../../features/plans/plans_page.dart';
import '../../features/plans/plans_routes.dart';
import '../../features/settings/my_info_page.dart';
import '../../features/settings/settings_page.dart';
import '../../features/settings/settings_routes.dart';
import '../../features/settings/split_tunnel_page.dart';
import '../../features/shell/app_shell.dart';
import '../../features/tutorials/tutorial_detail_page.dart';
import '../../features/tutorials/tutorials_page.dart';
import '../../providers/auth_providers.dart';
import 'transitions.dart';

/// 路由表（T1.6 + T2.5）：
/// - /login：真实登录页
/// - /（StatefulShellRoute.indexedStack：/home /nodes /plans /invite /settings）
/// - 二级：/orders /tutorials /tutorials/:id /payment /split-tunnel
///
/// redirect：无 token 且非 /login → /login；有 token 且在 /login → /home。
/// token 状态来自 tokenProvider（main 里已从 TokenStore 回填）。
final GoRouter appRouter = GoRouter(
  initialLocation: '/home',
  redirect: (context, state) {
    final token = providerContainer.read(tokenProvider);
    final loggedIn = token != null && token.isNotEmpty;
    final loggingIn = state.matchedLocation == '/login';
    if (!loggedIn && !loggingIn) return '/login';
    if (loggedIn && loggingIn) return '/home';
    // 无套餐不显示节点 tab，也禁止深链直达 /nodes（user 未加载时不拦截）。
    final user = providerContainer.read(userProvider).valueOrNull;
    if (user != null && user.planId == 0 && state.matchedLocation == '/nodes') {
      return '/home';
    }
    return null;
  },
  refreshListenable: _TokenListenable(providerContainer),
  routes: [
    GoRoute(
      path: '/login',
      pageBuilder: (context, state) =>
          AppTransitions.fadeLift(state: state, child: const LoginPage()),
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AppShell(shell: shell),
      branches: [
        StatefulShellBranch(routes: [_fadeRoute('/home', const HomePage())]),
        StatefulShellBranch(routes: [_fadeRoute(NodesRoutes.nodes, const NodesPage())]),
        StatefulShellBranch(
            routes: [_fadeRoute(SettingsRoutes.settings, const SettingsPage())]),
      ],
    ),
    GoRoute(
      path: PlansRoutes.plans,
      pageBuilder: (context, state) => AppTransitions.slideFromRight(
          state: state, child: const PlansPage()),
    ),
    GoRoute(
      path: PlansRoutes.payment,
      pageBuilder: (context, state) => AppTransitions.slideFromRight(
          state: state, child: PaymentWebviewPage(args: state.extra as PaymentArgs?)),
    ),
    GoRoute(
      path: PlansRoutes.orders,
      pageBuilder: (context, state) => AppTransitions.slideFromRight(
          state: state, child: const OrderHistoryPage()),
    ),
    GoRoute(
      path: SettingsRoutes.tutorials,
      pageBuilder: (context, state) => AppTransitions.slideFromRight(
          state: state, child: const TutorialsPage()),
    ),
    GoRoute(
      path: '/tutorials/:id',
      pageBuilder: (context, state) {
        final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
        return AppTransitions.slideFromRight(
            state: state, child: TutorialDetailPage(id: id));
      },
    ),
    GoRoute(
      path: SettingsRoutes.splitTunnel,
      pageBuilder: (context, state) => AppTransitions.slideFromRight(
          state: state, child: const SplitTunnelPage()),
    ),
    GoRoute(
      path: SettingsRoutes.myInfo,
      pageBuilder: (context, state) => AppTransitions.slideFromRight(
          state: state, child: const MyInfoPage()),
    ),
    GoRoute(
      path: '/announcements',
      pageBuilder: (context, state) => AppTransitions.slideFromRight(
          state: state, child: const AnnouncementsPage()),
    ),
  ],
);

/// shell 分支页：淡入切换（与 M1 一致）。
GoRoute _fadeRoute(String path, Widget child) {
  return GoRoute(
    path: path,
    pageBuilder: (context, state) =>
        AppTransitions.fadeLift(state: state, child: child),
  );
}

/// token 变化时刷新路由守卫（登录成功 / 登出 / 401 都会触发）。
class _TokenListenable extends ChangeNotifier {
  _TokenListenable(ProviderContainer container) {
    container.listen<String?>(tokenProvider, (prev, next) {
      notifyListeners();
    });
  }
}
