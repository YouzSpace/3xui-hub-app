import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/storage/prefs.dart';
import 'settings_repository.dart';
import 'site_config.dart';

/// 设置仓库 Provider（测试可 override 注入桩）。
final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(),
);

/// 站点配置 Provider（T8.1 关于分组用）。
///
/// 先出 prefs 缓存（首帧就有站点名，不闪），再拉网络覆盖；
/// 网络失败保留缓存，完全没数据时返回空配置（页面显示占位，不报错）。
final siteConfigProvider = FutureProvider<SiteConfig>((ref) async {
  final cached = SiteConfig.decode(await _readSiteConfigCache());
  try {
    return await ref.read(settingsRepositoryProvider).fetchSiteConfig();
  } catch (_) {
    return cached;
  }
});

Future<String?> _readSiteConfigCache() async {
  try {
    return await Prefs.getCacheSiteConfig();
  } catch (_) {
    return null;
  }
}

/// 本机版本（T8.5）：`package_info_plus` 读 pubspec 的 version/buildNumber。
final localVersionProvider = FutureProvider<LocalAppVersion>((ref) async {
  try {
    final info = await PackageInfo.fromPlatform();
    return LocalAppVersion(
      versionName: info.version,
      buildNumber: info.buildNumber,
    );
  } catch (_) {
    // 平台通道不可用（单测/桌面调试）：不阻塞设置页，显示占位。
    return const LocalAppVersion(versionName: '', buildNumber: '');
  }
});

/// 展示用版本信息，`v1.0.0 (1)` 由 [label] 统一拼（T8.5 验收口径）。
class LocalAppVersion {
  const LocalAppVersion({required this.versionName, required this.buildNumber});

  final String versionName;
  final String buildNumber;

  bool get isEmpty => versionName.isEmpty;

  String get label => isEmpty
      ? '—'
      : 'v$versionName${buildNumber.isEmpty ? '' : ' ($buildNumber)'}';
}

/// 订阅缓存清理钩子（T8.4 第 4 步）。
///
/// 当前订阅相关持久化只有「选中节点」（`Prefs.keySelectedNode`），M3 落地后
/// 若新增订阅正文缓存，override 本 Provider 把那些键一起删即可。
final subscriptionCacheClearerProvider = Provider<Future<void> Function()>(
  (ref) => clearSubscriptionCache,
);

/// 清订阅缓存（**不清**主题、**不清**分应用代理）。
///
/// 订阅相关持久化有「选中节点」与「节点测速结果」；键名仍从 [Prefs] 取，不新增字面量。
Future<void> clearSubscriptionCache() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(Prefs.keySelectedNode);
    await prefs.remove(Prefs.keyNodeLatency);
  } catch (_) {
    // 清缓存失败不该阻断退出/切换流程：下次拉订阅会覆盖旧值。
  }
}
