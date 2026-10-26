import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/prefs.dart';
import '../../providers/auth_providers.dart';
import '../../vpn/vpn_controller.dart';
import 'settings_providers.dart';

/// 退出登录（T8.4）。顺序是硬要求，任何一步失败都不阻断后续清理：
///
/// 1. 断开 VPN —— 必须先断，否则用户以为退了、隧道还在跑（流量泄漏）
/// 2. 清 token（安全存储 + 内存）
/// 3. 清用户缓存（`/api/me`、站点配置）
/// 4. 清订阅缓存（选中节点等）
///
/// **不清**：主题模式（`theme_mode`）、分应用代理（`blocked_apps`）——
/// 换账号后这些属于本机偏好，与账号无关。
///
/// 每一步都可注入，单测据此断言调用顺序。
class LogoutService {
  LogoutService({
    required this.disconnectVpn,
    required this.clearToken,
    required this.clearUserCache,
    required this.clearSubscriptionCache,
  });

  final Future<void> Function() disconnectVpn;
  final Future<void> Function() clearToken;
  final Future<void> Function() clearUserCache;
  final Future<void> Function() clearSubscriptionCache;

  /// 执行退出；按顺序调用，单步异常被吞掉并继续（清理比报错重要）。
  Future<void> run() async {
    await _guard(disconnectVpn);
    await _guard(clearToken);
    await _guard(clearUserCache);
    await _guard(clearSubscriptionCache);
  }

  Future<void> _guard(Future<void> Function() step) async {
    try {
      await step();
    } catch (_) {
      // 单步失败继续下一步：断 VPN 失败也一定要清掉 token。
    }
  }
}

/// 退出登录服务（真实依赖）。测试可 override 注入记录顺序的桩。
final logoutServiceProvider = Provider<LogoutService>((ref) {
  return LogoutService(
    disconnectVpn: () => ref.read(vpnProvider.notifier).disconnect(),
    clearToken: () => ref.read(tokenProvider.notifier).clear(),
    clearUserCache: () async {
      await Prefs.clearCache();
      // 让 userProvider 立刻回到「无用户」态，避免首页残留上一个账号的数据。
      ref.invalidate(userProvider);
    },
    clearSubscriptionCache: () => ref.read(subscriptionCacheClearerProvider)(),
  );
});
