import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/prefs.dart';

/// 已安装第三方应用（分应用代理选择列表用）。
class InstalledApp {
  final String packageName;
  final String appName;

  const InstalledApp({required this.packageName, required this.appName});

  @override
  bool operator ==(Object other) =>
      other is InstalledApp && other.packageName == packageName;

  @override
  int get hashCode => packageName.hashCode;
}

/// 已安装第三方应用列表（Android 启动器有入口的应用，按名称排序）。
///
/// 通过自写 MethodChannel 从 PackageManager 拿（device_apps 插件久未维护，
/// 任务书允许自写通道）。非 Android 平台返回空列表，M8 UI 用空态兜底。
final installedAppsProvider = FutureProvider<List<InstalledApp>>((ref) async {
  const channel = MethodChannel('controlhub/installed_apps');
  try {
    final result = await channel.invokeMethod<List<dynamic>>('getInstalledApps');
    final apps = (result ?? const [])
        .whereType<Map>()
        .map((m) => InstalledApp(
              packageName: m['packageName']?.toString() ?? '',
              appName: m['appName']?.toString() ?? '',
            ))
        .where((a) => a.packageName.isNotEmpty && a.appName.isNotEmpty)
        .toList()
      ..sort((a, b) => a.appName.compareTo(b.appName));
    return apps;
  } on PlatformException {
    return const [];
  } on MissingPluginException {
    return const [];
  }
});

/// 分应用代理被排除的应用包名列表（用户勾选结果，prefs 持久化）。
///
/// 连接时透传给 engine.start(blockedApps: [...])；M8 做勾选 UI。
class BlockedAppsNotifier extends Notifier<List<String>> {
  @override
  List<String> build() => const [];

  /// 启动时从 prefs 回填一次。
  Future<void> restore() async {
    try {
      state = await Prefs.getBlockedApps();
    } catch (_) {
      state = const [];
    }
  }

  Future<void> setApps(List<String> apps) async {
    state = List.unmodifiable(apps);
    await Prefs.setBlockedApps(state);
  }
}

final blockedAppsProvider =
    NotifierProvider<BlockedAppsNotifier, List<String>>(BlockedAppsNotifier.new);
