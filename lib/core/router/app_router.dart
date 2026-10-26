import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/shell/app_shell.dart';
import '../storage/token_store.dart';
import '../ui/state_views.dart';
import 'transitions.dart';

/// 认证占位（M2 接真认证）。
///
/// M1 占位实现：直接读 TokenStore。M2 换成「校验 /api/me、401 时清 token」
/// 的真实 provider，只需重赋值这一个变量，路由代码不用改。
typedef TokenProvider = Future<String?> Function();

TokenProvider tokenProvider = () => TokenStore.read();

/// 登录占位页（M2 实现）。
class _LoginPage extends StatelessWidget {
  const _LoginPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('登录')),
      body: const Center(
        child: EmptyView(
          icon: Icons.lock_outline,
          text: '登录功能将在 M2 阶段实现',
        ),
      ),
    );
  }
}

/// 路由表（T1.6）：
/// - `/login`
/// - `/`（StatefulShellRoute.indexedStack：/home /nodes /plans /invite /settings）
/// - 二级：/orders /tutorials /tutorials/:id /payment /split-tunnel
///
/// redirect：无 token 且非 /login → /login；有 token 且在 /login → /home。
final GoRouter appRouter = GoRouter(
  initialLocation: '/home',
  redirect: (context, state) async {
    final token = await tokenProvider();
    final loggedIn = token != null && token.isNotEmpty;
    final loggingIn = state.matchedLocation == '/login';
    if (!loggedIn && !loggingIn) return '/login';
    if (loggedIn && loggingIn) return '/home';
    return null;
  },
  routes: [
    GoRoute(
      path: '/login',
      pageBuilder: (context, state) =>
          AppTransitions.fadeLift(state: state, child: const _LoginPage()),
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AppShell(shell: shell),
      branches: [
        StatefulShellBranch(routes: [_shellRoute('/home', '首页', Icons.home_outlined)]),
        StatefulShellBranch(routes: [_shellRoute('/nodes', '节点', Icons.dns_outlined)]),
        StatefulShellBranch(routes: [_shellRoute('/plans', '套餐', Icons.storefront_outlined)]),
        StatefulShellBranch(routes: [_shellRoute('/invite', '邀请', Icons.card_giftcard)]),
        StatefulShellBranch(routes: [_shellRoute('/settings', '我的', Icons.person_outline)]),
      ],
    ),
    GoRoute(
      path: '/orders',
      pageBuilder: (context, state) => AppTransitions.slideFromRight(
          state: state, child: const _PlaceholderPage('订单记录')),
    ),
    GoRoute(
      path: '/tutorials',
      pageBuilder: (context, state) => AppTransitions.slideFromRight(
          state: state, child: const _PlaceholderPage('使用教程')),
    ),
    GoRoute(
      path: '/tutorials/:id',
      pageBuilder: (context, state) => AppTransitions.slideFromRight(
          state: state,
          child: _PlaceholderPage('教程详情 #${state.pathParameters['id']}')),
    ),
    GoRoute(
      path: '/payment',
      pageBuilder: (context, state) => AppTransitions.slideFromRight(
          state: state, child: const _PlaceholderPage('支付')),
    ),
    GoRoute(
      path: '/split-tunnel',
      pageBuilder: (context, state) => AppTransitions.slideFromRight(
          state: state, child: const _PlaceholderPage('分应用代理')),
    ),
  ],
);

/// 一个 shell 分支（M5-M8 各自实现页面，这里先挂占位页）。
GoRoute _shellRoute(String path, String title, IconData icon) {
  return GoRoute(
    path: path,
    pageBuilder: (context, state) => AppTransitions.fadeLift(
        state: state, child: _PlaceholderPage(title, icon: icon)),
  );
}

/// M2-M8 各功能页的占位（本任务只做 M1 基础设施）。
class _PlaceholderPage extends StatelessWidget {
  final String title;
  final IconData? icon;

  const _PlaceholderPage(this.title, {this.icon});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: EmptyView(
        icon: icon ?? Icons.construction,
        text: '$title页面将在后续阶段实现',
      ),
    );
  }
}
