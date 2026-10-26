import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/api_client.dart';

/// 版本决策（T9.6 / system-design §11）。
///
/// App 启动时拉取后台「App 版本」配置，在本地拿「最新版本名」与自身版本
/// 对比得出 [action]：`none` 静默、`optional` 可稍后、`force` 不可关闭。
class VersionDecision {
  const VersionDecision({
    required this.action,
    this.latestName,
    this.downloadUrl,
    this.notes,
  });

  /// none | optional | force。
  final String action;
  final String? latestName;
  final String? downloadUrl;

  /// 更新说明，换行分隔。
  final String? notes;

  bool get isNone => action == 'none';
  bool get isOptional => action == 'optional';
  bool get isForce => action == 'force';

  /// 用后台配置 + 本机版本名在本地算决策。
  ///
  /// 后台 `/api/app-version` 只返回配置数据，不做比较；比较在本地完成：
  /// 未配置版本名 → null；本机版本不低于最新 → none；强制开关开 → force；
  /// 否则 → optional。结构非法或未配置返回 null（一律按静默处理，绝不影响使用）。
  static VersionDecision? fromConfig(
    Object? data, {
    required String localVersionName,
  }) {
    if (data is! Map) return null;
    final latestName = _str(data['latest_version_name']);
    if (latestName == null) return null;
    final force =
        data['force_update'] == '1' || data['force_update'] == true;

    final String action;
    if (compareVersionName(localVersionName, latestName) >= 0) {
      action = 'none';
    } else if (force) {
      action = 'force';
    } else {
      action = 'optional';
    }

    return VersionDecision(
      action: action,
      latestName: latestName,
      downloadUrl: _str(data['download_url']),
      notes: _str(data['notes'])?.replaceAll('\r\n', '\n'),
    );
  }

  static String? _str(Object? v) {
    if (v == null) return null;
    final s = (v is String ? v : v.toString()).trim();
    return s.isEmpty ? null : s;
  }
}

/// 语义化比较两个版本名（如 1.2.0 vs 1.10.0），返回 -1/0/1。
/// 按「.」拆段逐段转整数比较；段数不足补 0；非数字段按 0。
int compareVersionName(String a, String b) {
  final as = a.split('.');
  final bs = b.split('.');
  final n = as.length > bs.length ? as.length : bs.length;
  for (var i = 0; i < n; i++) {
    final ai = i < as.length ? (int.tryParse(as[i].trim()) ?? 0) : 0;
    final bi = i < bs.length ? (int.tryParse(bs[i].trim()) ?? 0) : 0;
    if (ai < bi) return -1;
    if (ai > bi) return 1;
  }
  return 0;
}

/// 本机版本信息（`package_info_plus` 读取，测试可注入）。
class LocalVersion {
  const LocalVersion({
    required this.versionName,
    required this.buildNumber,
    required this.packageName,
  });

  /// pubspec 的 version 前缀，如 `1.0.0`。
  final String versionName;

  /// pubspec 的 `+` 后缀（Android 即 versionCode），如 `1`。
  final String buildNumber;
  final String packageName;
}

typedef LocalVersionLoader = Future<LocalVersion> Function();

/// 从平台读取本机版本（默认实现）。
Future<LocalVersion> loadLocalVersionFromPlatform() async {
  final info = await PackageInfo.fromPlatform();
  return LocalVersion(
    versionName: info.version,
    buildNumber: info.buildNumber,
    packageName: info.packageName,
  );
}

/// `GET /api/app-version` 的取数入口（接口化便于单测注入）。
abstract interface class VersionApi {
  Future<Map<String, dynamic>?> fetch();
}

/// 走统一 [ApiClient]（Bearer 由拦截器自动带上，对公开接口无副作用）。
class HttpVersionApi implements VersionApi {
  HttpVersionApi({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  @override
  Future<Map<String, dynamic>?> fetch() async {
    // ApiClient 拦截器已把 {code,msg,data} 解包成 data。
    final data = await _client.request('/api/app-version');
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }
}

/// 版本检查（T9.6）。
///
/// 铁律：检查更新失败**绝不影响** App 正常使用 —— 超时、网络错误、
/// 站点未配置（data 为 null）、已最新一律静默返回 null。
class VersionReporter {
  VersionReporter({
    VersionApi? api,
    LocalVersionLoader? localVersion,
    DateTime Function()? now,
    this.timeout = defaultTimeout,
    this.interval = defaultInterval,
  })  : _api = api ?? HttpVersionApi(),
        _localVersion = localVersion ?? loadLocalVersionFromPlatform,
        _now = now ?? DateTime.now;

  /// 接口超时（规格：5 秒）。
  static const Duration defaultTimeout = Duration(seconds: 5);

  /// 最短检查间隔（规格：24 小时内不重复）。
  static const Duration defaultInterval = Duration(hours: 24);

  /// prefs 键：上次成功拿到响应的毫秒时间戳。
  static const String lastCheckKey = 'update_last_check_at';

  final VersionApi _api;
  final LocalVersionLoader _localVersion;
  final DateTime Function() _now;
  final Duration timeout;
  final Duration interval;

  /// 拉取后台配置并在本地比较本机版本，得出决策。
  ///
  /// 返回 null = 静默跳过（不该做任何提示）。[force] 为 true 时忽略
  /// 24 小时节流（设置页「检查更新」用）。
  Future<VersionDecision?> report({bool force = false}) async {
    final now = _now();
    if (!force && await _checkedRecently(now)) return null;

    final VersionDecision? decision;
    try {
      // 读本机版本 + 拉配置 + 本地比较，整体受 5 秒超时约束。
      decision = await _fetch(localVersion: _localVersion, api: _api)
          .timeout(timeout);
    } catch (_) {
      // 超时 / 无网络 / 站点异常：静默，下次启动再试（不写 last_check_at）。
      return null;
    }

    // 拿到响应（含已最新）才记时间，避免断网时 24 小时不再重试。
    await _markChecked(now);

    if (decision == null || decision.isNone) return null;
    // 强制更新但没给下载地址：弹了会把用户锁死在不可关闭的弹窗里，静默跳过；
    // 可选更新照常返回，弹窗点「立即更新」时再提示未提供下载地址。
    if (decision.isForce && decision.downloadUrl == null) return null;
    return decision;
  }

  /// 读本机版本 → 拉配置 → 本地算决策。抽出来让 `.timeout()` 覆盖全过程。
  static Future<VersionDecision?> _fetch({
    required LocalVersionLoader localVersion,
    required VersionApi api,
  }) async {
    final local = await localVersion();
    final data = await api.fetch();
    return VersionDecision.fromConfig(data, localVersionName: local.versionName);
  }

  Future<bool> _checkedRecently(DateTime now) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(lastCheckKey);
      if (ms == null) return false;
      final last = DateTime.fromMillisecondsSinceEpoch(ms);
      return now.difference(last) < interval;
    } catch (_) {
      // prefs 读失败按「没查过」处理：宁可多查一次，也不要永远不查。
      return false;
    }
  }

  Future<void> _markChecked(DateTime now) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(lastCheckKey, now.millisecondsSinceEpoch);
    } catch (_) {
      // 写失败只影响节流，不影响本次决策展示。
    }
  }
}
