import 'package:flutter/services.dart' show rootBundle;

/// 应用品牌名配置（客户白标用，T9.2）。
///
/// 与 [ApiConfig] 同一套思路：品牌名放 `assets/config/app_name.txt`，
/// 客户用 MT 管理器改这个 txt 就能换名字，不必改代码。
///
/// 空文件（默认版）= 不覆盖，UI 继续用后台站点名 `site_title`，
/// 这样普通版换服务器仍然能自动跟着站点名走。
class AppConfig {
  static const String _assetPath = 'assets/config/app_name.txt';

  static String _appName = '';

  /// 客户品牌名；空串表示不覆盖（用后台站点名）。
  static String get appName => _appName;

  /// 启动时读 assets/config/app_name.txt；读不到按空处理，不阻塞启动。
  static Future<void> loadAppName() async {
    try {
      final s = await rootBundle.loadString(_assetPath);
      _appName = s.trim();
    } catch (_) {
      _appName = '';
    }
  }

  /// UI 显示名：品牌名非空用品牌名，否则用后台站点名（也可能为空）。
  static String displayName(String siteTitle) =>
      _appName.isNotEmpty ? _appName : siteTitle.trim();
}
