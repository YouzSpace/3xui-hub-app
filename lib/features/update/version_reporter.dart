import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/api_client.dart';

/// 版本决策（T9.6 / system-design §11）。
///
/// 决策四规则由后端算好，App 只拿 `action` 决定展示方式：
/// `none` 静默、`optional` 可稍后、`force` 不可关闭。
class VersionDecision {
  const VersionDecision({
    required this.action,
    this.latestName,
    this.latestCode,
    this.downloadUrl,
    this.size,
    this.sha256,
    this.notes,
    this.minSupportedCode,
  });

  /// none | optional | force（后端返回值，未知值按 none 处理）。
  final String action;
  final String? latestName;
  final int? latestCode;
  final String? downloadUrl;

  /// 安装包字节数（用于展示与进度）。后端缺省时为空。
  final int? size;
  final String? sha256;

  /// 更新说明，换行分隔。
  final String? notes;
  final int? minSupportedCode;

  bool get isNone => action == 'none';
  bool get isOptional => action == 'optional';
  bool get isForce => action == 'force';

  /// 解析 `data` 字段。
  ///
  /// 后端 Go 端数字字段实际按 number 返回（`latest_version_code`/`size`/
  /// `min_supported_code`），但契约文字写的是「全字符串」，两种都吃；
  /// 结构非法或 action 不认识时返回 null（一律按静默处理，绝不影响使用）。
  static VersionDecision? fromJson(Object? data) {
    if (data is! Map) return null;
    final action = _str(data['action'])?.toLowerCase();
    if (action == null) return null;
    if (action != 'none' && action != 'optional' && action != 'force') {
      return null;
    }
    return VersionDecision(
      action: action,
      latestName: _str(data['latest_version_name']),
      latestCode: _int(data['latest_version_code']),
      downloadUrl: _str(data['download_url']),
      size: _int(data['size']),
      sha256: _str(data['sha256']),
      notes: _str(data['notes'])?.replaceAll('\r\n', '\n'),
      minSupportedCode: _int(data['min_supported_code']),
    );
  }

  static String? _str(Object? v) {
    if (v == null) return null;
    final s = (v is String ? v : v.toString()).trim();
    return s.isEmpty ? null : s;
  }

  static int? _int(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return int.tryParse(s) ?? double.tryParse(s)?.toInt();
  }
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

  /// 后端只按整数比较版本，非数字构建号按 0（一定会被要求升级）。
  int get versionCode => int.tryParse(buildNumber.trim()) ?? 0;
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
  Future<Map<String, dynamic>?> fetch({
    required String versionCode,
    required String versionName,
    required String packageId,
  });
}

/// 走统一 [ApiClient]：Bearer 由拦截器按 TokenStore 自动带上
/// （已登录时后端会把版本写回用户，供后台统计版本分布）。
class HttpVersionApi implements VersionApi {
  HttpVersionApi({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  @override
  Future<Map<String, dynamic>?> fetch({
    required String versionCode,
    required String versionName,
    required String packageId,
  }) async {
    // ApiClient 拦截器已把 {code,msg,data} 解包成 data。
    final data = await _client.request('/api/app-version', query: {
      'version_code': versionCode,
      'version_name': versionName,
      'package_id': packageId,
      'platform': 'android',
    });
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }
}

/// 版本上报（T9.6）。
///
/// 铁律：检查更新失败**绝不影响** App 正常使用 —— 超时、网络错误、
/// 站点未配置（data 为 null）、action == none 一律静默返回 null。
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

  /// 上报本机版本并拿决策。
  ///
  /// 返回 null = 静默跳过（不该做任何提示）。[force] 为 true 时忽略
  /// 24 小时节流（设置页「检查更新」用）。
  Future<VersionDecision?> report({bool force = false}) async {
    final now = _now();
    if (!force && await _checkedRecently(now)) return null;

    final Map<String, dynamic>? data;
    try {
      // 读本机版本 + 请求整体受 5 秒超时约束（读包信息卡住也要能退出）。
      data = await _fetch(localVersion: _localVersion, api: _api)
          .timeout(timeout);
    } catch (_) {
      // 超时 / 无网络 / 站点异常：静默，下次启动再试（不写 last_check_at）。
      return null;
    }

    // 拿到响应（含 none）才记时间，避免断网时 24 小时不再重试。
    await _markChecked(now);

    final decision = VersionDecision.fromJson(data);
    if (decision == null || decision.isNone) return null;
    // 后端配了需升级却没给下载地址：弹了也装不了，按静默处理。
    if (decision.downloadUrl == null) return null;
    return decision;
  }

  /// 读本机版本 → 调接口。抽出来只为了让上面那行 `.timeout()` 覆盖全过程。
  static Future<Map<String, dynamic>?> _fetch({
    required LocalVersionLoader localVersion,
    required VersionApi api,
  }) async {
    final local = await localVersion();
    return api.fetch(
      versionCode: '${local.versionCode}',
      versionName: local.versionName,
      packageId: local.packageName,
    );
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
