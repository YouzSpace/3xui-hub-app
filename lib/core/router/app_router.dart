import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/login_page.dart';
import '../../features/home/home_page.dart';
import '../../features/shell/app_shell.dart';
import '../../providers/auth_providers.dart';
import '../ui/state_views.dart';
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
        StatefulShellBranch(routes: [_shellRoute('/', const HomePage())]),
        StatefulShellBranch(routes: [_shellRoute('/nodes', null, '节点', Icons.dns_outlined)]),
        StatefulShellBranch(routes: [_shellRoute('/plans', null, '套餐', Icons.storefront_outlined)]),
        StatefulShellBranch(routes: [_shellRoute('/invite', null, '邀请', Icons.card_giftcard)]),
        StatefulShellBranch(routes: [_shellRoute('/settings', null, '我的', Icons.person_outline)]),
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

/// 一个 shell 分支（带标题/图标的是占位页，M5-M8 各自实现）。
GoRoute _shellRoute(String path, Widget? child, [String? title, IconData? icon]) {
  return GoRoute(
    path: path,
    pageBuilder: (context, state) => AppTransitions.fadeLift(
      state: state,
      child: child ??
          _PlaceholderPage(title ?? '', icon: icon),
    ),
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

/// M2-M8 各功能页的占位。
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
