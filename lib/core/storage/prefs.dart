import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences 封装（非敏感数据，T1.5）。
///
/// 键名统一收口在这里。缓存值是 JSON 字符串，由调用方序列化。
class Prefs {
  static const String keyThemeMode = 'theme_mode';
  static const String keySelectedNode = 'selected_node';
  static const String keyCacheMe = 'cache_me';
  static const String keyCacheSiteConfig = 'cache_site_config';
  static const String keyBypassChina = 'bypass_china';
  static const String keyNodeLatency = 'node_latency';

  static Future<SharedPreferences> _p() => SharedPreferences.getInstance();

  static Future<String?> getThemeMode() async =>
      (await _p()).getString(keyThemeMode);

  static Future<void> setThemeMode(String v) async =>
      (await _p()).setString(keyThemeMode, v);

  static Future<String?> getSelectedNode() async =>
      (await _p()).getString(keySelectedNode);

  static Future<void> setSelectedNode(String v) async =>
      (await _p()).setString(keySelectedNode, v);

  static Future<String?> getCacheMe() async =>
      (await _p()).getString(keyCacheMe);

  static Future<void> setCacheMe(String v) async =>
      (await _p()).setString(keyCacheMe, v);

  static Future<String?> getCacheSiteConfig() async =>
      (await _p()).getString(keyCacheSiteConfig);

  static Future<void> setCacheSiteConfig(String v) async =>
      (await _p()).setString(keyCacheSiteConfig, v);

  /// 「绕开国内」开关：国内域名/IP 直连，国外走代理（规则模式）。
  static Future<bool> getBypassChina() async =>
      (await _p()).getBool(keyBypassChina) ?? true;

  static Future<void> setBypassChina(bool v) async =>
      (await _p()).setBool(keyBypassChina, v);

  /// 节点测速结果缓存（raw 分享链接 → 延迟毫秒）。JSON 字符串落盘，
  /// 冷启动回填，避免每次重开 App 都要重测一遍。
  static Future<Map<String, int>> getNodeLatency() async {
    final raw = (await _p()).getString(keyNodeLatency);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return decoded.map(
        (k, v) => MapEntry(k.toString(), (v as num).toInt()),
      );
    } catch (_) {
      return const {};
    }
  }

  static Future<void> setNodeLatency(Map<String, int> map) async =>
      (await _p()).setString(keyNodeLatency, jsonEncode(map));

  /// 清用户缓存（退出登录时用，保留主题/节点选择）。
  static Future<void> clearCache() async {
    final p = await _p();
    await p.remove(keyCacheMe);
    await p.remove(keyCacheSiteConfig);
  }
}
