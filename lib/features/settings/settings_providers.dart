import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/storage/prefs.dart';
import '../../data/models/user_profile.dart';
import '../../vpn/vpn_controller.dart';
import '../nodes/nodes_provider.dart';
import '../../vpn/vpn_state.dart';
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

/// 当前是否已连接（保存分应用代理后判断要不要提示「重新连接后生效」）。
///
/// 单独一层 Provider 便于 widget 测试直接 override 连接态，不必造 VPN 引擎。
final vpnConnectedProvider = Provider<bool>((ref) {
  return ref.watch(vpnProvider.select((s) => s.status == VpnStatus.connected));
});

/// 可切换的协议（后端 `POST /api/protocol` 只接受这两个值）。
const List<String> kSwitchableProtocols = ['vless', 'trojan'];

/// 协议显示名（后端返回小写）。
String protocolLabel(String protocol) {
  switch (protocol) {
    case 'vless':
      return 'VLESS';
    case 'trojan':
      return 'Trojan';
    default:
      return protocol.isEmpty ? '—' : protocol.toUpperCase();
  }
}

/// 协议切换入口是否显示（system-design §3.10 / proposal F8）。
///
/// 后端目前**没有**「站点支持多协议」字段（`/api/site-config` 白名单里没有），
/// 因此规则是：用户当前协议属于可切换集合（vless/trojan）就显示；
/// 若站点将来下发 `protocol_switch_enabled == "0"` 则强制隐藏，给站点留关闭口。
bool supportsProtocolSwitch(UserProfile? user, SiteConfig config) {
  if (config.values['protocol_switch_enabled'] == '0') return false;
  return kSwitchableProtocols.contains(user?.protocol ?? '');
}

/// 当前协议之外的可选项（切换弹层用）。
List<String> protocolAlternatives(String current) =>
    kSwitchableProtocols.where((p) => p != current).toList();

/// 订阅重拉钩子（协议切换后调用）。
///
/// M3 的 `nodesProvider` 已落地，直接调它的 `refresh()`（重拉订阅正文 +
/// 重新解析 + 对齐选中节点）；设置页只依赖这个 hook，不直接依赖 M3 的类。
final subscriptionRefresherProvider = Provider<Future<void> Function()?>(
  (ref) => () => ref.read(nodesProvider.notifier).refresh(),
);

/// 订阅缓存清理钩子（T8.4 第 4 步 / 协议切换后清缓存）。
///
/// 当前订阅相关持久化只有「选中节点」（`Prefs.keySelectedNode`），M3 落地后
/// 若新增订阅正文缓存，override 本 Provider 把那些键一起删即可。
final subscriptionCacheClearerProvider = Provider<Future<void> Function()>(
  (ref) => clearSubscriptionCache,
);

/// 清订阅缓存（**不清**主题、**不清**分应用代理）。
///
/// 订阅相关持久化目前只有「选中节点」；键名仍从 [Prefs] 取，不新增字面量。
Future<void> clearSubscriptionCache() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(Prefs.keySelectedNode);
  } catch (_) {
    // 清缓存失败不该阻断退出/切换流程：下次拉订阅会覆盖旧值。
  }
}
