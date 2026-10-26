import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences 封装（非敏感数据，T1.5）。
///
/// 键名统一收口在这里。缓存值是 JSON 字符串，由调用方序列化。
class Prefs {
  static const String keyThemeMode = 'theme_mode';
  static const String keySelectedNode = 'selected_node';
  static const String keyCacheMe = 'cache_me';
  static const String keyCacheSiteConfig = 'cache_site_config';

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

  /// 清用户缓存（退出登录时用，保留主题/节点选择）。
  static Future<void> clearCache() async {
    final p = await _p();
    await p.remove(keyCacheMe);
    await p.remove(keyCacheSiteConfig);
  }
}
